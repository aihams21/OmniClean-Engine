import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/ui/l10n/generated/app_localizations.dart';
import 'package:omni_clean_engine/ui/theme/app_theme.dart';
import 'package:omni_clean_engine/ui/widgets/arc_gauge.dart';
import 'package:omni_clean_engine/ui/widgets/cyber_background.dart';
import 'package:omni_clean_engine/ui/widgets/module_tile.dart';
import 'package:omni_clean_engine/ui/widgets/storage_bar.dart';

Widget _wrap(
  Widget child, {
  Locale locale = const Locale('en'),
  AccentChoice accent = AccentChoice.cyber,
  ThemeData? theme,
}) {
  return MaterialApp(
    theme: theme ?? AppTheme.build(accent),
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('CyberBackground', () {
    testWidgets('paints its grid behind the child', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CyberBackground(child: Text('payload')),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('payload'), findsOneWidget);
    });

    testWidgets('survives a zero-size box without throwing', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            height: 0,
            width: 0,
            child: CyberBackground(child: SizedBox.shrink()),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ArcGauge', () {
    testWidgets('renders the label and the rounded percentage',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const ArcGauge(label: 'CPU', value: 0.421)),
      );

      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
    });

    testWidgets('renders 0% for a genuine zero, not a blank', (tester) async {
      await tester.pumpWidget(_wrap(const ArcGauge(label: 'CPU', value: 0)));
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('shows the unavailable label instead of a fake zero',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ArcGauge(label: 'CPU', value: null),
          locale: const Locale('en'),
        ),
      );

      expect(find.text('42%'), findsNothing);
      expect(find.text('unavailable'), findsOneWidget);
    });

    testWidgets('shows the Arabic unavailable label under Arabic',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ArcGauge(label: 'المعالج', value: null),
          locale: const Locale('ar'),
        ),
      );

      expect(find.text('unavailable'), findsNothing);
      expect(find.text('غير متاح'), findsOneWidget);
    });
    testWidgets('clamps hostile values instead of overflowing',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const ArcGauge(label: 'RAM', value: 12.5)),
      );
      expect(find.text('100%'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const ArcGauge(label: 'RAM', value: -3)),
      );
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('exposes an accessible label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(const ArcGauge(label: 'CPU', value: 0.5)),
      );
      expect(tester.getSemantics(find.byType(ArcGauge)).label, 'CPU 50%');
      handle.dispose();
    });

    test('the sweep angle maps 0..1 onto a three-quarter dial', () {
      expect(ArcGaugePainter.sweepFor(0), 0);
      expect(ArcGaugePainter.sweepFor(1), closeTo(1.5 * 3.141592653589793, 1e-9));
      expect(ArcGaugePainter.sweepFor(0.5),
          closeTo(0.75 * 3.141592653589793, 1e-9));
      expect(ArcGaugePainter.sweepFor(9), closeTo(1.5 * 3.141592653589793, 1e-9));
      expect(ArcGaugePainter.sweepFor(-1), 0);
    });
  });

  group('StorageBar', () {
    testWidgets('renders a filled proportional bar with a legend',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StorageBar(usedBytes: 250000000000, freeBytes: 150000000000),
        ),
      );

      expect(find.byType(StorageBar), findsOneWidget);
      expect(find.byType(Expanded), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero-capacity disk still renders instead of dividing by zero',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const StorageBar(usedBytes: 0, freeBytes: 0)),
      );
      expect(tester.takeException(), isNull);
    });

    test('the fill fraction is clamped to 0..1', () {
      expect(StorageBar.fractionFor(usedBytes: 50, freeBytes: 50),
          closeTo(0.5, 1e-9));
      expect(StorageBar.fractionFor(usedBytes: 90, freeBytes: 0), 1.0);
      expect(StorageBar.fractionFor(usedBytes: 0, freeBytes: 0), 0.0);
    });
  });

  group('ModuleTile', () {
    testWidgets('shows the localized title, size and risk chip',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ModuleTile(
            title: 'APT archives',
            description: 'Downloaded .deb files',
            sizeText: '407 MB',
            risk: RiskLevel.moderate,
            selected: true,
          ),
        ),
      );

      expect(find.text('APT archives'), findsOneWidget);
      expect(find.text('Downloaded .deb files'), findsOneWidget);
      expect(find.text('407 MB'), findsOneWidget);
      expect(find.byType(RiskChip), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('tapping the tile toggles selection', (tester) async {
      var selected = false;
      await tester.pumpWidget(
        _wrap(
          ModuleTile(
            title: 'APT archives',
            description: 'x',
            sizeText: '1 MB',
            risk: RiskLevel.safe,
            selected: selected,
            onChanged: (value) => selected = value ?? false,
          ),
        ),
      );

      await tester.tap(find.text('APT archives'));
      await tester.pump();
      expect(selected, isTrue);
    });

    testWidgets('a module needing root says so in the user language',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ModuleTile(
            title: 'APT',
            description: 'x',
            sizeText: '1 MB',
            risk: RiskLevel.elevated,
            requiresPrivilege: true,
            selected: false,
          ),
          locale: const Locale('en'),
        ),
      );

      expect(find.text('Administrator rights required'), findsOneWidget);
    });
  });
}
