import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/boost/boost_plan.dart';

void main() {
  group('boostActionsFor', () {
    test('android is one native step and never asks for a script', () {
      final actions = boostActionsFor(os: 'android', isRoot: false);

      expect(actions, hasLength(1));
      expect(actions.single.id, 'android_platform_boost');
      expect(actions.single.script, isEmpty);
      expect(actions.single.requiresPrivilege, isFalse);
    });

    test('linux without root lists nothing rather than failing later', () {
      expect(boostActionsFor(os: 'linux', isRoot: false), isEmpty);
    });

    test('linux with root lists the frame-time steps first', () {
      final actions = boostActionsFor(os: 'linux', isRoot: true);

      expect(actions.map((a) => a.id), <String>[
        'linux_cpu_governor',
        'linux_swappiness',
        'linux_drop_caches',
        'linux_fstrim',
      ]);
      expect(actions.first.impact, BoostImpact.frames);
      expect(actions.every((a) => a.requiresPrivilege), isTrue);
      expect(actions.every((a) => a.script.trim().isNotEmpty), isTrue);
    });

    test('windows keeps the unprivileged steps and gates the privileged one',
        () {
      final plain = boostActionsFor(os: 'windows 10', isRoot: false);
      final admin = boostActionsFor(os: 'windows 11', isRoot: true);

      expect(plain.map((a) => a.id), <String>[
        'windows_power_plan',
        'windows_trim_working_sets',
      ]);
      expect(plain.every((a) => !a.requiresPrivilege), isTrue);
      expect(admin, hasLength(3));
      expect(admin.last.id, 'windows_suspend_indexer');
    });

    test('every step declares its own copy so the UI can never show a blank',
        () {
      final ids = <String>{};
      for (final os in <String>['android', 'linux', 'windows']) {
        for (final action in boostActionsFor(os: os, isRoot: true)) {
          expect(action.titleKey, isNotEmpty, reason: action.id);
          expect(action.descriptionKey, isNotEmpty, reason: action.id);
          expect(ids.add(action.id), isTrue, reason: '${action.id} duplicated');
        }
      }
    });

    test('the impact order puts frame time before storage', () {
      expect(boostImpactOrder.first, BoostImpact.frames);
      expect(boostImpactOrder, contains(BoostImpact.memory));
      expect(boostImpactOrder, hasLength(4));
    });
  });
}
