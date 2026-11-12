import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';

/// One colour of streak: its deep shade and its light one.
typedef VeinPair = (Color deep, Color light);

/// Colours a title's veins can take, and how often.
class VeinPalette {
  const VeinPalette(this.name, this.weight, this.pairs);

  final String name;

  /// Out of the weights of every palette.
  final int weight;
  final List<VeinPair> pairs;
}

/// Ink with thin coloured streaks running through it at a slant, like a
/// vein in marble: the effect on character names, in several colours.
abstract final class Veins {
  static final _random = math.Random();

  /// Pink, gold and purple about half the time; the rest share the others.
  static const palettes = [
    VeinPalette('Pink, gold and purple', 50, [
      (Color(0xFFB8417A), Color(0xFFF3A6CC)),
      (Color(0xFF9C7A12), Color(0xFFF2D77E)),
      (Color(0xFF6A2FB8), Color(0xFFC59BF5)),
    ]),
    VeinPalette('Rose and copper', 10, [
      (Color(0xFFA33F55), Color(0xFFF2A3B3)),
      (Color(0xFF9A4A1E), Color(0xFFF0A877)),
    ]),
    VeinPalette('Sea glass', 10, [
      (Color(0xFF1F7A74), Color(0xFF8FE0D4)),
      (Color(0xFF7C8B99), Color(0xFFE6EDF3)),
      (Color(0xFF244E9E), Color(0xFF7FA6F2)),
    ]),
    VeinPalette('Emerald and gold', 10, [
      (Color(0xFF146B43), Color(0xFF6EDDA2)),
      (Color(0xFF8A6C10), Color(0xFFF2D77E)),
    ]),
    VeinPalette('Midnight', 10, [
      (Color(0xFF33369E), Color(0xFF9A9EF5)),
      (Color(0xFF7C858F), Color(0xFFE3E8EE)),
      (Color(0xFF5A2BA8), Color(0xFFC1A2F7)),
    ]),
    VeinPalette('Ember', 10, [
      (Color(0xFF9B2335), Color(0xFFF08A7C)),
      (Color(0xFFB86E00), Color(0xFFFFD27A)),
    ]),
  ];

  /// A palette, by weight.
  static VeinPalette pick([math.Random? random]) {
    final total = palettes.fold(0, (sum, p) => sum + p.weight);
    var r = (random ?? _random).nextInt(total);
    for (final p in palettes) {
      if ((r -= p.weight) < 0) return p;
    }
    return palettes.first;
  }

  /// The ink between the streaks: near black on the light theme; on the
  /// dark one the page's own text, so it still reads.
  static Color ink(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? context.palette.text
      : const Color(0xFF161412);

  /// How soft the streaks' edges are, from 0 (sharp) to 1.
  static const softness = 0.6;

  /// How fast the streaks drift along their slant, in pixels a second.
  static const speed = 7.0;

  /// The streaks along one half of the pattern: where, which colour pair
  /// (counted on from the half's first), light or deep, and half-width.
  static const _streaks = [
    (.33, 0, false, .05),
    (.36, 0, true, .05),
    (.63, 1, false, .03),
    (.87, 2, true, .03),
  ];

  static final _ramps =
      <(Color, List<VeinPair>, int), (List<Color>, List<double>)>{};

  /// The colours along one full, mirrored period of the pattern, each
  /// streak blurred into the ink around it. Each half takes the next
  /// colours, starting from [lead].
  static (List<Color>, List<double>) _ramp(
    Color ink,
    List<VeinPair> pairs,
    int lead,
  ) => _ramps.putIfAbsent((ink, pairs, lead), () {
    final n = pairs.length;
    final streaks = [
      for (final (at, k, light, w) in _streaks) ...[
        (at / 2, pairs[(lead + k) % n], light, w / 2),
        ((2 - at) / 2, pairs[(lead + 1 + k) % n], light, w / 2),
      ],
    ];
    const samples = 96;
    final colours = <Color>[];
    final stops = <double>[];
    for (var i = 0; i <= samples; i++) {
      final u = i / samples;
      var sum = 0.0;
      var r = 0.0, g = 0.0, b = 0.0;
      for (final (at, pair, light, w) in streaks) {
        var d = (u - at).abs();
        d = math.min(d, 1 - d);
        final s = w * (0.55 + softness * 2.6);
        final a = math.exp(-(d * d) / (2 * s * s)) * (1 - softness * 0.25);
        final c = light ? pair.$2 : pair.$1;
        sum += a;
        r += a * c.r;
        g += a * c.g;
        b += a * c.b;
      }
      final a = math.min(1.0, sum);
      colours.add(
        sum == 0
            ? ink
            : Color.from(
                alpha: 1,
                red: ink.r * (1 - a) + r / sum * a,
                green: ink.g * (1 - a) + g / sum * a,
                blue: ink.b * (1 - a) + b / sum * a,
              ),
      );
      stops.add(u);
    }
    return (colours, stops);
  });

  /// Soft streaks at a slant from [origin]: along a line to 70 right of and
  /// 28 below the bottom-left of a [lineHeight] tall line, then mirrored, as
  /// on character names. [phase], from 0 to 1, and [drift], in pixels, move
  /// the streaks along.
  static Shader shader(
    Offset origin, {
    required Color ink,
    required List<VeinPair> pairs,
    required double lineHeight,
    int lead = 0,
    double phase = 0,
    double drift = 0,
  }) {
    final (colours, stops) = _ramp(ink, pairs, lead);
    final period = Offset(70, lineHeight + 28) * 2;
    final start = origin + period * ((phase + drift / period.distance) % 1);
    return ui.Gradient.linear(
      start,
      start + period,
      colours,
      stops,
      TileMode.repeated,
    );
  }
}

/// How far the streaks have drifted, in pixels: one clock for every veined
/// word in the app, so they all move at the same pace. It runs only while
/// something veined is on screen, and stays still when the system asks for
/// less motion.
class DriftClock extends ValueNotifier<double> {
  DriftClock._() : super(0);

