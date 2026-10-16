import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// A three-quarter dial that reports one live system reading.
///
/// `value` is deliberately nullable: a missing reading must render as the
/// localized "unavailable" word, never as a confident `0%`. Showing a healthy
/// idle figure when the kernel simply refused to answer would be a lie the user
/// cannot detect, and this app does not tell lies about machines.
class ArcGauge extends StatelessWidget {
  const ArcGauge({
    required this.label,
    required this.value,
    this.size = 132,
    this.color,
    super.key,
  });

  final String label;

  /// Fraction in `0..1`, or `null` when no reading is available.
  final double? value;

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);

    final double? reading = value == null
        ? null
        : (value!.isNaN ? 0.0 : value!.clamp(0.0, 1.0).toDouble());
    final String readout =
        reading == null ? l10n.unavailable : '${(reading * 100).round()}%';

    final ring = size;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: reading == null
          ? '$label, ${l10n.unavailable}'
          : '$label ${(reading * 100).round()}%',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: ring,
              height: ring,
              child: CustomPaint(
                painter: ArcGaugePainter(
                  value: reading,
                  accent: color ?? palette.accent,
                  track: palette.outline,
                ),
                child: Center(
                  child: Text(
                    readout,
                    textAlign: TextAlign.center,
                    style: text.titleLarge?.copyWith(
                      fontFamily: 'monospace',
                      color: reading == null
                          ? palette.textMuted
                          : palette.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: text.labelMedium?.copyWith(
                color: palette.textMuted,
                letterSpacing: context.labelTracking,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ArcGaugePainter extends CustomPainter {
  const ArcGaugePainter({
    required this.value,
    required this.accent,
    required this.track,
  });

  /// `null` while the reading is missing — the dial stays on the track and no
  /// accent arc is drawn, which is visibly different from "0% busy".
  final double? value;

  final Color accent;
  final Color track;

  static const double startAngle = math.pi * 0.75;
  static const double fullSweep = math.pi * 1.5;

  /// Maps a `0..1` fraction onto the dial's 270° sweep, clamping hostile input
  /// so a mis-parsed kernel counter cannot draw outside the arc.
  static double sweepFor(double value) {
    final double safe = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    return fullSweep * safe;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.09;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 4);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arcRect, startAngle, fullSweep, false, trackPaint);

    final double? reading = value;
    if (reading == null) return;

    final sweep = sweepFor(reading);
    if (sweep <= 0) return;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + fullSweep,
        colors: [accent.withValues(alpha: 0.45), accent],
        transform: GradientRotation(startAngle),
      ).createShader(arcRect);
    canvas.drawArc(arcRect, startAngle, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(ArcGaugePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.accent != accent ||
      oldDelegate.track != track;
}
