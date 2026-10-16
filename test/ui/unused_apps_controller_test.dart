import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/platform/method_channel_gateway.dart';
import 'package:omni_clean_engine/engine/platform/storage_gateway.dart';
import 'package:omni_clean_engine/ui/controllers/unused_apps_controller.dart';

AppUsage _app(
  String pkg,
  String label,
  int bytes, {
  int idleDays = 90,
  bool isSystem = false,
  String version = '',
}) =>
    AppUsage(
      packageName: pkg,
      label: label,
      sizeBytes: bytes,
      lastUsed: DateTime.now().subtract(Duration(days: idleDays)),
      versionName: version,
      isSystem: isSystem,
      installedMillis: DateTime.now()
          .subtract(Duration(days: idleDays + 30))
          .millisecondsSinceEpoch,
    );

/// A gateway that refuses everything, the way a locked-down phone does.
class _BlindGateway extends StorageGateway {
  @override
  Future<StorageCapabilities> capabilities() async =>
      const StorageCapabilities(apiLevel: 30);

  @override
  Future<JunkSummary> scanJunk(
          {Duration minAge = const Duration(days: 7)}) async =>
      JunkSummary(entries: const <StorageEntry>[]);

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
  Future<BoostReport> boost() async => BoostReport.nothing;

  @override
  Future<StorageCapabilities> requestAccess() async => capabilities();
}

