import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/core/safety/quarantine.dart';
import 'package:omni_clean_engine/core/safety/safe_delete.dart';
import 'package:omni_clean_engine/engine/duplicates/duplicate_finder.dart';
import 'package:omni_clean_engine/ui/controllers/duplicates_controller.dart';

void main() {
  late Directory sandbox;
  late Quarantine quarantine;
  late SafeDelete safeDelete;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('omniclean_dupes_');
    quarantine = Quarantine(
      root: Directory('${sandbox.path}/.omniclean/trash'),
      clock: () => DateTime.utc(2026, 10, 16, 12),
    );
    await quarantine.init();
    safeDelete = SafeDelete(
      quarantine: quarantine,
      clock: () => DateTime.utc(2026, 10, 16, 12),
    );
  });

  tearDown(() async {
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  /// Writes `bytes` of filler at `rel` and returns the absolute path.
  String write(String rel, {int bytes = 1024, DateTime? modified, Directory? base}) {
    final root = base ?? sandbox;
    final file = File('${root.path}/$rel');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(bytes, 0x61));
    file.setLastModifiedSync((modified ?? DateTime.utc(2026, 1, 1)).toLocal());
    return file.path;
  }

  DuplicateFile file(String path, {DateTime? modified}) => DuplicateFile(
        path: path,
        sizeBytes: 1024,
        modified: modified ?? DateTime.utc(2026, 1, 1),
        sha256: 'deadbeef',
      );

  Future<List<DuplicateGroup>> noResults(
    List<String> roots, {
    CancelToken? cancel,
    void Function(int, int, HashPhase)? onProgress,
  }) async =>
      const <DuplicateGroup>[];

  group('roots', () {
      test('a fresh controller starts with at least one usable root', () {
        final controller = DuplicatesController(
          scanner: noResults,
          safeDelete: safeDelete,
        );
        expect(controller.roots, isNotEmpty);
        expect(controller.canScan, isTrue);
        addTearDown(controller.dispose);
      });

      test('blank and duplicate roots are rejected, valid ones added', () {
        final controller = DuplicatesController(
          scanner: noResults,
          safeDelete: safeDelete,
          roots: [sandbox.path],
        );

        expect(controller.roots.length, greaterThanOrEqualTo(1));
        final before = controller.roots.length;

        controller.addRoot('   ');
        expect(controller.roots.length, before);

        controller.addRoot(sandbox.path);
        expect(controller.roots.length, before);

        controller.addRoot('${sandbox.path}/extra');
        expect(controller.roots.length, before + 1);
        expect(controller.roots.last, '${sandbox.path}/extra');
        addTearDown(controller.dispose);
      });

      test('removing a root drops it and canScan follows', () {
        final controller = DuplicatesController(
          scanner: noResults,
          safeDelete: safeDelete,
          roots: [sandbox.path],
        );

        controller.removeRoot(sandbox.path);
        expect(controller.roots, isNot(contains(sandbox.path)));

        controller.roots.forEach(controller.removeRoot);
        expect(controller.roots, isEmpty);
        expect(controller.canScan, isFalse);
        addTearDown(controller.dispose);
      });
    });

    group('scan', () {
      test('reports groups, wasted bytes and no selection', () async {
        final a = write('a.bin');
        final b = write('b.bin');
        final group = DuplicateGroup(sha256: 'hash-a', sizeBytes: 1024, files: [
          file(a),
          file(b),
        ]);

        final controller = DuplicatesController(
          scanner: (roots, {cancel, onProgress}) async => [group],
          safeDelete: safeDelete,
          roots: [sandbox.path],
        );
        addTearDown(controller.dispose);

        await controller.scan();

        expect(controller.groups, hasLength(1));
        expect(identical(controller.groups.first, group), isTrue);
        expect(controller.wastedBytes, 1024);
        expect(controller.phase, DuplicatesPhase.done);
        expect(controller.selectedCount, 0);
        expect(controller.canDelete, isFalse);
      });

      test('the progress phase is published as the scan runs', () async {
        final controller = DuplicatesController(
          scanner: (roots, {cancel, onProgress}) async {
            onProgress?.call(1, 4, HashPhase.walking);
            onProgress?.call(2, 4, HashPhase.hashing);
            return const <DuplicateGroup>[];
          },
          safeDelete: safeDelete,
          roots: [sandbox.path],
        );
        addTearDown(controller.dispose);

        final seen = <DuplicatesPhase>[];
        controller.addListener(() => seen.add(controller.phase));

        await controller.scan();

        expect(seen, contains(DuplicatesPhase.scanning));
        expect(seen.last, DuplicatesPhase.done);
      });

      test('a cancelled scan yields nothing and is flagged', () async {
        final controller = DuplicatesController(
          scanner: (roots, {cancel, onProgress}) async {
            cancel?.cancel();
            return [
              DuplicateGroup(sha256: 'h', sizeBytes: 10, files: const []),
            ];
          },
          safeDelete: safeDelete,
          roots: [sandbox.path],
        );
        addTearDown(controller.dispose);

        await controller.scan();

        expect(controller.wasCancelled, isTrue);
        expect(controller.groups, isEmpty);
        expect(controller.phase, DuplicatesPhase.idle);
        expect(controller.canScan, isTrue);
      });

      test('a scanner that throws degrades to failed', () async {
        final controller = DuplicatesController(
          scanner: (roots, {cancel, onProgress}) async => throw StateError('x'),
          safeDelete: safeDelete,
          roots: [sandbox.path],
        );
        addTearDown(controller.dispose);

        await controller.scan();

        expect(controller.phase, DuplicatesPhase.failed);
        expect(controller.groups, isEmpty);
      });

      test('scan refuses to run without roots and without overlapping runs',
          () async {
        var calls = 0;
        final controller = DuplicatesController(
          scanner: (roots, {cancel, onProgress}) async {
            calls++;
            return const <DuplicateGroup>[];
          },
          safeDelete: safeDelete,
          roots: [],
        );
        addTearDown(controller.dispose);

        await controller.scan();
        expect(calls, 0);

        controller.addRoot(sandbox.path);
        final first = controller.scan();
        await controller.scan();
        await first;
        expect(calls, 1);
      });
    });

    group('selection', () {
      late String keep;
      late String copy;
      late String third;
      late DuplicatesController controller;

      setUp(() async {
        keep = write('keep.bin', modified: DateTime.utc(2024, 1, 1));
        copy = write('copy.bin', modified: DateTime.utc(2025, 1, 1));
        third = write('third.bin', modified: DateTime.utc(2025, 6, 1));
        controller = DuplicatesController(
          scanner: (roots, {cancel, onProgress}) async => [
            DuplicateGroup(sha256: 'h', sizeBytes: 1024, files: [
              file(copy, modified: DateTime.utc(2025, 1, 1)),
              file(keep, modified: DateTime.utc(2024, 1, 1)),
              file(third, modified: DateTime.utc(2025, 6, 1)),
            ]),
          ],
          safeDelete: safeDelete,
          roots: [sandbox.path],
        );
        addTearDown(controller.dispose);
        await controller.scan();
      });

      test('selecting a group keeps the oldest and marks the rest', () {
        controller.selectGroup('h');

        expect(controller.keptPathFor('h'), keep);
        expect(controller.selectedPaths, containsAll(<String>[copy, third]));
        expect(controller.selectedPaths, isNot(contains(keep)));
        expect(controller.selectedCount, 2);
        expect(controller.canDelete, isTrue);
      });

      test('toggling a group twice clears it', () {
        controller.selectGroup('h');
        controller.selectGroup('h');
        expect(controller.selectedPaths, isEmpty);
        expect(controller.canDelete, isFalse);
      });

      test('selectAll selects every group but never a kept file', () {
        controller.selectAll();
        expect(controller.selectedCount, 2);
        expect(controller.selectedPaths, isNot(contains(keep)));
      });

      test('selectNone clears everything', () {
        controller.selectAll();
        controller.selectNone();
        expect(controller.selectedPaths, isEmpty);
      });

      test('a group of one file contributes nothing to keep or delete', () {
        final lonely = DuplicatesController(
          scanner: (roots, {cancel, onProgress}) async => [
            DuplicateGroup(sha256: 'solo', sizeBytes: 1024, files: [
              file(write('lonely.bin')),
            ]),
          ],
          safeDelete: safeDelete,
          roots: [sandbox.path],
        );
        addTearDown(lonely.dispose);

        return lonely.scan().then((_) {
          expect(lonely.keptPathFor('solo'), isNull);
          lonely.selectAll();
          expect(lonely.selectedPaths, isEmpty);
        });
      });

      test('selecting an unknown hash is a no-op', () {
        controller.selectGroup('nope');
        expect(controller.selectedPaths, isEmpty);
      });
    });

    group('deleteSelected', () {
      late String keep;
      late String copy;
      late DuplicatesController controller;

      setUp(() async {
        keep = write('keep.bin', modified: DateTime.utc(2024, 1, 1));
        copy = write('copy.bin', modified: DateTime.utc(2025, 1, 1));
        controller = DuplicatesController(
          scanner: (roots, {cancel, onProgress}) async => [
            DuplicateGroup(sha256: 'h', sizeBytes: 1024, files: [
              file(copy, modified: DateTime.utc(2025, 1, 1)),
              file(keep, modified: DateTime.utc(2024, 1, 1)),
            ]),
          ],
          safeDelete: safeDelete,
          roots: [sandbox.path],
        );
        addTearDown(controller.dispose);
        await controller.scan();
        controller.selectGroup('h');
      });

      test('quarantines every selected copy and keeps the original on disk',
          () async {
        final outcome = await controller.deleteSelected();

        expect(outcome.bytesFreed, 1024);
        expect(outcome.cleaned, [copy]);
        expect(File(copy).existsSync(), isFalse);
        expect(File(keep).existsSync(), isTrue);
        expect(controller.phase, DuplicatesPhase.done);
        expect(controller.lastOutcome, outcome);
      });

      test('the removed copy is restorable from quarantine', () async {
        await controller.deleteSelected();

        final items = await quarantine.list();
        expect(items, hasLength(1));
        expect(items.single.originalPath, copy);
        expect(items.single.bytes, 1024);

        await quarantine.restore(items.single.id);
        expect(File(copy).existsSync(), isTrue);
      });

      test('a file outside the declared roots is never deleted', () async {
        final elsewhere = await Directory.systemTemp.createTemp('omniclean_out_');
        addTearDown(() => elsewhere.delete(recursive: true));
        final outsider = write('outside.bin', base: elsewhere);
        controller.selectPath(outsider);

        final outcome = await controller.deleteSelected();

        expect(outcome.cleaned, isNot(contains(outsider)));
        expect(outcome.skipped, contains(outsider));
        expect(File(outsider).existsSync(), isTrue);
      });

      test('nothing selected means nothing happens', () async {
        controller.selectNone();

        final outcome = await controller.deleteSelected();

        expect(outcome.cleaned, isEmpty);
        expect(outcome.bytesFreed, 0);
        expect(File(copy).existsSync(), isTrue);
      });

      test('progress is reported while deleting', () async {
        final ticks = <int>[];
        controller.addListener(() {
          if (controller.progressTotal > 0) {
            ticks.add(controller.progressDone);
          }
        });

        await controller.deleteSelected();

        expect(ticks, isNotEmpty);
        for (var i = 1; i < ticks.length; i++) {
          expect(ticks[i], greaterThanOrEqualTo(ticks[i - 1]));
        }
        expect(controller.progressDone, controller.progressTotal);
        expect(controller.progressTotal, 0);
      });

      test('a second scan discards the previous selection', () async {
        await controller.deleteSelected();
        expect(controller.selectedPaths, isEmpty);
        expect(controller.groups, isEmpty);
      });
    });

    test('the real DuplicateFinder is the default scanner', () async {
      final controller = DuplicatesController(
        safeDelete: safeDelete,
        roots: [sandbox.path],
      );
      addTearDown(controller.dispose);

      write('one.bin', bytes: 8192);
      write('two.bin', bytes: 8192);

      await controller.scan();

      expect(controller.groups, hasLength(1));
      expect(controller.groups.single.files, hasLength(2));
      expect(controller.wastedBytes, 8192);
    });
}
