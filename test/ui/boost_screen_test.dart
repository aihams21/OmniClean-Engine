import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/boost/boost_plan.dart';
import 'package:omni_clean_engine/ui/controllers/boost_controller.dart';
import 'package:omni_clean_engine/ui/l10n/generated/app_localizations.dart';
import 'package:omni_clean_engine/ui/screens/boost_screen.dart';
import 'package:omni_clean_engine/ui/theme/app_theme.dart';

const BoostAction governor = BoostAction(
  id: 'linux_cpu_governor',
  titleKey: 'boostActionGovernorTitle',
  descriptionKey: 'boostActionGovernorDescription',
  impact: BoostImpact.frames,
  requiresPrivilege: true,
  script: 'echo performance',
);
const BoostAction caches = BoostAction(
  id: 'linux_drop_caches',
  titleKey: 'boostActionDropCachesTitle',
  descriptionKey: 'boostActionDropCachesDescription',
  impact: BoostImpact.memory,
  requiresPrivilege: true,
  script: 'echo 3 > /proc/sys/vm/drop_caches',
);

void main() {
  late Map<String, BoostActionResult> answers;

  BoostController build({List<BoostAction>? plan}) => BoostController(
        plan: plan ?? const <BoostAction>[governor, caches],
        executor: (_) async => answers,
      );

  setUp(() {
    answers = <String, BoostActionResult>{
      'linux_cpu_governor': const BoostActionResult(
          id: 'linux_cpu_governor', ok: true, detail: 'performance'),
      'linux_drop_caches': const BoostActionResult(
          id: 'linux_drop_caches', ok: false, detail: 'read-only file system'),
    };
  });

  Future<void> pump(WidgetTester tester, BoostController controller,
      {Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(1400, 900);
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
        home: Scaffold(body: BoostScreen(controller: controller)),
      ),
    );
    await tester.pump();
  }

  testWidgets('lists every step with its own copy', (tester) async {
    await pump(tester, build());

    expect(find.text('Boost'), findsOneWidget);
    expect(find.text('Pin the CPU to performance mode'), findsOneWidget);
    expect(
        find.text('Release the page cache back to the kernel'), findsOneWidget);
    expect(find.text('Boost now'), findsOneWidget);
  });

  testWidgets('says plainly when the platform has nothing to offer',
      (tester) async {
    await pump(tester, build(plan: const <BoostAction>[]));

    expect(find.text('Boost now'), findsNothing);
    expect(find.textContaining('needs administrator rights'), findsOneWidget);
  });

  testWidgets('a run reports what worked and what did not, verbatim',
      (tester) async {
    final controller = build();
    await pump(tester, controller);

    await tester.tap(find.text('Boost now'));
    await tester.pumpAndSettle();

    expect(find.text('performance'), findsOneWidget);
    expect(find.text('read-only file system'), findsOneWidget);
    expect(find.textContaining('1 of 2'), findsOneWidget);
    expect(controller.succeededCount, 1);
    expect(controller.failedCount, 1);
  });

  testWidgets('a run where nothing worked never claims a win', (tester) async {
    answers = <String, BoostActionResult>{
      for (final String id in <String>[
        'linux_cpu_governor',
        'linux_drop_caches'
      ])
        id: BoostActionResult(id: id, ok: false, detail: 'nope'),
    };
    final controller = build();
    await pump(tester, controller);

    await tester.tap(find.text('Boost now'));
    await tester.pumpAndSettle();

    expect(controller.didAnything, isFalse);
    expect(find.textContaining('Nothing changed'), findsOneWidget);
  });

  testWidgets('the button is disabled and honest while the run is in flight',
      (tester) async {
    final gate = Completer<void>();
    final controller = BoostController(
      plan: const <BoostAction>[governor],
      executor: (_) async {
        await gate.future;
        return answers;
      },
    );
    await pump(tester, controller);

    await tester.tap(find.text('Boost now'));
    await tester.pump();

    expect(find.text('Boosting…'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Boost again'), findsOneWidget);
  });

  testWidgets('Arabic renders the whole screen', (tester) async {
    await pump(tester, build(), locale: const Locale('ar'));

    expect(find.text('تسريع'), findsOneWidget);
    expect(find.text('سرّع الآن'), findsOneWidget);
  });
}
