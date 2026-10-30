import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'lexicon.dart';
import 'living_controller.dart';

/// A word laid out once, letter by letter, ready to be drawn with effects.
class WordGlyphs {
  WordGlyphs(this.text, this.style, this.paper) {
    word = _layout(text, style);
    size = word.size;
    em = style.fontSize ?? 16;
    final lines = word.computeLineMetrics();
    baseline = lines.isEmpty ? size.height * 0.8 : lines.first.baseline;
    for (var i = 0; i < text.length; i++) {
      final boxes = word.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      final box = boxes.isEmpty
          ? Rect.fromLTWH(i * size.width / text.length, 0, 0, size.height)
          : boxes.first.toRect();
      this.boxes.add(box);
      letters.add(_layout(text[i], style));
    }
  }

  final String text;
  final TextStyle style;

  /// The page colour behind the text.
  final Color paper;

  late final TextPainter word;
  late final Size size;
  late final double em;
  late final double baseline;
  final boxes = <Rect>[];
  final letters = <TextPainter>[];

  TextPainter? _outline;

  /// The word drawn as an outline, for dread.
  TextPainter get outline => _outline ??= _layout(
    text,
    TextStyle(
      inherit: false,
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      letterSpacing: style.letterSpacing,
      height: style.height,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, (style.fontSize ?? 16) * 0.045)
        ..strokeJoin = StrokeJoin.round
        ..color = ink,
    ),
  );

  Color get ink => style.color ?? Colors.black;

  /// The top of lowercase-and-capital ink, and the bottom of the descenders.
  double get top => baseline - em * 0.74;
  double get bottom => baseline + em * 0.22;
  double get band => bottom - top;

  /// Room around the word for anything drawn just outside it.
  Rect get room => (Offset.zero & size).inflate(em * 0.6);

  int get count => letters.length;

  /// The word's ink box, tight to the font (not the line height), to line
  /// it up with the same word inside a paragraph.
  late final Rect tight = () {
    final boxes = word.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    return boxes.isEmpty ? Offset.zero & size : boxes.first.toRect();
  }();

  /// 0 at the first letter, 1 at the last.
  double along(int i) => count < 2 ? 1 : i / (count - 1);

  void dispose() {
    word.dispose();
    _outline?.dispose();
    for (final l in letters) {
      l.dispose();
    }
  }

  static TextPainter _layout(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    maxLines: 1,
  )..layout();
}

/// Draws [effect] on [g] at strength [p] (0 looks like plain text) and
/// time [t]. [seed] varies the details from word to word.
void paintLivingEffect(
  Canvas canvas,
  WordGlyphs g,
  LivingEffect effect,
  double p,
  double t,
  int seed,
) {
  // Too faint to see: plain text, and none of the layers.
  if (p < 0.01) {
    g.word.paint(canvas, Offset.zero);
    return;
  }
  final fx = _WordFx(canvas, g, p, t, seed);
  switch (effect) {
    case LivingEffect.fire:
      fx.fire();
    case LivingEffect.roar:
      fx.roar();
    case LivingEffect.slash:
      fx.slash();
    case LivingEffect.bolt:
      fx.bolt();
    case LivingEffect.shatter:
      fx.shatter();
    case LivingEffect.frost:
      fx.frost();
    case LivingEffect.echo:
      fx.echo();
    case LivingEffect.blood:
      fx.blood();
    case LivingEffect.vanish:
      fx.vanish();
    case LivingEffect.dread:
      fx.dread();
    case LivingEffect.howl:
      fx.howl();
    case LivingEffect.drown:
      fx.drown();
    case LivingEffect.stone:
      fx.stone();
    case LivingEffect.crush:
      fx.crush();
    case LivingEffect.lunge:
      fx.lunge();
    case LivingEffect.tremble:
      fx.tremble();
    case LivingEffect.poison:
      fx.poison();
    case LivingEffect.choke:
      fx.choke();
    case LivingEffect.wither:
      fx.wither();
    case LivingEffect.plummet:
      fx.plummet();
    case LivingEffect.devour:
      fx.devour();
  }
}

/// Draws living word [id] with its own effect, at its own strength.
class LivingWordPainter extends CustomPainter {
  LivingWordPainter({
    required this.glyphs,
    required this.effect,
    required this.controller,
    required this.id,
  }) : super(repaint: controller.frame);

