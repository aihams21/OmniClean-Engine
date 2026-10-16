import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/core/safety/quarantine.dart';
import 'package:omni_clean_engine/core/safety/safe_delete.dart';
import 'package:omni_clean_engine/engine/cleaners/clean_target.dart';
import 'package:omni_clean_engine/engine/platform/method_channel_gateway.dart';
import 'package:omni_clean_engine/engine/platform/storage_gateway.dart';
import 'package:omni_clean_engine/ui/controllers/cleaner_controller.dart';
import 'package:omni_clean_engine/ui/controllers/platform_cleaner.dart';

StorageEntry _entry(
  String id,
  JunkKind kind,
  int bytes, {
  int daysOld = 60,
}) =>
    StorageEntry(
      id: id,
      name: id,
      path: '/storage/emulated/0/$id',
      sizeBytes: bytes,
      modified: DateTime.now().subtract(Duration(days: daysOld)),
      kind: kind,
    );

void main() {
  late Directory sandbox;
  late SafeDelete safeDelete;
  late FakeStorageGateway gateway;

  final trashed = _entry('gone.bin', JunkKind.trashed, 2 * 1024 * 1024);
  final residue =
      _entry('com.gone.game', JunkKind.appResidue, 512 * 1024 * 1024);
  final installer =
      _entry('com.old.app-1.apk', JunkKind.obsoleteInstaller, 64 * 1024 * 1024);

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('omniclean_storage_');
    safeDelete = SafeDelete(
      quarantine: Quarantine(root: Directory('${sandbox.path}/.trash')),
    );
    gateway = FakeStorageGateway(
      capability: const StorageCapabilities(
        apiLevel: 36,
        hasAllFilesAccess: true,
        hasMediaRead: true,
        canUninstallApps: true,
        storageRoot: '/storage/emulated/0',
        totalBytes: 256 * 1024 * 1024 * 1024,
        freeBytes: 8 * 1024 * 1024 * 1024,
        externalStorageMounted: true,
      ),
      entries: <StorageEntry>[trashed, residue, installer],
    );
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  CleanerController build(
          {StorageCleaner? storage, required List<CleanTarget> targets}) =>
      CleanerController(
        targets: CleanTargetSet(targets),
        safeDelete: safeDelete,
        storage: storage ?? StorageCleaner(gateway),
      );

  group('a storage-backed controller', () {
    test('reports the bytes the platform bridge found, not the filesystem',
        () async {
      final controller = build(targets: androidStorageTargets());
      addTearDown(controller.dispose);

      await controller.scan();

      // /storage/emulated/0 does not exist on the test host, so a directory
      // sweep would find exactly nothing. The numbers below can only have come
      // from the gateway.
      expect(controller.hasScanned, isTrue);
      expect(controller.totalFiles, 3);
      expect(controller.totalBytes,
          trashed.sizeBytes + residue.sizeBytes + installer.sizeBytes);
    });

    test(
        'the headline reclaimable figure is larger than a local sweep would be',
        () async {
      final controller = build(targets: androidStorageTargets());
      addTearDown(controller.dispose);

      await controller.scan();

      expect(controller.totalBytes, greaterThan(512 * 1024 * 1024));
    });

    test('cleaning a selection deletes through the platform, not dart:io',
        () async {
      final controller = build(targets: androidStorageTargets());
      addTearDown(controller.dispose);

      await controller.scan();
      controller.selectAll();
      await controller.cleanSelected();

      expect(gateway.deletedIds, hasLength(3));
      expect(
          gateway.deletedIds,
          containsAll(
              <String>['gone.bin', 'com.gone.game', 'com.old.app-1.apk']));
      expect(controller.bytesFreed,
          trashed.sizeBytes + residue.sizeBytes + installer.sizeBytes);
      expect(controller.phase, CleanPhase.done);
    });

    test('only the ticked modules are deleted', () async {
      final controller = build(targets: androidStorageTargets());
      addTearDown(controller.dispose);

      await controller.scan();
      controller.selectNone();
      controller.toggle('android_trashed');
      await controller.cleanSelected();

      expect(gateway.deletedIds, <String>['gone.bin']);
    });
  });

  group('a controller without a storage bridge', () {
    test('keeps the directory-sweeper behaviour and never touches the bridge',
        () async {
      final controller = CleanerController(
        targets: CleanTargetSet(androidStorageTargets()),
        safeDelete: safeDelete,
      );
      addTearDown(controller.dispose);

      await controller.scan();

      expect(controller.totalBytes, 0);
      expect(gateway.deletedIds, isEmpty);

      controller.selectAll();
      await controller.cleanSelected();
      expect(gateway.deletedIds, isEmpty);
      expect(controller.bytesFreed, 0);
    });
  });

  group('a blind platform', () {
    test('scans to nothing rather than inventing a number', () async {
      final blind = FakeStorageGateway(
        capability: const StorageCapabilities(apiLevel: 36),
        entries: <StorageEntry>[trashed, residue, installer],
      );
      final controller = build(
        targets: androidStorageTargets(),
        storage: StorageCleaner(blind),
      );
      addTearDown(controller.dispose);

      await controller.scan();

      expect(controller.totalBytes, 0);
      expect(controller.hasScanned, isTrue);
    });
  });
}
