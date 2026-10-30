import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'lexicon.dart';
import 'living_controller.dart';
import 'word_painter.dart' show hash01;

/// The page's mood while a living word plays: over the whole screen,
/// never taking touches, growing with the word.
class LivingMoodLayer extends StatelessWidget {
  const LivingMoodLayer({
    super.key,
    required this.controller,
    required this.ink,
    required this.paper,
    required this.dark,
  });

  final LivingWordsController controller;
  final Color ink;
  final Color paper;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<LivingEffect?>(
        valueListenable: controller.effect,
        builder: (context, effect, _) {
          if (effect == null) return const SizedBox.expand();
          return Stack(
            fit: StackFit.expand,
            children: [
              if (effect == LivingEffect.stone)
                ListenableBuilder(
                  listenable: controller.frame,
                  // The page drains toward grey-brown sepia.
                  builder: (_, _) => BackdropFilter(
                    filter: ColorFilter.matrix(_drain(controller.level)),
                    child: const SizedBox.expand(),
                  ),
                ),
              if (effect == LivingEffect.drown)
                // Soft edges, as if seen through water: rings of blur that
                // stack up toward the rim.
                for (final inset in const [64.0, 36.0, 16.0])
                  ListenableBuilder(
                    listenable: controller.frame,
                    builder: (_, _) {
                      final s = controller.level * 1.1;
                      if (s < 0.05) return const SizedBox.expand();
                      return ClipPath(
                        clipper: _Rim(inset),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s),
                          child: const SizedBox.expand(),
                        ),
                      );
                    },
                  ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _MoodPainter(effect, controller, ink, paper, dark),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Greyscale (half) then sepia (a third), scaled by [l].
  static List<double> _drain(double l) {
    final a = 0.5 * l;
    final b = 0.38 * l;
    final gray = [
      0.2126 + 0.7874 * (1 - a),
      0.7152 - 0.7152 * (1 - a),
      0.0722 - 0.0722 * (1 - a), //
      0.2126 - 0.2126 * (1 - a),
      0.7152 + 0.2848 * (1 - a),
      0.0722 - 0.0722 * (1 - a),
      0.2126 - 0.2126 * (1 - a),
      0.7152 - 0.7152 * (1 - a),
      0.0722 + 0.9278 * (1 - a),
    ];
    final sepia = [
      0.393 + 0.607 * (1 - b),
      0.769 - 0.769 * (1 - b),
      0.189 - 0.189 * (1 - b), //
      0.349 - 0.349 * (1 - b), 0.686 + 0.314 * (1 - b), 0.168 - 0.168 * (1 - b),
      0.272 - 0.272 * (1 - b), 0.534 - 0.534 * (1 - b), 0.131 + 0.869 * (1 - b),
    ];
    final m = List<double>.filled(9, 0);
    for (var r = 0; r < 3; r++) {
      for (var col = 0; col < 3; col++) {
        for (var k = 0; k < 3; k++) {
          m[r * 3 + col] += sepia[r * 3 + k] * gray[k * 3 + col];
        }
      }
    }
    return [
      m[0], m[1], m[2], 0, 0, //
      m[3], m[4], m[5], 0, 0,
      m[6], m[7], m[8], 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}

/// Everything outside a rounded rectangle [inset] in from the edges.
class _Rim extends CustomClipper<Path> {
  const _Rim(this.inset);

  final double inset;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(inset),
        Radius.circular(inset * 1.5),
      ),
    );

  @override
  bool shouldReclip(_Rim old) => old.inset != inset;
}

class _MoodPainter extends CustomPainter {
  _MoodPainter(this.effect, this.controller, this.ink, this.paper, this.dark)
    : super(repaint: controller.frame);

  final LivingEffect effect;
  final LivingWordsController controller;
  final Color ink;
  final Color paper;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final l = controller.level;
    if (l <= 0.005) return;
    _Mood(canvas, size, l, controller.time, ink, paper, dark).draw(effect);
  }

  @override
  bool shouldRepaint(_MoodPainter old) =>
      old.effect != effect || old.ink != ink || old.paper != paper;
}

class _Mood {
  _Mood(this.c, this.size, this.l, this.t, this.ink, this.paper, this.dark);

  final Canvas c;
  final Size size;
  final double l;
  final double t;
  final Color ink;
  final Color paper;
  final bool dark;

  Rect get all => Offset.zero & size;
  double get w => size.width;
  double get h => size.height;

  /// Colour gathering at the edges; clear inside [inner] (0 to 1 of the
  /// way out from the middle).
  void edges(Color color, double alpha, {double inner = 0.5, Offset? at}) {
    if (alpha <= 0.003) return;
    final centre = at ?? all.center;
    final reach = size.longestSide * 0.62;
    c.drawRect(
      all,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          reach,
          [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color.withValues(alpha: alpha.clamp(0.0, 1.0)),
          ],
          [0, inner.clamp(0.0, 0.95), 1],
          TileMode.clamp,
          // Stretched to the screen's shape.
          (Matrix4.identity()
                ..translateByDouble(centre.dx, centre.dy, 0, 1)
                ..scaleByDouble(
                  w / size.longestSide,
                  h / size.longestSide,
                  1,
                  1,
                )
                ..translateByDouble(-centre.dx, -centre.dy, 0, 1))
              .storage,
        ),
    );
  }

  void wash(Color color, double alpha, [BlendMode mode = BlendMode.srcOver]) {
    if (alpha <= 0.003) return;
    c.drawRect(
      all,
      Paint()
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..blendMode = mode,
    );
  }

  void from(Alignment side, Color color, double alpha, double depth) {
    if (alpha <= 0.003) return;
    final a = side.withinRect(all);
    final b = Alignment(-side.x, -side.y).withinRect(all);
    c.drawRect(
      all,
      Paint()
        ..shader = ui.Gradient.linear(
          a,
          b,
          [
            color.withValues(alpha: alpha.clamp(0.0, 1.0)),
            color.withValues(alpha: 0),
          ],
          [0, depth],
        ),
    );
  }

  void draw(LivingEffect effect) {
    switch (effect) {
      case LivingEffect.fire:
        final flick = 0.85 + 0.15 * math.sin(t * 6.1) * math.sin(t * 2.3);
        edges(const Color(0xFFE8641E), 0.2 * l * flick, inner: 0.55);
        from(Alignment.bottomCenter, const Color(0xFFF59E0B), 0.1 * l, 0.4);
      case LivingEffect.roar:
        final ph = (t % 2.6) / 2.6;
        final beat = ph < 0.07 ? ph / 0.07 : math.exp(-(ph - 0.07) * 7);
        edges(
          const Color(0xFF7F1D1D),
          (0.1 + 0.14 * beat) * l,
          inner: 0.5 - 0.06 * beat,
        );
      case LivingEffect.slash:
        final reach = (l * 1.6).clamp(0.0, 1.0);
        final a = Offset(w * 1.05, h * 0.16);
        final b = Offset.lerp(a, Offset(-w * 0.05, h * 0.64), reach)!;
        c.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFFB91C1C).withValues(alpha: 0.07 * l)
            ..strokeWidth = 8
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        c.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFFB91C1C).withValues(alpha: 0.3 * l)
            ..strokeWidth = 1.2,
        );
      case LivingEffect.bolt:
        final x = t % 3.7;
        final f = (math.exp(-x * 6) * (0.65 + 0.35 * math.cos(x * 55))).clamp(
          0.0,
          1.0,
        );
        wash(
          dark ? const Color(0xFF93C5FD) : const Color(0xFFDBEAFE),
          (dark ? 0.12 : 0.3) * f * l,
        );
        edges(const Color(0xFF3B5BDB), 0.1 * l, inner: 0.6);
      case LivingEffect.shatter:
        final r = math.Random(5);
        final crack = Paint()
          ..color = ink.withValues(alpha: 0.2 * l)
          ..strokeWidth = 0.9
          ..style = PaintingStyle.stroke;
        for (var k = 0; k < 4; k++) {
          var at = Offset(w, h * 0.04 * k);
          final angle = math.pi * (0.62 + 0.1 * k);
          final path = Path()..moveTo(at.dx, at.dy);
          final steps = (9 * l).ceil();
          for (var s = 0; s < steps; s++) {
            final a = angle + (r.nextDouble() - 0.5) * 0.9;
            at += Offset(math.cos(a), math.sin(a)) * (14 + 10 * r.nextDouble());
            path.lineTo(at.dx, at.dy);
          }
          c.drawPath(path, crack);
        }
        edges(ink, 0.06 * l, inner: 0.6);
      case LivingEffect.frost:
        edges(const Color(0xFF7FB2E5), 0.28 * l, inner: 0.42);
        wash(const Color(0xFFA5C8EE), 0.06 * l);
      case LivingEffect.echo:
        for (final lag in const [0.0, 0.5]) {
          final ph = ((t / 3.2) + lag) % 1;
          c.drawCircle(
            all.center,
            ph * size.longestSide * 0.7,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 16
              ..color = ink.withValues(alpha: 0.05 * l * (1 - ph))
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
          );
        }
      case LivingEffect.blood:
        // Blood stays in the words; the page is left alone.
        break;
      case LivingEffect.vanish:
        // A fog of paper that eats the text at the edges.
        edges(paper, 0.8 * l, inner: 0.42);
      case LivingEffect.dread:
        edges(Colors.black, 0.5 * l, inner: 0.72 - 0.34 * l);
      case LivingEffect.howl:
        final streak = Paint()
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round;
        for (var k = 0; k < 10; k++) {
          final y = h * hash01(k, 1);
          final speed = 0.25 + 0.2 * hash01(k, 2);
          final x = ((t * speed + hash01(k, 3)) % 1.6 - 0.3) * w;
          streak.color = ink.withValues(alpha: 0.07 * l);
          c.drawLine(Offset(x, y), Offset(x + w * 0.25, y + 3), streak);
        }
        edges(ink, 0.06 * l, inner: 0.55);
      case LivingEffect.drown:
        if (dark) {
          wash(const Color(0xFF2C6A80), 0.22 * l);
        } else {
          wash(const Color(0xFF9CC3D9), 0.6 * l, BlendMode.multiply);
        }
        edges(const Color(0xFF1E4A5A), 0.2 * l, inner: 0.45);
      case LivingEffect.stone:
        edges(const Color(0xFF5C4A36), 0.24 * l, inner: 0.5);
        final dust = Paint()
          ..color = const Color(0xFF5C4A36).withValues(alpha: 0.35 * l);
        for (var k = 0; k < 140; k++) {
          final x = hash01(k, 11) * w;
          final y = hash01(k, 12) * h;
          // Mostly near the edges.
          final edge = math.min(math.min(x, w - x) / w, math.min(y, h - y) / h);
          if (edge > 0.12 * l + 0.02) continue;
          c.drawCircle(Offset(x, y), 0.7 + 0.9 * hash01(k, 13), dust);
        }
      case LivingEffect.crush:
        final bear = math.pow(math.max(0, math.sin(2 * math.pi * t / 3.2)), 2);
        from(Alignment.topCenter, Colors.black, (0.2 + 0.1 * bear) * l, 0.35);
      case LivingEffect.lunge:
        final x = t % 3.6;
        final k = x < 0.42 ? 0.0 : math.exp(-(x - 0.42) * 3.2);
        from(Alignment.centerLeft, Colors.black, 0.16 * k * l, 0.2);
        from(Alignment.centerRight, Colors.black, 0.08 * k * l, 0.12);
      case LivingEffect.tremble:
        final step = (t / 0.07).floor();
        final jitter =
            Offset(hash01(step, 1) - 0.5, hash01(step, 2) - 0.5) * 10 * l;
        edges(Colors.black, 0.16 * l, inner: 0.6, at: all.center + jitter);
      case LivingEffect.poison:
        for (var k = 0; k < 2; k++) {
          final at = Offset(
            w * (0.3 + 0.4 * k) + w * 0.15 * math.sin(t * 0.13 + k * 2),
            h * (0.35 + 0.3 * k) + h * 0.1 * math.cos(t * 0.11 + k),
          );
          final radius = size.longestSide * 0.55;
          c.drawCircle(
            at,
            radius,
            Paint()
              ..shader = ui.Gradient.radial(at, radius, [
                const Color(0xFF9AA35A).withValues(alpha: 0.05 * l),
                const Color(0x009AA35A),
              ]),
          );
        }
        edges(const Color(0xFF5A6340), 0.08 * l, inner: 0.6);
      case LivingEffect.choke:
        final rise = 0.55 + 0.08 * math.sin(t * 0.4);
        from(Alignment.bottomCenter, const Color(0xFF6B6B6B), 0.3 * l, rise);
        for (var k = 0; k < 5; k++) {
          final ph = (t * 0.03 + k / 5) % 1;
          final at = Offset(w * hash01(k, 21), h * (1.1 - ph * 1.3));
          final radius = w * 0.45;
          c.drawCircle(
            at,
            radius,
            Paint()
              ..shader = ui.Gradient.radial(at, radius, [
                const Color(0xFF7A7A7A)
                    .withValues(alpha: 0.1 * l * math.sin(ph * math.pi)),
                const Color(0x007A7A7A),
              ]),
          );
        }
      case LivingEffect.wither:
        edges(const Color(0xFFC8A050), 0.3 * l, inner: 0.48);
      case LivingEffect.plummet:
        final streak = Paint()
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..color = ink.withValues(alpha: 0.07 * l);
        for (var k = 0; k < 12; k++) {
          final x = w * hash01(k, 31);
          final speed = 0.45 + 0.3 * hash01(k, 32);
          final y = h - ((t * speed + hash01(k, 33)) % 1.4) * h * 1.2;
          c.drawLine(Offset(x, y), Offset(x, y + h * 0.12), streak);
        }
      case LivingEffect.devour:
        // Devour bites the words only; the page is left alone.
        break;
    }
  }
}
