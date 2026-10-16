import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// The signature backdrop: a void-black field with a faint perspective grid and
/// a slow horizontal scanline sweep.
///
/// It is deliberately *not* animated by a controller. A repeating animation
/// would keep the raster thread busy for the lifetime of the app, which on a
/// machine whose whole purpose is to free resources is an own goal. The grid
/// is static; only the glow is a gradient.
class CyberBackground extends StatelessWidget {
  const CyberBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: CustomPaint(
        painter: _CyberGridPainter(palette),
        child: child,
      ),
    );
  }
}

class _CyberGridPainter extends CustomPainter {
  const _CyberGridPainter(this.palette);

  final CyberPalette palette;

  static const double _cell = 44;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = palette.outline.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.accent.withValues(alpha: 0.16),
          palette.accent.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.0),
          radius: size.shortestSide * 1.2,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(_CyberGridPainter oldDelegate) =>
      oldDelegate.palette.accent != palette.accent;
}
