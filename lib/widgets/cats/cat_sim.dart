import 'dart:math' as math;
import 'dart:ui';

import 'cat_breeds.dart';

// Realistic top-down cats. Each cat is a little skeleton: the head follows
// a curved path, the spine and tail follow the trail the head leaves, and
// the paws plant and step on their own.

/// Distances from the nose along the trail (before scaling): head centre,
/// neck, shoulders, chest, mid, loin, hips, rump, tail base.
const _spine = <double>[9.0, 19, 28, 36, 46, 56, 64, 71, 76];
const _halfWidth = <double>[0.0, 6.6, 9.6, 10.6, 10.2, 9.8, 10.6, 7.6, 3.2];
const _tabbyStripes = <double>[31.0, 36.5, 42, 47.5, 53, 58.5, 64, 69];
const _speed = {'walk': 34.0, 'trot': 72.0, 'run': 165.0};

/// Stride (body units per cycle), share of the cycle each paw is planted,
/// and each leg's place in the cycle [LF, RF, LH, RH]: a walk goes LH, LF,
/// RH, RF; a trot moves diagonal pairs; a gallop lands the hinds, then the
/// fores.
class _Gait {
  const _Gait(this.stride, this.duty, this.off);
  final double stride, duty;
  final List<double> off;
}

const _gaits = {
  'walk': _Gait(17, 0.62, [0.25, 0.75, 0, 0.5]),
  'trot': _Gait(24, 0.5, [0, 0.5, 0.5, 0]),
  'run': _Gait(46, 0.32, [0.5, 0.6, 0, 0.1]),
};

final _rng = math.Random();
double _rand(double a, double b) => a + _rng.nextDouble() * (b - a);
double _lerp(double a, double b, double t) => a + (b - a) * t;
Offset _lerpO(Offset a, Offset b, double t) =>
    Offset(_lerp(a.dx, b.dx, t), _lerp(a.dy, b.dy, t));

// ----------------------------------------------------------------- easing

typedef _Ease = double Function(double t);
double _sineInOut(double t) => -(math.cos(math.pi * t) - 1) / 2;
double _power1InOut(double t) =>
    t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
double _power2Out(double t) => 1 - math.pow(1 - t, 3).toDouble();

// ------------------------------------------------------- timeline steps

enum _Prop { sit, lie, groom, puff }

abstract class _Step {
  double get duration;
  void start();
  void apply(double t);
}

class _Wait implements _Step {
  _Wait(this.duration);
  @override
  final double duration;
  @override
  void start() {}
  @override
  void apply(double t) {}
}

class _Props implements _Step {
  _Props(this.cat, this.to, this.duration, [this.ease = _sineInOut]);
  final Cat cat;
  final Map<_Prop, double> to;
  @override
  final double duration;
  final _Ease ease;
  final Map<_Prop, double> _from = {};

  @override
  void start() {
    for (final k in to.keys) {
      _from[k] = cat._get(k);
    }
  }

  @override
  void apply(double t) {
    final e = ease(t.clamp(0.0, 1.0));
    to.forEach((k, v) => cat._set(k, _lerp(_from[k]!, v, e)));
  }
}

/// Moves the cat along a smooth curve through the given points.
class _Move implements _Step {
  _Move(this.cat, this.via, this.duration, this.ease, {this.minX, this.maxX});
  final Cat cat;
  final List<Offset> via;

  /// Keeps the path between these, e.g. inside a margin.
  final double? minX, maxX;
  @override
  final double duration;
  final _Ease ease;
  late List<Offset> _pts;
  late List<double> _len;

  @override
  void start() {
    final p = [cat.p, ...via];
    // Catmull-Rom through the points, sampled evenly.
    _pts = [];
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = p[math.max(i - 1, 0)], p1 = p[i], p2 = p[i + 1];
      final p3 = p[math.min(i + 2, p.length - 1)];
      for (var k = 0; k < 16; k++) {
        final t = k / 16;
        final t2 = t * t, t3 = t2 * t;
        _pts.add(
          (p1 * 2 +
                  (p2 - p0) * t +
                  (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                  (p1 * 3 - p0 - p2 * 3 + p3) * t3) /
              2,
        );
      }
    }
    _pts.add(p.last);
    _len = [0];
    for (var i = 1; i < _pts.length; i++) {
      _len.add(_len.last + (_pts[i] - _pts[i - 1]).distance);
    }
  }

  @override
  void apply(double t) {
    final want = ease(t.clamp(0.0, 1.0)) * _len.last;
    var i = 1;
    while (i < _len.length - 1 && _len[i] < want) {
      i++;
    }
    final a = _len[i - 1], b = _len[i];
    final f = b > a ? ((want - a) / (b - a)).clamp(0.0, 1.0) : 1.0;
    var p = _lerpO(_pts[i - 1], _pts[i], f);
    if (minX != null && maxX != null && minX! <= maxX!) {
      p = Offset(p.dx.clamp(minX!, maxX!), p.dy);
    }
    cat.p = p;
  }
}

class _Call implements _Step {
  _Call(this.fn);
  final void Function() fn;
  @override
  double get duration => 0;
  @override
  void start() {}
  @override
  void apply(double t) {}
}

/// Steps run one after another; [onComplete] runs at the end.
class _Timeline {
  _Timeline(this.steps, {this.onComplete});
  final List<_Step> steps;
  final void Function()? onComplete;
  int _i = 0;

  /// True while on a path (not sitting, washing or waiting).
  bool get moving => _i < steps.length && steps[_i] is _Move;
  double _elapsed = 0;
  bool _started = false;

