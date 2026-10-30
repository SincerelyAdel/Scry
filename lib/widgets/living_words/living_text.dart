import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme.dart';
import 'lexicon.dart';
import 'living_controller.dart';
import 'word_painter.dart';

/// Hands the [LivingWordsController] down to the words in the text.
class LivingWordsScope extends InheritedWidget {
  const LivingWordsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final LivingWordsController controller;

  static LivingWordsController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LivingWordsScope>()
      ?.controller;

  @override
  bool updateShouldNotify(LivingWordsScope old) => old.controller != controller;
}

/// A plain word in a paragraph, by its place in the paragraph's text (a
/// living word counts as one character there).
class _Token {
  const _Token(this.run, this.start, this.end, this.text);

  final int run;
  final int start;
  final int end;
  final String text;
}

/// A plain word caught in the spread: where it sits in the paragraph, and
/// how far it is from the playing word.
class _Caught {
  const _Caught(this.token, this.box, this.distance);

  final _Token token;
  final Rect box;
  final double distance;
}

/// A paragraph whose words can come alive. [id] keeps each living word's
/// identity steady across rebuilds: word k of this paragraph is
/// `id * 1000 + k`.
///
/// While a word plays nearby, the plain words around it within the
/// controller's reach take on its effect too: strongest beside it, fading
/// toward the edge of a circle that widens as it grows.
class LivingParagraph extends StatefulWidget {
  const LivingParagraph({
    super.key,
    required this.id,
    required this.runs,
    required this.style,
  });

  final int id;
  final List<LivingRun> runs;
  final TextStyle style;

  @override
  State<LivingParagraph> createState() => _LivingParagraphState();
}

class _LivingParagraphState extends State<LivingParagraph> {
  static final _word = RegExp(r"[A-Za-z][A-Za-z']*");

  final _text = GlobalKey();
  LivingWordsController? _controller;
  List<_Token> _tokens = const [];
  List<_Caught> _caught = const [];
  LivingEffect? _effect;
  final _glyphs = <int, WordGlyphs>{};

  @override
  void initState() {
    super.initState();
    _tokens = _tokenize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = LivingWordsScope.of(context);
    if (controller != _controller) {
      _controller?.active.removeListener(_onActive);
      _controller = controller;
      controller?.active.addListener(_onActive);
    }
  }

  @override
  void didUpdateWidget(LivingParagraph old) {
    super.didUpdateWidget(old);
    if (old.runs != widget.runs || old.style != widget.style) {
      _tokens = _tokenize();
      _release();
      if (_controller?.active.value != null) _catchLater();
    }
  }

  @override
  void dispose() {
    _controller?.active.removeListener(_onActive);
    _release();
    super.dispose();
  }

  List<_Token> _tokenize() {
    final tokens = <_Token>[];
    var at = 0;
    for (final (k, run) in widget.runs.indexed) {
      if (run.effect != null) {
        at += 1;
        continue;
      }
      for (final m in _word.allMatches(run.text)) {
        tokens.add(_Token(k, at + m.start, at + m.end, m[0]!));
      }
      at += run.text.length;
    }
    return tokens;
  }

  void _release() {
    for (final g in _glyphs.values) {
      g.dispose();
    }
    _glyphs.clear();
    _caught = const [];
    _effect = null;
  }

  void _onActive() {
    if (_controller?.active.value == null) {
      if (_caught.isNotEmpty && mounted) setState(_release);
      return;
    }
    _catchLater();
  }

