import 'dart:io';

import '../util/logger.dart';
import 'protected_paths.dart';
import 'quarantine.dart';

/// Why a candidate was accepted or refused.
enum VerdictCode {
  allowed,
  protected,
  outsideRoots,
  tooYoung,
  symlink,
  missing,
  tooLarge,
}

/// The result of gating a single path.
class DeleteVerdict {
  const DeleteVerdict.allowed({required this.bytes, required this.isDirectory})
      : code = VerdictCode.allowed,
        reason = '';

  const DeleteVerdict.refused(this.code, this.reason)
      : bytes = 0,
        isDirectory = false;

  final VerdictCode code;
  final String reason;
  final int bytes;
  final bool isDirectory;

  bool get isAllowed => code == VerdictCode.allowed;
}

/// Aggregate report for one cleaning run.
class CleanOutcome {
  CleanOutcome({
    required this.cleaned,
    required this.skipped,
    required this.bytesFreed,
    required this.errors,
    required this.failedPaths,
  });

  final List<String> cleaned;
  final List<String> skipped;
  final int bytesFreed;
  final List<String> errors;
  final List<String> failedPaths;

  bool get isNoop => cleaned.isEmpty;
}

/// The only sanctioned way to remove data from the machine.
///
/// It combines three independent gates — [ProtectedPaths] (never touch),
/// `allowedRoots` (only inside this module's declared tree) and `minAge`
/// (never touch data a live process is probably still using) — and then hands
/// the survivors to [Quarantine] instead of unlinking them.
class SafeDelete {
  SafeDelete({
    required this.quarantine,
    DateTime Function()? clock,
    Future<bool> Function()? privilegeProbe,
  })  : _clock = clock ?? DateTime.now,
        privilegeProbe = privilegeProbe ?? (() async => false);

  final Quarantine quarantine;
  final DateTime Function() _clock;

  /// Whether a privileged helper is available; surfaced so the UI can warn.
  final Future<bool> Function() privilegeProbe;

  /// Decides the fate of a single [rawPath].
  Future<DeleteVerdict> evaluate(
    String rawPath, {
    required List<String> allowedRoots,
    Duration minAge = Duration.zero,
    bool followLinks = false,
    int? maxBytes,
  }) async {
    final path = ProtectedPaths.normalize(rawPath);

    if (ProtectedPaths.isProtected(path)) {
      return DeleteVerdict.refused(
        VerdictCode.protected,
        ProtectedPaths.explain(path),
      );
    }

    // Anything outside the roots the module declared is refused, even when it
    // is harmless junk: a module that scans the wrong directory is a bug we
    // want to hear about loudly rather than "clean up" silently.
    if (!allowedRoots.any((r) => ProtectedPaths.isInside(path, r))) {
      return const DeleteVerdict.refused(
        VerdictCode.outsideRoots,
        'outside the declared cleanable roots',
      );
    }

    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return const DeleteVerdict.refused(
          VerdictCode.missing, 'no longer exists');
    }
    if (type == FileSystemEntityType.link && !followLinks) {
      return const DeleteVerdict.refused(
        VerdictCode.symlink,
        'symbolic link — refusing to follow',
      );
    }

    if (maxBytes != null && type == FileSystemEntityType.file) {
      final size = File(path).lengthSync();
      if (size > maxBytes) {
        return DeleteVerdict.refused(
          VerdictCode.tooLarge,
          'larger than the $maxBytes byte ceiling',
        );
      }
    }

    final isDirectory = type == FileSystemEntityType.directory;
    final modified = isDirectory
        ? Directory(path).statSync().modified
        : File(path).statSync().modified;

    if (minAge > Duration.zero &&
        _clock().toUtc().difference(modified.toUtc()) < minAge) {
      return const DeleteVerdict.refused(
        VerdictCode.tooYoung,
        'touched recently — a running app may still need it',
      );
    }

    final bytes = isDirectory ? _dirSize(path) : File(path).lengthSync();
    return DeleteVerdict.allowed(bytes: bytes, isDirectory: isDirectory);
  }

  /// Gates, then quarantines, every surviving path.
  ///
  /// A refusal is never fatal: it is counted in [CleanOutcome.skipped] and the
  /// loop continues, so one protected file cannot abort a whole module.
  Future<CleanOutcome> quarantineAll(
    List<String> paths, {
    required List<String> allowedRoots,
    required String module,
    Duration minAge = Duration.zero,
    int? maxBytes,
    void Function(int done, int total)? onProgress,
  }) async {
    final cleaned = <String>[];
    final skipped = <String>[];
    final errors = <String>[];
    final failed = <String>[];
    var freed = 0;

    final total = paths.length;
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      onProgress?.call(i, total);

      final verdict = await evaluate(
        path,
        allowedRoots: allowedRoots,
        minAge: minAge,
        maxBytes: maxBytes,
      );

      if (!verdict.isAllowed) {
        skipped.add(path);
        log.fine('skip $path → ${verdict.code.name}: ${verdict.reason}');
        continue;
      }

      try {
        final receipt = await quarantine.store(path, module: module);
        cleaned.add(receipt.originalPath);
        freed += receipt.bytes;
      } on FileSystemException catch (e) {
        errors.add('${path}: ${e.osError?.message ?? e.message}');
        failed.add(path);
      } catch (e) {
        errors.add('$path: $e');
        failed.add(path);
      }
    }

    onProgress?.call(total, total);
    return CleanOutcome(
      cleaned: cleaned,
      skipped: skipped,
      bytesFreed: freed,
      errors: errors,
      failedPaths: failed,
    );
  }

  static int _dirSize(String path) {
    var sum = 0;
    for (final entity
        in Directory(path).listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          sum += entity.lengthSync();
        } on FileSystemException {
          // Unreadable — nothing to reclaim.
        }
      }
    }
    return sum;
  }
}