  final WordGlyphs glyphs;
  final LivingEffect effect;
  final LivingWordsController controller;
  final int id;

  @override
  void paint(Canvas canvas, Size size) {
    paintLivingEffect(
      canvas,
      glyphs,
      effect,
      controller.selfLevel(id),
      controller.time,
      id,
    );
  }

  @override
  bool shouldRepaint(LivingWordPainter old) =>
      old.glyphs != glyphs || old.effect != effect || old.id != id;
}

/// A repeatable random number in [0, 1) for a pair of ints.
double hash01(int a, [int b = 0]) {
  var x = (a * 374761393 + b * 668265263 + 1442695040) & 0x7fffffff;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff;
  x ^= x >> 16;
  return (x & 0xffff) / 0x10000;
}

double _smooth(double x) {
  final s = x.clamp(0.0, 1.0);
  return s * s * (3 - 2 * s);
}

Paint _shaded(
  Shader shader,
  double alpha, [
  BlendMode mode = BlendMode.srcATop,
]) => Paint()
  ..shader = shader
  ..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0))
  ..blendMode = mode;

class _WordFx {
  _WordFx(this.c, this.g, this.p, this.t, this.seed);

  final Canvas c;
  final WordGlyphs g;
  final double p;
  final double t;
  final int seed;

  double get em => g.em;
  double get w => g.size.width;
  Rect get room => g.room;

  void word([Offset at = Offset.zero]) => g.word.paint(c, at);

  void letter(int i, [Offset shift = Offset.zero]) =>
      g.letters[i].paint(c, Offset(g.boxes[i].left, 0) + shift);

  /// Draws [body] into its own layer, so later colour lands only on ink.
  void layer(void Function() body, [Paint? paint]) {
    c.saveLayer(room, paint ?? Paint());
    body();
    c.restore();
  }

  /// Colour laid over ink already drawn in the current layer.
  void tint(Color color, double amount) {
    if (amount <= 0) return;
    c.drawRect(
      room,
      Paint()
        ..color = color.withValues(alpha: amount.clamp(0.0, 1.0))
        ..blendMode = BlendMode.srcATop,
    );
  }

  /// A soft coloured halo behind the word.
  void glow(
    Color color,
    double alpha,
    double sigma, [
    Offset at = Offset.zero,
  ]) {
    if (alpha <= 0.01) return;
    c.saveLayer(
      room.inflate(sigma * 3),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
        ..colorFilter = ColorFilter.mode(
          color.withValues(alpha: alpha.clamp(0.0, 1.0)),
          BlendMode.srcIn,
        ),
    );
    word(at);
    c.restore();
  }

  /// Rotates/scales about a point.
  void about(Offset o, void Function() body) {
    c.translate(o.dx, o.dy);
    body();
    c.translate(-o.dx, -o.dy);
  }

  // ---------------------------------------------------------------- fire

  /// Embers climb up inside each letter, flickering; a warm glow behind.
  void fire() {
    final flick = 0.82 + 0.18 * math.sin(t * 7.3) * math.sin(t * 2.9 + 1);
    glow(const Color(0xFFE8641E), 0.42 * p * flick, em * 0.1);
    layer(() {
      word();
      tint(const Color(0xFF7C2D12), 0.35 * p);
      for (var i = 0; i < g.count; i++) {
        final b = g.boxes[i];
        final line = (0.18 + 0.55 * p + 0.07 * math.sin(t * 5.1 + i * 1.7))
            .clamp(0.0, 0.95);
        c.drawRect(
          Rect.fromLTRB(b.left - 1, room.top, b.right + 1, room.bottom),
          _shaded(
            ui.Gradient.linear(
              Offset(0, g.bottom),
              Offset(0, g.top),
              const [Color(0xFFC2410C), Color(0xFFF59E0B), Color(0x00F59E0B)],
              [0, line, math.min(1, line + 0.28)],
            ),
            math.min(1, p * 1.4),
          ),
        );
      }
    });
  }

  // ---------------------------------------------------------------- roar

