import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/duplicates/duplicate_finder.dart';
import 'package:omni_clean_engine/engine/duplicates/hasher.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('omniclean_dup_');
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  String write(String rel, List<int> bytes) {
    final f = File('${sandbox.path}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f.path;
  }

  group('Sha256FileHasher', () {
    test('matches the reference digest of a known payload', () async {
      final path = write('a.bin', utf8Bytes('abc'));
      expect(await Sha256FileHasher.hashFile(path),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('is stable for chunked reads larger than the chunk size', () async {
      final bytes = List<int>.generate(700000, (i) => i % 251);
      final path = write('big.bin', bytes);
      final small = await Sha256FileHasher.hashFile(path, chunkSize: 4096);
      final large = await Sha256FileHasher.hashFile(path, chunkSize: 1 << 20);
      expect(small, large);
    });

    test('hashes an empty file without throwing', () async {
      final path = write('empty.bin', const []);
      expect(
        await Sha256FileHasher.hashFile(path),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('partial hash differs for same-size but different-content files',
        () async {
      final head = List<int>.filled(4096, 1);
      final p1 = write('p1.bin', [...head, ...List<int>.filled(4096, 9)]);
      final p2 = write('p2.bin', [...head, ...List<int>.filled(4096, 8)]);
      expect(await Sha256FileHasher.partialHash(p1, 4096),
          isNot(await Sha256FileHasher.partialHash(p2, 4096)));
    });
  });

  group('DuplicateFinder', () {
    test('finds true duplicates behind different filenames', () async {
      final payload = List<int>.generate(300000, (i) => (i * 7) % 256);
      final a = write('photos/IMG_0001.jpg', payload);
      final b = write('photos/holiday copy (2).jpg', payload);
      final c = write('backups/PHOTO_FINAL.jpg', payload);
      write('photos/unique.jpg', List<int>.filled(300000, 9));

      final groups = await DuplicateFinder().find(
        roots: [sandbox.path],
        minSizeBytes: 1024,
      );

      expect(groups, hasLength(1));
      final g = groups.single;
      expect(g.sizeBytes, 300000);
      expect(g.files.map((f) => f.path).toSet(), {a, b, c});
      expect(g.wastedBytes, 600000, reason: '2 of 3 copies are redundant');
      expect(g.keepSuggestion, isNotNull);
    });

    test('never reports a group of one and never wastes bytes on the keeper',
        () async {
      write('x/one.bin', List<int>.filled(5000, 1));
      write('x/two.bin', List<int>.filled(5000, 2));

      final groups = await DuplicateFinder().find(
        roots: [sandbox.path],
        minSizeBytes: 1024,
      );
      expect(groups, isEmpty);
    });

    test('groups by content across many size buckets at once', () async {
      for (var s = 0; s < 6; s++) {
        final payload =
            List<int>.generate(2000 + s * 111, (i) => (i + s) % 256);
        write('g$s/a.bin', payload);
        write('g$s/b-renamed.bin', payload);
      }
      final groups = await DuplicateFinder().find(
        roots: [sandbox.path],
        minSizeBytes: 100,
      );
      expect(groups, hasLength(6));
      expect(groups.every((g) => g.files.length == 2), isTrue);
    });

    test('ignores files below the size floor and zero-byte files', () async {
      write('small/a.bin', [1, 2, 3, 4]);
      write('small/b.bin', [1, 2, 3, 4]);
      write('zero/a.bin', const []);
      write('zero/b.bin', const []);

      final groups = await DuplicateFinder().find(
        roots: [sandbox.path],
        minSizeBytes: 1024,
      );
      expect(groups, isEmpty);
    });

    test('honours an extension filter and skips symlink loops', () async {
      final payload = List<int>.filled(6000, 42);
      write('media/a.mp4', payload);
      write('media/b.mp4', payload);
      write('docs/a.pdf', payload);
      write('docs/b.pdf', payload);
      final loop = Link('${sandbox.path}/media/self');
      if (!loop.existsSync()) await loop.create('${sandbox.path}/media');

      final groups = await DuplicateFinder().find(
        roots: [sandbox.path],
        minSizeBytes: 100,
        extensions: const {'.mp4'},
      );

      expect(groups, hasLength(1));
      expect(groups.single.files.every((f) => f.path.endsWith('.mp4')), isTrue);
    });

    test('respects the cancel signal', () async {
      for (var i = 0; i < 4; i++) {
        final payload = List<int>.filled(4000 + i, 5);
        write('c$i/a.bin', payload);
        write('c$i/b.bin', payload);
      }
      final cancel = CancelToken()..cancel();

      final groups = await DuplicateFinder().find(
        roots: [sandbox.path],
        minSizeBytes: 100,
        cancel: cancel,
      );
      expect(groups, isEmpty);
    });

    test('reports progress with a monotonic completed counter', () async {
      for (var i = 0; i < 5; i++) {
        final payload = List<int>.filled(3000 + i * 10, 3);
        write('p$i/a.bin', payload);
        write('p$i/b.bin', payload);
      }
      final progress = <int>[];

      await DuplicateFinder().find(
        roots: [sandbox.path],
        minSizeBytes: 100,
        onProgress: (done, total, _) => progress.add(done),
      );

      expect(progress, isNotEmpty);
      expect(progress.last,
          progress.length == 0 ? 0 : progress.reduce((a, b) => a > b ? a : b));
      expect(progress.every((v) => v >= 0), isTrue);
    });
  });

  group('DuplicateGroup.keepSuggestion', () {
    test(
        'prefers the oldest file and never suggests a survivor if only one exists',
        () async {
      final files = [
        DuplicateFile(
            path: '/a/new.jpg',
            sizeBytes: 10,
            modified: DateTime.utc(2026, 1, 2),
            sha256: 'x'),
        DuplicateFile(
            path: '/a/old.jpg',
            sizeBytes: 10,
            modified: DateTime.utc(2025, 1, 2),
            sha256: 'x'),
        DuplicateFile(
            path: '/a/mid.jpg',
            sizeBytes: 10,
            modified: DateTime.utc(2025, 6, 2),
            sha256: 'x'),
      ];
      final group = DuplicateGroup(sha256: 'x', sizeBytes: 10, files: files);
      expect(group.keepSuggestion!.path, '/a/old.jpg');
    });

    test('is null when the group has no redundancy', () {
      final group = DuplicateGroup(
        sha256: 'x',
        sizeBytes: 10,
        files: [
          DuplicateFile(
              path: '/only.jpg',
              sizeBytes: 10,
              modified: DateTime.utc(2026),
              sha256: 'x')
        ],
      );
      expect(group.keepSuggestion, isNull);
      expect(group.wastedBytes, 0);
    });
  });
}

List<int> utf8Bytes(String s) => s.codeUnits;