void main() {
  late FakeStorageGateway gateway;

  final stale =
      _app('com.old.game', 'Old Game', 2 * 1024 * 1024 * 1024, idleDays: 120);
  final forgetful =
      _app('com.maybe', 'Maybe This', 400 * 1024 * 1024, idleDays: 31);
  final recent = _app('com.today', 'Used Today', 50 * 1024 * 1024, idleDays: 1);
  final neverUsed = AppUsage(
    packageName: 'com.never',
    label: 'Never Opened',
    sizeBytes: 100 * 1024 * 1024,
    lastUsed: DateTime.fromMillisecondsSinceEpoch(0),
    versionName: '2.1',
    isSystem: false,
    installedMillis: 0,
  );
  final system = _app('com.android.settings', 'Settings', 12 * 1024 * 1024,
      idleDays: 200, isSystem: true);

  setUp(() {
    gateway = FakeStorageGateway(
      capability: const StorageCapabilities(
        apiLevel: 36,
        hasAllFilesAccess: true,
        hasMediaRead: true,
        canQueryUsageStats: true,
        canUninstallApps: true,
        storageRoot: '/storage/emulated/0',
        totalBytes: 128000000000,
        freeBytes: 16000000000,
        externalStorageMounted: true,
      ),
      applications: <AppUsage>[stale, forgetful, recent, neverUsed, system],
    );
  });

  UnusedAppsController build({StorageGateway? source}) =>
      UnusedAppsController(gateway: source ?? gateway);

  group('threshold', () {
    test('the default is thirty days and the options are the ones we ship', () {
      final controller = build();
      addTearDown(controller.dispose);

      expect(controller.thresholdDays, 30);
      expect(controller.thresholdOptions, contains(30));
      expect(controller.thresholdOptions, contains(90));
      expect(controller.thresholdOptions, contains(365));
    });

    test(
        'changing the threshold re-reads the list instead of filtering a stale one',
        () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.totalBytes, greaterThan(2 * 1024 * 1024 * 1024));

      controller.setThreshold(365);
      await controller.load();
      // Only the app that has genuinely never been opened survives a year.
      expect(controller.apps.map((AppUsage a) => a.packageName),
          <String>['com.never']);
    });

    test('setting the same threshold does not churn', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.load();
      var notifications = 0;
      controller.addListener(() => notifications++);

      // Only the setter is under test here: a reload is supposed to notify.
      controller.setThreshold(controller.thresholdDays);

      expect(notifications, 0);
    });
  });

  group('listing', () {
    test('never-used apps lead, then the longest-idle, biggest first',
        () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.phase, UnusedAppsPhase.done);
      // Three, not five: the system app is never offered, and an app opened
      // today is by definition not an unused one.
      expect(controller.apps, hasLength(3));
      expect(controller.apps.first.packageName, 'com.never');
      expect(controller.apps[1].packageName, 'com.old.game');
      expect(controller.apps[2].packageName, 'com.maybe');
    });

    test('an app used today is not an unused app', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.load();

      expect(
        controller.apps.where((AppUsage a) => a.packageName == 'com.today'),
        isEmpty,
      );
    });

    test('system apps are never offered for removal', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.load();

      expect(
        controller.apps.where((AppUsage a) => a.isSystem),
        isEmpty,
      );
    });

    test('the headline is the real reclaimable size', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.totalBytes,
          stale.sizeBytes + forgetful.sizeBytes + neverUsed.sizeBytes);
      expect(controller.count, 3);
    });

    test('selecting is independent of loading and survives a reload', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.load();
      controller.select('com.old.game');
      expect(controller.selectedCount, 1);
      expect(controller.selectedBytes, stale.sizeBytes);

      await controller.load();
      expect(controller.selectedCount, 1);
      expect(controller.isSelected('com.old.game'), isTrue);
    });

    test('an empty answer is reported as empty, not as failure', () async {
      final controller = build(
        source: FakeStorageGateway(
          capability: gateway.capability,
          applications: const <AppUsage>[],
        ),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.phase, UnusedAppsPhase.empty);
      expect(controller.totalBytes, 0);
    });
  });

  group('honesty', () {
    test('a device that cannot report usage says so instead of listing zero',
        () async {
      final controller = build(source: _BlindGateway());
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.phase, UnusedAppsPhase.blind);
      expect(controller.isBlind, isTrue);
      expect(controller.canUninstall, isFalse);
      expect(controller.totalBytes, 0);
    });

    test('a throwing bridge degrades to failed, not a crash', () async {
      final controller = build(source: _ExplodingGateway());
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.phase, UnusedAppsPhase.failed);
    });
  });

  group('uninstall', () {
    test('asking the platform to uninstall records the package', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.load();
      await controller.uninstall('com.old.game');

      expect(gateway.uninstallRequested, 'com.old.game');
      expect(controller.lastUninstalled, 'com.old.game');
      // The row is gone: the platform will remove it, so showing it again
      // would be a lie.
      expect(
          controller.apps.any((AppUsage a) => a.packageName == 'com.old.game'),
          isFalse);
    });

    test('the row only disappears once the platform accepted it', () async {
      final controller = build(source: _SilentUninstallGateway(gateway));
      addTearDown(controller.dispose);

      await controller.load();
      await controller.uninstall('com.old.game');

      expect(
          controller.apps.any((AppUsage a) => a.packageName == 'com.old.game'),
          isTrue);
      expect(controller.lastUninstalled, isNull);
    });

    test('cannot uninstall when the device refuses to', () async {
      final controller = build(
        source: FakeStorageGateway(
          capability: const StorageCapabilities(
            apiLevel: 36,
            canQueryUsageStats: true,
          ),
        ),
      );
      addTearDown(controller.dispose);

      expect(controller.canUninstall, isFalse);
      await controller.uninstall('com.old.game');
      expect(controller.lastUninstalled, isNull);
    });
  });
}

/// Reports usage fine but refuses the uninstall request, the way a device with
/// `REQUEST_DELETE_PACKAGES` denied does.
class _SilentUninstallGateway extends FakeStorageGateway {
  _SilentUninstallGateway(FakeStorageGateway source)
      : super(
          capability: source.capability,
          applications: source.applications,
        );

  @override
  Future<void> launchUninstall(String packageName) async =>
      throw UnsupportedError('REQUEST_DELETE_PACKAGES denied');
}

/// Can answer "can you report usage" with a yes, then blows up when asked.
class _ExplodingGateway extends _BlindGateway {
  @override
  Future<StorageCapabilities> capabilities() async =>
      const StorageCapabilities(apiLevel: 36, canQueryUsageStats: true);

  @override
  Future<List<AppUsage>> unusedApps({int unusedDays = 30}) async =>
      throw StateError('usage stats blew up');
}
