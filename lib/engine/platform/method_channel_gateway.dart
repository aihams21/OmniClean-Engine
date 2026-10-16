import 'package:flutter/services.dart';

import '../../core/util/logger.dart';
import 'storage_gateway.dart';

/// Talks to the Kotlin side over a [MethodChannel].
///
/// Everything is wrapped: a missing plugin (tests, desktop) and a real
/// platform failure both surface as an honest empty result plus a log line,
/// never as an exception escaping into the UI.
class MethodChannelStorageGateway extends StorageGateway {
  const MethodChannelStorageGateway([this.channel = defaultChannel]);

  static const MethodChannel defaultChannel =
      MethodChannel('dev.omniclean.engine/storage');

  static const String channelName = 'dev.omniclean.engine/storage';

  final MethodChannel channel;

  @override
  Future<StorageCapabilities> capabilities() async {
    final Map<Object?, Object?> raw = await _map('capabilities');
    return raw.isEmpty
        ? StorageCapabilities.none
        : StorageCapabilities.fromMap(raw);
  }

  @override
  Future<JunkSummary> scanJunk(
      {Duration minAge = const Duration(days: 7)}) async {
    final Map<Object?, Object?> raw =
        await _map('scanJunk', <String, Object?>{'minAgeDays': minAge.inDays});
    return raw.isEmpty ? JunkSummary.empty : JunkSummary.fromMap(raw);
  }

  @override
  Future<void> deleteEntries(List<String> ids) async {
    if (ids.isEmpty) return;
    await _map('deleteEntries', <String, Object?>{'ids': ids});
  }

  @override
  Future<void> emptyTrash() async {
    await _map('emptyTrash');
  }

  @override
  Future<List<MediaItem>> media({MediaKind kind = MediaKind.photos}) async {
    final Map<Object?, Object?> raw = await _map(
      'media',
      <String, Object?>{'kind': kind.name, 'limit': 500},
    );
    final Object? list = raw['items'];
    if (list is! List) return const <MediaItem>[];
    return list
        .whereType<Map<Object?, Object?>>()
        .map(MediaItem.fromMap)
        .toList(growable: false);
  }

  @override
  Future<List<StorageEntry>> mediaFiles({int minSizeBytes = 4 * 1024}) async {
    final Map<Object?, Object?> raw = await _map(
      'mediaFiles',
      <String, Object?>{'minSizeBytes': minSizeBytes},
    );
    final Object? list = raw['entries'];
    if (list is! List) return const <StorageEntry>[];
    return list
        .whereType<Map<Object?, Object?>>()
        .map(StorageEntry.fromMap)
        .toList(growable: false);
  }

  @override
  Future<List<AppUsage>> unusedApps({int unusedDays = 30}) async {
    final Map<Object?, Object?> raw =
        await _map('unusedApps', <String, Object?>{'unusedDays': unusedDays});
    final Object? list = raw['apps'];
    if (list is! List) return const <AppUsage>[];
    final List<AppUsage> apps = list
        .whereType<Map<Object?, Object?>>()
        .map(AppUsage.fromMap)
        .toList(growable: false);
    apps.sort((AppUsage a, AppUsage b) {
      final int byDays = b.unusedDays.compareTo(a.unusedDays);
      return byDays != 0 ? byDays : b.sizeBytes.compareTo(a.sizeBytes);
    });
    return apps;
  }

  @override
  Future<void> launchUninstall(String packageName) async {
    await _map(
        'launchUninstall', <String, Object?>{'packageName': packageName});
  }

  @override
  Future<BoostReport> boost() async {
    final Map<Object?, Object?> raw = await _map('boost');
    return raw.isEmpty ? BoostReport.nothing : BoostReport.fromMap(raw);
  }

  @override
  Future<StorageCapabilities> requestAccess() async {
    final Map<Object?, Object?> raw = await _map('requestAccess');
    return raw.isEmpty
        ? StorageCapabilities.none
        : StorageCapabilities.fromMap(raw);
  }

  Future<Map<Object?, Object?>> _map(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final Object? result = await channel.invokeMethod<Object?>(
        method,
        arguments,
      );
      if (result is Map) return result.cast<Object?, Object?>();
      return const <Object?, Object?>{};
    } on PlatformException catch (error) {
      log.warn('storage: $method failed — ${error.code}: ${error.message}');
      return const <Object?, Object?>{};
    } on MissingPluginException {
      // Expected on desktop and in tests: the channel has no native side.
      return const <Object?, Object?>{};
    }
  }
}

/// The gateway used everywhere the operating system will not talk to us.
///
/// It reports `canReadAnything == false`, which every screen uses to switch
/// from "0 bytes" to "this platform cannot do that here" — the honest
/// difference between a device with nothing to clean and a device where
/// the engine is blind.
class UnsupportedStorageGateway extends StorageGateway {
  const UnsupportedStorageGateway(
      [this.reason = 'Not available on this platform']);

  final String reason;

  @override
  Future<StorageCapabilities> capabilities() async =>
      const StorageCapabilities(storageRoot: '', externalStorageMounted: false);

