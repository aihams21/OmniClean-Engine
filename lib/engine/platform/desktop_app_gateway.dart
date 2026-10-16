import 'dart:convert';
import 'dart:io';

import '../../core/util/logger.dart';
import '../shell.dart';
import 'desktop_apps.dart';
import 'storage_gateway.dart';

/// Asks the desktop platform about installed apps and last-use times.
///
/// This is what makes the unused-apps screen work on Linux and Windows instead
/// of being an Android-only feature. Where the platform keeps no record it
/// reports an empty list, which the controller renders as "nothing scanned"
/// rather than as "you own no apps".
class DesktopAppGateway extends StorageGateway {
  DesktopAppGateway({
    DesktopAppSource? source,
    Future<ShellResult> Function(String executable, List<String> args)? run,
    DateTime Function()? clock,
    StorageCapabilities? capabilities,
  })  : _source = source,
        _run = run ?? Shell.run,
        _clock = clock ?? DateTime.now,
        _capabilities = capabilities ??
            const StorageCapabilities(
              apiLevel: 0,
              canRequestAllFiles: true,
              canQueryUsageStats: true,
              canUninstallApps: true,
            );

  final DesktopAppSource? _source;
  final Future<ShellResult> Function(String, List<String>) _run;
  final DateTime Function() _clock;
  final StorageCapabilities _capabilities;

  @override
  Future<StorageCapabilities> capabilities() async => _capabilities;

  @override
  Future<List<AppUsage>> unusedApps({int unusedDays = 30}) async {
    final DesktopAppSource source = _source ?? defaultSource();
    final List<DesktopApp> installed = await source.installedApps();
    if (installed.isEmpty) {
      log.info('desktop apps: the platform reported none');
      return const <AppUsage>[];
    }

    final DateTime now = _clock();
    final List<AppUsage> apps = <AppUsage>[];
    for (final DesktopApp app in installed) {
      final int? idle = app.idleDays(now);
      if (app.isRunning) continue;
      // An app the shell *did* record a launch for, but that was used recently,
      // is simply not an unused app. An app with no record at all stays: that
      // is the "never opened" case the user most wants to see.
      if (idle != null && idle < unusedDays) continue;
      apps.add(AppUsage(
        packageName: app.name,
        label: app.displayName,
        sizeBytes: app.sizeBytes,
        // A desktop app the shell never recorded as launched is reported with a
        // zero timestamp, which the controller renders as "never opened" and
        // ranks first — the same shape Android uses, so one screen serves both.
        lastUsed: app.lastUsed ?? DateTime.fromMillisecondsSinceEpoch(0),
        versionName: '',
        isSystem: false,
        installedMillis: 0,
      ));
    }
    return apps;
  }

  @override
  Future<void> launchUninstall(String packageName) async {
    final DesktopAppSource source = _source ?? defaultSource();
    final DesktopApp? app = packageName.isEmpty
        ? null
        : DesktopApp(name: packageName, displayName: packageName);
    List<String>? command = source.uninstallCommand(app!);
    if (command == null && _source == null) {
      command = Platform.isLinux
          ? <String>['pkexec', 'apt-get', 'remove', '--purge', packageName]
          : null;
    }
    if (command == null) {
      // Not a failure we can paper over: say so and let the row stand.
      throw UnsupportedError(
          'this platform has no scripted uninstall for $packageName');
    }
    final ShellResult result = await _run(command.first, command.sublist(1));
    if (!result.ok) {
      throw StateError(result.stderr.isEmpty
          ? 'uninstall of $packageName exited ${result.exitCode}'
          : result.stderr);
    }
    log.info('desktop apps: removed $packageName');
  }

  @override
  Future<JunkSummary> scanJunk(
          {Duration minAge = const Duration(days: 7)}) async =>
      JunkSummary(entries: const <StorageEntry>[], scannedEntries: 0);

  @override
  Future<void> deleteEntries(List<String> ids) async {}

  @override
  Future<void> emptyTrash() async {}

  @override
  Future<List<MediaItem>> media({MediaKind kind = MediaKind.photos}) async =>
      const <MediaItem>[];

  @override
  Future<List<StorageEntry>> mediaFiles({int minSizeBytes = 4 * 1024}) async =>
      const <StorageEntry>[];

  @override
  Future<BoostReport> boost() async => const BoostReport(
        unavailableReason:
            'boosting is handled by the shell on desktop, not by this gateway',
      );

  @override
  Future<StorageCapabilities> requestAccess() async => capabilities();

  @override
  Future<List<String>> browsableRoots() async => const <String>[];

  DesktopAppSource defaultSource() =>
      Platform.isWindows ? const _WindowsAppSource() : const _LinuxAppSource();
}

/// Reads `/usr/share/applications` and `~/.local/share/applications`, and
/// consults the shell history for a launch time when the entry has none.
class _LinuxAppSource implements DesktopAppSource {
  const _LinuxAppSource();

  static const String _stampKey = 'X-OmniClean-LastUsed';

