import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/safety/quarantine.dart';
import 'core/safety/safe_delete.dart';
import 'core/util/logger.dart';
import 'engine/metrics/metrics_collector.dart';
import 'engine/shell.dart';
import 'ui/controllers/cleaner_controller.dart';
import 'ui/controllers/duplicates_controller.dart';
import 'ui/controllers/quarantine_controller.dart';
import 'ui/controllers/settings_controller.dart';
import 'ui/l10n/generated/app_localizations.dart';
import 'ui/screens/app_shell.dart';
import 'ui/theme/app_theme.dart';

/// Turns a language preference into a concrete [Locale].
///
/// An unsupported device locale falls back to English rather than leaving
/// Material's resolution to pick something arbitrary — the app ships exactly
/// two translations and should never show a half-translated screen.
Locale resolveLocale(LanguageChoice choice, Locale platformLocale) {
  switch (choice) {
    case LanguageChoice.english:
      return const Locale('en');
    case LanguageChoice.arabic:
      return const Locale('ar');
    case LanguageChoice.system:
      return AppLocalizations.supportedLocales
              .any((l) => l.languageCode == platformLocale.languageCode)
          ? platformLocale
          : const Locale('en');
  }
}

/// Every long-lived object the shell needs, created once and disposed together.
class OmniCleanRuntime {
  OmniCleanRuntime({
    required this.quarantineRoot,
    required this.quarantine,
    required this.safeDelete,
    required this.settings,
    required this.cleaner,
    required this.duplicates,
    required this.quarantineController,
    required this.metrics,
    this.privilegeProbe = Shell.isRoot,
  });

  final Directory quarantineRoot;
  final Quarantine quarantine;
  final SafeDelete safeDelete;
  final SettingsController settings;
  final CleanerController cleaner;
  final DuplicatesController duplicates;
  final QuarantineController quarantineController;
  final SystemMetricsService metrics;
  final Future<bool> Function() privilegeProbe;

  bool _disposed = false;

  /// Safe to call twice: a widget tree can be rebuilt after the window closes.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    metrics.dispose();
    cleaner.dispose();
    duplicates.dispose();
    quarantineController.dispose();
    settings.dispose();
  }
}

/// Builds the real runtime: quarantine on disk, settings from preferences, and
/// the cleaner target set that matches this platform.
Future<OmniCleanRuntime> bootstrapRuntime({
  Directory? quarantineRoot,
  Future<bool> Function()? privilegeProbe,
  MetricsSource? metricsSource,
  Duration metricsInterval = const Duration(seconds: 2),
}) async {
  final root = quarantineRoot ??
      Directory('${(await getApplicationSupportDirectory()).path}/quarantine');
  await root.create(recursive: true);

  final quarantine = Quarantine(root: root);
  await quarantine.init();

  SettingsController settings;
  try {
    settings = SettingsController(store: await SharedPreferencesStore.open());
  } catch (error) {
    // Preferences are a convenience, never a prerequisite: a locked-down
    // profile must still be able to clean.
    log.warn('settings: falling back to defaults — $error');
    settings = SettingsController();
  }
  await settings.load();

  final safeDelete = SafeDelete(
    quarantine: quarantine,
    privilegeProbe: privilegeProbe ?? Shell.isRoot,
  );

  final metrics = SystemMetricsService(
    source: metricsSource ?? createMetricsSource(),
    interval: metricsInterval,
  );

  return OmniCleanRuntime(
    quarantineRoot: root,
    quarantine: quarantine,
    safeDelete: safeDelete,
    settings: settings,
    cleaner: CleanerController.forPlatform(safeDelete: safeDelete),
    duplicates: DuplicatesController(safeDelete: safeDelete),
    quarantineController: QuarantineController(
      quarantine: quarantine,
      retention: settings.retention,
    ),
    metrics: metrics,
    privilegeProbe: privilegeProbe ?? Shell.isRoot,
  );
}

/// The application root: theme, locale and the five-screen shell.
class OmniCleanApp extends StatefulWidget {
  const OmniCleanApp({required this.runtime, super.key});

  final OmniCleanRuntime runtime;

  @override
  State<OmniCleanApp> createState() => _OmniCleanAppState();
}

class _OmniCleanAppState extends State<OmniCleanApp> {
  @override
  void dispose() {
    widget.runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    return AnimatedBuilder(
      animation: runtime.settings,
      builder: (context, _) {
        final accent = runtime.settings.settings.accent;
        return MaterialApp(
          title: 'OmniClean Engine',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(accent),
          locale: resolveLocale(
            runtime.settings.settings.language,
            PlatformDispatcher.instance.locale,
          ),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppShell(
            settings: runtime.settings,
            metrics: runtime.metrics,
            cleaner: runtime.cleaner,
            duplicates: runtime.duplicates,
            quarantine: runtime.quarantineController,
            privilegeProbe: runtime.privilegeProbe,
          ),
        );
      },
    );
  }
}

/// Desktop window chrome: a real minimum size so the rail layout never
/// collapses into the phone one on a desktop.
Future<void> prepareWindow() async {
  if (!(Platform.isLinux || Platform.isWindows)) return;
  try {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(720, 560),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setTitle('OmniClean Engine');
      await windowManager.show();
    });
  } catch (error) {
    log.warn('window: chrome not applied — $error');
  }
}