  /// Moves on by [dt] seconds. True once every step is done.
  bool update(double dt) {
    var left = dt;
    while (_i < steps.length) {
      final step = steps[_i];
      if (!_started) {
        step.start();
        _started = true;
        _elapsed = 0;
      }
      final need = step.duration - _elapsed;
      if (left >= need) {
        step.apply(1);
        if (step is _Call) step.fn();
        left -= need;
        _i++;
        _started = false;
        continue;
      }
      _elapsed += left;
      step.apply(step.duration <= 0 ? 1 : _elapsed / step.duration);
      return false;
    }
    return true;
  }
}

// ----------------------------------------------------------------- cats

class _Leg {
  _Leg(this.pos) : lifted = pos;
  Offset pos;
  bool swing = false;
  Offset lifted;
  double lift = 0;
}

class _Spot {
  const _Spot(this.u, this.pos, this.normal);
  final double u;
  final Offset pos, normal;
}

/// Everything needed to draw one cat this frame.
class CatPose {
  CatPose({
    required this.outline,
    required this.back,
    required this.shadowOffset,
    required this.furAngle,
    required this.furOrigin,
    required this.stripes,
    required this.patchesA,
    required this.patchesB,
    required this.haunch,
    required this.tail,
    required this.tailSpine,
    required this.tailWidth,
    required this.tailRings,
    required this.legs,
    required this.paws,
    required this.head,
    required this.headAngle,
    required this.headScale,
    required this.lids,
    required this.earL,
    required this.earR,
  });

  /// The tail's outline, and the line down its middle.
  final Path outline, back, tail, tailSpine, legs, stripes, tailRings;
  final Offset shadowOffset, furOrigin;
  final double furAngle, tailWidth;
  final List<(Offset, double)> patchesA, patchesB;
  final (Offset, double)? haunch;

  /// Paw centre, size and angle.
  final List<(Offset, double, double, double)> paws;
  final Offset head;
  final double headAngle, headScale, lids, earL, earR;
}

class Cat {
  Cat(this.b, Size size)
    : s = b.size,
      p = _central(size),
      h = _rand(-math.pi, math.pi),
      nextLook = _rand(0.5, 2),
      nextEar = _rand(1, 4),
      phase = _rand(0, 1),
      side = _rng.nextBool() ? 1 : -1,
      seed = _rand(0, 100) {
    resetTrail();
  }

  final CatBreed b;
  final double s;
  Offset p;
  double h;
  List<Offset> trail = [];
  List<_Leg>? _legs;
  double sit = 1, lie = 0, groom = 0, puff = 0, run = 0;
  double look = 0, lookTarget = 0, nextLook;
  final ear = [0.0, 0.0];
  double nextEar, vel = 0, moved = 0, phase;
  String gait = 'sit';
  int side;

  /// Which margin it lives in: 0 left, 1 right.
  int zone = 0;
  final double seed;
  bool fleeing = false, peeking = false;
  _Spot? _spot;
  Offset? _last;

  /// Where it's walking to, so others don't head for the same spot.
  Offset? target;

  /// How long it's been waiting for another cat to get out of the way.
  double _blocked = 0;

  _Timeline? _tl, _wait;
  final List<_Timeline> _fx = [];

  CatPose? pose;

  /// Where a tap counts as touching the cat, and how far out.
  Offset hit = Offset.zero;
  double get hitRadius => 30 * s;

  double _get(_Prop k) => switch (k) {
    _Prop.sit => sit,
    _Prop.lie => lie,
    _Prop.groom => groom,
    _Prop.puff => puff,
  };

  void _set(_Prop k, double v) {
    switch (k) {
      case _Prop.sit:
        sit = v;
      case _Prop.lie:
        lie = v;
      case _Prop.groom:
        groom = v;
      case _Prop.puff:
        puff = v;
    }
  }

  void resetTrail() {
    trail = [];
    final d = Offset(math.cos(h), math.sin(h));
    for (var j = 60; j >= 1; j--) {
      trail.add(p - d * (j * 3.0));
    }
    _legs = null;
  }

  void stop() {
    _tl = null;
    _wait = null;
    _fx.clear();
  }

  void _tween(Map<_Prop, double> to, double duration, [_Ease e = _power2Out]) =>
      _fx.add(_Timeline([_Props(this, to, duration, e)]));

  void later(double seconds, void Function() fn) =>
      _wait = _Timeline([_Wait(seconds), _Call(fn)]);
}

/// A spot in the middle of the page: inside an oval about 60% of its size.
Offset _central(Size size) {
  final a = _rand(0, math.pi * 2), r = math.sqrt(_rng.nextDouble());
  return Offset(
    size.width / 2 + math.cos(a) * r * size.width * 0.3,
    size.height / 2 + math.sin(a) * r * size.height * 0.3,
  );
}

/// A point on the edge of the box, walking clockwise from the top-left
/// corner, with the normal pointing into the box.
(Offset, Offset) _edgePoint(double u, Size size) {
  final w = size.width, h = size.height;
  final per = 2 * (w + h);
  u = ((u % per) + per) % per;
  if (u < w) return (Offset(u, 0), const Offset(0, 1));
  if (u < w + h) return (Offset(w, u - w), const Offset(-1, 0));
  if (u < 2 * w + h) return (Offset(w - (u - w - h), h), const Offset(0, -1));
  return (Offset(0, h - (u - 2 * w - h)), const Offset(1, 0));
}

double _nearestEdgeU(Offset q, Size size) {
  final w = size.width, h = size.height;
  final d = [q.dy, w - q.dx, h - q.dy, q.dx];
  final k = d.indexOf(d.reduce(math.min));
  final x = q.dx.clamp(0.0, w), y = q.dy.clamp(0.0, h);
  return switch (k) {
    0 => x,
    1 => w + y,
    2 => w + h + (w - x),
    _ => 2 * w + h + (h - y),
  };
}

