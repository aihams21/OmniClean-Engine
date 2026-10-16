import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/boost/boost_plan.dart';
import 'package:omni_clean_engine/ui/controllers/boost_controller.dart';

void main() {
  const BoostAction a = BoostAction(
    id: 'a',
    titleKey: 't',
    descriptionKey: 'd',
    impact: BoostImpact.frames,
    requiresPrivilege: false,
  );
  const BoostAction b = BoostAction(
    id: 'b',
    titleKey: 't',
    descriptionKey: 'd',
    impact: BoostImpact.memory,
    requiresPrivilege: false,
  );

  group('BoostController', () {
    test('starts idle with every step listed and nothing run', () {
      final controller = BoostController(
        plan: <BoostAction>[a, b],
        executor: (_) async => const <String, BoostActionResult>{},
      );

      expect(controller.phase, BoostPhase.idle);
      expect(controller.actions, hasLength(2));
      expect(controller.results, isEmpty);
      expect(controller.didAnything, isFalse);
      expect(controller.canRun, isTrue);
    });

    test('running records one result per step and reports what worked',
        () async {
      final controller = BoostController(
        plan: <BoostAction>[a, b],
        executor: (_) async => const <String, BoostActionResult>{
          'a': BoostActionResult(id: 'a', ok: true, detail: 'performance'),
          'b': BoostActionResult(id: 'b', ok: false, detail: 'read-only'),
        },
      );
      addTearDown(controller.dispose);

      await controller.run();

      expect(controller.phase, BoostPhase.done);
      expect(controller.results, hasLength(2));
      expect(controller.resultFor('a')!.detail, 'performance');
      expect(controller.resultFor('b')!.ok, isFalse);
      expect(controller.succeededCount, 1);
      expect(controller.failedCount, 1);
      expect(controller.didAnything, isTrue);
    });

    test('a step the executor forgot about is reported as a failure', () async {
      final controller = BoostController(
        plan: <BoostAction>[a, b],
        executor: (_) async => const <String, BoostActionResult>{
          'a': BoostActionResult(id: 'a', ok: true, detail: 'done'),
        },
      );
      addTearDown(controller.dispose);

      await controller.run();

      expect(controller.results, hasLength(2));
      expect(controller.resultFor('b')!.ok, isFalse);
      expect(controller.resultFor('b')!.detail, isNotEmpty);
      expect(controller.failedCount, 1);
    });

    test('an executor that throws degrades to failed, never a crash', () async {
      final controller = BoostController(
        plan: <BoostAction>[a],
        executor: (_) async => throw StateError('no shell'),
      );
      addTearDown(controller.dispose);

      await controller.run();

      expect(controller.phase, BoostPhase.failed);
      expect(controller.results, isEmpty);
      expect(controller.didAnything, isFalse);
      expect(controller.canRun, isTrue);
    });

    test('an empty plan cannot be run and says so instead of faking success',
        () async {
      final controller = BoostController(
        plan: const <BoostAction>[],
        executor: (_) async => const <String, BoostActionResult>{},
      );
      addTearDown(controller.dispose);

      expect(controller.canRun, isFalse);
      await controller.run();

      expect(controller.phase, BoostPhase.idle);
      expect(controller.didAnything, isFalse);
    });

    test('running while busy is ignored, and progress is published', () async {
      final gate = Completer<void>();
      var calls = 0;
      final controller = BoostController(
        plan: <BoostAction>[a, b],
        executor: (_) async {
          calls++;
          await gate.future;
          return const <String, BoostActionResult>{};
        },
      );
      addTearDown(controller.dispose);

      final first = controller.run();
      expect(controller.isBusy, isTrue);
      expect(controller.progressTotal, 2);

      await controller.run();
      expect(calls, 1, reason: 'the second run must be a no-op');

      gate.complete();
      await first;

      expect(controller.isBusy, isFalse);
      expect(controller.progressTotal, 2);
    });

    test('results are keyed by step id and an unknown id answers null', () {
      final controller = BoostController(
        plan: <BoostAction>[a],
        executor: (_) async => const <String, BoostActionResult>{},
      );
      addTearDown(controller.dispose);

      expect(controller.resultFor('nope'), isNull);
    });
  });
}
