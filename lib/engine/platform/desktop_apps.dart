import 'dart:io';
import 'dart:typed_data';

import '../../core/util/logger.dart';

/// One application the desktop platform knows about.
class DesktopApp {
  DesktopApp({
    required this.name,
    required this.displayName,
    this.id = '',
    this.sizeBytes = 0,
    this.lastUsed,
    this.launchCount = 0,
    this.workingSetBytes = 0,
  });

  /// The platform's own identifier, which is what a launcher is asked to remove.
  final String name;

  /// A human label, never the raw name when a real one is available.
  final String displayName;

  /// The platform's package id, when it has one (desktop launchers use it for
  /// Flatpak/Snap bundles).
  final String id;

  /// Bytes on disk. Zero when the platform cannot attribute any.
  final int sizeBytes;

  /// When the user last launched it.
  final DateTime? lastUsed;

  /// How many times the desktop launcher recorded a launch.
  final int launchCount;

  /// Resident memory when the app is running right now.
  final int workingSetBytes;

  bool get isRunning => workingSetBytes > 0;

  /// Days since the last launch; [null] when the platform never recorded one.
  int? idleDays(DateTime now) {
    final DateTime? used = lastUsed;
    if (used == null) return null;
    return (now.difference(used).inHours ~/ 24).clamp(0, 1 << 20);
  }

  static DesktopApp? fromMap(Map<String, Object?> map) {
    final Object? name = map['name'];
    if (name is! String || name.isEmpty) return null;
    final Object? used = map['lastUsed'];
    return DesktopApp(
      name: name,
      displayName: (map['displayName'] as String?)?.trim().isNotEmpty ?? false
          ? map['displayName']! as String
          : name,
      id: (map['id'] as String?) ?? name,
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      lastUsed: used is int && used > 0
          ? DateTime.fromMillisecondsSinceEpoch(used)
          : null,
      launchCount: (map['launchCount'] as num?)?.toInt() ?? 0,
      workingSetBytes: (map['workingSetBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Reads the desktop platform's own record of what is installed and when it was
/// last opened.
///
/// Linux answers from the freedesktop launcher databases and the shell's own
/// history; Windows answers from the uninstall registry plus prefetch. Neither
/// can answer for every app, and where they cannot they say so rather than
/// guessing — an app with no recorded launch is reported as never-opened, which
/// is a fact, not an absence of one.
abstract class DesktopAppSource {
  Future<List<DesktopApp>> installedApps();

  /// The launcher-specific command that removes [app], or `null` when the
  /// platform will not do it for us.
  List<String>? uninstallCommand(DesktopApp app);

  /// The fallback when the launcher has no command of its own.
  List<String>? manualUninstallHint(DesktopApp app) => null;
}

/// The command that removes a Linux desktop entry.
///
/// Flatpak ids carry a namespace and have their own remover; everything else is
/// a system package and belongs to the package manager. Exposed as a pure
/// function so the choice can be tested without a desktop to run it on.
List<String> linuxUninstallCommand(String desktopEntryId) {
  final String base = desktopEntryId.endsWith('.desktop')
      ? desktopEntryId.substring(0, desktopEntryId.length - '.desktop'.length)
      : desktopEntryId;
  if (base.contains('.')) return <String>['flatpak', 'uninstall', '-y', base];
  return <String>['pkexec', 'apt-get', 'remove', '--purge', base];
}

/// Parses the `\0`-delimited key/value blocks that `grep -z` produces from the
/// freedesktop launcher databases.
List<DesktopApp> parseDesktopEntries(String raw, {DateTime? now}) {
  final List<DesktopApp> apps = <DesktopApp>[];
  final DateTime at = now ?? DateTime.now();

  // `\0` is not an escape in Dart: it is the literal character '0'. The
  // NUL byte that `grep -z` produces has to be spelled out in full, or the
  // split silently cuts every path that contains a zero in its name.
  for (final String block in raw.split('\u0000')) {
    if (block.isEmpty) continue;
    String? id;
    String? name;
    String? exec;
    int launches = 0;
    DateTime? lastUsed;
    DateTime? installed;

    for (final String line in block.split('\n')) {
      final int eq = line.indexOf('=');
      if (eq <= 0) continue;
      final String key = line.substring(0, eq);
      final String value = line.substring(eq + 1);
      // Every case breaks: a freedesktop entry keys off the *first* occurrence
      // of a name and off the Exec that actually launches something, so falling
      // through from one key to the next would happily store `Name=firefox` as
      // the executable and then discard the real Exec line.
      switch (key) {
        case 'Name':
          if (name == null) name = value;
          break;
        case 'Exec':
          exec ??= value;
          break;
        case 'X-OmniClean-Installed':
          installed = _parseEpoch(value);
          break;
        case 'X-OmniClean-LaunchCount':
          launches = int.tryParse(value) ?? 0;
          break;
        case 'X-OmniClean-LastUsed':
          lastUsed = _parseEpoch(value);
          break;
      }
    }

    final String? source = exec?.split(RegExp(r'\s+')).first;
    if (source == null || source.isEmpty) continue;
    id ??= '$source.desktop';
    apps.add(DesktopApp(
      name: id,
      displayName: (name == null || name.isEmpty) ? source : name,
      id: id,
      launchCount: launches,
      lastUsed: lastUsed ?? installed,
      sizeBytes: _installedSize(source),
    ));
  }

  log.info('desktop apps: ${apps.length} entries parsed at $at');
  return apps;
}

DateTime? _parseEpoch(String value) {
  final int? seconds = int.tryParse(value.trim());
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

int _installedSize(String executable) {
  // A desktop entry does not record its own size, so the honest answer is the
  // size of the binary it points at. A *script* reports zero rather than the
  // size of the interpreter behind it, and "is it a script" is answered by
  // looking for a NUL byte in the first block — not by guessing from the size,
  // because a perfectly real binary like /bin/dash is small too.
  try {
    final File file = File(executable);
    if (!file.existsSync()) return 0;
    final RandomAccessFile handle = file.openSync();
    try {
      final int length = handle.lengthSync();
      if (length == 0) return 0;
      final Uint8List probe = handle.readSync(
        length < 4096 ? length : 4096,
      );
      for (final int byte in probe) {
        if (byte == 0) return length;
      }
    } finally {
      handle.closeSync();
    }
    return 0;
  } on FileSystemException {
    return 0;
  }
}
