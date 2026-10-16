import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/core/safety/quarantine.dart';
import 'package:omni_clean_engine/core/safety/safe_delete.dart';
import 'package:omni_clean_engine/engine/cleaners/clean_target.dart';
import 'package:omni_clean_engine/ui/controllers/cleaner_controller.dart';

const CleanTarget _junk = CleanTarget(
  id: 'test_junk',
  titleKey: 't',
  descriptionKey: 'd',
  category: CleanCategory.temp,
);

const CleanTarget _safeCache = CleanTarget(
  id: 'test_cache',
  titleKey: 't',
  descriptionKey: 'd',
  category: CleanCategory.appCache,
);

const CleanTarget _risky = CleanTarget(
  id: 'test_risky',
  titleKey: 't',
  descriptionKey: 'd',
  category: CleanCategory.logs,
  risk: RiskLevel.elevated,
  requiresPrivilege: true,
);

const CleanTarget _moderate = CleanTarget(
  id: 'test_moderate',
  titleKey: 't',
  descriptionKey: 'd',
  category: CleanCategory.updates,
  risk: RiskLevel.moderate,
);

CleanFinding _finding(CleanTarget target, {int files = 1, int bytes = 100}) =>
    CleanFinding(target: target, fileCount: files, totalBytes: bytes);

CleanOutcome _outcome({
  List<String> cleaned = const <String>[],
  List<String> skipped = const <String>[],
  int bytesFreed = 0,
  List<String> errors = const <String>[],
}) =>
    CleanOutcome(
      cleaned: cleaned,
      skipped: skipped,
      bytesFreed: bytesFreed,
      errors: errors,
      failedPaths: const <String>[],
    );

