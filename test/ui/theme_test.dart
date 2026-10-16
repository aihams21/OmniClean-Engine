import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/ui/theme/app_theme.dart';

void main() {
  group('CyberPalette', () {
    test('the cyber accent is the agreed cyber green', () {
      expect(CyberPalette.forAccent(AccentChoice.cyber).accent,
          const Color(0xFF10B981));
    });

    test('the crimson accent is the agreed deep crimson', () {
      expect(CyberPalette.forAccent(AccentChoice.crimson).accent,
          const Color(0xFFFF1E1E));
    });

    test('void black is the background of both themes', () {
      expect(CyberPalette.forAccent(AccentChoice.cyber).background,
          const Color(0xFF000000));
      expect(CyberPalette.forAccent(AccentChoice.crimson).background,
          const Color(0xFF000000));
    });

    test('danger stays crimson even when crimson is the accent', () {
      for (final choice in AccentChoice.values) {
        expect(CyberPalette.forAccent(choice).danger, const Color(0xFFFF1E1E));
      }
    });

    test('every palette is fully opaque so nothing renders see-through', () {
      for (final choice in AccentChoice.values) {
        final palette = CyberPalette.forAccent(choice);
        for (final color in [
          palette.accent,
          palette.danger,
          palette.warning,
          palette.background,
          palette.surface,
          palette.elevated,
          palette.outline,
          palette.textPrimary,
          palette.textMuted,
        ]) {
          expect(color.a, 1.0, reason: 'color $color must be opaque');
        }
      }
    });
  });

  group('AppTheme', () {
    test('both accents produce a dark theme on void black', () {
      for (final choice in AccentChoice.values) {
        final theme = AppTheme.build(choice);
        expect(theme.brightness, Brightness.dark);
        expect(theme.colorScheme.brightness, Brightness.dark);
        expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
      }
    });

    test('the colour scheme follows the accent the user picked', () {
      expect(
        AppTheme.build(AccentChoice.cyber).colorScheme.primary,
        const Color(0xFF10B981),
      );
      expect(
        AppTheme.build(AccentChoice.crimson).colorScheme.primary,
        const Color(0xFFFF1E1E),
      );
    });

    test('the two themes are actually different', () {
      final cyber = AppTheme.build(AccentChoice.cyber);
      final crimson = AppTheme.build(AccentChoice.crimson);
      expect(cyber.colorScheme.primary, isNot(crimson.colorScheme.primary));
      expect(cyber.appBarTheme.backgroundColor,
          isNot(crimson.appBarTheme.backgroundColor));
    });

    test('building the same accent twice is deterministic', () {
      final a = AppTheme.build(AccentChoice.cyber);
      final b = AppTheme.build(AccentChoice.cyber);
      expect(a.colorScheme, b.colorScheme);
      expect(a.scaffoldBackgroundColor, b.scaffoldBackgroundColor);
      expect(a.textTheme.bodyMedium?.color, b.textTheme.bodyMedium?.color);
    });

    test('the extension carries the palette so widgets need no lookup table',
        () {
      final theme = AppTheme.build(AccentChoice.crimson);
      final palette = CyberTheme.of(theme);
      expect(palette.accent, const Color(0xFFFF1E1E));
      expect(palette.danger, const Color(0xFFFF1E1E));
    });

    test('a theme without the extension still yields a usable palette', () {
      final bare = ThemeData();
      expect(CyberTheme.of(bare).accent, isA<Color>());
      expect(CyberTheme.of(bare).background, isA<Color>());
    });

    test('unknown stored accent names fall back to cyber instead of crashing',
        () {
      expect(AppTheme.accentFromName('crimson'), AccentChoice.crimson);
      expect(AppTheme.accentFromName('CYBER'), AccentChoice.cyber);
      expect(AppTheme.accentFromName('nonsense'), AccentChoice.cyber);
      expect(AppTheme.accentFromName(null), AccentChoice.cyber);
      expect(AppTheme.nameOf(AccentChoice.crimson), 'crimson');
    });

    test('meters use the accent colour so gauges read as one system', () {
      final theme = AppTheme.build(AccentChoice.cyber);
      expect(theme.progressIndicatorTheme.color, const Color(0xFF10B981));
      expect(theme.sliderTheme.activeTrackColor, const Color(0xFF10B981));
      expect(
        theme.switchTheme.thumbColor?.resolve({WidgetState.selected}),
        const Color(0xFF10B981),
      );
    });

    test('destructive buttons are painted crimson, not the accent', () {
      final cyber = AppTheme.build(AccentChoice.cyber);
      expect(cyber.colorScheme.error, const Color(0xFFFF1E1E));
    });
  });
}
