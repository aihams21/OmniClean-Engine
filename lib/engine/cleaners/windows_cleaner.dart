import 'dart:io';

import 'clean_target.dart';

/// Expands `%VAR%` placeholders using [environment] and returns a path that is
/// always absolute.
///
/// Windows tooling writes caches with environment variables baked in, so the
/// target definitions stay readable (`%LOCALAPPDATA%\Temp`) and the real path
/// is only computed once, where the environment is actually known. Windows
/// environment names are case-insensitive, and so is this lookup.
String resolveWindowsRoot(String root,
    {required Map<String, String?> environment}) {
  final lookup = <String, String>{};
  environment.forEach((key, value) {
    if (value != null) lookup[key.toUpperCase()] = value;
  });

  var out = root;
  for (var i = 0; i < 8; i++) {
    final match = RegExp('%([A-Za-z_][A-Za-z0-9_]*)%').firstMatch(out);
    if (match == null) break;
    final value = lookup[match.group(1)!.toUpperCase()];
    if (value == null) break;
    out = out.replaceAll(match.group(0)!, value);
  }

  out = out.replaceAll('/', '\\');
  while (out.contains('\\\\')) {
    out = out.replaceAll('\\\\', '\\');
  }
  if (out.length > 3 && out.endsWith('\\')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

/// Everything OmniClean knows how to clean on Windows.
///
/// Roots are written with `%VAR%` placeholders and resolved at runtime by
/// [resolveWindowsRoot]. Only the sub-trees that `ProtectedPaths` explicitly
/// whitelists inside `C:\Windows` are listed — a target that can never pass the
/// deny-list is a target that would only ever report a lie.
class WindowsCleaner {
  const WindowsCleaner._();

  static CleanTargetSet? _cached;

  static CleanTargetSet get targets => _cached ??= CleanTargetSet(_build());

  static List<CleanTarget> _build() {
    return <CleanTarget>[
      CleanTarget(
        id: 'windows_user_temp',
        titleKey: 'targetUserTempTitle',
        descriptionKey: 'targetUserTempDescription',
        category: CleanCategory.temp,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: const <String>['%TEMP%', '%LOCALAPPDATA%\Temp'],
        minAge: const Duration(hours: 1),
      ),
      CleanTarget(
        id: 'windows_temp',
        titleKey: 'targetWindowsTempTitle',
        descriptionKey: 'targetWindowsTempDescription',
        category: CleanCategory.temp,
        risk: RiskLevel.moderate,
        requiresPrivilege: true,
        roots: const <String>['%WINDIR%\Temp'],
        minAge: const Duration(days: 1),
      ),
      CleanTarget(
        id: 'windows_edge_cache',
        titleKey: 'targetEdgeCacheTitle',
        descriptionKey: 'targetEdgeCacheDescription',
        category: CleanCategory.browser,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: const <String>[
          '%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache',
          '%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Code Cache',
          '%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\GPUCache',
          '%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage',
        ],
        minAge: const Duration(hours: 1),
      ),
      CleanTarget(
        id: 'windows_chrome_cache',
        titleKey: 'targetChromeCacheTitle',
        descriptionKey: 'targetChromeCacheDescription',
        category: CleanCategory.browser,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: const <String>[
          '%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache',
          '%LOCALAPPDATA%\Google\Chrome\User Data\Default\Code Cache',
          '%LOCALAPPDATA%\Google\Chrome\User Data\Default\GPUCache',
          '%LOCALAPPDATA%\Google\Chrome\User Data\Default\Service Worker\CacheStorage',
        ],
        minAge: const Duration(hours: 1),
      ),
      CleanTarget(
        id: 'windows_firefox_cache',
        titleKey: 'targetFirefoxCacheTitle',
        descriptionKey: 'targetFirefoxCacheDescription',
        category: CleanCategory.browser,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: const <String>['%LOCALAPPDATA%\Mozilla\Firefox\Profiles'],
        minAge: const Duration(days: 1),
        excludeDirectories: const <String>{
          'storage',
          'datareporting',
          'crashes'
        },
      ),
      CleanTarget(
        id: 'windows_event_logs',
        titleKey: 'targetEventLogsTitle',
        descriptionKey: 'targetEventLogsDescription',
        category: CleanCategory.logs,
        risk: RiskLevel.moderate,
        requiresPrivilege: true,
        roots: const <String>[
          '%WINDIR%\Logs',
          '%WINDIR%\System32\LogFiles',
          '%WINDIR%\System32\winevt\Logs',
        ],
        minAge: const Duration(days: 7),
      ),
      CleanTarget(
        id: 'windows_error_reporting',
        titleKey: 'targetErrorReportingTitle',
        descriptionKey: 'targetErrorReportingDescription',
        category: CleanCategory.dumps,
        risk: RiskLevel.moderate,
        requiresPrivilege: false,
        roots: const <String>[
          '%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive',
          '%LOCALAPPDATA%\Microsoft\Windows\WER\ReportQueue',
          '%LOCALAPPDATA%\CrashDumps',
        ],
        minAge: const Duration(days: 7),
      ),
      CleanTarget(
        id: 'windows_minidumps',
        titleKey: 'targetMinidumpsTitle',
        descriptionKey: 'targetMinidumpsDescription',
        category: CleanCategory.dumps,
        risk: RiskLevel.moderate,
        requiresPrivilege: true,
        roots: const <String>[
          '%WINDIR%\Minidump',
          '%WINDIR%\LiveKernelReports'
        ],
        minAge: const Duration(days: 7),
      ),
      CleanTarget(
        id: 'windows_update_download',
        titleKey: 'targetUpdateDownloadTitle',
        descriptionKey: 'targetUpdateDownloadDescription',
        category: CleanCategory.updates,
        risk: RiskLevel.elevated,
        requiresPrivilege: true,
        roots: const <String>['%WINDIR%\SoftwareDistribution\Download'],
        minAge: const Duration(days: 2),
      ),
      CleanTarget(
        id: 'windows_delivery_optimization',
        titleKey: 'targetDeliveryOptimizationTitle',
        descriptionKey: 'targetDeliveryOptimizationDescription',
        category: CleanCategory.updates,
        risk: RiskLevel.elevated,
        requiresPrivilege: true,
        roots: const <String>[
          '%WINDIR%\SoftwareDistribution\DeliveryOptimization',
        ],
        minAge: const Duration(days: 2),
      ),
      CleanTarget(
        id: 'windows_installer_pending',
        titleKey: 'targetInstallerPendingTitle',
        descriptionKey: 'targetInstallerPendingDescription',
        category: CleanCategory.updates,
        risk: RiskLevel.elevated,
        requiresPrivilege: true,
        roots: const <String>['%WINDIR%\INF\Pending'],
        minAge: const Duration(days: 2),
      ),
      CleanTarget(
        id: 'windows_setup_logs',
        titleKey: 'targetSetupLogsTitle',
        descriptionKey: 'targetSetupLogsDescription',
        category: CleanCategory.logs,
        risk: RiskLevel.moderate,
        requiresPrivilege: true,
        roots: const <String>['%WINDIR%\Panther'],
        minAge: const Duration(days: 7),
      ),
    ];
  }

  /// Resolves every target root for the live environment.
  static CleanTargetSet resolve({Map<String, String?>? environment}) {
    final env = environment ?? _liveEnvironment();
    final resolved = targets.targets
        .map(
          (target) => CleanTarget(
            id: target.id,
            titleKey: target.titleKey,
            descriptionKey: target.descriptionKey,
            category: target.category,
            risk: target.risk,
            requiresPrivilege: target.requiresPrivilege,
            roots: target.roots
                .map((r) => resolveWindowsRoot(r, environment: env))
                .toList(growable: false),
            minAge: target.minAge,
            includeHidden: target.includeHidden,
            excludeDirectories: target.excludeDirectories,
            extensions: target.extensions,
            excludeExtensions: target.excludeExtensions,
            maxDepth: target.maxDepth,
            capBytes: target.capBytes,
          ),
        )
        .toList(growable: false);
    return CleanTargetSet(resolved);
  }
}

/// `dart:io`'s environment as the nullable map [resolveWindowsRoot] expects.
Map<String, String?> _liveEnvironment() {
  const keys = <String>[
    'LOCALAPPDATA',
    'APPDATA',
    'WINDIR',
    'SystemDrive',
    'SystemRoot',
    'TEMP',
    'TMP',
    'ProgramData',
    'USERPROFILE',
  ];
  final map = <String, String?>{};
  for (final key in keys) {
    map[key] = Platform.environment[key];
  }
  return map;
}
