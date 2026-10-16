import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/logger.dart';
import 'protected_paths.dart';

/// Result of storing one path into the quarantine.
class QuarantineReceipt {
  QuarantineReceipt({
    required this.id,
    required this.originalPath,
    required this.storedPath,
    required this.bytes,
    required this.isDirectory,
    required this.module,
  });

  final String id;
  final String originalPath;
  final String storedPath;
  final int bytes;
  final bool isDirectory;
  final String module;
}

/// One entry recorded in the quarantine manifest.
class QuarantineItem {
  QuarantineItem({
    required this.id,
    required this.originalPath,
    required this.storedPath,
    required this.bytes,
    required this.isDirectory,
    required this.module,
    required this.quarantinedAt,
  });

  factory QuarantineItem.fromJson(Map<String, dynamic> json) => QuarantineItem(
        id: json['id'] as String,
        originalPath: json['originalPath'] as String,
        storedPath: json['storedPath'] as String,
        bytes: (json['bytes'] as num).toInt(),
        isDirectory: json['isDirectory'] as bool? ?? false,
        module: json['module'] as String? ?? 'unknown',
        quarantinedAt: DateTime.parse(json['quarantinedAt'] as String),
      );

  final String id;
  final String originalPath;
  final String storedPath;
  final int bytes;
  final bool isDirectory;
  final String module;
  final DateTime quarantinedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalPath': originalPath,
        'storedPath': storedPath,
        'bytes': bytes,
        'isDirectory': isDirectory,
        'module': module,
        'quarantinedAt': quarantinedAt.toUtc().toIso8601String(),
      };
}

