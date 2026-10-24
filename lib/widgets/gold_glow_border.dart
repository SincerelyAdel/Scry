import 'package:flutter/material.dart';

import '../theme.dart';

/// Draws a soft glow around the edge of the screen, gold running into the
/// app icon's purple, on top of [child].
/// It ignores touches, so the app underneath works as normal.
class GoldGlowBorder extends StatelessWidget {
  const GoldGlowBorder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _GlowPainter(context.palette)),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter(this.palette);

  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    // Strokes sit on the screen edge and are heavily blurred, so only their
    // inner half shows: light that fades softly inward with no hard line.
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    final strength = palette.isDark ? 1.0 : 0.7;

    // Gold at the top left and bottom right, purple in the other corners.
    Shader sweep(Color gold, Color purple, double alpha) => SweepGradient(
      colors: [
        gold.withValues(alpha: alpha),
        purple.withValues(alpha: alpha),
        gold.withValues(alpha: alpha),
        purple.withValues(alpha: alpha),
        gold.withValues(alpha: alpha),
      ],
    ).createShader(rect);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..shader = sweep(palette.accent, palette.violet, 0.55 * strength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..shader = sweep(
          palette.accentLight,
          palette.violetLight,
          0.45 * strength,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) => old.palette != palette;
}
