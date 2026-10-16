import 'clean_target.dart';

/// Why a file on the shared storage is junk.
enum JunkKind {
  /// A download the browser or the store abandoned mid-flight.
  partialDownload,

  /// An APK left behind by an update or by an install that failed.
  installer,

  /// A scratch file whose name says it was never meant to survive.
  temp,
}

final _partialSuffixes = <String>[
  '.part',
  '.crdownload',
  '.opdownload',
  '.download',
];

final _tempPattern = RegExp(r'(^|_)\d*\.tmp$|^[a-z0-9]+_\d+\.tmp$');

/// Classifies a bare file name — no directory, no extension guessing.
///
/// Only three shapes are ever called junk, and every one of them is a *file the
/// system itself was still writing*: an interrupted download, an installer
/// payload, or a scratch file that named itself `.tmp`. A photo, a PDF, an MP3
/// or a SQLite database is never touched, whatever its name.
JunkKind? classifyJunkName(String name) {
  final lower = name.toLowerCase();
  if (lower.isEmpty) return null;

  for (final suffix in _partialSuffixes) {
    if (lower.endsWith(suffix)) return JunkKind.partialDownload;
  }

  if (lower.endsWith('.apk') || lower.endsWith('.apk.tmp')) {
    return JunkKind.installer;
  }

  if (_tempPattern.hasMatch(lower)) return JunkKind.temp;

  return null;
}

/// Returns `true` when a directory listing means "nothing a user can see".
///
/// Android scatters marker files around shared storage: a folder holding only
/// `.nomedia` looks empty in the file manager and is still not garbage.
bool isEmptyDirectoryListing(List<String> names) {
  for (final name in names) {
    if (name.isEmpty) continue;
    if (!name.startsWith('.')) return false;
  }
  return true;
}

String _apkBase(String name) {
  var stem = name.toLowerCase();
  if (stem.endsWith('.apk')) stem = stem.substring(0, stem.length - 4);
  return stem.replaceFirst(RegExp(r'-\d+(?:\.\d+)*$'), '');
}

/// Returns the APKs that a newer, installed copy has already superseded.
///
/// The caller declares which file is the current one. Without that declaration
/// this returns nothing at all: two APKs with the same base name may be two
/// different apps, and guessing which one the user wants would be deleting a
/// backup someone made on purpose.
List<String> obsoleteApks(
  Map<String, int> byName, {
  String? currentPackageName,
}) {
  if (currentPackageName == null) return const <String>[];
  final current = byName.containsKey(currentPackageName)
      ? currentPackageName
      : null;
  if (current == null) return const <String>[];

  final base = _apkBase(current);
  final obsolete = byName.keys
      .where((name) => name != current && _apkBase(name) == base)
      .toList()
    ..sort();
  return obsolete;
}

/// Everything OmniClean knows how to clean on Android.
///
/// Android is the honest hard case: from API 30 an app cannot read or delete
/// another app's cache. So the module is split in two — [android_app_cache_root]
/// does the full sweep but only ever with `su`, and everything else works
/// unrooted on the shared storage and on our own cache directory.
class AndroidCleaner {
  const AndroidCleaner._();

  static const String packageName = 'dev.omniclean.omni_clean_engine';
  static const String storageRoot = '/storage/emulated/0';

  static CleanTargetSet? _cached;

  static CleanTargetSet get targets => _cached ??= CleanTargetSet(_build());

  static List<CleanTarget> _build() {
    return <CleanTarget>[
      CleanTarget(
        id: 'android_app_cache_root',
        titleKey: 'targetAppCacheRootTitle',
        descriptionKey: 'targetAppCacheRootDescription',
        category: CleanCategory.appCache,
        risk: RiskLevel.elevated,
        requiresPrivilege: true,
        roots: const <String>['/data/data', '/data/user/0'],
        minAge: const Duration(days: 1),
        excludeDirectories: const <String>{'code_cache'},
      ),
      CleanTarget(
        id: 'android_app_cache_self',
        titleKey: 'targetAppCacheSelfTitle',
        descriptionKey: 'targetAppCacheSelfDescription',
        category: CleanCategory.appCache,
        risk: RiskLevel.safe,
        requiresPrivilege: false,
        roots: <String>['/data/data/$packageName/cache'],
        minAge: const Duration(minutes: 30),
      ),
      CleanTarget(
        id: 'android_downloads_junk',
        titleKey: 'targetDownloadsJunkTitle',
        descriptionKey: 'targetDownloadsJunkDescription',
        category: CleanCategory.downloads,
        risk: RiskLevel.moderate,
        requiresPrivilege: false,
        roots: const <String>[
          '$storageRoot/Download',
          '$storageRoot/Downloads',
        ],
        minAge: const Duration(days: 7),
        excludeDirectories: const <String>{'.nomedia'},
      ),
      CleanTarget(
        id: 'android_obb_leftovers',
        titleKey: 'targetObbLeftoversTitle',
        descriptionKey: 'targetObbLeftoversDescription',
        category: CleanCategory.junk,
        risk: RiskLevel.moderate,
        requiresPrivilege: false,
        roots: <String>['$storageRoot/Android/obb/$packageName'],
        minAge: const Duration(days: 30),
      ),
      CleanTarget(
        id: 'android_media_store_thumbnails',
        titleKey: 'targetMediaThumbnailsTitle',
        descriptionKey: 'targetMediaThumbnailsDescription',
        category: CleanCategory.junk,
        risk: RiskLevel.moderate,
        requiresPrivilege: false,
        roots: <String>['$storageRoot/Android/media/$packageName'],
        minAge: const Duration(days: 30),
      ),
    ];
  }
}