/// The cats on a page: where they go and how they move. Call [tick] every
/// frame; then each cat's [Cat.pose] says how to draw it.
class CatPack {
  CatPack({this.count = 6});

  /// How many cats (one of each breed, up to six).
  final int count;

  /// The width of the text down the middle of the page, which the cats
  /// keep out of: they live in the margins either side. 0 lets them roam
  /// the middle instead.
  double textWidth = 0;

  /// Narrowest a margin gets for cats: on a phone they keep to a strip
  /// along each edge.
  static const _minZone = 70.0;

  /// The left and right of [c]'s margin.
  (double, double) _zone(Cat c) {
    final w = size.width;
    if (textWidth <= 0 || textWidth >= w) return (0, w);
    final gap = (w - textWidth) / 2 - 6;
    return c.zone == 0
        ? (0, math.max(gap, _minZone))
        : (math.min(w - gap, w - _minZone), w);
  }

  /// A spot in [c]'s margin, or the middle of the page when there's no
  /// text to keep clear of.
  Offset _home(Cat c) {
    if (textWidth <= 0) return _central(size);
    final (l, r) = _zone(c);
    final inset = math.min(26.0, (r - l) * 0.3);
    return Offset(
      _rand(l + inset, r - inset),
      _rand(size.height * 0.1, size.height * 0.9),
    );
  }

  final List<Cat> cats = [];
  Size size = Size.zero;
  double _time = 0;

  bool _resting = false;
  bool _shooed = false;
  bool get resting => _resting;
  bool get shooed => _shooed;

  void _ensure(Size newSize) {
    size = newSize;
    if (cats.isNotEmpty || size.isEmpty) return;
    for (final (i, b) in catBreeds.take(count).indexed) {
      final c = Cat(b, size)..zone = i.isEven ? 0 : 1;
      // Start apart from the others.
      var best = _home(c);
      var bestGap = 0.0;
      for (var k = 0; k < 24; k++) {
        final q = _home(c);
        final gap = cats.fold(1e9, (m, o) => math.min(m, (q - o.p).distance));
        if (gap > bestGap) {
          bestGap = gap;
          best = q;
        }
      }
      c
        ..p = best
        ..target = best
        ..resetTrail();
      cats.add(c);
      c.later(_rand(0.4, 2.8), () => _roam(c));
    }
  }

  /// The pause button: cats stop where they are and sit or lie down;
  /// pressed again, they get up and wander off.
  set resting(bool value) {
    if (value == _resting) return;
    _resting = value;
    for (final c in cats) {
      if (c.fleeing || c.peeking) continue;
      if (value) {
        _settle(c);
      } else {
        c.stop();
        c.later(_rand(0.2, 1.6), () => _roam(c));
      }
    }
  }

  /// The shoo button: every cat bolts for the nearest edge, then creeps
  /// back until just its head pokes in. Pressed again, they come back in.
  set shooed(bool value) {
    if (value == _shooed) return;
    _shooed = value;
    for (final (i, c) in cats.indexed) {
      if (value) {
        c.later(i * 0.06, () => _goHide(c));
      } else {
        _callBack(c);
      }
    }
  }

  /// A tap at [at]: the cat there puffs up and bolts off the page; close
  /// neighbours spook too. True if a cat was touched.
  bool tap(Offset at) {
    Cat? hit;
    var best = double.infinity;
    for (final c in cats) {
      final d = (c.hit - at).distance;
      if (d < c.hitRadius && d < best) {
        best = d;
        hit = c;
      }
    }
    final c = hit;
    if (c == null || c.fleeing) return false;
    if (c.peeking) {
      _duck(c, true);
      return true;
    }
    _flee(c, at);
    for (final o in cats) {
      if (o == c || o.fleeing || o.peeking) continue;
      if ((o.p - at).distance < 130 && _rng.nextDouble() < 0.75) {
        o.later(_rand(0.08, 0.35), () => _flee(o, at));
      }
    }
    return true;
  }

  // ------------------------------------------------------------ behaviour

  void _settle(Cat c) {
    c.stop();
    final lie = _rng.nextBool();
    c.gait = lie ? 'lie' : 'sit';
    c._tl = _Timeline([
      _Props(c, {
        _Prop.sit: lie ? 0 : 1,
        _Prop.lie: lie ? 1 : 0,
        _Prop.groom: 0,
      }, 0.9),
    ]);
  }

  void _moveTo(
    Cat c,
    Offset target,
    String gait,
    double speed, [
    void Function()? onDone,
  ]) {
    final d = math.max(1.0, (target - c.p).distance);
    // Leave along the current heading, so turns curve like a real walk.
    final lead = math.min(26 * c.s, d * 0.3);
    final p1 = c.p + Offset(math.cos(c.h), math.sin(c.h)) * lead;
    var bend = _rand(-0.28, 0.28) * d;
    double? minX, maxX;
    if (textWidth > 0 && !c.peeking) {
      // Narrow margins: curve less, and never stray out of them, running
      // away included.
      final (l, r) = _zone(c);
      final most = (r - l) * 0.3;
      if (!c.fleeing) bend = bend.clamp(-most, most);
      // Coming in from the far side of the screen edge is fine.
      minX = c.zone == 0 ? double.negativeInfinity : l + 4;
      maxX = c.zone == 0 ? r - 4 : double.infinity;
    }
    final delta = target - c.p;
    final mid = (p1 + target) / 2 + Offset(-delta.dy / d, delta.dx / d) * bend;
    c.gait = gait;
    c.target = target;
    final steps = <_Step>[];
    if (c.sit > 0.05 || c.groom > 0.05 || c.lie > 0.05) {
      steps.add(
        _Props(
          c,
          {_Prop.sit: 0, _Prop.lie: 0, _Prop.groom: 0},
          c.fleeing
              ? 0.12
              : c.lie > 0.5
              ? 0.7
              : 0.4,
        ),
      );
    }
    steps.add(
      _Move(
        c,
        [p1, mid, target],
        math.max(0.5, d * 1.15 / speed),
        gait == 'walk' ? _sineInOut : _power1InOut,
        minX: minX,
        maxX: maxX,
      ),
    );
    c._tl = _Timeline(steps, onComplete: onDone);
  }

