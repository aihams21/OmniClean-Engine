import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/core/safety/quarantine.dart';
import 'package:omni_clean_engine/core/safety/safe_delete.dart';
import 'package:omni_clean_engine/engine/cleaners/clean_target.dart';
import 'package:omni_clean_engine/engine/metrics/metrics_collector.dart';
import 'package:omni_clean_engine/engine/metrics/system_snapshot.dart';
import 'package:omni_clean_engine/ui/controllers/cleaner_controller.dart';
import 'package:omni_clean_engine/ui/controllers/duplicates_controller.dart';
import 'package:omni_clean_engine/ui/controllers/quarantine_controller.dart';
import 'package:omni_clean_engine/ui/controllers/settings_controller.dart';
import 'package:omni_clean_engine/ui/screens/app_shell.dart';
import 'package:omni_clean_engine/ui/l10n/generated/app_localizations.dart';
import 'package:omni_clean_engine/ui/theme/app_theme.dart';

void main() {
  late Directory sandbox;
  late Quarantine quarantine;
  late SafeDelete safeDelete;
  late SettingsController settings;
  late CleanerController cleaner;
  late DuplicatesController duplicates;
  late QuarantineController quarantineController;
  late SystemMetricsService metrics;

  final target = CleanTarget(
    id: 'test_cache',
    titleKey: 'cleanerTitle',
    descriptionKey: 'cleanerSubtitle',
    category: CleanCategory.appCache,
    roots: ['/tmp'],
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('omniclean_shell_');
    quarantine = Quarantine(
      root: Directory('${sandbox.path}/.omniclean/trash'),
      clock: () => DateTime.utc(2026, 10, 16, 12),
    );
    await quarantine.init();
    safeDelete = SafeDelete(
      quarantine: quarantine,
      clock: () => DateTime.utc(2026, 10, 16, 12),
    );
    settings = SettingsController();
    cleaner = CleanerController(
      targets: CleanTargetSet([target]),
      safeDelete: safeDelete,
      scanner: (targets, {cancel, onTarget}) async =>
          const <CleanFinding>[],
      cleaner: (t, {onProgress}) async => _emptyOutcome,
    );
    duplicates = DuplicatesController(safeDelete: safeDelete);
    quarantineController = QuarantineController(quarantine: quarantine);
    metrics = SystemMetricsService(
      source: const _SilentMetricsSource(),
      interval: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    metrics.dispose();
    cleaner.dispose();
    duplicates.dispose();
    settings.dispose();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = const Size(1400, 900),
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AccentChoice.cyber),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: AppShell(
          settings: settings,
          metrics: metrics,
          cleaner: cleaner,
          duplicates: duplicates,
          quarantine: quarantineController,
          privilegeProbe: () async => false,
        ),
      ),
    );
    await tester.pump();
  }

  group('navigation', () {
    testWidgets('opens on the dashboard', (tester) async {
      await pumpShell(tester);

      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('offers all five destinations in English', (tester) async {
      await pumpShell(tester);

      expect(find.text('Dashboard'), findsOneWidget);
      for (final label in ['Cleaner', 'Duplicates', 'Quarantine', 'Settings']) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('reaches every screen by tapping its destination',
        (tester) async {
      await pumpShell(tester);

      for (final entry in <String, String>{
        'Cleaner': 'Cleaner',
        'Duplicates': 'Duplicate finder',
        'Quarantine': 'Quarantine',
        'Settings': 'Settings',
      }.entries) {
        await tester.tap(find.text(entry.key).first);
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsWidgets,
            reason: 'expected ${entry.value} after tapping ${entry.key}');
      }
    });

    testWidgets('uses a rail on a wide window and a bar on a narrow one',
        (tester) async {
      await pumpShell(tester, size: const Size(1400, 900));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await pumpShell(tester, size: const Size(420, 900));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('renders Arabic labels right-to-left', (tester) async {
      await pumpShell(
        tester,
        locale: const Locale('ar'),
        direction: TextDirection.rtl,
      );

      expect(find.text('لوحة التحكم'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('لوحة التحكم').first)),
        TextDirection.rtl,
      );
    });
  });

  group('dashboard', () {
    testWidgets('shows the gauges and the reclaimable headline',
        (tester) async {
      await pumpShell(tester);

      expect(find.text('RECLAIMABLE NOW'), findsOneWidget);
      expect(find.text('unavailable'), findsWidgets);
    });

    testWidgets('reports gauges as unavailable instead of a fake zero',
        (tester) async {
      await pumpShell(tester);

      expect(find.text('0%'), findsNothing);
    });

    testWidgets('lists the modules found by the last scan', (tester) async {
      cleaner = CleanerController(
        targets: CleanTargetSet([target]),
        safeDelete: safeDelete,
        scanner: (targets, {cancel, onTarget}) async => <CleanFinding>[
          const CleanFinding(
            target: _target,
            fileCount: 3,
            totalBytes: 2048,
          ),
        ],
        cleaner: (t, {onProgress}) async => _emptyOutcome,
      );
      await cleaner.scan();
      await pumpShell(tester);

      await tester.tap(find.text('Cleaner').first);
      await tester.pumpAndSettle();

      expect(find.text('2.0 KB'), findsWidgets);
      expect(find.byType(Checkbox), findsOneWidget);
    });
  });
}

const _target = CleanTarget(
  id: 'test_cache',
  titleKey: 'cleanerTitle',
  descriptionKey: 'cleanerSubtitle',
  category: CleanCategory.appCache,
  roots: ['/tmp'],
);

/// Never touches the real `/proc` tree: the dashboard must show "unavailable"
/// rather than a live reading the assertion cannot predict.
class _SilentMetricsSource implements MetricsSource {
  const _SilentMetricsSource();

  @override
  MetricsPlatform get platform => MetricsPlatform.unsupported;

  @override
  Future<SystemSnapshot> capture() async =>
      SystemSnapshot.empty(MetricsPlatform.unsupported);
}

final _emptyOutcome = CleanOutcome(
  cleaned: [],
  skipped: [],
  bytesFreed: 0,
  errors: [],
  failedPaths: [],
);
