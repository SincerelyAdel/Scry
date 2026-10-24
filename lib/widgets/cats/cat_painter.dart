import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'cat_breeds.dart';
import 'cat_sim.dart';

/// Draws the cats of a [CatPack] as they are this frame.
class CatPainter extends CustomPainter {
  CatPainter(this.pack, {required Listenable repaint, this.opacity = 1})
    : super(repaint: repaint);

  final CatPack pack;
  final double opacity;

  static final Map<String, ui.Image> _fur = {};

  /// Fine fur strokes, tiled over the coat (4.2 x 3 units, drawn 6x).
  static ui.Image _furTile(CatBreed b) {
    return _fur.putIfAbsent(b.id, () {
      const k = 6.0;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..scale(k);
      final dark = Paint()
        ..color = b.dark.withValues(alpha: 0.55)
        ..strokeWidth = 0.42
        ..strokeCap = StrokeCap.round;
      final light = Paint()
        ..color = b.light.withValues(alpha: 0.45)
        ..strokeWidth = 0.34
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(const Offset(0, .7), const Offset(2.6, .7), dark)
        ..drawLine(const Offset(2.1, 2.2), const Offset(4.7, 2.2), dark)
        ..drawLine(const Offset(.9, 1.45), const Offset(3.1, 1.45), light)
        ..drawLine(const Offset(3.2, .1), const Offset(4.6, .1), light)
        ..drawLine(const Offset(-.2, 2.9), const Offset(1.4, 2.9), light);
      return rec.endRecording().toImageSync((4.2 * k).round(), (3 * k).round());
    });
  }

  Paint _furPaint(CatBreed b, Offset origin, double angle) {
    final m = Matrix4.identity()
      ..translateByDouble(origin.dx, origin.dy, 0, 1)
      ..rotateZ(angle)
      ..scaleByDouble(1 / 6, 1 / 6, 1, 1);
    return Paint()
      ..shader = ImageShader(
        _furTile(b),
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList(m.storage),
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    if (opacity < 1) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
    for (final c in pack.cats) {
      final pose = c.pose;
      if (pose != null) _cat(canvas, c, pose);
    }
    if (opacity < 1) canvas.restore();
  }

  void _cat(Canvas canvas, Cat c, CatPose p) {
    final b = c.b, s = c.s;
    Paint stroke(Color color, double width, [double alpha = 1]) => Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    // Shadow under the body.
    canvas.drawPath(
      p.outline.shift(p.shadowOffset),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.6 * s),
    );

    // Legs and paws.
    canvas.drawPath(p.legs, stroke(b.legs, 4.6 * s));
    for (final (at, rx, ry, angle) in p.paws) {
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(angle);
      final r = Rect.fromCenter(
        center: Offset.zero,
        width: rx * 2,
        height: ry * 2,
      );
      canvas
        ..drawOval(r, Paint()..color = b.paws)
        ..drawOval(r, stroke(b.rim, 0.5, 0.6))
        ..restore();
    }

    // Tail.
    canvas
      ..drawPath(p.tail, stroke(b.fringe, p.tailWidth * 1.48, 0.18))
      ..drawPath(p.tail, stroke(b.tail, p.tailWidth))
      ..drawPath(p.tailBase, stroke(b.tail, 6.6 * s))
      ..drawPath(p.tailRings, stroke(b.stripeColor, 2.2 * s, b.stripeOpacity));

    // Body, then its coat inside the outline.
    canvas.drawPath(p.outline, Paint()..color = b.base);
    canvas
      ..save()
      ..clipPath(p.outline);
    canvas.drawPath(p.outline, _furPaint(b, p.furOrigin, p.furAngle));
    for (final (at, r) in p.patchesA) {
      canvas.drawCircle(at, r, Paint()..color = b.patchA ?? b.base);
    }
    for (final (at, r) in p.patchesB) {
      canvas.drawCircle(at, r, Paint()..color = b.patchB ?? b.base);
    }
    final haunch = p.haunch;
    if (haunch != null) {
      canvas.drawCircle(
        haunch.$1,
        haunch.$2,
        Paint()..color = (b.points ?? b.base).withValues(alpha: 0.32),
      );
    }
    if (b.stripe != null) {
      canvas
        ..drawPath(p.back, stroke(b.stripeColor, 3.8 * s, b.stripeOpacity))
        ..drawPath(p.stripes, stroke(b.stripeColor, 2.3 * s, b.stripeOpacity));
    }
    // A soft sheen along the back.
    final sheen = b.sheenOpacity * 0.6;
    for (final w in [17.0, 10.5, 5.0]) {
      canvas.drawPath(p.back, stroke(b.light, w * s, sheen));
    }
    // Darker edges, so the body looks round.
    canvas
      ..drawPath(p.outline, stroke(b.rim, 6 * s, 0.5))
      ..restore();
    canvas.drawPath(p.outline, stroke(b.fringe, 1.8 * s, 0.22));

    _head(canvas, c, p);
  }

