import 'package:flutter/foundation.dart';

/// What a device can actually do for OmniClean Engine.
///
/// On Android this is the difference between "the cleaner freed 97 KB"
/// and "the cleaner freed 9 GB", so the UI asks before it promises
/// anything. Every flag here maps to a real capability that either is
/// granted already or can be requested with a single tap.
@immutable
class StorageCapabilities {
  const StorageCapabilities({
    this.apiLevel = 0,
    this.hasAllFilesAccess = false,
    this.hasMediaRead = false,
    this.canRequestAllFiles = false,
    this.canQueryUsageStats = false,
    this.canUninstallApps = false,
    this.storageRoot = '',
    this.totalBytes = 0,
    this.freeBytes = 0,
    this.externalStorageMounted = false,
  });

  static const StorageCapabilities none = StorageCapabilities();

  final int apiLevel;

  /// `MANAGE_EXTERNAL_STORAGE` — the only way to reach `Android/data`,
  /// `.trash`, thumbnails and app residue on Android 11+.
  final bool hasAllFilesAccess;
  final bool hasMediaRead;
  final bool canRequestAllFiles;
  final bool canQueryUsageStats;
  final bool canUninstallApps;
  final String storageRoot;
  final int totalBytes;
  final int freeBytes;
  final bool externalStorageMounted;

  /// True when the engine can enumerate real files, which is the
  /// precondition for showing any number at all.
  bool get canReadAnything => hasAllFilesAccess || hasMediaRead;

  /// True when the engine can *remove* what it enumerates. Reading a
  /// number it is not allowed to act on is worse than showing nothing.
  bool get canClean => hasAllFilesAccess;

  int get usedBytes {
    if (totalBytes <= 0) return 0;
    final int delta = totalBytes - freeBytes;
    return delta < 0 ? 0 : delta;
  }