  void _roam(Cat c) {
    if (c.fleeing) return;
    if (_shooed) {
      if (!c.peeking) _goHide(c);
      return;
    }
    if (_resting) {
      _settle(c);
      return;
    }
    final others = cats.where((o) => o != c && !o.fleeing && !o.peeking);
    Offset? best;
    var bestScore = -1.0;
    for (var i = 0; i < 16; i++) {
      final q = _home(c);
      final d = (q - c.p).distance;
      if (d < 50) continue;
      // Away from where the others are and where they're going.
      final near = others.fold(
        1e9,
        (m, o) => math.min(
          m,
          math.min((q - o.p).distance, (q - (o.target ?? o.p)).distance),
        ),
      );
      final score = math.min(near, 170) + math.min(d, 260) * 0.25;
      if (score > bestScore) {
        bestScore = score;
        best = q;
      }
    }
    final r = _rng.nextDouble();
    final gait = r < 0.55
        ? 'walk'
        : r < 0.85
        ? 'trot'
        : 'run';
    _moveTo(c, best ?? _home(c), gait, _speed[gait]! * c.s, () => _rest(c));
  }

  /// After a stretch: look around, sit a while, or sit and wash.
  void _rest(Cat c) {
    if (c.fleeing) return;
    if (_shooed) {
      if (!c.peeking) _goHide(c);
      return;
    }
    if (_resting) {
      _settle(c);
      return;
    }
    final r = _rng.nextDouble();
    final steps = <_Step>[];
    if (r < 0.35) {
      c.gait = 'pause';
      steps.add(_Wait(_rand(0.7, 1.8)));
    } else if (r < 0.75) {
      c.gait = 'sit';
      steps
        ..add(_Props(c, {_Prop.sit: 1}, 0.6))
        ..add(_Wait(_rand(2, 5)));
    } else {
      c.gait = 'groom';
      c.side = _rng.nextBool() ? 1 : -1;
      steps
        ..add(_Props(c, {_Prop.sit: 1}, 0.6))
        ..add(_Props(c, {_Prop.groom: 1}, 0.45))
        ..add(_Wait(_rand(2.2, 4.5)))
        ..add(_Props(c, {_Prop.groom: 0}, 0.4))
        ..add(_Wait(_rand(0.5, 1.5)));
    }
    c._tl = _Timeline(steps, onComplete: () => _roam(c));
  }

  void _flee(Cat c, Offset from) {
    if (c.fleeing) return;
    c.stop();
    c.fleeing = true;
    c._tween({_Prop.puff: 1}, 0.14);
    var dir = c.p - from;
    if (dir.distance < 4) {
      final a = _rand(-math.pi, math.pi);
      dir = Offset(math.cos(a), math.sin(a));
    }
    dir = dir / dir.distance;
    // Out through its own side, never across the text.
    if (textWidth > 0 && (c.zone == 0) == (dir.dx > 0)) {
      dir = Offset(-dir.dx, dir.dy);
    }
    // Run until the tail tip is past the edge too.
    final out = 175 * c.s;
    final w = size.width, h = size.height;
    final tx = dir.dx > 0
        ? (w + out - c.p.dx) / dir.dx
        : dir.dx < 0
        ? (-out - c.p.dx) / dir.dx
        : 1e9;
    final ty = dir.dy > 0
        ? (h + out - c.p.dy) / dir.dy
        : dir.dy < 0
        ? (-out - c.p.dy) / dir.dy
        : 1e9;
    final t = math.min(tx, ty);
    // A spooked cat spins on the spot before it bolts.
    c.h = math.atan2(dir.dy, dir.dx);
    _moveTo(c, c.p + dir * t, 'run', 290 * c.s, () {
      c.later(_rand(4, 9), () => _comeBack(c));
    });
  }

  /// Creeps back in from an edge, then stops to check it's safe.
  void _comeBack(Cat c) {
    if (_shooed) {
      c.fleeing = false;
      c.peeking = true;
      c._spot = _peekSpot(c);
      _peekIn(c);
      return;
    }
    final w = size.width, h = size.height;
    // In from its own side, or the top or bottom of its margin.
    final (l, r) = _zone(c);
    final x = _rand(l + 20, math.max(l + 20, r - 20));
    final start = switch (_rng.nextInt(3)) {
      0 => Offset(x, -70),
      1 => Offset(x, h + 70),
      _ =>
        textWidth > 0
            ? Offset(c.zone == 0 ? -70 : w + 70, _rand(40, h - 40))
            : Offset(_rng.nextBool() ? -70 : w + 70, _rand(40, h - 40)),
    };
    final target = _home(c);
    c
      ..p = start
      ..h = math.atan2(target.dy - start.dy, target.dx - start.dx)
      ..puff = 0
      ..sit = 0
      ..lie = 0
      ..groom = 0
      ..fleeing = false
      ..resetTrail();
    _moveTo(c, target, 'walk', _speed['walk']! * 0.8 * c.s, () {
      c.gait = 'pause';
      c._tl = _Timeline([_Wait(_rand(1.2, 2.4))], onComplete: () => _rest(c));
    });
  }

