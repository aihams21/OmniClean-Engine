import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/core/safety/quarantine.dart';
import 'package:omni_clean_engine/core/safety/safe_delete.dart';
import 'package:omni_clean_engine/engine/cleaners/clean_target.dart';
import 'package:omni_clean_engine/engine/cleaners/directory_sweeper.dart';
import 'package:omni_clean_engine/engine/duplicates/duplicate_finder.dart' show CancelToken;

late Directory sandbox;
late DateTime now;
late Quarantine quarantine;
late SafeDelete safeDelete;

String filled(int bytes, [int seed = 7]) =>
    String.fromCharCodes(List.generate(bytes, (i) => 65 + ((i + seed) % 26)));

File write(String rel, int bytes, {Duration age = const Duration(days: 30)}) {
  final f = File('${sandbox.path}/$rel');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(filled(bytes).codeUnits);
  final stamp = now.subtract(age);
  // POSIX cannot set mtime on a file easily; utimes via Process would be slow.
  // Instead we rely on the injected clock: `age` is simulated by giving the
  // sweeper a clock in the future relative to the real mtime.
  f.setLastModifiedSync(stamp.toLocal());
  return f;
}

void main() {
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('oc_sweep_');
    now = DateTime.utc(2026, 3, 1, 12);
    quarantine = Quarantine(root: Directory('${sandbox.path}/quarantine'), clock: () => now);
    await quarantine.init();
    safeDelete = SafeDelete(quarantine: quarantine, clock: () => now);
  });

  tearDown(() async {
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('CleanTarget', () {
    test('exposes a stable identity and metadata', () {
      const t = CleanTarget(
        id: 'linux.apt.cache',
        titleKey: 'target.aptCache.title',
        descriptionKey: 'target.aptCache.desc',
        category: CleanCategory.packageCache,
        risk: RiskLevel.safe,
        minAge: Duration(hours: 1),
        roots: ['/var/cache/apt/archives'],
      );
      expect(t.id, 'linux.apt.cache');
      expect(t.category, CleanCategory.packageCache);
      expect(t.risk, RiskLevel.safe);
      expect(t.requiresPrivilege, isFalse);
      expect(t.isCapped, isFalse);
    });

    test('a target that caps bytes reports it and defaults the cap', () {
      const t = CleanTarget(
        id: 'x',
        titleKey: 'a',
        descriptionKey: 'b',
        category: CleanCategory.temp,
        risk: RiskLevel.moderate,
        roots: [],
      );
      expect(t.isCapped, isFalse);
      expect(t.maxBytes, isNull);

      const capped = CleanTarget(
        id: 'y',
        titleKey: 'a',
        descriptionKey: 'b',
        category: CleanCategory.temp,
        risk: RiskLevel.moderate,
        capBytes: 1024,
        roots: [],
      );
      expect(capped.isCapped, isTrue);
      expect(capped.maxBytes, 1024);
    });

    test('ids must be unique within a module', () {
      const a = CleanTarget(id: 'dup', titleKey: 'a', descriptionKey: 'b', category: CleanCategory.temp, roots: ['/tmp']);
      const b = CleanTarget(id: 'dup', titleKey: 'a', descriptionKey: 'b', category: CleanCategory.temp, roots: ['/tmp']);
      expect(() => CleanTargetSet([a, b]), throwsArgumentError);
    });
  });

  group('CleanFinding', () {
    test('totals aggregate across findings', () {
      final list = <CleanFinding>[
        CleanFinding(
          target: const CleanTarget(id: 'a', titleKey: 'a', descriptionKey: 'b', category: CleanCategory.temp, roots: ['/tmp']),
          fileCount: 3,
          totalBytes: 300,
          samples: const ['/tmp/a'],
        ),
        CleanFinding(
          target: const CleanTarget(id: 'b', titleKey: 'a', descriptionKey: 'b', category: CleanCategory.logs, roots: ['/var/log']),
          fileCount: 1,
          totalBytes: 100,
        ),
      ];
      expect(list.totalBytes, 400);
      expect(list.totalFiles, 4);
      expect(list.isEmpty, isFalse);
      expect(const <CleanFinding>[].isEmpty, isTrue);
    });
  });

  group('DirectorySweeper.measure', () {
    test('counts files and bytes, recursing into subdirectories', () async {
      write('a.txt', 100);
      write('sub/b.txt', 200);
      write('sub/deep/c.txt', 300);

      final result = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(minAge: Duration(days: 1)),
        clock: () => now,
      );

      expect(result.fileCount, 3);
      expect(result.bytes, 600);
      expect(result.scannedDirectories, greaterThanOrEqualTo(3));
    });

    test('ignores roots that do not exist instead of throwing', () async {
      write('a.txt', 100);
      final result = await DirectorySweeper().measure(
        ['${sandbox.path}/a.txt', '${sandbox.path}/nope'],
        const SweepOptions(),
        clock: () => now,
      );
      expect(result.fileCount, 1);
      expect(result.bytes, 100);
    });

    test('minAge separates reclaimable bytes from what a live app still holds', () async {
      write('old.txt', 100, age: const Duration(days: 40));
      write('fresh.txt', 999, age: const Duration(minutes: 5));

      final result = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(minAge: Duration(days: 7)),
        clock: () => now,
      );

      expect(result.fileCount, 2, reason: 'both are seen');
      expect(result.bytes, 1099);
      expect(result.selectableFiles, 2,
          reason: 'age is a safety gate, not a content filter');
      expect(result.selectableBytes, 1099);
      expect(result.agedFiles, 1);
      expect(result.agedBytes, 100);
      expect(result.heldBackFiles, 1);
      expect(result.heldBackBytes, 999);
    });

    test('never follows symlinks out of the root', () async {
      final outside = await Directory.systemTemp.createTemp('oc_outside_');
      addTearDown(() => outside.delete(recursive: true));
      File('${outside.path}/secret.txt').writeAsStringSync(filled(5000));

      write('inside.txt', 10);
      Link('${sandbox.path}/escape').createSync(outside.path);
      Link('${sandbox.path}/escape.txt').createSync('${outside.path}/secret.txt');

      final result = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(),
        clock: () => now,
      );

      expect(result.fileCount, 1);
      expect(result.bytes, 10);
      expect(result.symlinksSkipped, 2);
    });

    test('excludes hidden files unless asked, and honours name filters', () async {
      write('visible.txt', 100);
      write('.hidden', 200);
      write('keep/index.dat', 300);
      write('drop/cache.tmp', 400);

      final plain = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(),
        clock: () => now,
      );
      expect(plain.fileCount, 4);

      final filtered = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(includeHidden: false),
        clock: () => now,
      );
      expect(filtered.fileCount, 3, reason: '.hidden skipped');

      final byExt = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(extensions: {'.txt'}),
        clock: () => now,
      );
      expect(byExt.fileCount, 1);

      final byExcludedExt = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(excludeExtensions: {'.tmp'}),
        clock: () => now,
      );
      expect(byExcludedExt.fileCount, 3);

      final skippedDirs = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(excludeDirectories: {'keep'}),
        clock: () => now,
      );
      expect(skippedDirs.fileCount, 3);
      expect(skippedDirs.skippedDirectories, greaterThanOrEqualTo(1));
    });

    test('depth limit stops descending', () async {
      write('l1.txt', 10);
      write('l2/l3/l4/deep.txt', 20);

      final shallow = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(maxDepth: 1),
        clock: () => now,
      );
      expect(shallow.fileCount, 1);

      final deep = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(maxDepth: 8),
        clock: () => now,
      );
      expect(deep.fileCount, 2);
    });

    test('a byte cap keeps the largest files first and reports it', () async {
      write('small.bin', 100);
      write('medium.bin', 1000);
      write('large.bin', 5000);

      final result = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(maxBytes: 4000),
        clock: () => now,
      );

      expect(result.fileCount, 3);
      expect(result.capped, isTrue);
      expect(result.selected, ['medium.bin', 'small.bin'],
          reason: 'the 5000 B file does not fit a 4000 B budget');
      expect(result.selectableBytes, 6100);
      expect(result.bytes, 6100);
    });

    test('cancelling stops the walk and reports incompleteness', () async {
      for (var i = 0; i < 20; i++) {
        write('f$i.bin', 10 + i);
      }
      final token = CancelToken();
      var seen = 0;

      final result = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(),
        clock: () => now,
        cancel: token,
        onFile: (_) {
          seen++;
          if (seen == 3) token.cancel();
        },
      );

      expect(result.cancelled, isTrue);
      expect(result.fileCount, lessThan(20));
    });

    test('emits the largest files as samples for the UI', () async {
      write('s1.bin', 10);
      write('s2.bin', 9999);
      write('s3.bin', 5000);

      final result = await DirectorySweeper().measure(
        [sandbox.path],
        const SweepOptions(maxSamples: 2),
        clock: () => now,
      );

      expect(result.samples.length, 2);
      expect(result.samples.first.name, 's2.bin');
    });
  });

  group('DirectorySweeper.clean', () {
    test('moves selected files into quarantine and frees their bytes', () async {
      write('old.bin', 2000, age: const Duration(days: 40));
      write('fresh.bin', 3000, age: const Duration(minutes: 2));

      final outcome = await DirectorySweeper().clean(
        [sandbox.path],
        const SweepOptions(minAge: Duration(days: 7)),
        safeDelete: safeDelete,
        allowedRoots: [sandbox.path],
        module: 'test',
        clock: () => now,
      );

      expect(outcome.cleaned, hasLength(1));
      expect(outcome.cleaned.single, endsWith('old.bin'));
      expect(outcome.bytesFreed, 2000);
      expect(outcome.skipped, hasLength(1), reason: 'fresh file is too young');
      expect(File('${sandbox.path}/old.bin').existsSync(), isFalse);
      expect(File('${sandbox.path}/fresh.bin').existsSync(), isTrue);
      expect(await quarantine.totalBytes(), 2000);
    });

    test('never deletes outside the declared roots', () async {
      write('old.bin', 500, age: const Duration(days: 40));

      final outcome = await DirectorySweeper().clean(
        [sandbox.path],
        const SweepOptions(minAge: Duration(days: 7)),
        safeDelete: safeDelete,
        allowedRoots: ['${sandbox.path}/somewhere-else'],
        module: 'test',
        clock: () => now,
      );

      expect(outcome.cleaned, isEmpty);
      expect(outcome.skipped, hasLength(1));
      expect(outcome.bytesFreed, 0);
      expect(File('${sandbox.path}/old.bin').existsSync(), isTrue);
    });

    test('measure and clean agree on what is selectable', () async {
      write('a.bin', 100, age: const Duration(days: 40));
      write('b.bin', 200, age: const Duration(days: 40));
      write('c.bin', 9000, age: const Duration(minutes: 1));

      const options = SweepOptions(minAge: Duration(days: 7));
      final measurement = await DirectorySweeper()
          .measure([sandbox.path], options, clock: () => now);
      final outcome = await DirectorySweeper().clean(
        [sandbox.path],
        options,
        safeDelete: safeDelete,
        allowedRoots: [sandbox.path],
        module: 'test',
        clock: () => now,
      );

      expect(measurement.selectableFiles, 3,
          reason: 'all three are junk the scan can see');
      expect(measurement.agedFiles, outcome.cleaned.length,
          reason: 'clean removes exactly what the scan called old enough');
      expect(measurement.agedBytes, outcome.bytesFreed);
      expect(measurement.heldBackFiles, outcome.skipped.length,
          reason: 'the gap is reported, never silently dropped');
    });

    test('everything it removes is restorable from quarantine', () async {
      write('tree/a.bin', 111, age: const Duration(days: 40));
      write('tree/nested/b.bin', 222, age: const Duration(days: 40));

      await DirectorySweeper().clean(
        [sandbox.path],
        const SweepOptions(minAge: Duration(days: 7)),
        safeDelete: safeDelete,
        allowedRoots: [sandbox.path],
        module: 'restore-me',
        clock: () => now,
      );

      final items = await quarantine.list();
      expect(items, isNotEmpty);
      for (final item in items) {
        await quarantine.restore(item.id);
      }
      expect(File('${sandbox.path}/tree/a.bin').existsSync(), isTrue);
      expect(File('${sandbox.path}/tree/nested/b.bin').existsSync(), isTrue);
    });

    test('reports progress monotonically and finishes at the total', () async {
      for (var i = 0; i < 5; i++) {
        write('p$i.bin', 10, age: const Duration(days: 40));
      }
      final ticks = <int>[];

      await DirectorySweeper().clean(
        [sandbox.path],
        const SweepOptions(minAge: Duration(days: 7)),
        safeDelete: safeDelete,
        allowedRoots: [sandbox.path],
        module: 'test',
        clock: () => now,
        onProgress: (done, total) {
          expect(done, lessThanOrEqualTo(total));
          ticks.add(done);
        },
      );

      expect(ticks, isNotEmpty);
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i], greaterThanOrEqualTo(ticks[i - 1]));
      }
    });
  });

  group('scanAll', () {
    test('produces one finding per target that has anything to reclaim', () async {
      final populated = CleanTarget(
        id: 'populated',
        titleKey: 't',
        descriptionKey: 'd',
        category: CleanCategory.temp,
        roots: [sandbox.path],
      );
      final empty = CleanTarget(
        id: 'empty',
        titleKey: 't',
        descriptionKey: 'd',
        category: CleanCategory.temp,
        roots: ['${sandbox.path}/does-not-exist'],
      );

      write('x.bin', 4242, age: const Duration(days: 40));

      final findings = await DirectorySweeper().scanAll(
        [populated, empty],
        clock: () => now,
      );

      expect(findings.map((f) => f.target.id), ['populated']);
      expect(findings.single.totalBytes, 4242);
      expect(findings.single.fileCount, 1);
    });
  });
}