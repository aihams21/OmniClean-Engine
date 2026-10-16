import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/platform/method_channel_gateway.dart';
import 'package:omni_clean_engine/engine/platform/storage_gateway.dart';
import 'package:omni_clean_engine/ui/controllers/unused_apps_controller.dart';
import 'package:omni_clean_engine/ui/l10n/generated/app_localizations.dart';
import 'package:omni_clean_engine/ui/screens/unused_apps_screen.dart';
import 'package:omni_clean_engine/ui/theme/app_theme.dart';

AppUsage _app(
  String pkg,
  String label,
  int bytes, {
  int idleDays = 90,
  bool isSystem = false,
  bool neverOpened = false,
}) =>
    AppUsage(
      packageName: pkg,
      label: label,
      sizeBytes: bytes,
      lastUsed: neverOpened
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.now().subtract(Duration(days: idleDays)),
      isSystem: isSystem,
    );

void main() {
  final stale = _app('com.old.game', 'Dead Game', 2000000000, idleDays: 120);
  final forgetful = _app('com.maybe', 'Maybe News', 400000000, idleDays: 31);
  final never = _app(
    'com.never',
    'Never Opened',
    100000000,
    neverOpened: true,
  );

  FakeStorageGateway gatewayWith({
    List<AppUsage>? apps,
    StorageCapabilities? capability,
  }) =>
      FakeStorageGateway(
        capability: capability ??
            const StorageCapabilities(
              apiLevel: 36,
              hasAllFilesAccess: true,
              hasMediaRead: true,
              canQueryUsageStats: true,
              canUninstallApps: true,
              storageRoot: '/storage/emulated/0',
              totalBytes: 128000000000,
              freeBytes: 16000000000,
              externalStorageMounted: true,
            ),
        applications: apps ?? <AppUsage>[stale, forgetful, never],
      );

  Future<void> pump(
    WidgetTester tester,
    UnusedAppsController controller, {
    Locale locale = const Locale('en'),
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
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
        home: Scaffold(
          body: UnusedAppsScreen(controller: controller),
        ),
      ),
    );
    await tester.pump();
  }

  UnusedAppsController build(FakeStorageGateway gateway) =>
      UnusedAppsController(gateway: gateway);

  testWidgets('offers the idle threshold before anything is scanned',
      (tester) async {
    final controller = build(gatewayWith());
    addTearDown(controller.dispose);

    await pump(tester, controller);

    expect(find.text('Unused apps'), findsOneWidget);
    expect(find.text('Idle for'), findsOneWidget);
    for (final days in <String>['1', '7', '30', '90', '180', '365']) {
      expect(find.text(days), findsWidgets, reason: 'threshold $days');
    }
  });

  testWidgets('says nothing is scanned yet instead of claiming zero apps',
      (tester) async {
    final controller = build(gatewayWith());
    addTearDown(controller.dispose);

    await pump(tester, controller);

    expect(find.textContaining('Nothing is scanned yet'), findsOneWidget);
    expect(find.text('No unused apps at this threshold.'), findsNothing);
  });

  testWidgets('the scan button loads the apps and their real sizes',
      (tester) async {
    final controller = build(gatewayWith());
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.tap(find.text('Scan my apps'));
    await tester.pumpAndSettle();

    expect(find.text('Dead Game'), findsOneWidget);
    expect(find.text('Never Opened'), findsOneWidget);
    expect(find.textContaining('3 apps'), findsOneWidget);
    expect(find.text('Never opened'), findsOneWidget);
    expect(find.text('31 days idle'), findsOneWidget);
  });

  testWidgets('a device that cannot report usage says so and offers the grant',
      (tester) async {
    final controller = build(
      gatewayWith(capability: const StorageCapabilities(apiLevel: 36)),
    );
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.tap(find.text('Scan my apps'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Usage access is required'), findsOneWidget);
    expect(find.text('Allow usage access'), findsOneWidget);
    expect(find.text('Dead Game'), findsNothing);
  });

  testWidgets('selecting apps then uninstalling asks the platform once each',
      (tester) async {
    final gateway = gatewayWith();
    final controller = build(gateway);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.tap(find.text('Scan my apps'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dead Game'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 selected'), findsOneWidget);

    await tester.tap(find.text('Uninstall selected'));
    await tester.pumpAndSettle();

    expect(gateway.uninstallRequested, 'com.old.game');
  });

  testWidgets('renders right-to-left in Arabic', (tester) async {
    final controller = build(gatewayWith());
    addTearDown(controller.dispose);

    await pump(tester, controller, locale: const Locale('ar'));

    expect(find.text('تطبيقات ما بتستخدمها'), findsOneWidget);
    expect(
      Directionality.of(
          tester.element(find.text('تطبيقات ما بتستخدمها').first)),
      TextDirection.rtl,
    );
  });
}