  @override
  Future<List<DesktopApp>> installedApps() async {
    final List<String> roots = <String>[
      '${Platform.environment['HOME'] ?? '/root'}/.local/share/applications',
      '/usr/share/applications',
      '/usr/local/share/applications',
      '/var/lib/flatpak/exports/share/applications',
    ].where((String path) => Directory(path).existsSync()).toList();
    if (roots.isEmpty) return const <DesktopApp>[];

    final Map<String, int> launches = await _launchCounts();
    final List<DesktopApp> apps = <DesktopApp>[];
    for (final String root in roots) {
      for (final FileSystemEntity entity
          in Directory(root).listSync(followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.desktop')) continue;
        final int? count = launches[entity.path.split('/').last];
        apps.addAll(parseDesktopEntries(
          _withStamps(entity, count),
          now: DateTime.now(),
        ));
      }
    }
    return apps;
  }

  /// The shell only records the last command per line, so the count is the
  /// number of history lines mentioning the executable — enough to separate
  /// "never opened" from "opened once a year ago".
  Future<Map<String, int>> _launchCounts() async {
    final String home = Platform.environment['HOME'] ?? '';
    final List<String> histories = <String>[
      if (home.isNotEmpty) '$home/.zsh_history',
      if (home.isNotEmpty) '$home/.bash_history',
      if (home.isNotEmpty) '$home/.local/share/fish/fish_history',
    ].where((String path) => File(path).existsSync()).toList();
    if (histories.isEmpty) return <String, int>{};

    final String script = r'cat "$@" 2>/dev/null | tr "\n" "\0"';
    final ShellResult result = await Shell.run('sh', <String>[
      '-c',
      script,
      'sh',
      ...histories,
    ]);
    if (!result.ok) return <String, int>{};

    final Map<String, int> counts = <String, int>{};
    for (final String line in result.stdout.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final String executable = trimmed.split(RegExp(r'\s+')).first;
      final String name = executable.split('/').last;
      if (!name.isEmpty)
        counts['$name.desktop'] = (counts['$name.desktop'] ?? 0) + 1;
    }
    return counts;
  }

  String _withStamps(File file, int? launches) {
    final String raw = file.readAsStringSync();
    final int launchCount = launches ?? 0;
    final FileStat stat = file.statSync();
    return '$raw\n$_stampKey=${stat.modified.millisecondsSinceEpoch ~/ 1000}'
        '\nX-OmniClean-LaunchCount=$launchCount';
  }

  @override
  List<String> uninstallCommand(DesktopApp app) =>
      linuxUninstallCommand(app.id);

  @override
  List<String>? manualUninstallHint(DesktopApp app) =>
      <String>['gnome-software', 'remove', app.name];
}

/// Reads the Windows uninstall registry and maps each entry to a real binary.
class _WindowsAppSource implements DesktopAppSource {
  const _WindowsAppSource();

  static const String _script = r'''
$paths = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$out = @()
foreach ($p in $paths) {
  Get-ItemProperty $p -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and $_.InstallLocation } |
    ForEach-Object {
      $dir = $_.InstallLocation
      $bytes = 0
      if (Test-Path $dir) {
        $bytes = (Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
      }
      $exe = Join-Path $dir '*.exe'
      $out += [pscustomobject]@{
        name        = $_.PSChildName
        displayName = $_.DisplayName
        id          = $_.PSChildName
        installDir  = $dir
        exe         = (Get-ChildItem $exe -ErrorAction SilentlyContinue |
                        Select-Object -First 1).FullName
        sizeBytes   = [int64]$bytes
      }
    }
}
$out | ConvertTo-Json -Compress
''';

  @override
  Future<List<DesktopApp>> installedApps() async {
    final ShellResult result =
        await Shell.runScript(_script, timeout: const Duration(minutes: 3));
    if (!result.ok || result.stdout.trim().isEmpty) {
      log.warn('windows apps: registry read failed — ${result.stderr}');
      return const <DesktopApp>[];
    }
    Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      return const <DesktopApp>[];
    }
    final Object? list = decoded is List ? decoded : <Object?>[decoded];
    final DateTime now = DateTime.now();
    final List<DesktopApp> apps = <DesktopApp>[];
    for (final Map<String, Object?> row
        in (list as List<Object?>).whereType<Map<String, Object?>>()) {
      final DesktopApp? app = _fromRow(row, now);
      if (app != null) apps.add(app);
    }
    return apps;
  }

  DesktopApp? _fromRow(Map<String, Object?> row, DateTime now) {
    final String? name = row['name'] as String?;
    if (name == null || name.isEmpty) return null;
    final String? exe = row['exe'] as String?;
    if (exe == null || exe.isEmpty) return null;
    // Windows records no last-launch time for a program; the executable's own
    // write time is the only honest proxy, and saying so beats inventing one.
    DateTime? touched;
    try {
      final File file = File(exe);
      if (file.existsSync()) touched = file.lastModifiedSync();
    } on FileSystemException {
      touched = null;
    }
    return DesktopApp(
      name: name,
      displayName: (row['displayName'] as String?) ?? name,
      id: (row['id'] as String?) ?? name,
      sizeBytes: (row['sizeBytes'] as num?)?.toInt() ?? 0,
      lastUsed: touched,
      workingSetBytes: 0,
    );
  }

  @override
  List<String>? uninstallCommand(DesktopApp app) =>
      <String>['cmd', '/c', 'start', '', 'ms-settings:appsfeatures'];

  @override
  List<String>? manualUninstallHint(DesktopApp app) =>
      <String>['cmd', '/c', 'start', '', 'appwiz.cpl'];
}
