import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// A card coloured by its tags: the outline runs through the tag colours,
/// and a wash of them is brushed in from the left with a bright stroke
/// passing over, after [delay]. Works for any number of colours; with none
/// it's a plain card. A new [key] replays the sweep.
class TagSweepCard extends StatefulWidget {
  const TagSweepCard({
    super.key,
    required this.colors,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.highlight = false,
    this.dimmed = false,
    this.animate = true,
    this.delay = Duration.zero,
  });

  final List<Color> colors;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Gold-to-purple edge on an untagged card, e.g. when unread.
  final bool highlight;

  /// Softer colours, e.g. for read articles.
  final bool dimmed;

  /// False shows the colours straight away.
  final bool animate;
  final Duration delay;

  @override
  State<TagSweepCard> createState() => _TagSweepCardState();
}

class _TagSweepCardState extends State<TagSweepCard>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  Timer? _start;

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (!widget.animate || reduceMotion || widget.colors.isEmpty) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _start = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    const radius = 16.0;
    final colors = widget.colors;
    final content = InkWell(
      onTap: widget.onTap,
      child: Padding(padding: widget.padding, child: widget.child),
    );

    if (colors.isEmpty && !widget.highlight) {
      return Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }
    if (colors.isEmpty) {
      // Highlighted: an edge from gold into the icon's purple.
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: c.goldViolet(alpha: c.isDark ? 0.55 : 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(radius - 1),
            clipBehavior: Clip.antiAlias,
            child: content,
          ),
        ),
      );
    }

    final edge = widget.dimmed ? 0.4 : 0.75;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            for (final color
                in colors.length == 1 ? [...colors, ...colors] : colors)
              color.withValues(alpha: edge),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(radius - 1),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: _SweepPainter(
              _controller,
              colors,
              strength: widget.dimmed ? 0.55 : 1,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.progress, this.colors, {required this.strength})
    : super(repaint: progress);

  final Animation<double> progress;
  final List<Color> colors;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final full = Offset.zero & size;

    // The wash: the tag colours from the left, fading out to the right.
    final reveal = Curves.easeOutCubic.transform((t / 0.73).clamp(0.0, 1.0));
    if (reveal > 0) {
      final wash = <Color>[];
      final stops = <double>[];
      for (final (i, color) in colors.indexed) {
        wash.add(color.withValues(alpha: 0.22 * strength));
        stops.add(colors.length == 1 ? 0 : 0.6 * i / (colors.length - 1));
      }
      wash
        ..add(colors.last.withValues(alpha: 0.08 * strength))
        ..add(colors.last.withValues(alpha: 0.04 * strength));
      stops
        ..add(colors.length == 1 ? 0.7 : 0.8)
        ..add(1);
      final paint = Paint()
        ..shader = LinearGradient(
          colors: wash,
          stops: stops,
        ).createShader(full);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * reveal, size.height),
        paint,
      );
    }

    // The stroke: a bright band in the tag colours crossing once.
    if (t > 0 && t < 1) {
      final s = Curves.easeOut.transform(t);
      final band = size.width * 0.45;
      final left = -band + s * (size.width + band);
      final rect = Rect.fromLTWH(left, 0, band, size.height);
      final first = colors.first.withValues(alpha: 0.45 * strength);
      final last = colors.last.withValues(alpha: 0.45 * strength);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -0.2),
          end: const Alignment(1, 0.2),
          colors: [
            first.withValues(alpha: 0),
            first,
            Colors.white.withValues(alpha: 0.16 * strength),
            last,
            last.withValues(alpha: 0),
          ],
          stops: const [0, 0.38, 0.5, 0.62, 1],
        ).createShader(rect);
      canvas.drawRect(rect.intersect(full), paint);
    }
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.colors != colors || old.strength != strength;
}
