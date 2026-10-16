import 'dart:io';

import '../../core/util/logger.dart';
import '../shell.dart';
import 'apt_parsers.dart';
import 'clean_target.dart';

/// Everything OmniClean knows how to clean on a Debian-family Linux box.
///
/// The list is data, not code: [DirectorySweeper] walks each target's roots and
/// [SafeDelete] re-validates every single file, so adding a target here can
/// never widen what the app is allowed to delete beyond the roots it declares.
class LinuxCleaner {
  const LinuxCleaner._();

  static CleanTargetSet? _cached;

  static CleanTargetSet get targets => _cached ??= CleanTargetSet(_build());

  static List<CleanTarget> _build() {
    final home = Platform.environment['HOME'] ?? '/root';
    final xdgCache = Platform.environment['XDG_CACHE_HOME'] ?? '$home/.cache';
    final xdgData = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';

    return <CleanTarget>[
      CleanTarget(
        id: 'linux_apt_archive',
        titleKey: 'targetAptArchiveTitle',
        descriptionKey: 'targetAptArchiveDescription',
        category: CleanCategory.packageCache,
        risk: RiskLevel.moderate,
        requiresPrivilege: true,
        roots: const <String>['/var/cache/apt/archives'],
        minAge: const Duration(hours: 24),
        extensions: const <String>{'.deb', '.partial'},
        excludeDirectories: const <String>{'partial'},
      ),
      CleanTarget(
        id: 'linux_apt_lists',
        titleKey: 'targetAptListsTitle',
        descriptionKey: 'targetAptListsDescription',
        category: CleanCategory.packageCache,
        risk: RiskLevel.moderate,
        requiresPrivilege: true,
        roots: const <String>['/var/lib/apt/lists'],
        minAge: const Duration(hours: 24),
        extensions: const <String>{'.lz4', '.gz', '.xz', '.bz2'},
      ),
      CleanTarget(
        id: 'linux_journal',
        titleKey: 'targetJournalTitle',
        descriptionKey: 'targetJournalDescription',
        category: CleanCategory.logs,
        risk: RiskLevel.elevated,
        requiresPrivilege: true,
        roots: <String>[
          '/var/log/journal',
          '/run/log/journal',
          '$home/.local/share/systemd/journal',
        ],
        minAge: const Duration(days: 7),
        excludeDirectories: const <String>{'@'},
      ),
      CleanTarget(
        id: 'linux_crash_reports',
        titleKey: 'targetCrashReportsTitle',
        descriptionKey: 'targetCrashReportsDescription',
        category: CleanCategory.dumps,
        risk: RiskLevel.moderate,
        requiresPrivilege: true,
        roots: const <String>['/var/crash'],
        minAge: const Duration(days: 1),
      ),
      CleanTarget(
        id: 'linux_tmp',
        titleKey: 'targetTmpTitle',
        descriptionKey: 'targetTmpDescription',
        category: CleanCategory.temp,
        risk: RiskLevel.moderate,
        requiresPrivilege: true,
        roots: const <String>['/tmp', '/var/tmp'],
        minAge: const Duration(days: 1),
        excludeDirectories: const <String>{
          'systemd-private-',
          '.X11-unix',
          '.ICE-unix',
          '.XIM-unix',
          'hsperfdata_root',
          'snap-private-tmp',
        },
      ),
      CleanTarget(
        id: 'linux_home_cache',
        titleKey: 'targetHomeCacheTitle',
        descriptionKey: 'targetHomeCacheDescription',
        category: CleanCategory.appCache,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: <String>[xdgCache],
        minAge: const Duration(hours: 1),
      ),
      CleanTarget(
        id: 'linux_user_journal',
        titleKey: 'targetUserJournalTitle',
        descriptionKey: 'targetUserJournalDescription',
        category: CleanCategory.logs,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: <String>['$xdgData/systemd/journal'],
        minAge: const Duration(days: 7),
      ),
      CleanTarget(
        id: 'linux_trash',
        titleKey: 'targetTrashTitle',
        descriptionKey: 'targetTrashDescription',
        category: CleanCategory.temp,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: <String>['$xdgData/Trash/files'],
        minAge: const Duration(days: 1),
      ),
      CleanTarget(
        id: 'linux_flatpak_cache',
        titleKey: 'targetFlatpakCacheTitle',
        descriptionKey: 'targetFlatpakCacheDescription',
        category: CleanCategory.appCache,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: <String>['$xdgCache/flatpak'],
        minAge: const Duration(days: 1),
      ),
      CleanTarget(
        id: 'linux_thumbnails',
        titleKey: 'targetThumbnailsTitle',
        descriptionKey: 'targetThumbnailsDescription',
        category: CleanCategory.appCache,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: <String>['$xdgCache/thumbnails'],
        minAge: const Duration(days: 1),
      ),
    ];
  }

  /// Asks apt what `autoremove` *would* remove. Never mutates the system.
  static Future<AptSimulatePlan> simulateAutoremove({int timeoutSeconds = 45}) async {
    final result = await Shell.run('apt-get', <String>[
      '-s',
      'autoremove',
    ], timeout: Duration(seconds: timeoutSeconds));
    if (!result.ok) {
      log.warn('apt simulate failed: ${result.stderr}');
    }
    return parseAptSimulate(result.stdout);
  }

  /// Actually runs `apt-get autoremove`. Requires root and is therefore only
  /// reachable from a privileged session.
  static Future<ShellResult> runAutoremove({int timeoutSeconds = 600}) {
    return Shell.runPrivileged(
      'DEBIAN_FRONTEND=noninteractive apt-get -y autoremove',
      timeout: Duration(seconds: timeoutSeconds),
    );
  }

  /// Bytes the systemd journal occupies, or 0 when journald is not running.
  static Future<int> journalBytes({int timeoutSeconds = 15}) async {
    final result = await Shell.run(
      'journalctl',
      <String>['--disk-usage'],
      timeout: Duration(seconds: timeoutSeconds),
    );
    if (!result.ok) return 0;
    return parseJournalDiskUsage(result.stdout);
  }
}