  double get usedFraction =>
      totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0).toDouble();

  StorageCapabilities copyWith({
    bool? hasAllFilesAccess,
    bool? hasMediaRead,
    bool? canRequestAllFiles,
    bool? canQueryUsageStats,
    bool? canUninstallApps,
    String? storageRoot,
    int? totalBytes,
    int? freeBytes,
    bool? externalStorageMounted,
  }) =>
      StorageCapabilities(
        apiLevel: apiLevel,
        hasAllFilesAccess: hasAllFilesAccess ?? this.hasAllFilesAccess,
        hasMediaRead: hasMediaRead ?? this.hasMediaRead,
        canRequestAllFiles: canRequestAllFiles ?? this.canRequestAllFiles,
        canQueryUsageStats: canQueryUsageStats ?? this.canQueryUsageStats,
        canUninstallApps: canUninstallApps ?? this.canUninstallApps,
        storageRoot: storageRoot ?? this.storageRoot,
        totalBytes: totalBytes ?? this.totalBytes,
        freeBytes: freeBytes ?? this.freeBytes,
        externalStorageMounted:
            externalStorageMounted ?? this.externalStorageMounted,
      );

  factory StorageCapabilities.fromMap(Map<Object?, Object?> map) {
    int readInt(String key) {
      final Object? value = map[key];
      if (value is! num) return 0;
      // A negative capacity is not a thing; clamping here keeps a hostile or
      // buggy native payload from turning into a negative "freed" figure.
      final int parsed = value.toInt();
      return parsed < 0 ? 0 : parsed;
    }

    bool readBool(String key) => map[key] == true;

    return StorageCapabilities(
      apiLevel: readInt('apiLevel'),
      hasAllFilesAccess: readBool('hasAllFilesAccess'),
      hasMediaRead: readBool('hasMediaRead'),
      canRequestAllFiles: readBool('canRequestAllFiles'),
      canQueryUsageStats: readBool('canQueryUsageStats'),
      canUninstallApps: readBool('canUninstallApps'),
      storageRoot:
          map['storageRoot'] is String ? map['storageRoot']! as String : '',
      totalBytes: readInt('totalBytes'),
      freeBytes: readInt('freeBytes'),
      externalStorageMounted: readBool('externalStorageMounted'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StorageCapabilities &&
      other.apiLevel == apiLevel &&
      other.hasAllFilesAccess == hasAllFilesAccess &&
      other.hasMediaRead == hasMediaRead &&
      other.canRequestAllFiles == canRequestAllFiles &&
      other.canQueryUsageStats == canQueryUsageStats &&
      other.canUninstallApps == canUninstallApps &&
      other.storageRoot == storageRoot &&
      other.totalBytes == totalBytes &&
      other.freeBytes == freeBytes &&
      other.externalStorageMounted == externalStorageMounted;

  @override
  int get hashCode => Object.hash(
        apiLevel,
        hasAllFilesAccess,
        hasMediaRead,
        canRequestAllFiles,
        canQueryUsageStats,
        canUninstallApps,
        storageRoot,
        totalBytes,
        freeBytes,
        externalStorageMounted,
      );
}

/// The buckets of reclaimable data the engine understands.
///
/// Every one of these is a real query against a real system database,
/// never a guess about a path that might not be readable.
enum JunkKind {
  /// Files the user already sent to the system trash and never emptied.
  trashed,

  /// Installers of apps that are still installed, and installers whose app
  /// is gone. Both are dead weight the moment the app runs.
  obsoleteInstaller,

  /// Partial and temporary downloads: `.part`, `.crdownload`, `.opdownload`,
  /// `.tmp`, `.download`, plus the half-written files app updaters leave.
  partialDownload,

  /// Caches written inside `Android/data` and `Android/obb` by apps that
  /// are no longer installed, plus the thumbnails Android regenerates.
  appResidue,

  /// Old screenshots. Phones fill up with them faster than anything else.
  screenshots,

  /// Duplicate images the engine found by content, not by name.
  duplicateMedia,

  /// Empty directories, `.nomedia` folders with nothing inside, log files.
  emptyFolder,

  /// System and app log files older than the retention window.
  logs,
}

/// One real, resolvable file on the device.
@immutable
class StorageEntry {
  const StorageEntry({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
    required this.kind,
    this.mimeType = '',
    this.isDirectory = false,
    this.packageName = '',
  });

  /// Stable handle the native side can resolve back to a content URI.
  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modified;
  final JunkKind kind;
  final String mimeType;
  final bool isDirectory;

  /// Set only for [JunkKind.appResidue]: the package that left this behind.
  final String packageName;

  factory StorageEntry.fromMap(Map<Object?, Object?> map) => StorageEntry(
        id: map['id'] is String ? map['id']! as String : '',
        name: map['name'] is String ? map['name']! as String : '',
        path: map['path'] is String ? map['path']! as String : '',
        sizeBytes:
            map['sizeBytes'] is num ? (map['sizeBytes']! as num).toInt() : 0,
        modified: DateTime.fromMillisecondsSinceEpoch(
          map['modifiedMillis'] is num
              ? (map['modifiedMillis']! as num).toInt()
              : 0,
        ),
        kind: _kindFrom(map['kind']),
        mimeType: map['mimeType'] is String ? map['mimeType']! as String : '',
        isDirectory: map['isDirectory'] == true,
        packageName:
            map['packageName'] is String ? map['packageName']! as String : '',
      );

  static JunkKind _kindFrom(Object? raw) {
    final String name = raw is String ? raw : '';
    for (final JunkKind kind in JunkKind.values) {
      if (kind.name == name) return kind;
    }
    return JunkKind.logs;
  }

  @override
  bool operator ==(Object other) =>
      other is StorageEntry &&
      other.id == id &&
      other.path == path &&
      other.sizeBytes == sizeBytes &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, path, sizeBytes, kind);
}

/// Reclaimable bytes grouped by bucket, so the cleaner screen can show a
/// breakdown instead of one opaque total.
@immutable
class JunkSummary {
  const JunkSummary({
    this.entries = const <StorageEntry>[],
    this.reportedTotalBytes,
    this.scannedEntries = 0,
    this.capped = false,
  });

  static const JunkSummary empty = JunkSummary();

  final List<StorageEntry> entries;

  /// What the native side claimed. The UI trusts the entries, because a
  /// total that disagrees with the list the user is looking at is worse than
  /// no total at all.
  final int? reportedTotalBytes;

  final int scannedEntries;

  /// True when the native side stopped early instead of scanning the whole
  /// device. The UI must say so rather than pretending the total is final.
  final bool capped;

  bool get isEmpty => entries.isEmpty;

  /// Summed from the entries on every call, so a summary built by hand in a
  /// test or a fake can never claim a total its own list contradicts.
  int get totalBytes {
    var sum = 0;
    for (final StorageEntry entry in entries) {
      sum += entry.sizeBytes < 0 ? 0 : entry.sizeBytes;
    }
    return sum;
  }

  Map<JunkKind, int> get byKind {
    final Map<JunkKind, int> totals = <JunkKind, int>{};
    for (final StorageEntry entry in entries) {
      totals[entry.kind] = (totals[entry.kind] ?? 0) + entry.sizeBytes;
    }
    return totals;
  }

  List<StorageEntry> ofKind(JunkKind kind) =>
      entries.where((StorageEntry e) => e.kind == kind).toList(growable: false);

  factory JunkSummary.fromMap(Map<Object?, Object?> map) {
    final Object? raw = map['entries'];
    final List<StorageEntry> parsed = <StorageEntry>[];
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is Map) parsed.add(StorageEntry.fromMap(item));
      }
    }
    return JunkSummary(
      entries: parsed,
      reportedTotalBytes:
          map['totalBytes'] is num ? (map['totalBytes']! as num).toInt() : null,
      scannedEntries: map['scannedEntries'] is num
          ? (map['scannedEntries']! as num).toInt()
          : parsed.length,
      capped: map['capped'] == true,
    );
  }
}