  /// A free spot on the edge near the cat, away from corners and other
  /// heads.
  _Spot _peekSpot(Cat c, [double? nearU]) {
    final w = size.width, h = size.height;
    final per = 2 * (w + h);
    final others = [
      for (final o in cats)
        if (o != c && o.peeking && o._spot != null) o._spot!.pos,
    ];
    final want = nearU ?? _nearestEdgeU(c.p, size);
    _Spot? best;
    var bestCost = 1e9;
    for (var u = 0.0; u < per; u += 8) {
      final (e, n) = _edgePoint(u, size);
      final corner = [
        e.distance,
        (Offset(w, 0) - e).distance,
        (Offset(0, h) - e).distance,
        (Offset(w, h) - e).distance,
      ].reduce(math.min);
      if (corner < 60) continue;
      if (others.any((o) => (o - e).distance < 78)) continue;
      final du = (u - want).abs();
      final cost = math.min(du, per - du);
      if (cost < bestCost) {
        bestCost = cost;
        best = _Spot(u, e, n);
      }
    }
    if (best != null) return best;
    final (e, n) = _edgePoint(want, size);
    return _Spot(want, e, n);
  }

  void _goHide(Cat c) {
    if (!_shooed) return;
    c.stop();
    c.fleeing = false;
    c.peeking = true;
    final spot = c._spot = _peekSpot(c);
    c._tween({_Prop.puff: 1}, 0.14);
    final exit = spot.pos - spot.normal * (175 * c.s);
    c.h = math.atan2(exit.dy - c.p.dy, exit.dx - c.p.dx);
    _moveTo(c, exit, 'run', 290 * c.s, () {
      c.later(_rand(0.8, 2.6), () => _peekIn(c));
    });
  }

  /// From just past the edge, creep in until the head shows.
  void _peekIn(Cat c) {
    final spot = c._spot;
    if (!_shooed || !c.peeking || spot == null) return;
    c
      ..p = spot.pos - spot.normal * (34 * c.s)
      ..h = math.atan2(spot.normal.dy, spot.normal.dx)
      ..puff = 0
      ..sit = 0
      ..lie = 0
      ..groom = 0
      ..resetTrail();
    _moveTo(
      c,
      spot.pos + spot.normal * (13 * c.s),
      'walk',
      20 * c.s,
      () => _peekIdle(c),
    );
  }

  /// Peering in: looks around, and now and then ducks out of sight.
  void _peekIdle(Cat c) {
    if (!_shooed || !c.peeking) return;
    c.gait = 'peek';
    c._tl = _Timeline(
      [_Wait(_rand(2.5, 6))],
      onComplete: () =>
          _rng.nextDouble() < 0.3 ? _duck(c, false) : _peekIdle(c),
    );
  }

  /// Ducks back out (tapped, or just shy), then peeks again nearby.
  void _duck(Cat c, bool scared) {
    final spot = c._spot;
    if (!c.peeking || spot == null) return;
    c.stop();
    c.h = math.atan2(-spot.normal.dy, -spot.normal.dx);
    if (scared) c._tween({_Prop.puff: 1}, 0.12);
    _moveTo(
      c,
      spot.pos - spot.normal * (60 * c.s),
      scared ? 'run' : 'walk',
      (scared ? 200 : 60) * c.s,
      () {
        c.later(scared ? _rand(1.5, 3.5) : _rand(0.8, 2), () {
          if (scared) {
            c.peeking = false;
            c._spot = _peekSpot(c, spot.u + _rand(-90, 90));
            c.peeking = true;
          }
          _peekIn(c);
        });
      },
    );
  }

  void _callBack(Cat c) {
    c.stop();
    c.peeking = false;
    c._spot = null;
    c.fleeing = false;
    c._tween({_Prop.puff: 0}, 0.3);
    final target = _home(c);
    final off =
        c.p.dx < 0 || c.p.dy < 0 || c.p.dx > size.width || c.p.dy > size.height;
    if (off) c.h = math.atan2(target.dy - c.p.dy, target.dx - c.p.dx);
    c.later(_rand(0.1, 1.2), () {
      _moveTo(c, target, 'walk', _speed['walk']! * c.s, () => _rest(c));
    });
  }

  // --------------------------------------------------------------- frames

  /// Moves everything on by [dt] seconds on a page of [newSize].
  void tick(double dt, Size newSize) {
    _ensure(newSize);
    if (size.isEmpty) return;
    dt = math.min(0.05, dt);
    _time += dt;
    for (final c in cats) {
      _run(c, dt);
      _advance(c, dt);
      c.pose = _draw(c, _time, dt);
    }
  }

  /// Runs the cat's timelines; their callbacks may start new ones.
  void _run(Cat c, double dt) {
    final wait = c._wait;
    if (wait != null && wait.update(dt)) {
      if (c._wait == wait) c._wait = null;
      wait.onComplete?.call();
    }
    final tl = c._tl;
    if (tl != null && tl.moving && _inTheWay(c) != null) {
      // Someone's just ahead: wait for them, and after a while go
      // somewhere else instead.
      c._blocked += dt;
      if (c._blocked > 2.2) {
        c._blocked = 0;
        _roam(c);
      }
    } else {
      c._blocked = 0;
      if (tl != null && tl.update(dt)) {
        if (c._tl == tl) c._tl = null;
        tl.onComplete?.call();
      }
    }
    c._fx.removeWhere((f) => f.update(dt));
  }

  /// Another cat right in front of walking [c], if one is. Of two cats
  /// walking into each other, the first in the pack goes on.
  Cat? _inTheWay(Cat c) {
    if (c.fleeing || c.peeking) return null;
    final ahead = Offset(math.cos(c.h), math.sin(c.h));
    for (final o in cats) {
      if (o == c || o.fleeing || o.peeking) continue;
      final to = o.hit - c.p;
      final d = to.distance;
      if (d > 52 * (c.s + o.s) / 2 || d == 0) continue;
      // In front, not beside or behind.
      if ((to.dx * ahead.dx + to.dy * ahead.dy) / d < 0.35) continue;
      final oMoving = o._tl?.moving ?? false;
      if (oMoving && cats.indexOf(o) > cats.indexOf(c)) continue;
      return o;
    }
    return null;
  }