  @override
  Future<JunkSummary> scanJunk(
          {Duration minAge = const Duration(days: 7)}) async =>
      JunkSummary.empty;

  @override
  Future<void> deleteEntries(List<String> ids) async {}

  @override
  Future<void> emptyTrash() async {}

  @override
  Future<List<MediaItem>> media({MediaKind kind = MediaKind.photos}) async =>
      const <MediaItem>[];

  @override
  Future<List<AppUsage>> unusedApps({int unusedDays = 30}) async =>
      const <AppUsage>[];

  @override
  Future<void> launchUninstall(String packageName) async {}

  @override
  Future<BoostReport> boost() async => BoostReport(unavailableReason: reason);

  @override
  Future<StorageCapabilities> requestAccess() async => capabilities();
}

/// A gateway with fixed contents, for tests and for the walkthrough capture.
class FakeStorageGateway extends StorageGateway {
  FakeStorageGateway({
    this.capability = const StorageCapabilities(
      apiLevel: 34,
      hasAllFilesAccess: true,
      hasMediaRead: true,
      canRequestAllFiles: true,
      canQueryUsageStats: true,
      canUninstallApps: true,
      storageRoot: '/storage/emulated/0',
      totalBytes: 128000000000,
      freeBytes: 64000000000,
      externalStorageMounted: true,
    ),
    List<StorageEntry> entries = const <StorageEntry>[],
    this.applications = const <AppUsage>[],
    this.mediaItems = const <MediaItem>[],
    List<StorageEntry> mediaLibrary = const <StorageEntry>[],
    this.boostReport = BoostReport.nothing,
    this.roots = const <String>[],
    List<String>? deleted,
  })  : entries = List<StorageEntry>.of(entries),
        mediaLibrary = List<StorageEntry>.of(mediaLibrary),
        deletedIds = deleted ?? <String>[];

  StorageCapabilities capability;
  List<StorageEntry> entries;
  List<AppUsage> applications;
  List<MediaItem> mediaItems;

  /// The whole media library, as a flat list with real paths — what the
  /// duplicate finder hashes when the user never picks a folder.
  List<StorageEntry> mediaLibrary;

  BoostReport boostReport;
  List<String> roots;
  final List<String> deletedIds;

  int emptiedTrash = 0;
  String? uninstallRequested;

  @override
  Future<StorageCapabilities> capabilities() async => capability;

  @override
  Future<JunkSummary> scanJunk(
      {Duration minAge = const Duration(days: 7)}) async {
    return JunkSummary(
      entries: List<StorageEntry>.unmodifiable(entries),
      scannedEntries: entries.length,
    );
  }

  @override
  Future<void> deleteEntries(List<String> ids) async {
    deletedIds.addAll(ids);
    entries = entries
        .where((StorageEntry e) => !ids.contains(e.id))
        .toList(growable: false);
  }

  @override
  Future<void> emptyTrash() async {
    emptiedTrash++;
    entries = entries
        .where((StorageEntry e) => e.kind != JunkKind.trashed)
        .toList(growable: false);
  }

  @override
  Future<List<MediaItem>> media({MediaKind kind = MediaKind.photos}) async {
    // The fake has to behave like the platform, or every library that is not
    // "photos" or "videos" silently returns the whole device and the merged
    // "Files" view counts each file twice.
    bool image(MediaItem m) => m.isImage;
    bool video(MediaItem m) => m.isVideo;
    bool audio(MediaItem m) => m.mimeType.startsWith('audio/');
    bool document(MediaItem m) =>
        !image(m) && !video(m) && !audio(m) && !m.path.contains('/Download/');
    bool download(MediaItem m) => m.path.contains('/Download/');
    final bool Function(MediaItem) keep = switch (kind) {
      MediaKind.photos => image,
      MediaKind.videos => video,
      MediaKind.audio => audio,
      MediaKind.documents => document,
      MediaKind.downloads => download,
      MediaKind.allFiles => (MediaItem m) => true,
    };
    return mediaItems.where(keep).toList(growable: false);
  }

  @override
  Future<List<StorageEntry>> mediaFiles({int minSizeBytes = 4 * 1024}) async =>
      mediaLibrary
          .where((StorageEntry e) => e.sizeBytes >= minSizeBytes)
          .toList(growable: false);

  @override
  Future<List<AppUsage>> unusedApps({int unusedDays = 30}) async {
    final List<AppUsage> filtered = applications
        .where((AppUsage a) => a.unusedDays >= unusedDays)
        .toList(growable: false);
    filtered
        .sort((AppUsage a, AppUsage b) => b.sizeBytes.compareTo(a.sizeBytes));
    return filtered;
  }

  @override
  Future<void> launchUninstall(String packageName) async {
    uninstallRequested = packageName;
  }

  @override
  Future<BoostReport> boost() async => boostReport;

  @override
  Future<StorageCapabilities> requestAccess() async {
    capability = capability.copyWith(
      hasAllFilesAccess: true,
      hasMediaRead: true,
    );
    return capability;
  }

  @override
  Future<List<String>> browsableRoots() async => roots;
}
