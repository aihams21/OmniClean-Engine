import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/core/safety/quarantine.dart';
import 'package:omni_clean_engine/core/safety/safe_delete.dart';
import 'package:omni_clean_engine/engine/duplicates/duplicate_finder.dart';
import 'package:omni_clean_engine/engine/duplicates/hasher.dart';
import 'package:omni_clean_engine/engine/platform/method_channel_gateway.dart';
import 'package:omni_clean_engine/engine/platform/storage_gateway.dart';
import 'package:omni_clean_engine/ui/controllers/duplicates_controller.dart';

StorageEntry _media(String path, int bytes) => StorageEntry(
      id: path,
      name: path.split('/').last,
      path: path,
      sizeBytes: bytes,
      modified: DateTime.now().subtract(const Duration(days: 3)),
      kind: JunkKind.duplicateMedia,
    );

void main() {
  late Directory sandbox;
  late SafeDelete safeDelete;
  late FakeStorageGateway gateway;

  File write(String name, List<int> bytes, {int? modified}) {
    final file = File('${sandbox.path}/photos/$name')
      ..createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    if (modified != null) {
      file.setLastModifiedSync(DateTime.fromMillisecondsSinceEpoch(modified));
    }
    return file;
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('omniclean_mediadup_');
    safeDelete = SafeDelete(
      quarantine: Quarantine(root: Directory('${sandbox.path}/.trash')),
    );
    gateway = FakeStorageGateway(
      capability: const StorageCapabilities(
        apiLevel: 36,
        hasAllFilesAccess: true,
        hasMediaRead: true,
        storageRoot: '/storage/emulated/0',
        totalBytes: 128 * 1024 * 1024 * 1024,
        freeBytes: 16 * 1024 * 1024 * 1024,
        externalStorageMounted: true,
      ),
    );
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  group('DuplicateFinder.scanFiles', () {
    test('finds byte-identical media handed in as a list', () async {
      final payload = List<int>.generate(64 * 1024, (i) => i % 251);
      final a = write('IMG_0001.jpg', payload);
      final b = write('IMG_0002.jpg', payload);
      final c = write(
          'unique.jpg', List<int>.generate(64 * 1024, (i) => (i * 7) % 253));

      final groups = await const DuplicateFinder().scanFiles(<DuplicateFile>[
        DuplicateFile(
            path: a.path,
            sizeBytes: a.lengthSync(),
            modified: a.lastModifiedSync(),
            sha256: ''),
        DuplicateFile(
            path: b.path,
            sizeBytes: b.lengthSync(),
            modified: b.lastModifiedSync(),
            sha256: ''),
        DuplicateFile(
            path: c.path,
            sizeBytes: c.lengthSync(),
            modified: c.lastModifiedSync(),
            sha256: ''),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.files, hasLength(2));
      expect(groups.single.sha256, await Sha256FileHasher.hashFile(a.path));
      expect(groups.single.wastedBytes, 64 * 1024);
    });

    test('ignores files that share a name but differ in content', () async {
      // Two distinct paths with the same base name: a name-based matcher
      // would call these duplicates, and it would be wrong.
      final a = write('camera-a/same.jpg', List<int>.filled(8192, 1));
      final b = write('camera-b/same.jpg', List<int>.filled(8192, 2));

      final groups = await const DuplicateFinder().scanFiles(<DuplicateFile>[
        DuplicateFile(
            path: a.path,
            sizeBytes: a.lengthSync(),
            modified: a.lastModifiedSync(),
            sha256: ''),
        DuplicateFile(
            path: b.path,
            sizeBytes: b.lengthSync(),
            modified: b.lastModifiedSync(),
            sha256: ''),
      ]);

      expect(groups, isEmpty);
    });

    test('a single file is never a duplicate group', () async {
      final a = write('one.jpg', List<int>.filled(8192, 3));

      final groups = await const DuplicateFinder().scanFiles(<DuplicateFile>[
        DuplicateFile(
            path: a.path,
            sizeBytes: a.lengthSync(),
            modified: a.lastModifiedSync(),
            sha256: ''),
      ]);

      expect(groups, isEmpty);
    });

    test('cancellation stops before any hashing starts', () async {
      final payload = List<int>.filled(8192, 9);
      final a = write('a.jpg', payload);
      final b = write('b.jpg', payload);
      final token = CancelToken()..cancel();

      final groups = await const DuplicateFinder().scanFiles(
        <DuplicateFile>[
          DuplicateFile(
              path: a.path,
              sizeBytes: a.lengthSync(),
              modified: a.lastModifiedSync(),
              sha256: ''),
          DuplicateFile(
              path: b.path,
              sizeBytes: b.lengthSync(),
              modified: b.lastModifiedSync(),
              sha256: ''),
        ],
        cancel: token,
      );

      expect(groups, isEmpty);
    });
  });

  group('DuplicatesController over the platform bridge', () {
    test('needs no folder: it scans whatever MediaStore reports', () async {
      final payload = List<int>.generate(48 * 1024, (i) => i % 97);
      final a = write('IMG_10.jpg', payload);
      final b = write('IMG_11.jpg', payload);
      write('noise.jpg', List<int>.generate(48 * 1024, (i) => (i * 3) % 89));

      final finder = const DuplicateFinder();
      gateway.mediaLibrary = <StorageEntry>[
        _media(a.path, a.lengthSync()),
        _media(b.path, b.lengthSync()),
      ];

      final controller = DuplicatesController(
        safeDelete: safeDelete,
        gateway: gateway,
        scanner: (roots, {cancel, onProgress}) async {
          final entries = await gateway.mediaFiles();
          onProgress?.call(entries.length, entries.length, HashPhase.walking);
          return finder.scanFiles(
            entries
                .map((e) => DuplicateFile(
                      path: e.path,
                      sizeBytes: e.sizeBytes,
                      modified: e.modified,
                      sha256: '',
                    ))
                .toList(growable: false),
            cancel: cancel,
            onProgress: onProgress,
          );
        },
        roots: const <String>[],
      );
      addTearDown(controller.dispose);

      expect(controller.canScan, isTrue);

      await controller.scan();

      expect(controller.groups, hasLength(1));
      expect(controller.groups.single.files, hasLength(2));
      expect(controller.wastedBytes, 48 * 1024);
      expect(b.path, isNotEmpty);
    });

    test('deleting the copies removes them through the platform', () async {
      final payload = List<int>.filled(8192, 5);
      final a = write('x1.jpg', payload);
      final b = write('x2.jpg', payload);

      final finder = const DuplicateFinder();
      final entries = <StorageEntry>[
        _media(a.path, a.lengthSync()),
        _media(b.path, b.lengthSync()),
      ];

      final controller = DuplicatesController(
        safeDelete: safeDelete,
        gateway: gateway,
        roots: const <String>[],
        scanner: (roots, {cancel, onProgress}) async => finder.scanFiles(
          entries
              .map((e) => DuplicateFile(
                    path: e.path,
                    sizeBytes: e.sizeBytes,
                    modified: e.modified,
                    sha256: '',
                  ))
              .toList(growable: false),
        ),
      );
      addTearDown(controller.dispose);

      await controller.scan();
      controller.selectAll();
      await controller.deleteSelected();

      expect(a.existsSync(), isTrue, reason: 'the original is kept');
      expect(b.existsSync(), isFalse, reason: 'the copy is gone');
      expect(controller.groups, isEmpty);
      expect(controller.lastOutcome?.bytesFreed, 8192);
    });
  });
}
