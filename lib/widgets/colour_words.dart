import 'package:flutter/material.dart';

import 'veins.dart';

/// Words that name a colour, drawn in a chapter with veins of that colour.
/// Separate from living words, and always on.
class ColourWords {
  ColourWords._() {
    final words = _colours.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    _pattern = RegExp(
      "(?<![A-Za-z'])(${words.map(RegExp.escape).join('|')})(?![A-Za-z'])",
      caseSensitive: false,
    );
  }

  static final instance = ColourWords._();

  late final RegExp _pattern;

  /// Left out because they mostly mean something else: "rose" (stood up),
  /// "tan", "cream", "navy", "lime".
  static const Map<String, VeinPair> _colours = {
    'red': (Color(0xFF9E1B1B), Color(0xFFFF6A5C)),
    'crimson': (Color(0xFF8B0A22), Color(0xFFFF5C74)),
    'scarlet': (Color(0xFFA3150F), Color(0xFFFF7A5C)),
    'vermilion': (Color(0xFFB0260C), Color(0xFFFF8A5C)),
    'ruby': (Color(0xFF7E0F2E), Color(0xFFF25C88)),
    'maroon': (Color(0xFF5E0B1A), Color(0xFFC0475E)),
    'pink': (Color(0xFFB8417A), Color(0xFFFFB0CB)),
    'magenta': (Color(0xFF9E1C78), Color(0xFFFF7AD6)),
    'orange': (Color(0xFFB25500), Color(0xFFFFA347)),
    'amber': (Color(0xFFB86E00), Color(0xFFFFCC66)),
    'saffron': (Color(0xFFB87A00), Color(0xFFFFD45C)),
    'ochre': (Color(0xFF8F5E12), Color(0xFFE0A84A)),
    'gold': (Color(0xFF8A6C10), Color(0xFFF2D77E)),
    'golden': (Color(0xFF8A6C10), Color(0xFFF2D77E)),
    'yellow': (Color(0xFF9E8400), Color(0xFFFFE45C)),
    'green': (Color(0xFF1E6B2E), Color(0xFF6ED67E)),
    'emerald': (Color(0xFF0F6B44), Color(0xFF5CE8A0)),
    'jade': (Color(0xFF2C7A62), Color(0xFF9BEBCB)),
    'teal': (Color(0xFF136B6B), Color(0xFF5CD6D0)),
    'turquoise': (Color(0xFF14807A), Color(0xFF6FE6DB)),
    'cyan': (Color(0xFF0C7490), Color(0xFF6FE0FF)),
    'azure': (Color(0xFF1C6FB8), Color(0xFF8FD3FF)),
    'cerulean': (Color(0xFF1B5E9E), Color(0xFF7CC0F5)),
    'blue': (Color(0xFF1D4A9E), Color(0xFF6F9CFF)),
    'sapphire': (Color(0xFF163C8F), Color(0xFF7FA2FF)),
    'cobalt': (Color(0xFF173A9E), Color(0xFF6A8BFF)),
    'indigo': (Color(0xFF2E2A8A), Color(0xFFA49DFF)),
    'violet': (Color(0xFF5A2BA8), Color(0xFFCDB0FF)),
    'purple': (Color(0xFF5E1F8F), Color(0xFFC08AF0)),
    'lavender': (Color(0xFF6F5A9E), Color(0xFFD9CCFF)),
    'lilac': (Color(0xFF7E5A9E), Color(0xFFE3C8F5)),
    'silver': (Color(0xFF6E7781), Color(0xFFF2F5F8)),
    'silvery': (Color(0xFF6E7781), Color(0xFFF2F5F8)),
    'grey': (Color(0xFF5C6166), Color(0xFFB9BEC4)),
    'gray': (Color(0xFF5C6166), Color(0xFFB9BEC4)),
    'copper': (Color(0xFF8A4A22), Color(0xFFF0A877)),
    'bronze': (Color(0xFF7A5222), Color(0xFFD9A066)),
    'brown': (Color(0xFF5E3A1E), Color(0xFFB07A4E)),
    'russet': (Color(0xFF7A3216), Color(0xFFD27A4E)),
    'ivory': (Color(0xFF9E9474), Color(0xFFFFF8E2)),
    'white': (Color(0xFF9AA0A6), Color(0xFFFFFFFF)),
    'black': (Color(0xFF000000), Color(0xFF6A6A6A)),
    'ebony': (Color(0xFF000000), Color(0xFF5A4E44)),
    'obsidian': (Color(0xFF0A0A12), Color(0xFF5E5A78)),
  };

  /// The colour [word] names, if it names one.
  VeinPair? colourOf(String word) => _colours[word.toLowerCase()];

  final _paints = <(VeinPair, Color, double), Paint>{};

  /// Soft streaks of [pair], in the paragraph's own space, drifted
  /// [drift] pixels along.
  Paint _paint(VeinPair pair, Color ink, double size, double drift) {
    Paint make() => Paint()
      ..shader = Veins.shader(
        Offset.zero,
        ink: ink,
        pairs: [pair],
        lineHeight: size * 1.35,
        drift: drift,
      );
    if (drift != 0) return make();
    return _paints.putIfAbsent((pair, ink, size), make);
  }

  /// Whether [text] has a colour word in it.
  bool any(String text) => _pattern.hasMatch(text);

  /// [text] as spans, colour words veined. Plain text keeps the
  /// paragraph's style.
  List<InlineSpan> spans(
    String text, {
    required Color ink,
    double size = 16,
    double shift = 0,
  }) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      final pair = _colours[m[0]!.toLowerCase()]!;
      spans.add(
        TextSpan(
          text: m[0],
          style: TextStyle(foreground: _paint(pair, ink, size, shift)),
        ),
      );
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }
}

/// A paragraph with its colour words veined and drifting.
class ColourParagraph extends StatefulWidget {
  const ColourParagraph(
    this.text, {
    super.key,
    required this.style,
    required this.ink,
  });

  final String text;
  final TextStyle style;
  final Color ink;

  @override
  State<ColourParagraph> createState() => _ColourParagraphState();
}

class _ColourParagraphState extends State<ColourParagraph> with VeinDrifting {
  late bool _drifts = ColourWords.instance.any(widget.text);

  @override
  bool get drifts => _drifts;

  @override
  void didUpdateWidget(ColourParagraph old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _drifts = ColourWords.instance.any(widget.text);
      driftsChanged();
    }
  }

  @override
  // Drawn on its own, so the streaks keep to the paragraph as it scrolls.
  Widget build(BuildContext context) => RepaintBoundary(
    child: Text.rich(
      TextSpan(
        children: ColourWords.instance.spans(
          widget.text,
          ink: widget.ink,
          size: widget.style.fontSize ?? 16,
          shift: drift,
        ),
      ),
      style: widget.style,
    ),
  );
}
