import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A single stacked bar showing how much of a filesystem is committed.
class StorageBar extends StatelessWidget {
  const StorageBar({
    required this.usedBytes,
    required this.freeBytes,
    this.height = 16,
    this.showLegend = true,
    super.key,
  });

  final int usedBytes;
  final int freeBytes;
  final double height;
  final bool showLegend;

  /// Fraction of the volume that is used, clamped into `0..1`.
  ///
  /// A capacity of zero (an unmounted volume, a stale probe) yields `0` instead
  /// of a NaN that would paint nothing and read as "healthy".
  static double fractionFor({required int usedBytes, required int freeBytes}) {
    final total = usedBytes + freeBytes;
    if (total <= 0) return 0;
    final fraction = usedBytes / total;
    if (fraction.isNaN) return 0;
    return fraction.clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    final text = Theme.of(context).textTheme;
    final fraction = fractionFor(usedBytes: usedBytes, freeBytes: freeBytes);

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              flex: fraction <= 0 ? 0 : (fraction * 1000).round(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.accent.withValues(alpha: 0.65),
                      palette.accent,
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: fraction >= 1 ? 0 : ((1 - fraction) * 1000).round() + 1,
              child: ColoredBox(color: palette.outline),
            ),
          ],
        ),
      ),
    );

    if (!showLegend) return bar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bar,
        const SizedBox(height: 8),
        Text(
          '${(fraction * 100).round()}%',
          style: text.labelMedium?.copyWith(
            color: palette.textMuted,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
