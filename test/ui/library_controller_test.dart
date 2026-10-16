import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/platform/method_channel_gateway.dart';
import 'package:omni_clean_engine/engine/platform/storage_gateway.dart';
import 'package:omni_clean_engine/ui/controllers/library_controller.dart';

MediaItem _item(
  String name,
  int bytes, {
  String mime = 'image/jpeg',
  int daysOld = 2,
  String folder = 'DCIM/Camera',
}) =>
    MediaItem(
      id: 'media:$name',
      name: name,
      path: '/storage/emulated/0/$folder/$name',
      sizeBytes: bytes,
      modified: DateTime.now().subtract(Duration(days: daysOld)),
      mimeType: mime,
      width: 4032,
      height: 3024,
    );

void main() {
  final photos = <MediaItem>[
    _item('IMG_0001.jpg', 4 * 1024 * 1024),
    _item('IMG_0002.jpg', 6 * 1024 * 1024, daysOld: 10),
    _item('beach.jpeg', 2 * 1024 * 1024, daysOld: 40),
  ];
  final videos = <MediaItem>[
    _item('clip1.mp4', 64 * 1024 * 1024, mime: 'video/mp4', daysOld: 3),
  ];
  final documents = <MediaItem>[
    _item('invoice.pdf', 512 * 1024,
        mime: 'application/pdf', daysOld: 90, folder: 'Documents'),
    _item('notes.txt', 4 * 1024,
        mime: 'text/plain', daysOld: 1, folder: 'Documents'),
  ];
  final downloads = <MediaItem>[
    _item('setup.apk', 128 * 1024 * 1024,
        mime: 'application/vnd.android.package-archive',
        daysOld: 1,
        folder: 'Download'),
  ];

  FakeStorageGateway gatewayWith() => FakeStorageGateway(
        capability: const StorageCapabilities(
          apiLevel: 36,
          hasAllFilesAccess: true,
          hasMediaRead: true,
          storageRoot: '/storage/emulated/0',
          totalBytes: 128 * 1024 * 1024 * 1024,
          freeBytes: 16 * 1024 * 1024 * 1024,
          externalStorageMounted: true,
        ),
        mediaItems: <MediaItem>[
          ...photos,
          ...videos,
          ...documents,
          ...downloads
        ],
      );

  group('classification', () {
    test('each library kind maps to one MediaKind', () {
      expect(MediaKind.photos.wire, 'photos');
      expect(MediaKind.videos.wire, 'videos');
      expect(MediaKind.documents.wire, 'documents');
      expect(MediaKind.downloads.wire, 'downloads');
      expect(MediaKind.allFiles.wire, 'documents');
    });

    test('MediaKind.allFiles is the union a user expects from "Files"', () {
      expect(MediaKind.allFiles.label, 'All files');
      expect(MediaKind.documents.label, 'Documents');
      expect(MediaKind.photos.label, 'Photos');
      expect(MediaKind.videos.label, 'Videos');
      expect(MediaKind.downloads.label, 'Downloads');
    });
  });

  group('LibraryController', () {
    test('starts empty and idle', () {
      final c = LibraryController(gateway: gatewayWith());
      addTearDown(c.dispose);

      expect(c.items, isEmpty);
      expect(c.phase, LibraryPhase.idle);
      expect(c.totalBytes, 0);
      expect(c.canLoad, isTrue);
    });

    test('loads photos newest first and totals their bytes', () async {
      final c = LibraryController(gateway: gatewayWith());
      addTearDown(c.dispose);
      c.selectKind(MediaKind.photos);

      expect(c.canLoad, isTrue);
      await c.load();

      expect(c.phase, LibraryPhase.done);
      expect(c.items, hasLength(3));
      expect(c.items.first.name, 'IMG_0001.jpg');
      expect(c.items.last.name, 'beach.jpeg');
      expect(c.totalBytes, 12 * 1024 * 1024);
      expect(c.items.map((MediaItem m) => m.isImage), everyElement(isTrue));
    });

    test('videos are listed separately from photos', () async {
      final c = LibraryController(gateway: gatewayWith());
      addTearDown(c.dispose);

      c.selectKind(MediaKind.videos);
      await c.load();

      expect(c.items, hasLength(1));
      expect(c.items.single.isVideo, isTrue);
      expect(c.totalBytes, 64 * 1024 * 1024);
    });

    test('"Files" merges documents and downloads', () async {
      final c = LibraryController(gateway: gatewayWith());
      addTearDown(c.dispose);

      c.selectKind(MediaKind.allFiles);
      await c.load();

      expect(c.items, hasLength(3));
      expect(c.totalBytes, 128 * 1024 * 1024 + 512 * 1024 + 4 * 1024);
    });

    test('changing the kind clears the previous list immediately', () async {
      final c = LibraryController(gateway: gatewayWith());
      addTearDown(c.dispose);

      c.selectKind(MediaKind.photos);
      await c.load();
      expect(c.items, isNotEmpty);

      c.selectKind(MediaKind.videos);
      expect(c.items, isEmpty);
      expect(c.phase, LibraryPhase.idle);
    });

    test('a blind platform says so instead of showing an empty gallery',
        () async {
      final blind = FakeStorageGateway(
        capability: const StorageCapabilities(apiLevel: 36),
      );
      final c = LibraryController(gateway: blind);
      addTearDown(c.dispose);
      c.selectKind(MediaKind.photos);

      await c.load();

      expect(c.phase, LibraryPhase.blind);
      expect(c.items, isEmpty);
      expect(c.isBlind, isTrue);
    });

    test('a gateway that throws degrades to failed, not a crash', () async {
      final c = LibraryController(gateway: _ExplodingGateway());
      addTearDown(c.dispose);
      c.selectKind(MediaKind.photos);

      await c.load();

      expect(c.phase, LibraryPhase.failed);
      expect(c.items, isEmpty);
    });

    test('a load already in flight is not started twice', () async {
      final c = LibraryController(gateway: gatewayWith());
      addTearDown(c.dispose);
      c.selectKind(MediaKind.photos);

      await Future.wait<void>(<Future<void>>[c.load(), c.load()]);

      expect(c.items, hasLength(3));
    });

    test('tells the user which of the five libraries is empty', () async {
      final empty = FakeStorageGateway();
      final c = LibraryController(gateway: empty);
      addTearDown(c.dispose);

      for (final MediaKind kind in MediaKind.values) {
        c.selectKind(kind);
        await c.load();
        expect(c.phase, LibraryPhase.empty);
        expect(c.items, isEmpty);
      }
    });

    test('notifies listeners as the list arrives', () async {
      final c = LibraryController(gateway: gatewayWith());
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);

      c.selectKind(MediaKind.photos);
      await c.load();

      expect(notifications, greaterThanOrEqualTo(2));
      c.selectKind(MediaKind.photos);
      expect(notifications, 2,
          reason: 'selecting the library already shown is a no-op');
    });
  });
}

class _ExplodingGateway extends FakeStorageGateway {
  _ExplodingGateway()
      : super(
          capability: const StorageCapabilities(
            apiLevel: 36,
            hasAllFilesAccess: true,
            hasMediaRead: true,
            storageRoot: '/storage/emulated/0',
            totalBytes: 1024,
            freeBytes: 512,
            externalStorageMounted: true,
          ),
        );

  @override
  Future<List<MediaItem>> media({MediaKind kind = MediaKind.photos}) async =>
      throw StateError('provider died');
}