  void _advance(Cat c, double dt) {
    final last = c.trail.last;
    if ((c.p - last).distance > 0.35) c.trail.add(c.p);
    if (c.trail.length > 420) c.trail.removeRange(0, c.trail.length - 420);
    c.moved = c._last == null ? 0 : (c.p - c._last!).distance;
    // A jump (coming back in from an edge) isn't a step.
    if (c.moved > 60) c.moved = 0;
    c.vel = _lerp(c.vel, c.moved / dt, 0.2);
    c._last = c.p;
    c.run = _lerp(
      c.run,
      c.gait == 'run' && c.vel > 20 ? 1 : 0,
      math.min(1, dt * 6),
    );

    c.nextLook -= dt;
    if (c.nextLook <= 0) {
      final idle = c.vel < 8 || c.gait == 'peek';
      c.lookTarget = idle ? _rand(-0.75, 0.75) : _rand(-0.18, 0.18);
      c.nextLook = idle ? _rand(0.9, 2.6) : _rand(1.5, 3.5);
    }
    c.look = _lerp(c.look, c.lookTarget, math.min(1, dt * 4));
    c.nextEar -= dt;
    if (c.nextEar <= 0) {
      c.ear[_rng.nextBool() ? 0 : 1] = _rand(0.35, 0.7);
      c.nextEar = _rand(1.4, 5);
    }
    final fade = math.pow(0.04, dt).toDouble();
    c.ear[0] *= fade;
    c.ear[1] *= fade;
  }

  /// Points along the trail at the given distances behind the nose.
  List<Offset> _sampleAll(Cat c, List<double> ds) {
    final out = <Offset>[];
    final tr = c.trail;
    var acc = 0.0;
    var i = tr.length - 1, k = 0;
    var pt = c.p;
    var dir = Offset(math.cos(c.h), math.sin(c.h));
    while (k < ds.length) {
      final want = ds[k];
      if (i < 0) {
        out.add(pt - dir * (want - acc));
        k++;
        continue;
      }
      final q = tr[i];
      final sv = pt - q;
      final seg = sv.distance;
      if (seg < 1e-6) {
        i--;
        continue;
      }
      if (acc + seg >= want) {
        out.add(pt - sv * ((want - acc) / seg));
        k++;
      } else {
        acc += seg;
        pt = q;
        dir = sv / seg;
        i--;
      }
    }
    return out;
  }

