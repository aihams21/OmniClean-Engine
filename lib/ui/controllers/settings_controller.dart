import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

export '../theme/app_theme.dart' show AccentChoice;

enum LanguageChoice { system, english, arabic }

/// The handful of choices that survive a restart.
///
/// Anything that would change *how much* the app is allowed to delete lives
/// here too, so a corrupted preference can never widen the blast radius beyond
/// what the user explicitly agreed to.
@immutable
class AppSettings {
  const AppSettings({
    required this.accent,
    required this.language,
    required this.minAgeHours,
    required this.retentionDays,
  });

  static const AppSettings defaults = AppSettings(
    accent: AccentChoice.cyber,
    language: LanguageChoice.system,
    minAgeHours: 24,
    retentionDays: 7,
  );

  final AccentChoice accent;
  final LanguageChoice language;

  /// How old a file must be before the engine is even allowed to consider it.
  final int minAgeHours;

  /// How long a quarantined item stays restorable.
  final int retentionDays;

  AppSettings copyWith({
    AccentChoice? accent,
    LanguageChoice? language,
    int? minAgeHours,
    int? retentionDays,
  }) {
    return AppSettings(
      accent: accent ?? this.accent,
      language: language ?? this.language,
      minAgeHours: minAgeHours ?? this.minAgeHours,
      retentionDays: retentionDays ?? this.retentionDays,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.accent == accent &&
        other.language == language &&
        other.minAgeHours == minAgeHours &&
        other.retentionDays == retentionDays;
  }

  @override
  int get hashCode => Object.hash(accent, language, minAgeHours, retentionDays);

  @override
  String toString() => 'AppSettings($accent, $language, '
      'minAge: ${minAgeHours}h, retention: ${retentionDays}d)';
}

/// Key-value persistence, injected so the controller can be tested without a
/// plugin channel.
abstract class SettingsStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// The real store: `shared_preferences`, which is already on disk before the
/// first frame on every supported platform.
class SharedPreferencesStore implements SettingsStore {
  SharedPreferencesStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPreferencesStore> open() async {
    return SharedPreferencesStore._(await SharedPreferences.getInstance());
  }

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }
}

/// Owns [AppSettings] and publishes changes to the widget tree.
class SettingsController extends ChangeNotifier {
  SettingsController({SettingsStore? store})
      : _store = store ?? _unopenedStore();

  static const int maxMinAgeHours = 24 * 30;
  static const int minRetentionDays = 1;
  static const int maxRetentionDays = 365;

  static const String _kAccent = 'accent';
  static const String _kLanguage = 'language';
  static const String _kMinAgeHours = 'minAgeHours';
  static const String _kRetentionDays = 'retentionDays';

  final SettingsStore? _store;
  AppSettings _settings = AppSettings.defaults;
  bool _loaded = false;

  AppSettings get settings => _settings;

  bool get isLoaded => _loaded;

  /// Age gate handed straight to `SafeDelete` and `DirectorySweeper`.
  Duration get minAge => Duration(hours: _settings.minAgeHours);

  /// Retention handed to `Quarantine.purgeOlderThan`.
  Duration get retention => Duration(days: _settings.retentionDays);

  static SettingsStore _unopenedStore() {
    return _DeferredStore();
  }

  Future<void> load() async {
    final store = _store;
    if (store != null) {
      _settings = AppSettings(
        accent: AppTheme.accentFromName(await store.read(_kAccent)),
        language: _languageFrom(await store.read(_kLanguage)),
        minAgeHours: _clampNum(
          _parseInt(await store.read(_kMinAgeHours)),
          AppSettings.defaults.minAgeHours,
          0,
          maxMinAgeHours,
        ),
        retentionDays: _clampNum(
          _parseInt(await store.read(_kRetentionDays)),
          AppSettings.defaults.retentionDays,
          minRetentionDays,
          maxRetentionDays,
        ),
      );
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAccent(AccentChoice accent) => _update(
      _settings.copyWith(accent: accent), {_kAccent: AppTheme.nameOf(accent)});

  Future<void> setLanguage(LanguageChoice language) => _update(
      _settings.copyWith(language: language), {_kLanguage: language.name});

  Future<void> setMinAgeHours(int hours) {
    final clamped = _clampNum(
      hours,
      AppSettings.defaults.minAgeHours,
      0,
      maxMinAgeHours,
    );
    return _update(
      _settings.copyWith(minAgeHours: clamped),
      {_kMinAgeHours: '$clamped'},
    );
  }

  Future<void> setRetentionDays(int days) {
    final clamped = _clampNum(
      days,
      AppSettings.defaults.retentionDays,
      minRetentionDays,
      maxRetentionDays,
    );
    return _update(
      _settings.copyWith(retentionDays: clamped),
      {_kRetentionDays: '$clamped'},
    );
  }

  Future<void> reset() => _update(AppSettings.defaults, const <String, String>{
        _kAccent: 'cyber',
        _kLanguage: 'system',
        _kMinAgeHours: '24',
        _kRetentionDays: '7',
      });

  Future<void> _update(AppSettings next, Map<String, String> persisted) async {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    final store = _store;
    if (store == null) return;
    for (final entry in persisted.entries) {
      await store.write(entry.key, entry.value);
    }
  }

  static int? _parseInt(String? raw) {
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  static int _clampNum(int? value, int fallback, int min, int max) {
    if (value == null) return fallback;
    return value.clamp(min, max);
  }

  static LanguageChoice _languageFrom(String? raw) {
    for (final choice in LanguageChoice.values) {
      if (choice.name == raw) return choice;
    }
    return LanguageChoice.system;
  }
}

/// A store that reads nothing and swallows writes. It exists so the app can
/// construct the controller before `shared_preferences` has finished opening,
/// and so widget tests never need a platform channel.
class _DeferredStore implements SettingsStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}
