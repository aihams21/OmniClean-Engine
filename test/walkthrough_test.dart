import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/bootstrap.dart';
import 'package:omni_clean_engine/core/safety/quarantine.dart';
import 'package:omni_clean_engine/core/safety/safe_delete.dart';
import 'package:omni_clean_engine/engine/cleaners/clean_target.dart';
import 'package:omni_clean_engine/engine/metrics/metrics_collector.dart';
import 'package:omni_clean_engine/engine/metrics/system_snapshot.dart';
import 'package:omni_clean_engine/ui/controllers/cleaner_controller.dart';
import 'package:omni_clean_engine/ui/controllers/duplicates_controller.dart';
import 'package:omni_clean_engine/ui/controllers/quarantine_controller.dart';
import 'package:omni_clean_engine/ui/controllers/settings_controller.dart';

/// Replays the real application offscreen and writes one PNG per scene.
///
/// Every screenshot is produced by the genuine widget tree, the genuine themes
/// and the genuine l10n layer; only the GPU is replaced by the software
/// rasteriser that `flutter test` ships with. The numbers on screen are real:
/// the metrics come from `/proc`, and the cleaner runs against a sandbox tree
/// full of genuine junk.
class _FrozenMetricsSource implements MetricsSource {
  const _FrozenMetricsSource(this._snapshot);

  final SystemSnapshot _snapshot;

  @override
  MetricsPlatform get platform => _snapshot.platform;

  @override
  Future<SystemSnapshot> capture() async => _snapshot;
}

const String _canvasKey = 'walkthrough-canvas';
const String _framesDir = 'docs/walkthrough/frames';

final Map<String, Object?> _manifest = <String, Object?>{
  'width': 1280,
  'height': 820,
  'scenes': <Map<String, Object?>>[],
};

const String _flutterRoot = '/home/aiham/flutter';

Future<void> _loadFonts() async {
  Future<void> register(String family, List<String> paths) async {
    final FontLoader loader = FontLoader(family);
    for (final String path in paths) {
      if (!File(path).existsSync()) continue;
      final Uint8List bytes = await File(path).readAsBytes();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await register('Roboto', <String>[
    '$_flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    '$_flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf',
    '$_flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf',
  ]);
  await register('NotoSansArabic', <String>[
    '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansArabic-Bold.ttf',
  ]);
  await register('MaterialIcons', <String>[
    '$_flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  await register('monospace', <String>[
    '$_flutterRoot/bin/cache/artifacts/material_fonts/RobotoMono-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
  ]);
}

/// Fills a directory with genuine, aged junk so every byte on screen is real.
void _seedJunk(Directory sandbox) {
  final Random random = Random(7);
  const List<String> trees = <String>[
    'cache/browser',
    'cache/thumbnails',
    'cache/app-runtime',
    'tmp',
    'logs',
    'trash/files',
  ];
  for (int t = 0; t < trees.length; t++) {
    final Directory dir = Directory('${sandbox.path}/${trees[t]}');
    dir.createSync(recursive: true);
    for (int i = 0; i < 6 + t * 3; i++) {
      final int size = 4000 + random.nextInt(180000);
      final File file = File('${dir.path}/blob_${t}_$i.bin');
      file.writeAsBytesSync(List<int>.filled(size, 65 + (i % 26)));
      file.setLastModifiedSync(
        DateTime.now().subtract(Duration(days: 10 + i)),
      );
    }
  }
}

void _seedDuplicates(Directory sandbox) {
  final Directory dir = Directory('${sandbox.path}/photos')..createSync(recursive: true);
  Uint8List chunk(int seed) => Uint8List.fromList(
        List<int>.generate(20000, (int i) => (i * 7 + seed * 31) % 251),
      );
  File('${dir.path}/IMG_0042.jpg').writeAsBytesSync(chunk(1));
  File('${dir.path}/holiday-copy.jpg').writeAsBytesSync(chunk(1));
  File('${dir.path}/beach.jpeg').writeAsBytesSync(chunk(1));
  File('${dir.path}/sunset.jpg').writeAsBytesSync(chunk(2));
  File('${dir.path}/sunset (1).jpg').writeAsBytesSync(chunk(2));
  File('${dir.path}/notes.txt').writeAsStringSync('not a duplicate');
}

/// Pumps, then writes the current frame and records where it was taken.
Future<void> _scene(
  WidgetTester tester,
  String name, {
  String? caption,
  Offset? click,
  int holdFrames = 26,
}) async {
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 120));
  await tester.runAsync(() => _shoot(tester, name));
  final Map<String, Object?> scene = <String, Object?>{
    'image': '$_framesDir/$name.png',
    'caption': caption ?? '',
    'hold': holdFrames,
  };
  if (click != null) {
    scene['click'] = <int>[click.dx.round(), click.dy.round()];
  }
  (_manifest['scenes']! as List<Map<String, Object?>>).add(scene);
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final RenderRepaintBoundary boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey<String>(_canvasKey)),
  );
  final ui.Image image = await boundary.toImage(pixelRatio: 1);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final File out = File('$_framesDir/$name.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(data!.buffer.asUint8List());
}

