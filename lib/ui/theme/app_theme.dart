import 'package:flutter/material.dart';

/// Which accent the user picked in Settings.
///
/// Both are shipped; switching is instant and persisted.
enum AccentChoice { cyber, crimson }

/// The single source of colour truth.
///
/// Widgets never hard-code a hex value: they read [CyberTheme.of] so a theme
/// switch repaints the whole application, including custom painters.
@immutable
class CyberPalette {
  const CyberPalette({
    required this.accent,
    required this.accentSoft,
    required this.background,
    required this.surface,
    required this.elevated,
    required this.outline,
    required this.textPrimary,
    required this.textMuted,
    required this.danger,
    required this.warning,
    required this.info,
  });

  static const CyberPalette cyber = CyberPalette(
    accent: Color(0xFF10B981),
    accentSoft: Color(0xFF064E3B),
    background: Color(0xFF000000),
    surface: Color(0xFF07100D),
    elevated: Color(0xFF0D1A16),
    outline: Color(0xFF1C2B25),
    textPrimary: Color(0xFFE6F5EF),
    textMuted: Color(0xFF7C9189),
    danger: Color(0xFFFF1E1E),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF38BDF8),
  );

  static const CyberPalette crimson = CyberPalette(
    accent: Color(0xFFFF1E1E),
    accentSoft: Color(0xFF4C0F0F),
    background: Color(0xFF000000),
    surface: Color(0xFF12070A),
    elevated: Color(0xFF1D0B10),
    outline: Color(0xFF331319),
    textPrimary: Color(0xFFFDEBEF),
    textMuted: Color(0xFF9C8087),
    danger: Color(0xFFFF1E1E),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF38BDF8),
  );

  static const Map<AccentChoice, CyberPalette> _byAccent = {
    AccentChoice.cyber: cyber,
    AccentChoice.crimson: crimson,
  };

  factory CyberPalette.forAccent(AccentChoice choice) => _byAccent[choice]!;

  final Color accent;
  final Color accentSoft;
  final Color background;
  final Color surface;
  final Color elevated;
  final Color outline;
  final Color textPrimary;
  final Color textMuted;

  /// Always deep crimson, in both themes: "this destroys data" must never be
  /// confused with "this is the colour you picked".
  final Color danger;
  final Color warning;
  final Color info;
}

/// Carries the [CyberPalette] through the [ThemeData] so any widget can read it.
@immutable
class CyberTheme extends ThemeExtension<CyberTheme> {
  const CyberTheme(this.palette);

  final CyberPalette palette;

  /// Never throws: a theme built without the extension degrades to cyber.
  static CyberPalette of(ThemeData theme) =>
      theme.extension<CyberTheme>()?.palette ??
      CyberPalette.forAccent(AccentChoice.cyber);

  @override
  CyberTheme copyWith({CyberPalette? palette}) =>
      CyberTheme(palette ?? this.palette);

  @override
  CyberTheme lerp(CyberTheme? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Builds the two dark themes the application ships.
class AppTheme {
  const AppTheme._();

  static ThemeData build(AccentChoice choice) {
    final palette = CyberPalette.forAccent(choice);
    const base = Brightness.dark;

    final scheme = ColorScheme(
      brightness: base,
      primary: palette.accent,
      onPrimary: palette.background,
      primaryContainer: palette.accentSoft,
      onPrimaryContainer: palette.textPrimary,
      secondary: palette.info,
      onSecondary: palette.background,
      error: palette.danger,
      onError: Colors.white,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      surfaceContainerHighest: palette.elevated,
      outline: palette.outline,
      outlineVariant: palette.outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: base,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      extensions: <ThemeExtension<dynamic>>[CyberTheme(palette)],
      textTheme: _textTheme(palette),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(
        color: palette.outline,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: palette.textMuted),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.elevated,
        circularTrackColor: palette.elevated,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.elevated,
        thumbColor: palette.accent,
        overlayColor: palette.accentSoft,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? palette.accent
              : palette.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentSoft
              : palette.elevated,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? palette.accent
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll<Color?>(palette.background),
        side: BorderSide(color: palette.outline),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.elevated,
        contentTextStyle: TextStyle(
          color: palette.textPrimary,
          fontFamilyFallback: fontFallbacks,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.outline),
        ),
        textStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 12,
          fontFamilyFallback: fontFallbacks,
        ),
      ),
    );
  }

  /// Tolerant parser for the persisted preference: anything unrecognised (an
  /// older build, a hand-edited config) resolves to cyber instead of crashing.
  static AccentChoice accentFromName(String? name) {
    for (final choice in AccentChoice.values) {
      if (choice.name.toLowerCase() == name?.trim().toLowerCase()) {
        return choice;
      }
    }
    return AccentChoice.cyber;
  }

  static String nameOf(AccentChoice choice) => choice.name;

  /// Families consulted, in order, when the primary family has no glyph.
  ///
  /// The app ships a complete Arabic translation, so Arabic must never depend
  /// on which Latin family the host platform happens to resolve first. Naming
  /// the fallbacks explicitly is what keeps the RTL screens readable on a bare
  /// Linux desktop as well as on Windows and Android.
  static const List<String> fontFallbacks = <String>[
    'NotoSansArabic',
    'NotoNaskhArabic',
    'NotoSans',
    'Arial',
    'Segoe UI',
    'DejaVu Sans',
  ];

  static TextTheme _textTheme(CyberPalette palette) {
    TextStyle style(double size, FontWeight weight, Color color) => TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.35,
          fontFamilyFallback: fontFallbacks,
        );

    return TextTheme(
      displaySmall: style(34, FontWeight.w700, palette.textPrimary),
      headlineMedium: style(24, FontWeight.w700, palette.textPrimary),
      headlineSmall: style(21, FontWeight.w600, palette.textPrimary),
      titleLarge: style(19, FontWeight.w600, palette.textPrimary),
      titleMedium: style(16, FontWeight.w600, palette.textPrimary),
      titleSmall: style(13, FontWeight.w600, palette.textPrimary),
      bodyLarge: style(15, FontWeight.w400, palette.textPrimary),
      bodyMedium: style(14, FontWeight.w400, palette.textPrimary),
      bodySmall: style(12.5, FontWeight.w400, palette.textMuted),
      labelLarge: style(14, FontWeight.w600, palette.textPrimary),
      labelMedium: style(12, FontWeight.w600, palette.textMuted),
      labelSmall: style(11, FontWeight.w500, palette.textMuted),
    );
  }
}

/// Script-aware tracking for the small uppercase labels used across the app.
///
/// Tracking is a Latin typographic device: it separates glyphs that were never
/// meant to be joined. Applying it to Arabic stretches the joining strokes
/// apart and breaks the script's shaping, so it is switched off for every
/// non-Latin locale and the label falls back to weight and colour alone.
extension CyberLabels on BuildContext {
  bool get _isLatinScript {
    final String language =
        Localizations.localeOf(this).languageCode.toLowerCase();
    return const <String>{'en', 'de', 'fr', 'es', 'it', 'pt', 'nl', 'tr'}
        .contains(language);
  }

  double get labelTracking => _isLatinScript ? 1.2 : 0;
  double get tightTracking => _isLatinScript ? 0.6 : 0;
}