/// The safety net of the whole application.
///
/// Nothing is ever `unlink`ed or `rm -rf`ed. Every removal *moves* the payload
/// under [root] and writes a JSON manifest next to it, so any mistake is a
/// single tap on "Restore" away from being permanent. That is the mechanical
/// guarantee behind the product promise "never deletes important files".
class Quarantine {
  Quarantine({required this.root, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Directory root;
  final DateTime Function() _clock;

  Directory get _objectsDir => Directory(p.join(root.path, 'objects'));
  Directory get _manifestDir => Directory(p.join(root.path, 'manifest'));

  Future<void> init() async {
    await _objectsDir.create(recursive: true);
    await _manifestDir.create(recursive: true);
  }

  DateTime get _now => _clock();

  /// Moves [rawPath] into the quarantine and records it.
  ///
  /// Refuses protected paths outright. Cross-device moves fall back to
  /// copy-then-verify-then-remove, and the source is only removed once the
  /// byte totals match.
  Future<QuarantineReceipt> store(String rawPath, {required String module}) async {
    final normalized = ProtectedPaths.normalize(rawPath);
    if (ProtectedPaths.isProtected(normalized)) {
      throw FileSystemException(
        'refusing to quarantine a protected path',
        normalized,
      );
    }

    await init();

    final type = FileSystemEntity.typeSync(normalized, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('path no longer exists', normalized);
    }
    if (type == FileSystemEntityType.link) {
      throw FileSystemException('refusing to follow a symlink', normalized);
    }

    final isDirectory = type == FileSystemEntityType.directory;
    final bytes = isDirectory
        ? _treeSize(Directory(normalized))
        : File(normalized).lengthSync();

    final id = _newId();
    final stored = p.join(_objectsDir.path, id);

    final FileSystemEntity payload =
        isDirectory ? Directory(normalized) : File(normalized);
    await _move(payload, stored);

    final item = QuarantineItem(
      id: id,
      originalPath: normalized,
      storedPath: stored,
      bytes: bytes,
      isDirectory: isDirectory,
      module: module,
      quarantinedAt: _now,
    );
    await _writeManifest(item);
    log.info('quarantined ${item.bytes}B from ${item.originalPath}');
    return QuarantineReceipt(
      id: item.id,
      originalPath: item.originalPath,
      storedPath: item.storedPath,
      bytes: item.bytes,
      isDirectory: isDirectory,
      module: item.module,
    );
  }

  /// Every recorded entry, newest first. Corrupt manifests are reported as
  /// skipped rather than thrown — a half-written JSON file must not make the
  /// whole Quarantine screen unusable.
  Future<List<QuarantineItem>> list() async {
    if (!_manifestDir.existsSync()) return const [];
    final items = <QuarantineItem>[];
    for (final entity in _manifestDir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(entity.readAsStringSync());
        if (decoded is Map<String, dynamic>) {
          items.add(QuarantineItem.fromJson(decoded));
        }
      } catch (e) {
        log.warn('skipping corrupt quarantine manifest ${entity.path}: $e');
      }
    }
    items.sort((a, b) => b.quarantinedAt.compareTo(a.quarantinedAt));
    return items;
  }

  /// Moves a quarantined payload back to where it came from.
  Future<void> restore(String id) async {
    final item = (await list()).where((i) => i.id == id).firstOrNull;
    if (item == null) throw StateError('no quarantine entry $id');

    final source = item.isDirectory
        ? Directory(item.storedPath)
        : File(item.storedPath);
    if (!source.existsSync()) {
      await _deleteManifest(id);
      throw StateError('quarantine payload missing for $id');
    }

    final destination = Directory(item.originalPath).parent;
    await destination.create(recursive: true);
    await _move(source, item.originalPath);
    await _deleteManifest(id);
    log.info('restored ${item.originalPath}');
  }

  /// Permanently deletes one entry by id.
  ///
  /// Throws [StateError] when no such entry exists, so the UI can tell "you
  /// purged something" apart from "that row was already gone".
  Future<QuarantineItem> purgeItem(String id) async {
    final item = (await list()).where((i) => i.id == id).firstOrNull;
    if (item == null) throw StateError('no quarantine entry $id');
    await _destroy(item);
    log.info('purged quarantine entry $id (${item.originalPath})');
    return item;
  }

  /// Permanently deletes entries older than [retention].
  Future<List<QuarantineItem>> purgeOlderThan(Duration retention) async {
    final cutoff = _now.subtract(retention);
    final purged = <QuarantineItem>[];
    for (final item in await list()) {
      if (!item.quarantinedAt.isBefore(cutoff)) continue;
      await _destroy(item);
      purged.add(item);
    }
    if (purged.isNotEmpty) {
      log.info('purged ${purged.length} quarantine entries older than $retention');
    }
    return purged;
  }

  Future<void> _destroy(QuarantineItem item) async {
    final payload =
        item.isDirectory ? Directory(item.storedPath) : File(item.storedPath);
    if (payload.existsSync()) {
      if (item.isDirectory) {
        await payload.delete(recursive: true);
      } else {
        await payload.delete();
      }
    }
    await _deleteManifest(item.id);
  }

  /// Deletes every entry regardless of age.
  ///
  /// Deliberately not implemented as `purgeOlderThan(Duration.zero)`: an entry
  /// quarantined during this very clock tick is *not* "before now", so a
  /// zero-retention cutoff would silently spare exactly the newest entries.
  Future<List<QuarantineItem>> purgeAll() async {
    final purged = <QuarantineItem>[];
    for (final item in await list()) {
      await _destroy(item);
      purged.add(item);
    }
    if (purged.isNotEmpty) {
      log.info('purged all ${purged.length} quarantine entries');
    }
    return purged;
  }

  /// Total bytes currently held in the quarantine.
  Future<int> totalBytes() async {
    var sum = 0;
    for (final item in await list()) {
      sum += item.bytes;
    }
    return sum;
  }

  String _newId() {
    final stamp = _now.toUtc().microsecondsSinceEpoch.toRadixString(36);
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$stamp-$salt';
  }

  Future<void> _writeManifest(QuarantineItem item) =>
      File(p.join(_manifestDir.path, '${item.id}.json'))
          .writeAsString(jsonEncode(item.toJson()), flush: true);

  Future<void> _deleteManifest(String id) async {
    final f = File(p.join(_manifestDir.path, '$id.json'));
    if (f.existsSync()) await f.delete();
  }

  static int _treeSize(Directory dir) {
    var sum = 0;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          sum += entity.lengthSync();
        } on FileSystemException {
          // Unreadable file: ignore, we cannot recover its bytes anyway.
        }
      }
    }
    return sum;
  }

  /// Rename first, copy+verify+delete as a fallback for `EXDEV`.
  static Future<void> _move(FileSystemEntity source, String destination) async {
    try {
      await source.rename(destination);
      return;
    } on FileSystemException catch (e) {
      // `EXDEV` (cross-device link) is the only case worth retrying; a
      // permission error must surface immediately.
      if (e.osError?.errorCode != 18) rethrow;
      log.warn('cross-device move, falling back to copy: ${e.message}');
    }

    final src = source is Directory ? Directory(source.path) : File(source.path);
    if (src is Directory) {
      await _copyTree(src, Directory(destination));
      final copied = _treeSize(Directory(destination));
      final original = _treeSize(src);
      if (copied != original) {
        await Directory(destination).delete(recursive: true);
        throw FileSystemException(
          'copy verification failed ($copied != $original)',
          source.path,
        );
      }
      await src.delete(recursive: true);
    } else {
      final file = File(source.path);
      await file.copy(destination);
      final copied = File(destination).lengthSync();
      final original = file.lengthSync();
      if (copied != original) {
        await File(destination).delete();
        throw FileSystemException(
          'copy verification failed ($copied != $original)',
          source.path,
        );
      }
      await file.delete();
    }
  }

  static Future<void> _copyTree(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: src.path);
      final target = p.join(dst.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entity.copy(target);
      }
      // Links are intentionally not copied.
    }
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}