Offset _centre(WidgetTester tester, Finder finder) =>
    tester.getCenter(finder.first);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 260));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('the documented walkthrough is reproducible', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A fixed, readable path: the duplicate screen shows its roots verbatim,
    // and a random `omniclean_walk_PCDYU` suffix looks like a bug in a GIF.
    final Directory sandbox =
        Directory('${Directory.systemTemp.path}/OmniClean-Demo');
    await tester.runAsync(() async {
      if (sandbox.existsSync()) await sandbox.delete(recursive: true);
      await sandbox.create(recursive: true);
    });
    addTearDown(() async {
      if (sandbox.existsSync()) await sandbox.delete(recursive: true);
    });

    // Real junk, real duplicates, real metrics.
    await tester.runAsync(() async {
      _seedJunk(sandbox);
      _seedDuplicates(sandbox);
    });

    // Two real captures so the CPU number is a genuine delta, not a zero.
    final SystemSnapshot live = (await tester.runAsync(() async {
      final MetricsSource source = createMetricsSource();
      await source.capture();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      return source.capture();
    }))!;

    final Quarantine quarantine = Quarantine(
      root: Directory('${sandbox.path}/.omniclean/trash'),
    );
    await tester.runAsync(quarantine.init);

    final SettingsController settings = SettingsController();
    await tester.runAsync(settings.load);
    final SafeDelete safeDelete = SafeDelete(
      quarantine: quarantine,
      privilegeProbe: () async => false,
    );

    String root(String relative) => '${sandbox.path}/$relative';

    final CleanTargetSet walkTargets = CleanTargetSet(<CleanTarget>[
      CleanTarget(
        id: 'walk_home_cache',
        titleKey: 'targetHomeCacheTitle',
        descriptionKey: 'targetHomeCacheDescription',
        category: CleanCategory.appCache,
        roots: <String>[root('cache/browser'), root('cache/app-runtime')],
        minAge: const Duration(hours: 1),
      ),
      CleanTarget(
        id: 'walk_thumbnails',
        titleKey: 'targetThumbnailsTitle',
        descriptionKey: 'targetThumbnailsDescription',
        category: CleanCategory.appCache,
        roots: <String>[root('cache/thumbnails')],
        minAge: const Duration(hours: 1),
      ),
      CleanTarget(
        id: 'walk_tmp',
        titleKey: 'targetTmpTitle',
        descriptionKey: 'targetTmpDescription',
        category: CleanCategory.temp,
        risk: RiskLevel.moderate,
        roots: <String>[root('tmp')],
        minAge: const Duration(hours: 1),
      ),
      CleanTarget(
        id: 'walk_logs',
        titleKey: 'targetCrashReportsTitle',
        descriptionKey: 'targetCrashReportsDescription',
        category: CleanCategory.logs,
        risk: RiskLevel.elevated,
        requiresPrivilege: true,
        roots: <String>[root('logs')],
        minAge: const Duration(hours: 1),
      ),
      CleanTarget(
        id: 'walk_trash',
        titleKey: 'targetTrashTitle',
        descriptionKey: 'targetTrashDescription',
        category: CleanCategory.junk,
        roots: <String>[root('trash/files')],
        minAge: const Duration(hours: 1),
      ),
    ]);

    final CleanerController cleaner = CleanerController(
      targets: walkTargets,
      safeDelete: safeDelete,
    );
    final DuplicatesController duplicates = DuplicatesController(
      safeDelete: safeDelete,
      roots: <String>['${sandbox.path}/photos'],
    );
    final QuarantineController quarantineController = QuarantineController(
      quarantine: quarantine,
      retention: settings.retention,
    );
    final SystemMetricsService metrics = SystemMetricsService(
      source: _FrozenMetricsSource(live),
      interval: const Duration(hours: 1),
    );

    final OmniCleanRuntime runtime = OmniCleanRuntime(
      quarantineRoot: quarantine.root,
      quarantine: quarantine,
      safeDelete: safeDelete,
      settings: settings,
      cleaner: cleaner,
      duplicates: duplicates,
      quarantineController: quarantineController,
      metrics: metrics,
      privilegeProbe: () async => false,
    );
    addTearDown(runtime.dispose);

    // ---------------------------------------------------------------- 01
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey<String>(_canvasKey),
        child: OmniCleanApp(runtime: runtime),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Dashboard'), findsWidgets);
    await _scene(tester, '01_dashboard_idle');

    // ---------------------------------------------------------------- 02
    await tester.runAsync(cleaner.scan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(cleaner.totalBytes, greaterThan(0));
    await _scene(tester, '02_dashboard_scanned');

    // ---------------------------------------------------------------- 03
    final Offset cleanerTab = _centre(tester, find.text('Cleaner'));
    await _tap(tester, find.text('Cleaner'));
    await _scene(tester, '03_cleaner_list', click: cleanerTab);

    // ---------------------------------------------------------------- 04
    final Finder cleanButton = find.textContaining('Clean selected');
    final Offset cleanPoint = _centre(tester, cleanButton);
    await _tap(tester, cleanButton);
    await _scene(tester, '04_confirm_dialog', click: cleanPoint);

    // ---------------------------------------------------------------- 05
    final Finder proceed = find.textContaining('Move to quarantine').last;
    final Offset proceedPoint = _centre(tester, proceed);
    await _tap(tester, proceed);
    // The dialog's own confirm button starts the clean inside the test's fake
    // clock zone, so real file I/O only progresses while we open real-async
    // windows and pump again.
    for (int i = 0; i < 900 && cleaner.phase == CleanPhase.cleaning; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(cleaner.bytesFreed, greaterThan(0));
    await _scene(tester, '05_cleaned', click: proceedPoint);

    // ---------------------------------------------------------------- 06
    final Offset quarantineTab = _centre(tester, find.text('Quarantine'));
    await _tap(tester, find.text('Quarantine'));
    await tester.runAsync(quarantineController.load);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(quarantineController.items, isNotEmpty);
    await _scene(tester, '06_quarantine', click: quarantineTab);

    // ---------------------------------------------------------------- 07
    final Offset dupesTab = _centre(tester, find.text('Duplicates'));
    await _tap(tester, find.text('Duplicates'));
    await tester.runAsync(duplicates.scan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(duplicates.groups, isNotEmpty);
    await _scene(tester, '07_duplicates', click: dupesTab);

    // ---------------------------------------------------------------- 08
    duplicates.selectGroup(duplicates.groups.first.sha256);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final Offset deletePoint = _centre(
      tester,
      find.textContaining('Delete the rest'),
    );
    await _tap(tester, find.textContaining('Delete the rest'));
    await _scene(tester, '08_duplicates_confirm', click: deletePoint);

    // ---------------------------------------------------------------- 09
    final Offset settingsTab = _centre(tester, find.text('Settings'));
    await _tap(tester, find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 200));
    await _scene(tester, '09_settings', click: settingsTab);

    // ---------------------------------------------------------------- 10
    await tester.runAsync(
      () => settings.setAccent(AccentChoice.crimson),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    final Offset dashTab = _centre(tester, find.text('Dashboard'));
    await _tap(tester, find.text('Dashboard'));
    await _scene(tester, '10_crimson_dashboard', click: dashTab);

    // ---------------------------------------------------------------- 11
    await tester.runAsync(
      () => settings.setAccent(AccentChoice.cyber),
    );
    await tester.runAsync(
      () => settings.setLanguage(LanguageChoice.arabic),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('لوحة التحكم'), findsWidgets);
    await _scene(tester, '11_arabic_dashboard');

    // ---------------------------------------------------------------- 12
    final Offset arCleaner = _centre(tester, find.text('المنظّف'));
    await _tap(tester, find.text('المنظّف'));
    await _scene(tester, '12_arabic_cleaner', click: arCleaner);

    // ---------------------------------------------------------------- 13
    await tester.runAsync(
      () => settings.setLanguage(LanguageChoice.english),
    );
    tester.view.physicalSize = const Size(430, 820);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _scene(tester, '13_narrow_layout');
    tester.view.physicalSize = const Size(1280, 820);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final File manifest = File('docs/walkthrough/scenes.json');
    manifest.parent.createSync(recursive: true);
    manifest.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_manifest),
    );
    expect(manifest.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
