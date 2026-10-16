import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/cleaners/clean_target.dart';
import 'package:omni_clean_engine/engine/platform/method_channel_gateway.dart';
import 'package:omni_clean_engine/engine/platform/storage_gateway.dart';
import 'package:omni_clean_engine/ui/controllers/platform_cleaner.dart';

void main() {
  group('androidStorageTargets', () {
    test('one target per junk kind, ids stable and unique', () {
      final targets = androidStorageTargets();
      expect(targets, isNotEmpty);

      final ids = targets.map((t) => t.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(id, startsWith('android_'));
      }
      // The id is the contract between Dart and the localized title lookup.
      for (final target in targets) {
        expect(target.titleKey, endsWith('Title'));
        expect(target.descriptionKey, endsWith('Description'));
      }
    });

    test('every target declares roots and a non-zero minimum age', () {
      for (final target in androidStorageTargets()) {
        expect(target.roots, isNotEmpty, reason: target.id);
        expect(target.minAge, greaterThan(Duration.zero), reason: target.id);
      }
    });

    test('junk kinds map onto distinct targets', () {
      final ids = androidStorageTargets().map((t) => t.id).toSet();
      expect(ids, contains('android_trashed'));
      expect(ids, contains('android_obsolete_installers'));
      expect(ids, contains('android_partial_downloads'));
      expect(ids, contains('android_app_residue'));
      expect(ids, contains('android_screenshots'));
    });
  });

  group('StorageCleaner.scan', () {
    late FakeStorageGateway gateway;

    StorageEntry entry(
      String id,
      JunkKind kind,
      int bytes, {
      int daysOld = 30,
    }) =>
        StorageEntry(
          id: id,
          name: id,
          path: '/storage/emulated/0/$id',
          sizeBytes: bytes,
          modified: DateTime.now().subtract(Duration(days: daysOld)),
          kind: kind,
        );

    setUp(() {
      gateway = FakeStorageGateway(
        capability: const StorageCapabilities(
          apiLevel: 34,
          hasAllFilesAccess: true,
          hasMediaRead: true,
          canRequestAllFiles: false,
          canQueryUsageStats: true,
          canUninstallApps: true,
          storageRoot: '/storage/emulated/0',
          totalBytes: 128 * 1024 * 1024 * 1024,
          freeBytes: 20 * 1024 * 1024 * 1024,
          externalStorageMounted: true,
        ),
      );
    });

    test('reports real bytes grouped by junk kind', () async {
      gateway.entries = <StorageEntry>[
        entry('a.bin', JunkKind.trashed, 5 * 1024 * 1024),
        entry('b.bin', JunkKind.trashed, 3 * 1024 * 1024),
        entry('c.apk', JunkKind.obsoleteInstaller, 40 * 1024 * 1024),
        entry('d.crdownload', JunkKind.partialDownload, 1024 * 1024),
        entry('e.png', JunkKind.screenshots, 512 * 1024),
      ];

      final cleaner = StorageCleaner(gateway);
      final findings = await cleaner.scan();

      expect(
          findings.totalBytes,
          5 * 1024 * 1024 +
              3 * 1024 * 1024 +
              40 * 1024 * 1024 +
              1024 * 1024 +
              512 * 1024);
      expect(findings.totalFiles, 5);
      expect(findings.where((f) => f.isEmpty), isEmpty);
      final byId = <String, CleanFinding>{
        for (final f in findings) f.target.id: f,
      };
      expect(byId['android_trashed']!.totalBytes, 8 * 1024 * 1024);
      expect(byId['android_obsolete_installers']!.totalBytes, 40 * 1024 * 1024);
    });

    test('empty kinds are omitted so the list never shows a fake zero row',
        () async {
      gateway.entries = <StorageEntry>[
        entry('a.bin', JunkKind.trashed, 1024),
      ];

      final findings = await StorageCleaner(gateway).scan();

      expect(findings, hasLength(1));
      expect(findings.single.target.id, 'android_trashed');
    });

    test('a blind gateway scans to nothing rather than to a fake zero',
        () async {
      gateway.capability = StorageCapabilities.none;
      gateway.entries = <StorageEntry>[
        entry('a.bin', JunkKind.trashed, 1024),
      ];

      final findings = await StorageCleaner(gateway).scan();

      expect(findings, isEmpty);
    });

    test('entries younger than the target minimum age are held back', () async {
      gateway.entries = <StorageEntry>[
        entry('old.bin', JunkKind.trashed, 4096, daysOld: 30),
        entry('new.bin', JunkKind.trashed, 8192, daysOld: 0),
      ];

      final findings = await StorageCleaner(gateway).scan();

      expect(findings.single.fileCount, 1);
      expect(findings.single.totalBytes, 4096);
    });

    test('empty folders are reported as directories with zero size', () async {
      gateway.entries = <StorageEntry>[
        StorageEntry(
          id: 'dir',
          name: 'EmptyFolder',
          path: '/storage/emulated/0/EmptyFolder',
          sizeBytes: 0,
          modified: DateTime.now().subtract(const Duration(days: 60)),
          kind: JunkKind.emptyFolder,
          isDirectory: true,
        ),
      ];

      final findings = await StorageCleaner(gateway).scan();

      expect(findings.single.target.id, 'android_empty_folders');
      expect(findings.single.fileCount, 1);
      expect(findings.totalBytes, 0);
    });
  });

  group('StorageCleaner.clean', () {
    late FakeStorageGateway gateway;
    late List<StorageEntry> seed;

    StorageEntry entry(String id, JunkKind kind, int bytes) => StorageEntry(
          id: id,
          name: id,
          path: '/storage/emulated/0/$id',
          sizeBytes: bytes,
          modified: DateTime.now().subtract(const Duration(days: 60)),
          kind: kind,
        );

    setUp(() {
      seed = <StorageEntry>[
        entry('a', JunkKind.trashed, 1024),
        entry('b', JunkKind.trashed, 2048),
        entry('c', JunkKind.obsoleteInstaller, 4096),
      ];
      gateway = FakeStorageGateway(entries: seed);
    });

    test('deletes exactly the selected ids and frees their bytes', () async {
      final cleaner = StorageCleaner(gateway);
      final targets = await cleaner.scan();
      final selected =
          targets.where((f) => f.target.id == 'android_trashed').toList();

      final outcome = await cleaner.clean(selected);

      expect(gateway.deletedIds, <String>['a', 'b']);
      expect(outcome.bytesFreed, 3072);
      expect(outcome.cleaned, hasLength(2));
      expect(outcome.failedPaths, isEmpty);
    });

    test('cleaning nothing never crosses the bridge', () async {
      final outcome = await StorageCleaner(gateway).clean(
        const <CleanFinding>[],
      );

      expect(outcome.bytesFreed, 0);
      expect(gateway.deletedIds, isEmpty);
    });

    test('a blind gateway refuses to delete anything', () async {
      final cleaner = StorageCleaner(gateway);
      final targets = await cleaner.scan();
      gateway.capability = StorageCapabilities.none;

      final outcome = await cleaner.clean(targets);

      expect(outcome.bytesFreed, 0);
      expect(gateway.deletedIds, isEmpty);
    });

    test('progress is reported per file', () async {
      final cleaner = StorageCleaner(gateway);
      final targets = await cleaner.scan();
      final seen = <int>[];

      await cleaner.clean(
        targets,
        onProgress: (done, total) => seen.add(done),
      );

      expect(seen, isNotEmpty);
      expect(seen.last, 3);
    });
  });
}
