import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/ui/controllers/settings_controller.dart';

class MemoryStore implements SettingsStore {
  MemoryStore([Map<String, String>? seed])
      : values = <String, String>{...?seed};

  final Map<String, String> values;
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }
}

void main() {
  group('AppSettings', () {
    test('defaults are conservative and localizable', () {
      const settings = AppSettings.defaults;
      expect(settings.accent, AccentChoice.cyber);
      expect(settings.language, LanguageChoice.system);
      expect(settings.minAgeHours, 24);
      expect(settings.retentionDays, 7);
    });

    test('copyWith replaces only what it is given', () {
      const settings = AppSettings.defaults;
      final updated = settings.copyWith(accent: AccentChoice.crimson);
      expect(updated.accent, AccentChoice.crimson);
      expect(updated.language, settings.language);
      expect(updated.minAgeHours, settings.minAgeHours);
    });
  });

  group('SettingsController', () {
    test('an empty store yields the defaults and never throws', () async {
      final controller = SettingsController(store: MemoryStore());
      await controller.load();

      expect(controller.settings, AppSettings.defaults);
      expect(controller.isLoaded, isTrue);
    });

    test('it round-trips every field through the store', () async {
      final store = MemoryStore();
      final controller = SettingsController(store: store);
      await controller.load();

      await controller.setAccent(AccentChoice.crimson);
      await controller.setLanguage(LanguageChoice.arabic);
      await controller.setMinAgeHours(48);
      await controller.setRetentionDays(30);

      final restored = SettingsController(store: store);
      await restored.load();

      expect(restored.settings.accent, AccentChoice.crimson);
      expect(restored.settings.language, LanguageChoice.arabic);
      expect(restored.settings.minAgeHours, 48);
      expect(restored.settings.retentionDays, 30);
    });

    test('it tolerates a corrupt store instead of crashing', () async {
      final store = MemoryStore(<String, String>{
        'accent': 'neon-banana',
        'language': 'klingon',
        'minAgeHours': 'not-a-number',
        'retentionDays': '',
      });
      final controller = SettingsController(store: store);

      await controller.load();

      expect(controller.settings.accent, AccentChoice.cyber);
      expect(controller.settings.language, LanguageChoice.system);
      expect(controller.settings.minAgeHours, AppSettings.defaults.minAgeHours);
      expect(controller.settings.retentionDays, AppSettings.defaults.retentionDays);
    });

    test('it clamps hostile numeric values instead of trusting them', () async {
      final store = MemoryStore(<String, String>{
        'minAgeHours': '999999',
        'retentionDays': '0',
      });
      final controller = SettingsController(store: store);
      await controller.load();

      expect(controller.settings.minAgeHours, SettingsController.maxMinAgeHours);
      expect(controller.settings.retentionDays, SettingsController.minRetentionDays);

      await controller.setMinAgeHours(-5);
      expect(controller.settings.minAgeHours, 0);

      await controller.setRetentionDays(9999);
      expect(controller.settings.retentionDays, SettingsController.maxRetentionDays);
    });

    test('every change notifies its listeners', () async {
      final controller = SettingsController(store: MemoryStore());
      await controller.load();

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setAccent(AccentChoice.crimson);
      await controller.setLanguage(LanguageChoice.english);
      await controller.setMinAgeHours(12);
      await controller.setRetentionDays(3);

      expect(notifications, 4);
    });

    test('setting the same value again is not a change worth announcing', () async {
      final controller = SettingsController(store: MemoryStore());
      await controller.load();

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setAccent(AccentChoice.cyber);
      await controller.setAccent(AccentChoice.crimson);
      await controller.setAccent(AccentChoice.crimson);

      expect(notifications, 1);
    });

    test('reset returns every field to its default and persists that', () async {
      final store = MemoryStore();
      final controller = SettingsController(store: store);
      await controller.load();
      await controller.setAccent(AccentChoice.crimson);
      await controller.setLanguage(LanguageChoice.arabic);

      await controller.reset();

      expect(controller.settings, AppSettings.defaults);

      final restored = SettingsController(store: store);
      await restored.load();
      expect(restored.settings, AppSettings.defaults);
    });

    test('minAge and retention are exposed as durations for the engine', () async {
      final controller = SettingsController(store: MemoryStore());
      await controller.load();

      expect(controller.minAge, const Duration(hours: 24));
      expect(controller.retention, const Duration(days: 7));

      await controller.setMinAgeHours(2);
      expect(controller.minAge, const Duration(hours: 2));
    });
  });
}