  /// The word swells on a beat, letters pushed out from the middle.
  void roar() {
    final ph = (t % 2.6) / 2.6;
    final beat = ph < 0.07 ? ph / 0.07 : math.exp(-(ph - 0.07) * 7);
    final cx = w / 2;
    final s = 1 + 0.04 * p * beat;
    c.save();
    about(Offset(cx, g.baseline - em * 0.3), () => c.scale(s));
    layer(() {
      for (var i = 0; i < g.count; i++) {
        final dx = (g.boxes[i].center.dx - cx) / math.max(w, 1) * em * 0.09;
        letter(i, Offset(dx * p * beat, 0));
      }
      tint(const Color(0xFF7F1D1D), 0.45 * p);
    });
    c.restore();
  }

  // ---------------------------------------------------------------- slash

  /// A diagonal cut; the top half slides along it, edged in red.
  void slash() {
    final a = Offset(room.left, g.baseline - em * 0.14);
    final b = Offset(room.right, g.baseline - em * 0.5);
    final dir = (b - a) / (b - a).distance;
    final upper = Path()
      ..moveTo(room.left, room.top)
      ..lineTo(room.right, room.top)
      ..lineTo(b.dx, b.dy)
      ..lineTo(a.dx, a.dy)
      ..close();
    final lower = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(room.right, room.bottom)
      ..lineTo(room.left, room.bottom)
      ..close();
    final slide = dir * em * 0.07 * p + Offset(0, -em * 0.025 * p);
    layer(() {
      c.save();
      c.clipPath(lower);
      word();
      c.restore();
      c.save();
      c.clipPath(upper);
      word(slide);
      c.restore();
      tint(const Color(0xFF3B0D0D), 0.25 * p);
      c.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xFFDC2626).withValues(alpha: p)
          ..strokeWidth = em * 0.06
          ..blendMode = BlendMode.srcATop,
      );
    });
  }

  // ---------------------------------------------------------------- bolt

  /// Charged blue; every few seconds a fork of lightning runs through.
  void bolt() {
    const period = 3.7;
    final n = (t / period).floor();
    final x = t - n * period;
    final f = (math.exp(-x * 6) * (0.65 + 0.35 * math.cos(x * 55))).clamp(
      0.0,
      1.0,
    );
    glow(const Color(0xFF60A5FA), 0.85 * f * p, em * 0.12);
    layer(() {
      word();
      tint(const Color(0xFF1E3A8A), 0.4 * p);
      final sweep = (t * 0.5) % 1.6 - 0.3;
      c.drawRect(
        room,
        _shaded(
          ui.Gradient.linear(
            Offset(w * (sweep - 0.25), 0),
            Offset(w * (sweep + 0.25), 0),
            const [Color(0x0093C5FD), Color(0xFF93C5FD), Color(0x0093C5FD)],
            const [0, 0.5, 1],
          ),
          0.45 * p,
        ),
      );
      if (f > 0.02) {
        final r = math.Random(seed * 31 + n);
        final path = Path()..moveTo(-em * 0.1, g.top + g.band * r.nextDouble());
        const steps = 7;
        for (var k = 1; k <= steps; k++) {
          path.lineTo(
            w * k / steps + (r.nextDouble() - 0.5) * em * 0.2,
            g.top + g.band * (0.15 + 0.7 * r.nextDouble()),
          );
        }
        c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = em * 0.07
            ..strokeJoin = StrokeJoin.miter
            ..color = const Color(0xFFF0F7FF).withValues(alpha: f * p)
            ..blendMode = BlendMode.srcATop,
        );
      }
    });
  }

  // ------------------------------------------------------------- shatter

  /// The word breaks into four pieces that drift a hair apart.
  void shatter() {
    const cuts = [0.27, 0.53, 0.78];
    final r = math.Random(seed);
    final lines = [
      for (final x in cuts)
        (
          Offset(w * x + (r.nextDouble() - 0.5) * em * 0.35, room.top),
          Offset(w * x + (r.nextDouble() - 0.5) * em * 0.35, room.bottom),
        ),
    ];
    const drift = [
      Offset(-0.035, -0.02),
      Offset(0.012, 0.03),
      Offset(-0.012, -0.032),
      Offset(0.035, 0.018),
    ];
    for (var k = 0; k < 4; k++) {
      final left = k == 0 ? (room.topLeft, room.bottomLeft) : lines[k - 1];
      final right = k == 3 ? (room.topRight, room.bottomRight) : lines[k];
      final piece = Path()
        ..moveTo(left.$1.dx, left.$1.dy)
        ..lineTo(right.$1.dx, right.$1.dy)
        ..lineTo(right.$2.dx, right.$2.dy)
        ..lineTo(left.$2.dx, left.$2.dy)
        ..close();
      final breathe = 0.85 + 0.15 * math.sin(t * 1.3 + k * 2);
      final shift = drift[k] * em * p * breathe;
      final centre = Offset(
        (left.$1.dx + right.$1.dx) / 2,
        g.baseline - em * 0.3,
      );
      c.save();
      c.clipPath(piece.shift(shift));
      c.translate(shift.dx, shift.dy);
      about(centre, () => c.rotate((k.isEven ? -1 : 1) * 0.02 * p * breathe));
      word();
      c.restore();
    }
  }

  // --------------------------------------------------------------- frost

  /// Icy blue rimes the letters from the top, glinting now and then.
  void frost() {
    layer(() {
      word();
      tint(const Color(0xFF4F7FA6), 0.6 * p);
      c.drawRect(
        room,
        _shaded(
          ui.Gradient.linear(
            Offset(0, g.top),
            Offset(0, g.bottom),
            const [Color(0xFFE6F2FF), Color(0x00E6F2FF)],
            [0, 0.55],
          ),
          0.75 * p,
        ),
      );
      final r = math.Random(seed);
      for (var k = 0; k < 16; k++) {
        final at = Offset(r.nextDouble() * w, g.top + r.nextDouble() * g.band);
        final tw = math.pow(
          0.5 + 0.5 * math.sin(t * (1.4 + r.nextDouble()) + k * 2.1),
          3,
        );
        c.drawCircle(
          at,
          em * (0.025 + 0.025 * r.nextDouble()),
          Paint()
            ..color = Colors.white.withValues(alpha: p * tw.toDouble())
            ..blendMode = BlendMode.srcATop,
        );
      }
    });
  }

  // ---------------------------------------------------------------- echo

  /// Faint copies ripple out to either side and fade.
  void echo() {
    for (final lag in const [0.0, 0.5]) {
      final ph = ((t / 2.8) + lag) % 1;
      final alpha = 0.34 * p * (1 - ph) * math.min(1, ph * 6);
      if (alpha <= 0.01) continue;
      for (final side in const [-1, 1]) {
        c.saveLayer(
          room,
          Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)),
        );
        word(Offset(side * em * 0.15 * ph, 0));
        c.restore();
      }
    }
    word();
  }

  // --------------------------------------------------------------- blood

  /// Red spreads through the word from its middle like an infection: deep
  /// at the heart, thinning gradually toward the ends, reaching further as
  /// it grows. Drips gather below once it's well in.
  void blood() {
    const red = Color(0xFF991B1B);
    const deep = Color(0xFF6B0F0F);
    layer(() {
      word();
      final mid = Offset(w / 2, (g.top + g.bottom) / 2);
      // Out past the ends of the word at full strength; a slow pulse.
      final pulse = 1 + 0.04 * math.sin(t * 1.4);
      final radius =
          math.max(em, (w / 2 + em * 0.5) * (0.35 + 0.85 * p)) * pulse;
      c.drawRect(
        room,
        _shaded(
          ui.Gradient.radial(
            mid,
            radius,
            [deep, red, red.withValues(alpha: 0.55), red.withValues(alpha: 0)],
            const [0, 0.3, 0.65, 1],
          ),
          math.min(1, p * 1.6),
        ),
      );
    });
    // Drips under two letters, only once the soak is well in.
    final drip = _smooth((p - 0.25) / 0.5);
    if (drip <= 0 || g.count == 0) return;
    final r = math.Random(seed);
    for (var k = 0; k < 2; k++) {
      final i = r.nextInt(g.count);
      final b = g.boxes[i];
      final x = b.left + b.width * (0.3 + 0.4 * r.nextDouble());
      final len = em * 0.16 * drip * (0.75 + 0.25 * math.sin(t * 0.5 + k * 2));
      final paint = Paint()..color = red.withValues(alpha: drip);
      final y0 = g.baseline - em * 0.04;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - em * 0.03, y0, em * 0.06, len),
          Radius.circular(em * 0.03),
        ),
        paint,
      );
      c.drawCircle(Offset(x, y0 + len), em * 0.05 * drip, paint);
    }
  }

  // -------------------------------------------------------------- vanish

  /// Parts of letters fade away: the bottoms of some, the tops of others.
  void vanish() {
    const tops = [false, true, false, false, true, true, false, true];
    final m = 0.8 * p;
    for (var i = 0; i < g.count; i++) {
      final up = tops[(i + seed) % tops.length];
      final shader = up
          ? ui.Gradient.linear(
              Offset(0, g.bottom),
              Offset(0, g.top),
              [Colors.black, Colors.black, Color.fromRGBO(0, 0, 0, 1 - m)],
              const [0, 0.5, 0.68],
            )
          : ui.Gradient.linear(
              Offset(0, g.top),
              Offset(0, g.bottom),
              [Colors.black, Colors.black, Color.fromRGBO(0, 0, 0, 1 - m)],
              const [0, 0.46, 0.7],
            );
      layer(() {
        letter(i);
        c.drawRect(
          room,
          Paint()
            ..shader = shader
            ..blendMode = BlendMode.dstIn,
        );
      });
    }
  }

  // --------------------------------------------------------------- dread

  /// The letters hollow out from the top, leaving their outline, and
  /// shiver now and then.
  void dread() {
    final fit = math.pow(math.max(0, math.sin(t * 0.9)), 8).toDouble();
    final dx = em * 0.014 * p * fit * math.sin(t * 47);
    c.save();
    c.translate(dx, 0);
    layer(() {
      word();
      tint(Colors.black, 0.2 * p);
      c.drawRect(
        room,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, g.top),
            Offset(0, g.bottom),
            [
              Color.fromRGBO(0, 0, 0, 1 - 0.92 * p),
              Color.fromRGBO(0, 0, 0, 1 - 0.75 * p),
              Color.fromRGBO(0, 0, 0, 1 - 0.3 * p),
            ],
            const [0, 0.6, 1],
          )
          ..blendMode = BlendMode.dstIn,
      );
    });
    c.saveLayer(room, Paint()..color = Color.fromRGBO(0, 0, 0, p));
    g.outline.paint(c, Offset.zero);
    c.restore();
    c.restore();
  }

  // ---------------------------------------------------------------- howl

  /// Gusts bend the word sideways; streaks of wind cut through it.
  void howl() {
    final gust = p * math.pow(math.max(0, math.sin(t * 2 * math.pi / 3.4)), 3);
    c.save();
    c.translate(em * 0.05 * gust, g.baseline);
    c.skew(-0.24 * gust, 0);
    c.translate(0, -g.baseline);
    layer(() {
      word();
      final streak = Paint()
        ..color = g.paper.withValues(alpha: 0.6 * p)
        ..strokeWidth = math.max(0.8, em * 0.04)
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.srcATop;
      for (var k = 0; k < 3; k++) {
        final y = g.top + g.band * (0.25 + 0.22 * k);
        final x = ((t * (0.9 + 0.2 * k) + k * 0.37) % 1.4 - 0.2) * w;
        c.drawLine(Offset(x, y), Offset(x + em * 0.7, y), streak);
      }
    });
    c.restore();
  }

  // --------------------------------------------------------------- drown

  /// Each letter floats on its own, with still water risen inside it.
  void drown() {
    final lv = 0.27 + 0.26 * p;
    final water = ui.Gradient.linear(
      Offset(0, g.bottom),
      Offset(0, g.top),
      const [
        Color(0xFF245F74),
        Color(0xFF3F8BA3),
        Color(0xE696CDDC),
        Color(0x00CDEBF2),
      ],
      [0, lv, lv + 0.02, lv + 0.07],
    );
    for (var i = 0; i < g.count; i++) {
      final u = (1 - math.cos(2 * math.pi * (t + i * 0.62) / 4.4)) / 2;
      final dy = em * p * (0.06 - 0.13 * u);
      final turn = p * (-2.5 + 5 * u) * math.pi / 180;
      final b = g.boxes[i];
      c.save();
      c.translate(0, dy);
      about(Offset(b.center.dx, g.baseline - em * 0.3), () => c.rotate(turn));
      layer(() {
        letter(i);
        tint(const Color(0xFF1E4A5A), 0.6 * p);
        c.drawRect(room, _shaded(water, math.min(1, p * 1.5)));
      });
      c.restore();
    }
  }

  // --------------------------------------------------------------- stone

  /// The letters turn to brown stone, dark grain creeping across them.
  void stone() {
    final r = math.Random(seed);
    layer(() {
      word();
      tint(const Color(0xFF7A6248), 0.85 * p);
      for (var k = 0; k < 90; k++) {
        final at = Offset(
          r.nextDouble() * w,
          g.top - em * 0.1 + r.nextDouble() * (g.band + em * 0.2),
        );
        final radius = em * (0.018 + 0.03 * r.nextDouble());
        final show = _smooth((p * 1.15 - r.nextDouble()) / 0.15);
        if (show <= 0) continue;
        c.drawCircle(
          at,
          radius,
          Paint()
            ..color = const Color(0xFF1A120A).withValues(alpha: 0.7 * show)
            ..blendMode = BlendMode.srcATop,
        );
      }
    });
  }

  // --------------------------------------------------------------- crush

  /// Pressed flat from above, bearing down in slow pulses.
  void crush() {
    final bear = math.pow(math.max(0, math.sin(2 * math.pi * t / 3.2)), 2);
    final sy = 1 - p * (0.13 + 0.05 * bear);
    final sx = 1 + p * (0.03 + 0.015 * bear);
    c.save();
    about(Offset(w / 2, g.baseline), () => c.scale(sx, sy));
    layer(() {
      word();
      tint(const Color(0xFF292524), 0.3 * p);
    });
    c.restore();
  }

  // --------------------------------------------------------------- lunge

  /// Winds back, then springs forward with a smear behind it.
  void lunge() {
    final x = t % 3.6;
    double k;
    if (x < 0.3) {
      k = -0.25 * math.sin(math.pi / 2 * x / 0.3);
    } else if (x < 0.42) {
      k = -0.25 + 1.25 * (x - 0.3) / 0.12;
    } else {
      k = math.exp(-(x - 0.42) * 3.2);
    }
    k *= p;
    if (k > 0.02) {
      c.saveLayer(room, Paint()..color = Color.fromRGBO(0, 0, 0, 0.3 * k));
      word(Offset(-em * 0.1 * k, 0));
      c.restore();
    }
    c.save();
    c.translate(em * 0.07 * k, g.baseline);
    c.skew(-0.18 * k, 0);
    c.translate(0, -g.baseline);
    word();
    c.restore();
  }

  // ------------------------------------------------------------- tremble

  /// Each letter quivers on its own, with a faint double behind.
  void tremble() {
    final step = (t / 0.07).floor();
    final q = p * (0.7 + 0.3 * math.sin(t * 1.7));
    final reach = em * 0.032 * q;
    c.saveLayer(room, Paint()..color = Color.fromRGBO(0, 0, 0, 0.2 * p));
    word(
      Offset(
        (hash01(seed, step) - 0.5) * 2 * reach,
        (hash01(seed + 7, step) - 0.5) * 2 * reach,
      ),
    );
    c.restore();
    for (var i = 0; i < g.count; i++) {
      letter(
        i,
        Offset(
          (hash01(i * 13 + seed, step) - 0.5) * 2 * reach,
          (hash01(i * 17 + seed + 3, step) - 0.5) * 2 * reach,
        ),
      );
    }
  }

  // -------------------------------------------------------------- poison

  /// Green venom seeps up through the letters in slow blooms.
  void poison() {
    layer(() {
      word();
      tint(const Color(0xFF3F5F17), 0.45 * p);
      for (var k = 0; k < 5; k++) {
        final at = Offset(
          w * (k + 0.5) / 5 + em * 0.2 * math.sin(t * 0.7 + k),
          g.bottom + em * 0.1 - ((t * 0.09 + k * 0.23) % 1) * g.band * 1.4,
        );
        c.drawCircle(
          at,
          em * 0.45,
          _shaded(
            ui.Gradient.radial(at, em * 0.45, const [
              Color(0xFF84CC16),
              Color(0x0084CC16),
            ]),
            0.9 * p,
          ),
        );
      }
    });
  }

  // --------------------------------------------------------------- choke

  /// Smoke rises through the letters, which dim and soften.
  void choke() {
    final blur = em * 0.035 * p;
    layer(
      () {
        word();
        tint(const Color(0xFF44403C), 0.3 * p);
        for (var k = 0; k < 6; k++) {
          final at = Offset(
            w * (k + 0.5) / 6 + em * 0.25 * math.sin(t * 0.5 + k * 1.3),
            g.bottom + em * 0.15 - ((t * 0.11 + k * 0.19) % 1) * g.band * 1.5,
          );
          final radius = em * (0.35 + 0.15 * hash01(seed, k));
          c.drawCircle(
            at,
            radius,
            _shaded(
              ui.Gradient.radial(at, radius, const [
                Color(0xFF8A8A8A),
                Color(0x008A8A8A),
              ]),
              0.75 * p,
            ),
          );
        }
      },
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, 1 - 0.28 * p)
        ..imageFilter = blur > 0.05
            ? ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur)
            : null,
    );
  }

  // -------------------------------------------------------------- wither

  /// Letters sag more toward the end of the word and dry to brown.
  void wither() {
    final droop = 0.92 + 0.08 * math.sin(t * 0.6);
    layer(() {
      for (var i = 0; i < g.count; i++) {
        final f = g.along(i) * p * droop;
        final b = g.boxes[i];
        c.save();
        c.translate(0, em * 0.07 * f);
        about(
          Offset(b.left, g.baseline),
          () => c.rotate(f * 4 * math.pi / 180),
        );
        letter(i);
        c.restore();
      }
      tint(const Color(0xFF8A6A3A), 0.5 * p);
      final r = math.Random(seed);
      for (var k = 0; k < 6; k++) {
        final at = Offset(r.nextDouble() * w, g.top + r.nextDouble() * g.band);
        final radius = em * 0.14 * (0.5 + p);
        c.drawCircle(
          at,
          radius,
          _shaded(
            ui.Gradient.radial(at, radius, const [
              Color(0xFF5A3A1A),
              Color(0x005A3A1A),
            ]),
            0.6 * p,
          ),
        );
      }
    });
  }

  // ------------------------------------------------------------- plummet

  /// Letters step downward and drop now and then; streaks rush up
  /// through them.
  void plummet() {
    final x = t % 4.8;
    layer(() {
      for (var i = 0; i < g.count; i++) {
        final stair = em * 0.12 * p * g.along(i);
        final d = x - 0.08 * i;
        final drop = d > 0 && d < 0.5
            ? math.sin(math.pi * d / 0.5) * em * 0.08 * p
            : 0.0;
        letter(i, Offset(0, stair + drop));
      }
      final streak = Paint()
        ..color = g.paper.withValues(alpha: 0.55 * p)
        ..strokeWidth = math.max(0.8, em * 0.035)
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.srcATop;
      for (var k = 0; k < 4; k++) {
        final sx = w * (0.15 + 0.23 * k);
        final y =
            g.bottom + em * 0.2 - ((t * 1.3 + k * 0.31) % 1.3) * g.band * 1.8;
        c.drawLine(Offset(sx, y), Offset(sx, y + em * 0.3), streak);
      }
    });
  }

  // -------------------------------------------------------------- devour

  /// Bites appear in the letters, one after another, and grow.
  void devour() {
    final r = math.Random(seed);
    final bites = [
      (Offset(w * (0.15 + 0.1 * r.nextDouble()), g.top - em * 0.02), 0.0),
      (Offset(w * (0.5 + 0.12 * r.nextDouble()), g.bottom - em * 0.02), 0.25),
      (Offset(w * (0.82 + 0.1 * r.nextDouble()), g.top + em * 0.08), 0.5),
    ];
    final gone = Paint()..blendMode = BlendMode.dstOut;
    layer(() {
      word();
      for (final (k, (at, from)) in bites.indexed) {
        final grow = ((p - from) / (1 - from)).clamp(0.0, 1.0);
        if (grow <= 0) continue;
        final radius =
            em * 0.24 * math.sqrt(grow) * (1 + 0.05 * math.sin(t * 3 + k));
        c.drawCircle(at, radius, gone);
        // Two smaller scoops at the edge, like teeth.
        for (final side in const [-1, 1]) {
          c.drawCircle(
            at + Offset(side * radius * 0.85, side * radius * 0.15),
            radius * 0.45,
            gone,
          );
        }
      }
    });
  }
}