/// One installed application and how long it has been sitting there unused.
@immutable
class AppUsage {
  const AppUsage({
    required this.packageName,
    required this.label,
    required this.sizeBytes,
    required this.lastUsed,
    this.versionName = '',
    this.isSystem = false,
    this.installedMillis = 0,
  });

  final String packageName;
  final String label;
  final int sizeBytes;

  /// Zero means the system has never seen it used, which is the strongest
  /// possible signal that nobody wants it.
  final DateTime lastUsed;

  final String versionName;
  final bool isSystem;
  final int installedMillis;

  int get unusedDays {
    if (lastUsed.millisecondsSinceEpoch <= 0) return 9999;
    final int days = (DateTime.now().millisecondsSinceEpoch -
            lastUsed.millisecondsSinceEpoch) ~/
        86400000;
    return days < 0 ? 0 : days;
  }

  factory AppUsage.fromMap(Map<Object?, Object?> map) => AppUsage(
        packageName:
            map['packageName'] is String ? map['packageName']! as String : '',
        label: map['label'] is String ? map['label']! as String : '',
        sizeBytes:
            map['sizeBytes'] is num ? (map['sizeBytes']! as num).toInt() : 0,
        lastUsed: DateTime.fromMillisecondsSinceEpoch(
          map['lastUsedMillis'] is num
              ? (map['lastUsedMillis']! as num).toInt()
              : 0,
        ),
        versionName:
            map['versionName'] is String ? map['versionName']! as String : '',
        isSystem: map['isSystem'] == true,
        installedMillis: map['installedMillis'] is num
            ? (map['installedMillis']! as num).toInt()
            : 0,
      );

  @override
  bool operator ==(Object other) =>
      other is AppUsage &&
      other.packageName == packageName &&
      other.sizeBytes == sizeBytes &&
      other.lastUsed == lastUsed;

  @override
  int get hashCode => Object.hash(packageName, sizeBytes, lastUsed);
}

/// One media file for the photos and files browsers.
@immutable
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
    this.mimeType = '',
    this.width = 0,
    this.height = 0,
    this.durationMillis = 0,
  });

  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modified;
  final String mimeType;
  final int width;
  final int height;
  final int durationMillis;

  bool get isVideo => mimeType.startsWith('video/');
  bool get isImage => mimeType.startsWith('image/');

  factory MediaItem.fromMap(Map<Object?, Object?> map) => MediaItem(
        id: map['id'] is String ? map['id']! as String : '',
        name: map['name'] is String ? map['name']! as String : '',
        path: map['path'] is String ? map['path']! as String : '',
        sizeBytes:
            map['sizeBytes'] is num ? (map['sizeBytes']! as num).toInt() : 0,
        modified: DateTime.fromMillisecondsSinceEpoch(
          map['modifiedMillis'] is num
              ? (map['modifiedMillis']! as num).toInt()
              : 0,
        ),
        mimeType: map['mimeType'] is String ? map['mimeType']! as String : '',
        width: map['width'] is num ? (map['width']! as num).toInt() : 0,
        height: map['height'] is num ? (map['height']! as num).toInt() : 0,
        durationMillis: map['durationMillis'] is num
            ? (map['durationMillis']! as num).toInt()
            : 0,
      );
}

/// What a boost run actually did, measured before and after.
///
/// The promise "your device is faster" is worthless without a number, so
/// the result always carries the before/after pair the UI shows.
@immutable
class BoostReport {
  const BoostReport({
    this.freedBytes = 0,
    this.killedProcesses = 0,
    this.droppedCaches = false,
    this.cpuBefore = 0,
    this.cpuAfter = 0,
    this.memoryBeforeBytes = 0,
    this.memoryAfterBytes = 0,
    this.actions = const <String>[],
    this.unavailableReason = '',
  });

  static const BoostReport nothing = BoostReport();

  final int freedBytes;
  final int killedProcesses;
  final bool droppedCaches;

  /// Busy fraction in `0..1`, sampled immediately before and after.
  final double cpuBefore;
  final double cpuAfter;

  /// Memory the kernel could hand back, before and after.
  final int memoryBeforeBytes;
  final int memoryAfterBytes;

