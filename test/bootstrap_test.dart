import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/bootstrap.dart';
import 'package:omni_clean_engine/engine/metrics/metrics_collector.dart';
import 'package:omni_clean_engine/engine/metrics/system_snapshot.dart';
import 'package:omni_clean_engine/ui/controllers/settings_controller.dart';
import 'package:omni_clean_engine/ui/l10n/generated/app_localizations.dart';
import 'package:omni_clean_engine/ui/theme/app_theme.dart';

/// Keeps the dashboard off the real `/proc` tree: under `FakeAsync` a genuine
/// `Process.run` would never resolve and `pumpAndSettle` would spin forever.
class _SilentMetricsSource implements MetricsSource {
  const _SilentMetricsSource();

  @override
  MetricsPlatform get platform => MetricsPlatform.unsupported;

  @override
  Future<SystemSnapshot> capture() async =>
      SystemSnapshot.empty(MetricsPlatform.unsupported);
}

void main() {
  group('resolveLocale', () {
    test('an explicit choice wins over the platform locale', () {
      expect(
        resolveLocale(LanguageChoice.english, const Locale('ar', 'DZ')),
        const Locale('en'),
      );
      expect(
        resolveLocale(LanguageChoice.arabic, const Locale('en', 'US')),
        const Locale('ar'),
      );
    });

    test('"system" follows whatever the device reports', () {
      expect(
        resolveLocale(LanguageChoice.system, const Locale('ar', 'EG')),
        const Locale('ar', 'EG'),
      );
      expect(
        resolveLocale(LanguageChoice.system, const Locale('en')),
        const Locale('en'),
      );
    });

    test('an unsupported device locale falls back to English', () {
      expect(
        resolveLocale(LanguageChoice.system, const Locale('fr', 'FR')),
        const Locale('en'),
      );
    });
  });

  group('OmniCleanRuntime', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('omniclean_boot_');
    });

    tearDown(() async {
      if (sandbox.existsSync()) await sandbox.delete(recursive: true);
    });

    test('wires every controller the shell needs', () async {
      final runtime = await bootstrapRuntime(
        quarantineRoot: Directory('${sandbox.path}/.omniclean/trash'),
      );
      addTearDown(runtime.dispose);

      expect(runtime.settings.isLoaded, isTrue);
      expect(runtime.cleaner.modules, isNotEmpty);
      expect(runtime.duplicates.roots, isNotEmpty);
      expect(runtime.metrics.latest, isNull);
      await runtime.quarantineController.load();
      expect(runtime.quarantineController.items, isEmpty);
    });

    test('creating the quarantine directory is part of bootstrapping',
        () async {
      final root = Directory('${sandbox.path}/.omniclean/trash');
      final runtime = await bootstrapRuntime(quarantineRoot: root);
      addTearDown(runtime.dispose);

      expect(root.existsSync(), isTrue);
      expect(Directory('${root.path}/manifest').existsSync(), isTrue);
    });

    test('dispose is idempotent', () async {
      final runtime = await bootstrapRuntime(
        quarantineRoot: Directory('${sandbox.path}/.omniclean/trash'),
      );

      runtime.dispose();
      expect(runtime.dispose, returnsNormally);
    });
  });

  group('OmniCleanApp', () {
    testWidgets('renders the shell with the saved accent and language',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final sandbox = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('omniclean_app_'),
      ))!;
      addTearDown(() async {
        if (sandbox.existsSync()) await sandbox.delete(recursive: true);
      });

      final runtime = (await tester.runAsync(
        () => bootstrapRuntime(
          quarantineRoot: Directory('${sandbox.path}/.omniclean/trash'),
          privilegeProbe: () async => false,
          metricsSource: const _SilentMetricsSource(),
          // The 2 s production tick would fire forever under `FakeAsync`: every
          // tick rebuilds the dashboard, so `pumpAndSettle` could never settle.
          metricsInterval: const Duration(hours: 1),
        ),
      ))!;
      addTearDown(runtime.dispose);
      await runtime.settings.setLanguage(LanguageChoice.arabic);

      await tester.pumpWidget(OmniCleanApp(runtime: runtime));
      await tester.pumpAndSettle();

      expect(find.text('لوحة التحكم'), findsWidgets);
      expect(find.byType(NavigationRail), findsOneWidget);
    });
  });

  group('AppTheme', () {
    test('still offers both accents after the app is wired', () {
      expect(AppTheme.build(AccentChoice.crimson).primaryColor,
          AppTheme.build(AccentChoice.crimson).primaryColor);
      expect(AppLocalizations.supportedLocales.length, 2);
    });
  });
}