void main() {
  late Directory sandbox;
  late SafeDelete safeDelete;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('omniclean_cleaner_');
    final quarantine = Quarantine(
      root: Directory('${sandbox.path}/quarantine'),
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

  CleanerController build({
    List<CleanTarget> targets = const <CleanTarget>[_junk, _risky],
    ModuleScanner? scanner,
    ModuleCleaner? cleaner,
  }) =>
      CleanerController(
        targets: CleanTargetSet(targets),
        safeDelete: safeDelete,
        scanner: scanner ??
            (targets, {cancel, onTarget}) async =>
                <CleanFinding>[for (final t in targets) _finding(t)],
        cleaner: cleaner ?? (target, {onProgress}) async => _outcome(),
      );

  group('before scanning', () {
    test('every target is listed with nothing to reclaim yet', () {
      final controller = build();

      expect(controller.modules.length, 2);
      expect(
        controller.modules.map((m) => m.target.id).toList(),
        <String>['test_junk', 'test_risky'],
      );
      expect(controller.totalBytes, 0);
      expect(controller.totalFiles, 0);
      expect(controller.hasScanned, isFalse);
      expect(controller.phase, CleanPhase.idle);
      expect(controller.canClean, isFalse);
      expect(controller.selectedBytes, 0);
    });

    test('every listed module reports itself empty', () {
      expect(build().modules.every((m) => m.isEmpty), isTrue);
    });
  });

  group('scan', () {
    test('fills per-module counts and the headline total', () async {
      final controller = build(
        targets: const <CleanTarget>[_junk, _safeCache],
        scanner: (targets, {cancel, onTarget}) async => <CleanFinding>[
          _finding(_junk, files: 3, bytes: 300),
          _finding(_safeCache, files: 1, bytes: 50),
        ],
      );

      await controller.scan();

      expect(controller.hasScanned, isTrue);
      expect(controller.phase, CleanPhase.idle);
      expect(controller.totalBytes, 350);
      expect(controller.totalFiles, 4);
      expect(controller.modules.first.files, 3);
      expect(controller.modules.last.bytes, 50);
    });

    test('safe targets are auto-selected, elevated ones never are', () async {
      final controller = build(
        targets: const <CleanTarget>[_safeCache, _moderate, _risky],
        scanner: (targets, {cancel, onTarget}) async => <CleanFinding>[
          _finding(_safeCache, files: 2, bytes: 200),
          _finding(_moderate, files: 4, bytes: 400),
          _finding(_risky, files: 9, bytes: 900),
        ],
      );

      await controller.scan();

      final byId = <String, ModuleStatus>{
        for (final m in controller.modules) m.target.id: m,
      };
      expect(byId['test_cache']!.selected, isTrue);
      expect(byId['test_moderate']!.selected, isTrue);
      expect(byId['test_risky']!.selected, isFalse);
      expect(controller.selectedBytes, 600);
      expect(controller.selectedNeedsPrivilege, isFalse);
    });

    test('a cancelled scan goes back to idle and is flagged', () async {
      final controller = build(
        scanner: (targets, {cancel, onTarget}) async {
          cancel?.cancel();
          return <CleanFinding>[_finding(_junk)];
        },
      );

      await controller.scan();

      expect(controller.wasCancelled, isTrue);
      expect(controller.phase, CleanPhase.idle);
      expect(controller.canClean, isFalse);
    });

    test('a scanner that throws degrades to a failed phase, not a crash',
        () async {
      final controller = build(
        scanner: (targets, {cancel, onTarget}) async =>
            throw StateError('boom'),
      );

      await controller.scan();

      expect(controller.phase, CleanPhase.failed);
      expect(controller.totalBytes, 0);
      expect(controller.modules.length, 2);
    });

    test('an empty scan leaves nothing selected and nothing to clean',
        () async {
      final controller = build(
        scanner: (targets, {cancel, onTarget}) async => <CleanFinding>[],
      );

      await controller.scan();

      expect(controller.hasScanned, isTrue);
      expect(controller.totalBytes, 0);
      expect(controller.canClean, isFalse);
      expect(controller.modules.every((m) => m.isEmpty), isTrue);
    });
  });

  group('selection', () {
    test('toggling adds and removes a module from the totals', () async {
      final controller = build(
        targets: const <CleanTarget>[_junk, _safeCache],
        scanner: (targets, {cancel, onTarget}) async => <CleanFinding>[
          _finding(_junk, files: 2, bytes: 200),
          _finding(_safeCache, files: 5, bytes: 500),
        ],
      );
      await controller.scan();
      controller.selectNone();
      expect(controller.selectedBytes, 0);
      expect(controller.canClean, isFalse);

      controller.toggle('test_junk');
      expect(controller.selectedBytes, 200);
      expect(controller.selectedFiles, 2);

      controller.toggle('test_cache');
      expect(controller.selectedBytes, 700);
      expect(controller.selectedFiles, 7);

      controller.toggle('test_junk');
      expect(controller.selectedBytes, 500);

      controller.selectNone();
      expect(controller.selectedBytes, 0);
    });

    test('selectAll picks up elevated targets only when asked explicitly',
        () async {
      final controller = build(
        targets: const <CleanTarget>[_risky],
        scanner: (targets, {cancel, onTarget}) async =>
            <CleanFinding>[_finding(_risky, files: 3, bytes: 300)],
      );
      await controller.scan();
      expect(controller.selectedBytes, 0);
      expect(controller.selectedNeedsPrivilege, isFalse);

      controller.selectAll();

      expect(controller.selectedBytes, 300);
      expect(controller.selectedNeedsPrivilege, isTrue);
    });

    test('toggling an unknown id is a no-op', () {
      final controller = build();
      expect(() => controller.toggle('nope'), returnsNormally);
      expect(controller.selectedBytes, 0);
    });
  });

  group('cleanSelected', () {
    test('cleans only the selected targets and sums their outcomes', () async {
      final called = <String>[];
      final controller = build(
        targets: const <CleanTarget>[_junk, _safeCache],
        scanner: (targets, {cancel, onTarget}) async => <CleanFinding>[
          _finding(_junk, files: 3, bytes: 300),
          _finding(_safeCache, files: 1, bytes: 50),
        ],
        cleaner: (target, {onProgress}) async {
          called.add(target.id);
          return _outcome(
            cleaned: <String>['/${target.id}'],
            bytesFreed: target.id == 'test_junk' ? 300 : 50,
          );
        },
      );

      await controller.scan();
      controller.selectNone();
      controller.toggle('test_junk');
      await controller.cleanSelected();

      expect(called, <String>['test_junk']);
      expect(controller.bytesFreed, 300);
      expect(controller.filesCleaned, 1);
      expect(controller.phase, CleanPhase.done);
      expect(controller.activeModuleId, isNull);
    });

    test('with nothing selected it does not call the cleaner at all', () async {
      var calls = 0;
      final controller = build(
        targets: const <CleanTarget>[_junk],
        scanner: (targets, {cancel, onTarget}) async =>
            <CleanFinding>[_finding(_junk)],
        cleaner: (target, {onProgress}) async {
          calls++;
          return _outcome();
        },
      );
      await controller.scan();
      controller.selectNone();

      await controller.cleanSelected();

      expect(calls, 0);
      expect(controller.bytesFreed, 0);
    });

    test('a module that throws does not abort the others', () async {
      final controller = build(
        targets: const <CleanTarget>[_junk, _safeCache],
        scanner: (targets, {cancel, onTarget}) async => <CleanFinding>[
          _finding(_junk, bytes: 100),
          _finding(_safeCache, bytes: 200),
        ],
        cleaner: (target, {onProgress}) async {
          if (target.id == 'test_junk') throw StateError('permission denied');
          return _outcome(cleaned: <String>['ok'], bytesFreed: 200);
        },
      );

      await controller.scan();
      await controller.cleanSelected();

      expect(controller.bytesFreed, 200);
      expect(controller.failedModules, <String>['test_junk']);
      expect(controller.phase, CleanPhase.done);
    });

    test('skipped files are counted without being treated as freed', () async {
      final controller = build(
        targets: const <CleanTarget>[_junk],
        scanner: (targets, {cancel, onTarget}) async =>
            <CleanFinding>[_finding(_junk, files: 5, bytes: 500)],
        cleaner: (target, {onProgress}) async => _outcome(
          cleaned: <String>['a', 'b'],
          skipped: <String>['c', 'd', 'e'],
          bytesFreed: 220,
        ),
      );

      await controller.scan();
      await controller.cleanSelected();

      expect(controller.filesCleaned, 2);
      expect(controller.filesSkipped, 3);
      expect(controller.bytesFreed, 220);
    });

    test('reports per-module progress monotonically', () async {
      final seen = <int>[];
      final controller = build(
        targets: const <CleanTarget>[_junk],
        scanner: (targets, {cancel, onTarget}) async =>
            <CleanFinding>[_finding(_junk, files: 4, bytes: 400)],
        cleaner: (target, {onProgress}) async {
          onProgress?.call(0, 4);
          onProgress?.call(2, 4);
          onProgress?.call(4, 4);
          return _outcome();
        },
      );
      controller.addListener(() {
        if (controller.progressDone > 0) seen.add(controller.progressDone);
      });

      await controller.scan();
      await controller.cleanSelected();

      expect(seen, isNotEmpty);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
      expect(controller.progressTotal, 4);
    });

    test('the active module is cleared and the phase is done afterwards',
        () async {
      late CleanerController controller;
      controller = build(
        targets: const <CleanTarget>[_junk],
        scanner: (targets, {cancel, onTarget}) async =>
            <CleanFinding>[_finding(_junk)],
        cleaner: (target, {onProgress}) async {
          expect(controller.activeModuleId, 'test_junk');
          expect(controller.phase, CleanPhase.cleaning);
          return _outcome(bytesFreed: 100);
        },
      );

      await controller.scan();
      await controller.cleanSelected();

      expect(controller.activeModuleId, isNull);
      expect(controller.phase, CleanPhase.done);
    });
  });

  test('canClean is false while a scan is running', () async {
    late CleanerController controller;
    controller = build(
      scanner: (targets, {cancel, onTarget}) async {
        expect(controller.canClean, isFalse);
        return <CleanFinding>[_finding(_junk)];
      },
    );
    await controller.scan();
  });

  test('cancelScan stops an in-flight scan', () async {
    late CleanerController controller;
    controller = build(
      scanner: (targets, {cancel, onTarget}) async {
        controller.cancelScan();
        return <CleanFinding>[_finding(_junk)];
      },
    );

    await controller.scan();

    expect(controller.wasCancelled, isTrue);
  });

  test('a second scan replaces the first set of findings', () async {
    var round = 0;
    final controller = build(
      scanner: (targets, {cancel, onTarget}) async {
        round++;
        return <CleanFinding>[_finding(_junk, bytes: round * 10)];
      },
    );

    await controller.scan();
    expect(controller.totalBytes, 10);
    await controller.scan();
    expect(controller.totalBytes, 20);
  });
}