  /// Human-readable list of what ran, for the UI to show verbatim.
  final List<String> actions;

  /// Set when the platform refused: the honest answer is "not here", never
  /// a fake success bar.
  final String unavailableReason;

  bool get didAnything =>
      freedBytes > 0 ||
      killedProcesses > 0 ||
      droppedCaches ||
      actions.isNotEmpty;

  int get memoryReclaimedBytes {
    final int delta = memoryBeforeBytes - memoryAfterBytes;
    return delta < 0 ? 0 : delta;
  }

  factory BoostReport.fromMap(Map<Object?, Object?> map) {
    final Object? raw = map['actions'];
    final List<String> actions = <String>[];
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is String) actions.add(item);
      }
    }
    return BoostReport(
      freedBytes:
          map['freedBytes'] is num ? (map['freedBytes']! as num).toInt() : 0,
      killedProcesses: map['killedProcesses'] is num
          ? (map['killedProcesses']! as num).toInt()
          : 0,
      droppedCaches: map['droppedCaches'] == true,
      cpuBefore:
          map['cpuBefore'] is num ? (map['cpuBefore']! as num).toDouble() : 0,
      cpuAfter:
          map['cpuAfter'] is num ? (map['cpuAfter']! as num).toDouble() : 0,
      memoryBeforeBytes: map['memoryBeforeBytes'] is num
          ? (map['memoryBeforeBytes']! as num).toInt()
          : 0,
      memoryAfterBytes: map['memoryAfterBytes'] is num
          ? (map['memoryAfterBytes']! as num).toInt()
          : 0,
      actions: actions,
      unavailableReason: map['unavailableReason'] is String
          ? map['unavailableReason']! as String
          : '',
    );
  }
}

/// The seam between the app and whatever the operating system actually
/// offers. Desktop and web run against [_UnsupportedStorageGateway]; Android
/// runs against the real MediaStore bridge; tests run against a fake.
///
/// Every method degrades to an honest "nothing here" instead of throwing,
/// because a cleaner that crashes is exactly the failure this project
/// exists to avoid.
abstract class StorageGateway {
  const StorageGateway();

  Future<StorageCapabilities> capabilities();

  Future<JunkSummary> scanJunk({Duration minAge = const Duration(days: 7)});

  Future<void> deleteEntries(List<String> ids);

  Future<void> emptyTrash();

  Future<List<MediaItem>> media({MediaKind kind = MediaKind.photos});

  /// Every media file on the device that is big enough to be worth hashing,
  /// as a flat list with a real path the hasher can open.
  ///
  /// This is what makes the duplicate finder work with zero setup: the user
  /// never picks a folder, the platform hands over the whole library, and
  /// [DuplicateFinder.scanFiles] runs the same three verification passes over
  /// it that it runs over a walked disk. A platform with no media store (or no
  /// permission to read one) returns an empty list rather than a guess.
  Future<List<StorageEntry>> mediaFiles({int minSizeBytes = 4 * 1024}) async =>
      const <StorageEntry>[];

  Future<List<AppUsage>> unusedApps({int unusedDays = 30});

  Future<void> launchUninstall(String packageName);

  Future<BoostReport> boost();

  /// Requests the runtime grants the device is missing. Returns the
  /// capabilities as they stand afterwards.
  Future<StorageCapabilities> requestAccess();

  /// Lists directories the user may want to clean outside the system
  /// databases. Android has none; desktop does.
  Future<List<String>> browsableRoots() async => const <String>[];
}

/// Which media library to page through.
enum MediaKind { photos, videos, audio, documents, downloads, allFiles }

/// Presentation and platform-transport details for a [MediaKind].
///
/// [allFiles] is not a real MediaStore table: it is the union a user means by
/// "Files", and the controller asks for its two halves and merges them.
/// [wire] is what crosses the bridge.
extension MediaKindX on MediaKind {
  String get wire => switch (this) {
        MediaKind.photos => 'photos',
        MediaKind.videos => 'videos',
        MediaKind.audio => 'audio',
        MediaKind.documents => 'documents',
        MediaKind.downloads => 'downloads',
        MediaKind.allFiles => 'documents',
      };

  String get label => switch (this) {
        MediaKind.photos => 'Photos',
        MediaKind.videos => 'Videos',
        MediaKind.audio => 'Audio',
        MediaKind.documents => 'Documents',
        MediaKind.downloads => 'Downloads',
        MediaKind.allFiles => 'All files',
      };

  /// The tables that make up this view, in merge order.
  List<MediaKind> get sources => switch (this) {
        MediaKind.allFiles => const <MediaKind>[
            MediaKind.documents,
            MediaKind.downloads,
          ],
        _ => <MediaKind>[this],
      };
}