  /// Once the frame is laid out, finds the words within reach. They and
  /// the playing word scroll together, so this holds until it ends.
  void _catchLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _catch();
    });
  }

  void _catch() {
    final controller = _controller;
    final centre = controller?.centre;
    final effect = controller?.effect.value;
    final box = _paragraph();
    if (controller == null ||
        centre == null ||
        effect == null ||
        box is! RenderParagraph ||
        !box.hasSize) {
      return;
    }
    final here = box.globalToLocal(centre);
    final reach = controller.reach;
    // Nothing of this paragraph within reach.
    final area = Offset.zero & box.size;
    final nearest = Offset(
      here.dx.clamp(area.left, area.right),
      here.dy.clamp(area.top, area.bottom),
    );
    if ((nearest - here).distance > reach) return;
    final caught = <_Caught>[];
    for (final token in _tokens) {
      final boxes = box.getBoxesForSelection(
        TextSelection(baseOffset: token.start, extentOffset: token.end),
      );
      // Skip a word split across lines.
      if (boxes.length != 1) continue;
      final rect = boxes.first.toRect();
      final distance = (rect.center - here).distance;
      if (distance < reach) caught.add(_Caught(token, rect, distance));
    }
    if (caught.isEmpty) return;
    setState(() {
      _caught = caught;
      _effect = effect;
    });
  }

  /// The paragraph's text layout. Inside a selection area, [Text] wraps it
  /// in a mouse region, so it can sit a level or two down.
  RenderParagraph? _paragraph() {
    RenderParagraph? found;
    void visit(RenderObject r) {
      if (found != null) return;
      if (r is RenderParagraph) {
        found = r;
        return;
      }
      r.visitChildren(visit);
    }

    final root = _text.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  WordGlyphs _glyphsFor(_Token token, TextStyle style, Color paper) {
    final g = _glyphs[token.start];
    if (g != null && g.style == style && g.paper == paper) return g;
    g?.dispose();
    return _glyphs[token.start] = WordGlyphs(token.text, style, paper);
  }

  @override
  Widget build(BuildContext context) {
    final caught = {for (final c in _caught) c.token.start};
    final hidden = const TextStyle(color: Colors.transparent);
    final spans = <InlineSpan>[];
    var tokenAt = 0;
    var at = 0;
    for (final (k, run) in widget.runs.indexed) {
      if (run.effect != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: LivingWord(
              key: ValueKey(widget.id * 1000 + k),
              id: widget.id * 1000 + k,
              text: run.text,
              effect: run.effect!,
              style: widget.style,
            ),
          ),
        );
        at += 1;
        continue;
      }
      if (caught.isEmpty) {
        spans.add(TextSpan(text: run.text));
      } else {
        // The caught words go clear; they're drawn again over the top.
        var from = 0;
        while (tokenAt < _tokens.length && _tokens[tokenAt].run == k) {
          final token = _tokens[tokenAt++];
          if (!caught.contains(token.start)) continue;
          final start = token.start - at;
          if (start > from) {
            spans.add(TextSpan(text: run.text.substring(from, start)));
          }
          spans.add(TextSpan(text: token.text, style: hidden));
          from = token.end - at;
        }
        if (from < run.text.length) {
          spans.add(TextSpan(text: run.text.substring(from)));
        }
      }
      // Tokens of this run not reached above (when nothing was caught).
      while (tokenAt < _tokens.length && _tokens[tokenAt].run == k) {
        tokenAt++;
      }
      at += run.text.length;
    }

    final text = Text.rich(
      TextSpan(children: spans),
      key: _text,
      style: widget.style,
    );
    final controller = _controller;
    final effect = _effect;
    if (_caught.isEmpty || controller == null || effect == null) return text;
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final paper = context.palette.bg;
    return CustomPaint(
      foregroundPainter: _SpreadPainter(
        controller: controller,
        effect: effect,
        words: [
          for (final c in _caught) (c, _glyphsFor(c.token, style, paper)),
        ],
      ),
      child: text,
    );
  }
}

/// Draws the caught words of a paragraph with the playing word's effect,
/// each as strongly as its distance allows.
class _SpreadPainter extends CustomPainter {
  _SpreadPainter({
    required this.controller,
    required this.effect,
    required this.words,
  }) : super(repaint: controller.frame);

  final LivingWordsController controller;
  final LivingEffect effect;
  final List<(_Caught, WordGlyphs)> words;

  @override
  void paint(Canvas canvas, Size size) {
    final t = controller.time;
    for (final (caught, g) in words) {
      final at = caught.box.topLeft - g.tight.topLeft;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      paintLivingEffect(
        canvas,
        g,
        effect,
        controller.strengthAt(caught.distance),
        t,
        caught.token.start * 31 + caught.token.run,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SpreadPainter old) =>
      old.words != words || old.effect != effect;
}

/// One living word. It always plays its own effect, as strongly as the
/// controller says; a tap makes it lead the page, or silences it if it
/// leads already.
class LivingWord extends StatefulWidget {
  const LivingWord({
    super.key,
    required this.id,
    required this.text,
    required this.effect,
    required this.style,
  });

  final int id;
  final String text;
  final LivingEffect effect;
  final TextStyle style;

  @override
  State<LivingWord> createState() => _LivingWordState();
}

class _LivingWordState extends State<LivingWord> {
  LivingWordsController? _controller;
  WordGlyphs? _glyphs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = LivingWordsScope.of(context);
    if (controller != _controller) {
      _detach();
      _controller = controller;
      _attach();
    }
  }

  @override
  void didUpdateWidget(LivingWord old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.effect != widget.effect) {
      _detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _detach();
    _glyphs?.dispose();
    super.dispose();
  }

  void _attach() {
    _controller?.register(
      widget.id,
      widget.effect,
      () => mounted ? context.findRenderObject() as RenderBox? : null,
    );
  }

  void _detach() => _controller?.unregister(widget.id);

  WordGlyphs _glyphsFor(TextStyle style, Color paper) {
    final g = _glyphs;
    if (g != null &&
        g.text == widget.text &&
        g.style == style &&
        g.paper == paper) {
      return g;
    }
    g?.dispose();
    return _glyphs = WordGlyphs(widget.text, style, paper);
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final controller = _controller;
    // The paragraph already scales its inline widgets with the text size.
    final text = Text(
      widget.text,
      style: controller == null
          ? style
          : style.copyWith(color: Colors.transparent),
      textScaler: TextScaler.noScaling,
      maxLines: 1,
      softWrap: false,
    );
    if (controller == null) return text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => controller.tap(widget.id),
      child: CustomPaint(
        foregroundPainter: LivingWordPainter(
          glyphs: _glyphsFor(style, context.palette.bg),
          effect: widget.effect,
          controller: controller,
          id: widget.id,
        ),
        child: text,
      ),
    );
  }
}