  // The head, drawn nose along +x in its own units.
  static final _headShape = _svg(
    'M-9.6 0 C-9.6 -7.6 -4.6 -10.6 1 -10.1 C6.6 -9.5 10.6 -6.1 12.3 -2.7 '
    'C13.1 -1 13.1 1 12.3 2.7 C10.6 6.1 6.6 9.5 1 10.1 C-4.6 10.6 -9.6 7.6 '
    '-9.6 0 Z',
  );
  static final _earOuter = _svg(
    'M-5.6 -6 C-6.2 -10.2 -4.6 -14.6 -2.5 -17 C.3 -14.6 2.7 -10.6 3.3 -7.2 Z',
  );
  static final _earInner = _svg(
    'M-3.6 -8.6 C-3.6 -11.4 -3 -13.6 -2.4 -15 C-.8 -13.2 .9 -10.8 1.4 -8.4 Z',
  );
  static final _earTufts = _svg('M-2.4 -14.6 L-1.6 -10.4 M-1 -13.4 L-.6 -9.8');
  static final _blazePath = _svg(
    'M3 -1.8 C6 -1.2 9 -2 12.6 -1.2 L12.6 1.2 C9 2 6 1.2 3 1.8 Z',
  );
  static final _faceStripes = _svg(
    'M-6.2 -4.6 C-2.2 -3.6 .8 -3.9 3.6 -2.7 M-6.8 0 L3.4 0 '
    'M-6.2 4.6 C-2.2 3.6 .8 3.9 3.6 2.7 M-8 -2.3 L-3 -1.6 M-8 2.3 L-3 1.6 '
    'M4.2 -4.4 L6.8 -3.1 M4.2 4.4 L6.8 3.1',
  );
  static final _eyes = _svg(
    'M3.5 -6.6 Q6 -8.2 8.4 -6.3 Q6 -5.2 3.5 -6.6 Z '
    'M3.5 6.6 Q6 8.2 8.4 6.3 Q6 5.2 3.5 6.6 Z',
  );
  static final _pupils = _svg('M6 -7.5 L6.2 -5.7 M6 7.5 L6.2 5.7');
  static final _lidsPath = _svg(
    'M3.2 -6.7 Q6 -8.5 8.7 -6.4 Q6 -5.2 3.2 -6.7 Z '
    'M3.2 6.7 Q6 8.5 8.7 6.4 Q6 5.2 3.2 6.7 Z',
  );
  static final _brows = _svg('M3.2 -7.3 Q6 -9 8.8 -6.6 M3.2 7.3 Q6 9 8.8 6.6');
  static final _nosePath = _svg(
    'M12.1 -1.15 L13.5 0 L12.1 1.15 Q11.6 0 12.1 -1.15 Z',
  );
  static final _whiskers = _svg(
    'M10.6 -2.7 Q15 -4.6 21 -6.4 M10.9 -3.3 Q15 -6.6 19.6 -10.4 '
    'M10.5 -3.8 Q13.4 -8.2 16.6 -13.2 M10.6 2.7 Q15 4.6 21 6.4 '
    'M10.9 3.3 Q15 6.6 19.6 10.4 M10.5 3.8 Q13.4 8.2 16.6 13.2 '
    'M3.4 -8.6 Q4.6 -12 6.4 -14.6 M3.4 8.6 Q4.6 12 6.4 14.6',
  );
  static final _headBox = _headShape.getBounds();

