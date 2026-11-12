import 'package:flutter/material.dart';

/// Each reading of a book has a colour, for its ribbon on the cover and its
/// passages: pink, purple, crimson, indigo, gold, then round again.
abstract final class Readings {
  static const colours = [
    Color(0xFFF0559E),
    Color(0xFF9B4DF0),
    Color(0xFFDC1E3C),
    Color(0xFF4A4BE0),
    Color(0xFFE6A817),
  ];

  /// Reading [n], counting from 1.
  static Color colour(int n) => colours[(n - 1) % colours.length];

  static const _ordinals = [
    'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', //
    'eighth', 'ninth', 'tenth',
  ];

  /// "first", "second"… then "11th".
  static String ordinal(int n) {
    if (n >= 1 && n <= _ordinals.length) return _ordinals[n - 1];
    final teen = n % 100 >= 11 && n % 100 <= 13;
    final suffix = teen
        ? 'th'
        : switch (n % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return '$n$suffix';
  }

  /// "First reading", "Second reading"…
  static String label(int n) {
    final o = ordinal(n);
    return '${o[0].toUpperCase()}${o.substring(1)} reading';
  }
}

/// A book's cover with a ribbon behind it for each reading: only their
/// notched tails show, hanging [tail] below the cover.
class RibbonedCover extends StatelessWidget {
  const RibbonedCover({
    super.key,
    required this.cover,
    required this.width,
    required this.ribbons,
    this.tail = 14,
  });

  /// The cover itself, [width] wide at book proportions (2:3).
  final Widget cover;
  final double width;
  final int ribbons;
  final double tail;

  static const _tilts = [-0.07, 0.05, -0.025, 0.085, -0.1];

  @override
  Widget build(BuildContext context) {
    final height = width * 1.5;
    final ribbonWidth = (width * 0.09).clamp(5.0, 12.0);
    return SizedBox(
      width: width,
      height: height + tail,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (ribbons > 0)
            Positioned(
              right: width * 0.12,
              top: height * 0.5,
              bottom: 0,
              child: Row(
                // The first reading's ribbon on the right.
                textDirection: TextDirection.rtl,
                spacing: ribbonWidth * 0.4,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < ribbons; i++)
                    Transform.rotate(
                      angle: _tilts[i % _tilts.length],
                      alignment: Alignment.topCenter,
                      child: Ribbon(
                        colour: Readings.colour(i + 1),
                        width: ribbonWidth,
                      ),
                    ),
                ],
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            width: width,
            height: height,
            child: cover,
          ),
        ],
      ),
    );
  }
}

/// A silk ribbon with a notched end, glowing in its colour. As tall as it's
/// given, or [height].
class Ribbon extends StatelessWidget {
  const Ribbon({
    super.key,
    required this.colour,
    required this.width,
    this.height,
  });

  final Color colour;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, height ?? 0),
    painter: _RibbonPainter(colour),
  );
}

class _RibbonPainter extends CustomPainter {
  const _RibbonPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size s) {
    final notch = (s.width * 0.75).clamp(2.0, 8.0);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(s.width / 2, s.height - notch)
      ..lineTo(0, s.height)
      ..close();
    canvas
      ..drawPath(
        path,
        Paint()
          ..color = colour.withValues(alpha: 0.75)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.colour != colour;
}