  CatPose _draw(Cat c, double t, double dt) {
    final s = c.s, f = c.sit, lie = c.lie, puff = c.puff;
    final stretch = 1 + 0.05 * c.run;
    double comp(double d) =>
        (d <= 28 ? d : 28 + (d - 28) * (1 - 0.33 * f - 0.1 * lie)) *
        s *
        stretch;
    final ds = [for (final d in _spine) comp(d)];
    for (var i = 1; i <= 8; i++) {
      ds.add(comp(76) + i * 8 * s * (1 + 0.15 * puff));
    }
    final sp = _sampleAll(c, ds);
    final head = c.p;
    final dir = <Offset>[];
    for (var i = 0; i < sp.length; i++) {
      final a = i == 0 ? head : sp[i - 1];
      final b = i + 1 < sp.length ? sp[i + 1] : sp[i];
      final l = (a - b).distance;
      dir.add(l == 0 ? Offset(math.cos(c.h), math.sin(c.h)) : (a - b) / l);
    }
    c.h = math.atan2(dir[1].dy, dir[1].dx);
    final nrm = [for (final d in dir) Offset(-d.dy, d.dx)];
    final breath = f > 0.5 || lie > 0.5
        ? 1 + (0.022 + 0.012 * lie) * math.sin(t * (2.3 - 0.8 * lie) + c.seed)
        : 1.0;

    // Body outline from neck to tail base.
    final w = <double>[];
    for (var i = 0; i < _halfWidth.length; i++) {
      var m = 1 + 0.14 * puff;
      if (i >= 3 && i <= 5) m *= 1 + 0.12 * lie;
      if (i == 6) m *= 1 + 0.32 * f + 0.15 * lie;
      if (i == 7) m *= 1 + 0.6 * f;
      if (i == 3 || i == 4) m *= breath;
      w.add(_halfWidth[i] * s * m);
    }
    final left = <Offset>[], right = <Offset>[];
    for (var i = 1; i <= 8; i++) {
      left.add(sp[i] + nrm[i] * w[i]);
      right.insert(0, sp[i] - nrm[i] * w[i]);
    }
    final front = sp[1] + dir[1] * (4 * s);
    final outline = _closedPath([front, ...left, ...right]);

    final back = _openPath(sp.sublist(2, 8));
    final stripes = Path();
    if (c.b.stripe != null) {
      stripes.addPath(back, Offset.zero);
      for (final d0 in _tabbyStripes) {
        final q = _at(c, sp, dir, comp(d0));
        final wd = _widthAt(w, d0);
        for (final sd in [1, -1]) {
          final e = q.$1 + q.$3 * (sd * wd * 1.06);
          final m = q.$1 + q.$3 * (sd * wd * 0.55) - q.$2 * (2.4 * s);
          final z = q.$1 + q.$3 * (sd * wd * 0.12) - q.$2 * (0.8 * s);
          stripes
            ..moveTo(e.dx, e.dy)
            ..quadraticBezierTo(m.dx, m.dy, z.dx, z.dy);
        }
      }
    }
    final pa = <(Offset, double)>[], pb = <(Offset, double)>[];
    for (final pt in c.b.patches) {
      final q = _at(c, sp, dir, comp(pt.$1));
      final wd = _widthAt(w, pt.$1);
      final o = (q.$1 + q.$3 * (pt.$2 * wd), pt.$3 * s * (1 + 0.12 * f));
      (pt.$4 ? pa : pb).add(o);
    }
    (Offset, double)? haunch;
    if (c.b.points != null) {
      // Siamese: the coat darkens towards the hindquarters.
      haunch = (sp[7] - dir[7] * (2 * s), 9 * s * (1 + 0.4 * f));
    }

    // Tail: follows the trail with a sway; wraps round the paws when
    // sitting; rests in a loose curve along one side when lying.
    final sway =
        const {
          'walk': (3.2, 3.2),
          'trot': (2.4, 5.0),
          'run': (1.3, 8.0),
          'pause': (4.2, 1.6),
          'sit': (0.0, 1.0),
          'groom': (0.0, 1.0),
          'lie': (0.0, 1.0),
          'peek': (3.0, 1.4),
        }[c.gait] ??
        (3.0, 3.0);
    final hip = sp[6], hu = dir[6], hn = nrm[6];
    final tail = [sp[8]];
    for (var i = 1; i <= 8; i++) {
      final q = sp[8 + i], qn = nrm[8 + i];
      final sw =
          math.sin(t * sway.$2 - i * 0.55 + c.seed) *
          sway.$1 *
          s *
          (i / 8) *
          (1 - puff * 0.8);
      final free = q + qn * sw;
      final th = math.pi - (i / 8) * math.pi * 0.95;
      final r = (12.5 + i * 0.7) * s;
      final flick = i >= 7 ? math.sin(t * 1.7 + c.seed) * 0.18 : 0.0;
      final wrap =
          hip +
          hu * (math.cos(th + flick) * r) +
          hn * (c.side * math.sin(th + flick) * r * 1.05);
      final th2 = math.pi - (i / 8) * math.pi * 0.5;
      final r2 = (15 + i * 1.5) * s;
      final flick2 = i >= 7 ? math.sin(t * 0.9 + c.seed) * 0.1 : 0.0;
      final rest =
          hip +
          hu * (math.cos(th2 + flick2) * r2) +
          hn * (c.side * math.sin(th2 + flick2) * r2 * 0.8);
      tail.add(_lerpO(_lerpO(free, wrap, f), rest, lie));
    }
    final tw = 1 + 0.8 * puff;
    // One shape tapering smoothly from the body to a rounded tip, rather
    // than strokes of two widths.
    double tailHalf(int i) => _lerp(3.3, 1.5, i / 8) * s * tw;
    Offset tailNormal(int i) {
      final a = tail[math.max(i - 1, 0)], b = tail[math.min(i + 1, 8)];
      final d = b - a;
      final l = d.distance;
      return l == 0 ? Offset.zero : Offset(-d.dy / l, d.dx / l);
    }

    final tailLeft = <Offset>[], tailRight = <Offset>[];
    for (var i = 0; i <= 8; i++) {
      final n = tailNormal(i);
      tailLeft.add(tail[i] + n * tailHalf(i));
      tailRight.insert(0, tail[i] - n * tailHalf(i));
    }
    final end = tail[8] - tail[7];
    final tip =
        tail[8] +
        (end.distance == 0 ? Offset.zero : end / end.distance) *
            (tailHalf(8) * 0.9);
    // Starts a little inside the body, so it grows out of the rump.
    final tailShape = _closedPath([...tailLeft, tip, ...tailRight]);
    final rings = Path();
    if (c.b.stripe != null) {
      for (var i = 2; i <= 8; i += 2) {
        final n = tailNormal(i);
        final w = tailHalf(i) * 1.05;
        final p1 = tail[i] + n * w, p2 = tail[i] - n * w;
        rings
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy);
      }
    }

    final (legs, paws) = _legs(c, sp, dir, nrm, dt);

    // Head: follows the neck; looks around; turns back to wash a flank.
    final neck = sp[1];
    final a0 = math.atan2(dir[1].dy, dir[1].dx);
    final turn = c.side * 1.95 * c.groom;
    final lick = c.groom > 0.7 ? math.sin(t * 9) * 0.13 : 0.0;
    final groomPos =
        neck +
        Offset(
          math.cos(a0 + turn * 0.9) * 9 * s,
          math.sin(a0 + turn * 0.9) * 9 * s,
        );
    final hp = _lerpO(sp[0], groomPos, c.groom);
    final headAngle =
        a0 +
        turn +
        lick +
        c.look * (1 - c.groom) * (1 - c.run) * (1 - 0.7 * lie);
    final flat = 38 * puff;

