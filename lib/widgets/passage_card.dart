import 'package:flutter/material.dart';

import '../models/passage.dart';
import '../theme.dart';

/// A saved passage: the novel, the chapter's number and title, and the
/// passage itself under a large faint opening quote. A long passage scrolls
/// inside the card. A gold ribbon hangs from the top edge, as in a book.
class PassageCard extends StatelessWidget {
  const PassageCard({
    super.key,
    required this.passage,
    required this.onTap,
    this.onLongPress,
  });

  final Passage passage;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const _radius = 18.0;

  /// The passage shows about six lines before it scrolls.
  static const _bodySize = 16.0;
  static const _bodyHeight = 1.7;
  static const _maxBody = _bodySize * _bodyHeight * 6 + 10;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gold = dark ? c.accentLight : c.accent;
    final surface = dark ? const Color(0xFF1F1F1F) : c.surface;
    final number = passage.chapterNumber;

    return Semantics(
      button: true,
      label:
          'Passage from ${passage.novelTitle}, '
          '${number > 0 ? 'chapter $number, ' : ''}${passage.chapterTitle}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(_radius),
          border: dark ? Border.all(color: c.border) : null,
          boxShadow: dark
              ? const [
                  BoxShadow(
                    color: Color(0x8C000000),
                    blurRadius: 34,
                    offset: Offset(0, 14),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x0F1F1E1D),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                  BoxShadow(
                    color: Color(0x1C1F1E1D),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(_radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Where it's from.
                      Padding(
                        padding: const EdgeInsets.only(right: 30),
                        child: Row(
                          children: [
                            Icon(
                              Icons.menu_book_outlined,
                              size: 15,
                              color: c.accentLight,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                passage.novelTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (number > 0) ...[
                            Text(
                              'CHAPTER $number',
                              style: TextStyle(
                                color: gold,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            Container(
                              width: 3,
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: c.faint,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          Expanded(
                            child: Text(
                              passage.chapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: kSerif,
                                fontStyle: FontStyle.italic,
                                color: c.muted,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _Body(passage: passage, quote: gold, text: c.text),
                      // How much it holds.
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.only(top: 12),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: c.border)),
                        ),
                        child: Text(
                          passage.paragraphCount == 1
                              ? '1 paragraph'
                              : '${passage.paragraphCount} paragraphs',
                          style: TextStyle(color: c.faint, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 22,
                  child: _Ribbon(
                    light: c.accentLight,
                    deep: dark ? const Color(0xFF8A6C10) : c.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The passage in the reading font, scrolling past about six lines, with
/// a faint opening quote behind its start and a fade where more follows.
class _Body extends StatelessWidget {
  const _Body({required this.passage, required this.quote, required this.text});

  final Passage passage;
  final Color quote;
  final Color text;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: kSerif,
      fontSize: PassageCard._bodySize,
      height: PassageCard._bodyHeight,
      color: text,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -6,
          top: -30,
          child: IgnorePointer(
            child: Text(
              '“',
              style: TextStyle(
                fontFamily: kSerif,
                fontSize: 84,
                height: 1,
                color: quote.withValues(alpha: 0.2),
              ),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: PassageCard._maxBody),
          child: ShaderMask(
            // Fades the last few pixels, so a passage that goes on shows it.
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.black, Colors.black, Colors.transparent],
              stops: [0, 1 - 26 / rect.height.clamp(27, double.infinity), 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 6, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, p) in passage.paragraphs.indexed)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                      child: Text(p, style: style),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A bookmark ribbon with a notched end.
class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.light, required this.deep});

  final Color light;
  final Color deep;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _Notch(),
      child: Container(
        width: 14,
        height: 30,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [light, deep]),
        ),
      ),
    );
  }
}

class _Notch extends CustomClipper<Path> {
  const _Notch();

  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width / 2, s.height * 0.76)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(_Notch old) => false;
}