  static final instance = DriftClock._();

  /// Off in tests, so screens settle.
  static bool enabled = true;

  late final _ticker = Ticker(_tick, debugLabel: 'veins');
  Duration _last = Duration.zero;
  double _from = 0;
  int _users = 0;

  void _tick(Duration elapsed) {
    // About 30 a second is plenty at this pace.
    if (elapsed - _last < const Duration(milliseconds: 33)) return;
    _last = elapsed;
    value = _from + elapsed.inMicroseconds / 1e6 * Veins.speed;
  }

  void join() {
    _users++;
    _sync();
  }

  void leave() {
    _users--;
    _sync();
  }

  void _sync() {
    final still = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    final go = _users > 0 && enabled && !still;
    if (go && !_ticker.isActive) {
      _from = value;
      _last = Duration.zero;
      _ticker.start();
    } else if (!go && _ticker.isActive) {
      _ticker.stop();
    }
  }
}

/// Redraws veined text as the streaks drift, while it's on screen.
mixin VeinDrifting<T extends StatefulWidget> on State<T> {
  bool _joined = false;
  double _screen = 0;

  /// Whether this has anything veined in it. Call [driftsChanged] when
  /// that changes.
  bool get drifts => true;

  /// How far the streaks have drifted.
  double get drift => DriftClock.instance.value;

  @override
  void initState() {
    super.initState();
    driftsChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screen = MediaQuery.sizeOf(context).height;
  }

  /// Follows the clock while this drifts, and lets go of it otherwise.
  void driftsChanged() {
    final clock = DriftClock.instance;
    if (drifts && !_joined) {
      clock
        ..join()
        ..addListener(_onDrift);
      _joined = true;
    } else if (!drifts && _joined) {
      _part();
    }
  }

  void _part() {
    if (!_joined) return;
    DriftClock.instance
      ..removeListener(_onDrift)
      ..leave();
    _joined = false;
  }

  void _onDrift() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top > _screen || top + box.size.height < 0) return;
    setState(() {});
  }

  @override
  void dispose() {
    _part();
    super.dispose();
  }
}

/// Text drawn with veins. Without [pairs] it takes a palette at random
/// each time it's shown, and starts the streaks somewhere new.
class VeinText extends StatefulWidget {
  const VeinText(
    this.text, {
    super.key,
    required this.style,
    this.pairs,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final List<VeinPair>? pairs;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  State<VeinText> createState() => _VeinTextState();
}

class _VeinTextState extends State<VeinText> with VeinDrifting {
  static final _random = math.Random();

  late final _palette = Veins.pick(_random);
  late final _lead = _random.nextInt(3);
  late final _phase = _random.nextDouble();

  @override
  Widget build(BuildContext context) {
    final ink = Veins.ink(context);
    final size = widget.style.fontSize ?? 14;
    final drift = this.drift;
    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback: (rect) => Veins.shader(
          rect.topLeft,
          ink: ink,
          pairs: widget.pairs ?? _palette.pairs,
          lineHeight: size * 1.35,
          lead: _lead,
          phase: _phase,
          drift: drift,
        ),
        blendMode: BlendMode.srcIn,
        child: Text(
          widget.text,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          textAlign: widget.textAlign,
          style: widget.style.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