  void _head(Canvas canvas, Cat c, CatPose p) {
    final b = c.b;
    Paint fill(Color color, [double alpha = 1]) =>
        Paint()..color = color.withValues(alpha: alpha);
    Paint line(Color color, double width, [double alpha = 1]) => Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    canvas
      ..save()
      ..translate(p.head.dx, p.head.dy)
      ..rotate(p.headAngle)
      ..scale(p.headScale);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(1.8, 3.4), width: 22, height: 20),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6),
    );

    for (final (mirror, angle, pivot) in [
      (false, p.earL, const Offset(-3, -8)),
      (true, p.earR, const Offset(-3, 8)),
    ]) {
      canvas
        ..save()
        ..translate(pivot.dx, pivot.dy)
        ..rotate(angle)
        ..translate(-pivot.dx, -pivot.dy);
      if (mirror) canvas.scale(1, -1);
      canvas
        ..drawPath(_earOuter, fill(b.ear))
        ..drawPath(_earOuter, line(b.rim, 0.5, 0.7))
        ..drawPath(_earInner, fill(b.earIn, 0.55))
        ..drawPath(_earTufts, line(b.whisker, 0.3, 0.6))
        ..restore();
    }

    canvas
      ..drawPath(_headShape, fill(b.base))
      ..drawPath(_headShape, _furPaint(b, Offset.zero, 0));
    if (b.headPatch) {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(-2, -4.8),
          width: 12.4,
          height: 9.2,
        ),
        fill(b.patchA ?? b.base, 0.95),
      );
    }
    final points = b.points;
    if (points != null) {
      // Siamese mask over the face.
      final r = Rect.fromCenter(
        center: const Offset(6.4, 0),
        width: 14.8,
        height: 15.2,
      );
      canvas.drawOval(
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.2, 0),
            radius: 0.55,
            colors: [
              points.withValues(alpha: 0.97),
              points.withValues(alpha: 0.85),
              points.withValues(alpha: 0),
            ],
            stops: const [0, 0.62, 1],
          ).createShader(r),
      );
    }
    if (b.blaze != null) canvas.drawPath(_blazePath, fill(b.blaze!, 0.95));
    if (b.stripe != null) {
      canvas.drawPath(_faceStripes, line(b.stripeColor, 1.15, b.stripeOpacity));
    }
    // Light on the crown, shade at the edges.
    canvas.drawPath(
      _headShape,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.24, 0),
          radius: 0.72,
          colors: [
            b.light.withValues(alpha: 0.38),
            b.light.withValues(alpha: 0),
            b.rim.withValues(alpha: 0.5),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(_headBox),
    );
    for (final y in [-2.0, 2.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(9.8, y), width: 5.2, height: 4.6),
        fill(b.muzzle, 0.6),
      );
    }
    canvas
      ..drawPath(_eyes, fill(b.eye))
      ..drawPath(_pupils, line(const Color(0xFF080808), 0.75))
      ..drawCircle(const Offset(6.9, -6.8), 0.38, fill(Colors.white, 0.9))
      ..drawCircle(const Offset(6.9, 6.8), 0.38, fill(Colors.white, 0.9));
    if (p.lids > 0.01) canvas.drawPath(_lidsPath, fill(b.base, p.lids));
    canvas
      ..drawPath(_brows, line(b.rim, 0.55, 0.7))
      ..drawPath(_nosePath, fill(b.nose))
      ..drawPath(_headShape, line(b.fringe, 0.9, 0.25))
      ..drawPath(_whiskers, line(b.whisker, 0.32, 0.72))
      ..restore();
  }

  @override
  bool shouldRepaint(CatPainter old) =>
      old.pack != pack || old.opacity != opacity;
}

/// A path from SVG path data (absolute M, L, Q, C and Z only).
Path _svg(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLQCZ]|-?(?:\d+\.?\d*|\.\d+)')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  var cmd = 'M';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'^[MLQCZ]$').hasMatch(t)) {
      cmd = t;
      i++;
      if (cmd == 'Z') {
        path.close();
        continue;
      }
    }
    switch (cmd) {
      case 'M':
        path.moveTo(next(), next());
        cmd = 'L';
      case 'L':
        path.lineTo(next(), next());
      case 'Q':
        path.quadraticBezierTo(next(), next(), next(), next());
      case 'C':
        path.cubicTo(next(), next(), next(), next(), next(), next());
    }
  }
  return path;
}
