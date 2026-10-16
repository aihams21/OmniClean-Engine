import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/platform/method_channel_gateway.dart';
import 'package:omni_clean_engine/engine/platform/storage_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  group('StorageCapabilities', () {
    test('reads a real payload from the bridge shape', () {
      final StorageCapabilities c = StorageCapabilities.fromMap(
        <Object?, Object?>{
          'apiLevel': 34,
          'hasAllFilesAccess': true,
          'hasMediaRead': false,
          'canRequestAllFiles': true,
          'canQueryUsageStats': true,
          'canUninstallApps': true,
          'storageRoot': '/storage/emulated/0',
          'totalBytes': 128000000000,
          'freeBytes': 64000000000,
          'externalStorageMounted': true,
        },
      );

      expect(c.apiLevel, 34);
      expect(c.hasAllFilesAccess, isTrue);
      expect(c.hasMediaRead, isFalse);
      expect(c.canReadAnything, isTrue);
      expect(c.canClean, isTrue);
      expect(c.usedBytes, 64000000000);
      expect(c.usedFraction, closeTo(0.5, 0.001));
    });

    test('a device that granted nothing can neither read nor clean', () {
      const StorageCapabilities c = StorageCapabilities.none;

      expect(c.canReadAnything, isFalse);
      expect(c.canClean, isFalse);
      expect(c.usedFraction, 0);
      expect(c.usedBytes, 0);
    });

    test('reading without the ability to delete is never good enough', () {
      const StorageCapabilities c = StorageCapabilities(hasMediaRead: true);

      expect(c.canReadAnything, isTrue);
      expect(c.canClean, isFalse);
    });

    test('a hostile payload degrades instead of throwing', () {
      final StorageCapabilities c = StorageCapabilities.fromMap(
        <Object?, Object?>{
          'apiLevel': 'thirty-four',
          'hasAllFilesAccess': 'yes',
          'totalBytes': -5,
          'storageRoot': 42,
        },
      );

      expect(c.apiLevel, 0);
      expect(c.hasAllFilesAccess, isFalse);
      expect(c.totalBytes, 0);
      expect(c.usedBytes, 0);
      expect(c.storageRoot, '');
    });

    test('equality is by value so a rebuild is not a repaint', () {
      const StorageCapabilities a = StorageCapabilities(
        apiLevel: 33,
        hasAllFilesAccess: true,
      );
      const StorageCapabilities b = StorageCapabilities(
        apiLevel: 33,
        hasAllFilesAccess: true,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(hasMediaRead: true), isNot(b));
    });
  });

  group('StorageEntry', () {
    test('round-trips the bridge payload', () {
      final StorageEntry e = StorageEntry.fromMap(<Object?, Object?>{
        'id': 'trash:42',
        'name': 'IMG_20240101.jpg',
        'path': '/storage/emulated/0/.trash/IMG_20240101.jpg',
        'sizeBytes': 2048,
        'modifiedMillis': 1704067200000,
        'kind': 'trashed',
        'mimeType': 'image/jpeg',
      });

      expect(e.id, 'trash:42');
      expect(e.kind, JunkKind.trashed);
      expect(e.sizeBytes, 2048);
      expect(e.mimeType, 'image/jpeg');
      expect(e.isDirectory, isFalse);
      expect(e.packageName, '');
    });

    test('an unknown kind degrades to logs rather than crashing the scan', () {
      final StorageEntry e = StorageEntry.fromMap(<Object?, Object?>{
        'id': 'x',
        'kind': 'something-new-from-android-15',
      });

      expect(e.kind, JunkKind.logs);
      expect(e.sizeBytes, 0);
    });
  });

  group('JunkSummary', () {
    StorageEntry entry(String id, JunkKind kind, int bytes) => StorageEntry(
          id: id,
          name: id,
          path: '/tmp/$id',
          sizeBytes: bytes,
          modified: DateTime.utc(2026, 1, 1),
          kind: kind,
        );

    test('totals and groups by bucket', () {
      final JunkSummary s = JunkSummary(
        entries: <StorageEntry>[
          entry('a', JunkKind.trashed, 100),
          entry('b', JunkKind.screenshots, 250),
          entry('c', JunkKind.trashed, 50),
        ],
      );

      expect(s.totalBytes, 400);
      expect(s.isEmpty, isFalse);
      expect(s.byKind[JunkKind.trashed], 150);
      expect(s.ofKind(JunkKind.trashed), hasLength(2));
      expect(s.byKind[JunkKind.appResidue], isNull);
    });

    test('reads the bridge payload and recomputes the total', () {
      final JunkSummary s = JunkSummary.fromMap(<Object?, Object?>{
        'totalBytes': 999999,
        'scannedEntries': 2,
        'capped': true,
        'entries': <Object?>[
          <Object?, Object?>{
            'id': 'a',
            'sizeBytes': 10,
            'kind': 'logs',
          },
          <Object?, Object?>{
            'id': 'b',
            'sizeBytes': 20,
            'kind': 'logs',
          },
        ],
      });

      expect(s.reportedTotalBytes, 999999);
      expect(s.totalBytes, 30);
      expect(s.entries, hasLength(2));
      expect(s.capped, isTrue);
      expect(s.scannedEntries, 2);
    });

    test('an empty payload is an empty summary, not a crash', () {
      final JunkSummary s = JunkSummary.fromMap(<Object?, Object?>{});

      expect(s.isEmpty, isTrue);
      expect(s.totalBytes, 0);
      expect(s.capped, isFalse);
    });
  });

  group('AppUsage', () {
    test('reads the bridge payload and computes how long it has sat unused',
        () {
      final int fortyDaysAgo =
          DateTime.now().millisecondsSinceEpoch - (40 * 86400000);
      final AppUsage a = AppUsage.fromMap(<Object?, Object?>{
        'packageName': 'com.old.game',
        'label': 'Old Game',
        'sizeBytes': 987654321,
        'lastUsedMillis': fortyDaysAgo,
        'versionName': '1.2.3',
        'isSystem': false,
      });

      expect(a.packageName, 'com.old.game');
      expect(a.sizeBytes, 987654321);
      expect(a.unusedDays, greaterThanOrEqualTo(39));
      expect(a.versionName, '1.2.3');
    });

    test('an app the system has never seen used counts as the oldest', () {
      final AppUsage a = AppUsage.fromMap(<Object?, Object?>{
        'packageName': 'com.never.opened',
        'lastUsedMillis': 0,
      });

      expect(a.unusedDays, 9999);
    });

    test('a clock that went backwards does not produce a negative age', () {
      final AppUsage a = AppUsage.fromMap(<Object?, Object?>{
        'lastUsedMillis':
            DateTime.now().millisecondsSinceEpoch + (5 * 86400000),
      });

      expect(a.unusedDays, 0);
    });
  });

  group('MediaItem', () {
    test('classifies images and videos from the mime type', () {
      final MediaItem image = MediaItem(
        id: '1',
        name: 'a.jpg',
        path: '/a.jpg',
        sizeBytes: 1,
        modified: _epoch,
        mimeType: 'image/jpeg',
      );
      final MediaItem video = MediaItem(
        id: '2',
        name: 'b.mp4',
        path: '/b.mp4',
        sizeBytes: 1,
        modified: _epoch,
        mimeType: 'video/mp4',
      );

      expect(image.isImage, isTrue);
      expect(image.isVideo, isFalse);
      expect(video.isVideo, isTrue);
    });
  });

  group('BoostReport', () {
    test('carries the before and after pair that makes a boost honest', () {
      final BoostReport r = BoostReport.fromMap(<Object?, Object?>{
        'freedBytes': 1048576,
        'killedProcesses': 12,
        'droppedCaches': true,
        'cpuBefore': 0.85,
        'cpuAfter': 0.42,
        'memoryBeforeBytes': 2000,
        'memoryAfterBytes': 900,
        'actions': <Object?>[
          'trimmed app caches',
          'killed 12 background processes'
        ],
      });

      expect(r.freedBytes, 1048576);
      expect(r.killedProcesses, 12);
      expect(r.droppedCaches, isTrue);
      expect(r.memoryReclaimedBytes, 1100);
      expect(r.didAnything, isTrue);
      expect(r.actions, hasLength(2));
      expect(r.unavailableReason, '');
    });

    test('a refused boost says so instead of showing a fake success', () {
      const BoostReport r = BoostReport(
        unavailableReason: 'Needs root on this device',
      );

      expect(r.didAnything, isFalse);
      expect(r.unavailableReason, 'Needs root on this device');
    });

    test('a negative memory delta is clamped, never shown as a gain', () {
      const BoostReport r = BoostReport(
        memoryBeforeBytes: 100,
        memoryAfterBytes: 400,
      );

      expect(r.memoryReclaimedBytes, 0);
    });
  });

  group('MethodChannelStorageGateway', () {
    late List<MethodCall> calls;

    setUp(() => calls = <MethodCall>[]);

    test('scans junk and carries the age filter across', () async {
      final MethodChannelStorageGateway gateway = MethodChannelStorageGateway();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(gateway.channel, (MethodCall call) async {
        calls.add(call);
        return <Object?, Object?>{
          'totalBytes': 4096,
          'scannedEntries': 1,
          'capped': false,
          'entries': <Object?>[
            <Object?, Object?>{'id': 'a', 'sizeBytes': 4096, 'kind': 'trashed'},
          ],
        };
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(gateway.channel, null);
      });

      final JunkSummary s =
          await gateway.scanJunk(minAge: const Duration(days: 3));

      expect(calls.single.method, 'scanJunk');
      expect(calls.single.arguments, <String, Object?>{'minAgeDays': 3});
      expect(s.totalBytes, 4096);
      expect(s.entries.single.kind, JunkKind.trashed);
    });

    test('a missing native side yields honest empties, never a crash',
        () async {
      const MethodChannelStorageGateway gateway = MethodChannelStorageGateway();
      // No handler registered: the channel behaves like a desktop build.
      expect(await gateway.capabilities(), StorageCapabilities.none);
      expect((await gateway.scanJunk()).isEmpty, isTrue);
      expect(await gateway.unusedApps(), isEmpty);
      expect(await gateway.media(), isEmpty);
      expect((await gateway.boost()).didAnything, isFalse);
      expect(await gateway.browsableRoots(), isEmpty);
    });

    test('a platform exception is logged and swallowed', () async {
      final MethodChannelStorageGateway gateway = MethodChannelStorageGateway();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(gateway.channel, (MethodCall call) async {
        calls.add(call);
        throw PlatformException(code: 'NO_PERMISSION', message: 'denied');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(gateway.channel, null);
      });

      final StorageCapabilities c = await gateway.capabilities();

      expect(c.canReadAnything, isFalse);
      expect(calls.single.method, 'capabilities');
    });

    test('unused apps come back most-idle first', () async {
      final MethodChannelStorageGateway gateway = MethodChannelStorageGateway();
      final int now = DateTime.now().millisecondsSinceEpoch;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(gateway.channel, (MethodCall call) async {
        calls.add(call);
        return <Object?, Object?>{
          'apps': <Object?>[
            <Object?, Object?>{
              'packageName': 'com.recent',
              'sizeBytes': 10,
              'lastUsedMillis': now - 86400000,
            },
            <Object?, Object?>{
              'packageName': 'com.ancient',
              'sizeBytes': 20,
              'lastUsedMillis': now - (90 * 86400000),
            },
          ],
        };
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(gateway.channel, null);
      });

      final List<AppUsage> apps = await gateway.unusedApps(unusedDays: 30);

      expect(apps.map((AppUsage a) => a.packageName).toList(),
          <String>['com.ancient', 'com.recent']);
      expect(calls.single.arguments, <String, Object?>{'unusedDays': 30});
    });

    test('deleting nothing never crosses the bridge', () async {
      final MethodChannelStorageGateway gateway = MethodChannelStorageGateway();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(gateway.channel, (MethodCall call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(gateway.channel, null);
      });

      await gateway.deleteEntries(const <String>[]);

      expect(calls, isEmpty);
    });

    test('an uninstall request forwards the package name', () async {
      final MethodChannelStorageGateway gateway = MethodChannelStorageGateway();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(gateway.channel, (MethodCall call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(gateway.channel, null);
      });

      await gateway.launchUninstall('com.old.game');

      expect(calls.single.method, 'launchUninstall');
      expect(calls.single.arguments, <String, Object?>{
        'packageName': 'com.old.game',
      });
    });
  });

  group('UnsupportedStorageGateway', () {
    test('reports blindness instead of a fake zero', () async {
      const UnsupportedStorageGateway gateway = UnsupportedStorageGateway();

      final StorageCapabilities c = await gateway.capabilities();

      expect(c.canReadAnything, isFalse);
      expect((await gateway.scanJunk()).isEmpty, isTrue);
      expect(await gateway.unusedApps(), isEmpty);
      expect(await gateway.media(), isEmpty);
      expect((await gateway.boost()).unavailableReason, isNotEmpty);
    });
  });

  group('FakeStorageGateway', () {
    StorageEntry entry(String id, JunkKind kind, int bytes) => StorageEntry(
          id: id,
          name: id,
          path: '/tmp/$id',
          sizeBytes: bytes,
          modified: DateTime.utc(2026, 1, 1),
          kind: kind,
        );

    test('reports the capabilities it was handed', () async {
      final FakeStorageGateway gateway = FakeStorageGateway();

      expect((await gateway.capabilities()).canClean, isTrue);
    });

    test('totals its entries and drops the ones it deleted', () async {
      final FakeStorageGateway gateway = FakeStorageGateway(
        entries: <StorageEntry>[
          entry('a', JunkKind.trashed, 100),
          entry('b', JunkKind.logs, 50),
        ],
      );

      expect((await gateway.scanJunk()).totalBytes, 150);

      await gateway.deleteEntries(<String>['a']);

      expect(gateway.deletedIds, <String>['a']);
      expect((await gateway.scanJunk()).totalBytes, 50);
    });

    test('emptying the bin only drops the trashed entries', () async {
      final FakeStorageGateway gateway = FakeStorageGateway(
        entries: <StorageEntry>[
          entry('a', JunkKind.trashed, 100),
          entry('b', JunkKind.logs, 50),
        ],
      );

      await gateway.emptyTrash();

      expect(gateway.emptiedTrash, 1);
      expect((await gateway.scanJunk()).entries, hasLength(1));
    });

    test('filters apps by idle days and orders by size', () async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final FakeStorageGateway gateway = FakeStorageGateway(
        applications: <AppUsage>[
          AppUsage(
            packageName: 'com.fresh',
            label: 'Fresh',
            sizeBytes: 10,
            lastUsed: DateTime.fromMillisecondsSinceEpoch(now - 86400000),
          ),
          AppUsage(
            packageName: 'com.old.small',
            label: 'Old small',
            sizeBytes: 20,
            lastUsed:
                DateTime.fromMillisecondsSinceEpoch(now - (60 * 86400000)),
          ),
          AppUsage(
            packageName: 'com.old.big',
            label: 'Old big',
            sizeBytes: 900,
            lastUsed:
                DateTime.fromMillisecondsSinceEpoch(now - (90 * 86400000)),
          ),
        ],
      );

      final List<AppUsage> apps = await gateway.unusedApps(unusedDays: 30);

      expect(apps.map((AppUsage a) => a.packageName).toList(),
          <String>['com.old.big', 'com.old.small']);
    });

    test('granting access flips the capability flags', () async {
      final FakeStorageGateway gateway = FakeStorageGateway(
        capability: const StorageCapabilities(canRequestAllFiles: true),
      );

      expect((await gateway.capabilities()).canClean, isFalse);

      final StorageCapabilities after = await gateway.requestAccess();

      expect(after.canClean, isTrue);
      expect(after.canReadAnything, isTrue);
    });
  });

  group('bridge contract', () {
    test('the channel name is stable so the Kotlin side can be matched', () {
      expect(MethodChannelStorageGateway.channelName,
          'dev.omniclean.engine/storage');
      expect(MethodChannelStorageGateway.defaultChannel.name,
          MethodChannelStorageGateway.channelName);
    });

    test('a desktop process does not accidentally have an android gateway', () {
      // The class must be constructible everywhere; only the runtime decides.
      expect(const MethodChannelStorageGateway(), isA<StorageGateway>());
    });
  });
}