    c.hit = c.peeking ? hp : sp[3];
    return CatPose(
      outline: outline,
      back: back,
      shadowOffset: Offset(2.6 * s, 4.2 * s),
      furAngle: math.atan2(dir[4].dy, dir[4].dx),
      furOrigin: sp[4],
      stripes: stripes,
      patchesA: pa,
      patchesB: pb,
      haunch: haunch,
      tail: tailShape,
      tailSpine: _openPath(tail),
      tailWidth: 4.6 * s * tw,
      tailRings: rings,
      legs: legs,
      paws: paws,
      head: hp,
      headAngle: headAngle,
      headScale: s * (1 - 0.05 * c.groom - 0.04 * lie),
      lids: math.min(0.9, lie * 0.9),
      earL: (flat + c.ear[0] * 40) * math.pi / 180,
      earR: (-flat - c.ear[1] * 40) * math.pi / 180,
    );
  }

  /// Spine point at trail distance [d] (already scaled): position,
  /// direction and normal.
  (Offset, Offset, Offset) _at(
    Cat c,
    List<Offset> sp,
    List<Offset> dir,
    double d,
  ) {
    double sd(int k) {
      final v = _spine[k];
      return (v <= 28 ? v : 28 + (v - 28) * (1 - 0.33 * c.sit - 0.1 * c.lie)) *
          c.s *
          (1 + 0.05 * c.run);
    }

    var i = 1;
    while (i < 8 && sd(i + 1) < d) {
      i++;
    }
    final j = math.min(i + 1, 8);
    final a = sd(i), b = sd(j);
    final fr = b > a ? ((d - a) / (b - a)).clamp(0.0, 1.0) : 0.0;
    var dv = _lerpO(dir[i], dir[j], fr);
    dv = dv / (dv.distance == 0 ? 1 : dv.distance);
    return (_lerpO(sp[i], sp[j], fr), dv, Offset(-dv.dy, dv.dx));
  }

  double _widthAt(List<double> w, double d0) {
    var i = 1;
    while (i < 8 && _spine[i + 1] < d0) {
      i++;
    }
    final j = math.min(i + 1, 8);
    final a = _spine[i], b = _spine[j];
    final fr = b > a ? ((d0 - a) / (b - a)).clamp(0.0, 1.0) : 0.0;
    return _lerp(w[i], w[j], fr);
  }

  /// Paws plant and step: diagonal pairs at a walk or trot, front and
  /// back pairs at a run; tucked under when sitting.
  (Path, List<(Offset, double, double, double)>) _legs(
    Cat c,
    List<Offset> sp,
    List<Offset> dir,
    List<Offset> nrm,
    double dt,
  ) {
    final s = c.s, f = c.sit, lie = c.lie;
    final sh = sp[2], hp = sp[6], ch = sp[3];
    final du = dir[2], dn = nrm[2], hu = dir[6], hn = nrm[6];
    final anchors = [
      sh + dn * (6.2 * s),
      sh - dn * (6.2 * s),
      hp + hn * (6.6 * s * (1 + 0.3 * f)),
      hp - hn * (6.6 * s * (1 + 0.3 * f)),
    ];
    const side = [1.0, -1, 1, -1];
    final targets = <Offset>[];
    for (var i = 0; i < 4; i++) {
      final fore = i < 2;
      final a = anchors[i];
      final u = fore ? du : hu, n = fore ? dn : hn;
      final walk = a + u * ((fore ? 7 : -1) * s) + n * (side[i] * 1.8 * s);
      final sat = fore
          ? ch + du * (8.5 * s) + dn * (side[i] * 3.2 * s)
          : hp + hu * (5 * s) + hn * (side[i] * 11.5 * s);
      // Lying (sphinx): front paws stretched out ahead, hind legs tucked.
      final down = fore
          ? ch + du * (16 * s) + dn * (side[i] * 3.6 * s)
          : hp + hu * (3 * s) + hn * (side[i] * 10.5 * s);
      targets.add(_lerpO(_lerpO(walk, sat, f), down, lie));
    }
    final legs = c._legs ??= [for (final p in targets) _Leg(p)];
    // One gait cycle per stride travelled. Each paw is planted for the
    // duty share of the cycle and swings forward for the rest, so it never
    // slides or trails. Legs: 0 LF, 1 RF, 2 LH, 3 RH.
    final gait = _gaits[c.gait] ?? _gaits['walk']!;
    final stride = gait.stride * s;
    final reach = gait.duty * stride / 2;
    final moving = c.vel > 3 && f < 0.3 && lie < 0.3;
    if (dt > 0 && moving) c.phase = (c.phase + c.moved / stride) % 1;
    final maxReach = (9.5 + 8 * lie) * s;
    final path = Path();
    final paws = <(Offset, double, double, double)>[];
    for (var i = 0; i < 4; i++) {
      final leg = legs[i];
      final a = anchors[i];
      final u = i < 2 ? du : hu, n = i < 2 ? dn : hn;
      if (dt > 0) {
        if (!moving) {
          leg.pos = _lerpO(leg.pos, targets[i], math.min(1, dt * 8));
          leg.swing = false;
          leg.lift = 0;
        } else {
          final plant = a + u * reach + n * (side[i] * 1.6 * s);
          final ph = (c.phase + gait.off[i]) % 1;
          if (ph < gait.duty) {
            if (leg.swing) {
              leg.swing = false;
              leg.pos = plant;
            }
            leg.lift = 0;
          } else {
            if (!leg.swing) {
              leg.swing = true;
              leg.lifted = leg.pos;
            }
            final q = (ph - gait.duty) / (1 - gait.duty);
            final e = q * q * (3 - 2 * q);
            leg.pos = _lerpO(leg.lifted, plant, e);
            leg.lift = math.sin(math.pi * q);
          }
        }
        // A leg is only so long: never let a paw get further than that.
        final l = leg.pos - a;
        if (l.distance > maxReach) leg.pos = a + l / l.distance * maxReach;
      }
      final m = (a + leg.pos) / 2 + n * (side[i] * 1.6 * s);
      path
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(m.dx, m.dy, leg.pos.dx, leg.pos.dy);
      paws.add((
        leg.pos,
        3.5 * s * (1 + 0.18 * leg.lift),
        2.7 * s * (1 + 0.12 * leg.lift),
        math.atan2(u.dy, u.dx),
      ));
    }
    return (path, paws);
  }
}

/// A smooth closed curve through [p] (Catmull-Rom as cubic Béziers).
Path _closedPath(List<Offset> p) {
  final n = p.length;
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = p[(i - 1 + n) % n], p1 = p[i];
    final p2 = p[(i + 1) % n], p3 = p[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}

/// A smooth open curve through [p].
Path _openPath(List<Offset> p) {
  final n = p.length;
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  for (var i = 0; i < n - 1; i++) {
    final p0 = p[math.max(i - 1, 0)], p1 = p[i], p2 = p[i + 1];
    final p3 = p[math.min(i + 2, n - 1)];
    final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}
