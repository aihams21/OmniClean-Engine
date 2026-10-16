import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/platform/method_channel_gateway.dart';
import 'package:omni_clean_engine/engine/platform/storage_gateway.dart';
import 'package:omni_clean_engine/ui/controllers/library_controller.dart';
import 'package:omni_clean_engine/ui/l10n/generated/app_localizations.dart';
import 'package:omni_clean_engine/ui/screens/library_screen.dart';
import 'package:omni_clean_engine/ui/theme/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

MediaItem _item(
  String name,
  int bytes, {
  String mime = 'image/jpeg',
  int daysOld = 2,
  String folder = 'DCIM/Camera',
}) =>
    MediaItem(
      id: '/storage/emulated/0/$folder/$name',
      name: name,
      path: '/storage/emulated/0/$folder/$name',
      sizeBytes: bytes,
      modified: DateTime.now().subtract(Duration(days: daysOld)),
      mimeType: mime,
      width: 4032,
      height: 3024,
    );

void main() {
  late FakeStorageGateway gateway;

  setUp(() {
    gateway = FakeStorageGateway(
      capability: const StorageCapabilities(
        apiLevel: 36,
        hasAllFilesAccess: true,
        hasMediaRead: true,
        storageRoot: '/storage/emulated/0',
        totalBytes: 128000000000,
        freeBytes: 16000000000,
        externalStorageMounted: true,
      ),
      mediaItems: <MediaItem>[
        _item('IMG_0001.jpg', 5 * 1024 * 1024),
        _item('IMG_0002.jpg', 4 * 1024 * 1024),
        _item('beach.jpeg', 3 * 1024 * 1024, daysOld: 10),
        _item('clip.mp4', 40 * 1024 * 1024,
            mime: 'video/mp4', folder: 'Movies'),
        _item('invoice.pdf', 512 * 1024,
            mime: 'application/pdf', folder: 'Documents', daysOld: 90),
        _item('setup.apk', 128 * 1024 * 1024,
            mime: 'application/vnd.android.package-archive',
            folder: 'Download'),
      ],
    );
  });

  Future<void> pump(
    WidgetTester tester,
    LibraryController controller, {
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
        home: Scaffold(body: LibraryScreen(controller: controller)),
      ),
    );
    await tester.pump();
  }

  group('LibraryScreen', () {
    testWidgets('offers a tab per library kind', (tester) async {
      final controller = LibraryController(gateway: gateway);
      addTearDown(controller.dispose);
      await pump(tester, controller);

      for (final label in [
        'Photos',
        'Videos',
        'Audio',
        'Documents',
        'Downloads',
        'All files',
      ]) {
        expect(find.text(label), findsWidgets,
            reason: 'missing the $label tab');
      }
    });

    testWidgets('asks for nothing until the user taps load', (tester) async {
      final controller = LibraryController(gateway: gateway);
      addTearDown(controller.dispose);
      await pump(tester, controller);

      expect(find.text('IMG_0001.jpg'), findsNothing);
      expect(find.text('Nothing here yet.'), findsNothing);
      expect(find.text('Load'), findsOneWidget);
    });

    testWidgets('lists photos newest first with the real total',
        (tester) async {
      final controller = LibraryController(gateway: gateway);
      addTearDown(controller.dispose);
      await pump(tester, controller);

      await tester.tap(find.text('Load'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('IMG_0001.jpg'), findsOneWidget);
      expect(find.text('3 items · 12.0 MB'), findsOneWidget);
    });

    testWidgets('switching to files shows documents and downloads only',
        (tester) async {
      final controller = LibraryController(gateway: gateway);
      addTearDown(controller.dispose);
      await pump(tester, controller);

      await tester.tap(find.text('Load'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('All files').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('setup.apk'), findsOneWidget);
      expect(find.text('IMG_0001.jpg'), findsNothing);
    });

    testWidgets('a blind device asks for access instead of showing nothing',
        (tester) async {
      final blind = FakeStorageGateway(
        capability: const StorageCapabilities(apiLevel: 36),
        mediaItems: gateway.mediaItems,
      );
      final controller = LibraryController(gateway: blind);
      addTearDown(controller.dispose);
      await pump(tester, controller);

      await tester.tap(find.text('Load'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Storage access needed'), findsOneWidget);
      expect(find.text('Grant access'), findsOneWidget);
    });

    testWidgets('renders Arabic labels right-to-left', (tester) async {
      final controller = LibraryController(gateway: gateway);
      addTearDown(controller.dispose);
      await pump(tester, controller, locale: const Locale('ar'));

      expect(find.text('المكتبة'), findsWidgets);
      expect(find.text('الصور'), findsWidgets);
      expect(find.text('حمّل'), findsOneWidget);
    });
  });
}
