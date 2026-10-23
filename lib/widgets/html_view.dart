import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../utils/images.dart';
import 'net_image.dart';

/// Renders article HTML as Flutter widgets in Scry's reading style:
/// paragraphs, headings, links, bold and italic, lists, quotes, code,
/// simple tables, and images (tap to zoom). Scripts, styles, forms and
/// embedded players are left out.
class HtmlView extends StatefulWidget {
  const HtmlView({
    super.key,
    required this.html,
    this.baseUrl,
    required this.fontSize,
  });

  final String html;

  /// For resolving relative links and image addresses.
  final String? baseUrl;

  final double fontSize;

  @override
  State<HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<HtmlView> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final fragment = html_parser.parseFragment(widget.html);
    final builder = _Builder(
      palette: context.palette,
      fontSize: widget.fontSize,
      baseUrl: widget.baseUrl,
      recognizers: _recognizers,
      openLink: (url) =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: builder.blocks(fragment.nodes),
    );
  }
}

const _skip = {
  'script',
  'style',
  'noscript',
  'iframe',
  'svg',
  'form',
  'button',
  'input',
  'select',
  'textarea',
  'video',
  'audio',
  'object',
  'embed',
  'head',
  'title',
  'meta',
  'link',
};

const _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'header',
  'footer',
  'main',
  'aside',
  'nav',
  'blockquote',
  'pre',
  'ul',
  'ol',
  'li',
  'table',
  'figure',
  'figcaption',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'img',
  'picture',
  'dl',
  'dt',
  'dd',
  'details',
  'summary',
  'center',
};

class _Builder {
  _Builder({
    required this.palette,
    required this.fontSize,
    required this.baseUrl,
    required this.recognizers,
    required this.openLink,
  });

  final AppPalette palette;
  final double fontSize;
  final String? baseUrl;
  final List<TapGestureRecognizer> recognizers;
  final void Function(String url) openLink;

  TextStyle get _body => TextStyle(
    fontFamily: kSerif,
    color: palette.text,
    fontSize: fontSize,
    height: 1.6,
  );

  /// Builds the widgets for a run of nodes, as block content.
  List<Widget> blocks(List<dom.Node> nodes, {TextStyle? style}) {
    final out = <Widget>[];
    final para = _Paragraph();
    final base = style ?? _body;

    void flush() {
      final w = para.build(base);
      if (w != null) out.add(_spaced(w));
      para.clear();
    }

    void walk(List<dom.Node> nodes, TextStyle style, String? link) {
      for (final node in nodes) {
        if (node is dom.Text) {
          para.addText(node.text, style, _recognizer(link));
          continue;
        }
        if (node is! dom.Element) continue;
        final tag = node.localName ?? '';
        if (_skip.contains(tag)) continue;
        if (_blockTags.contains(tag)) {
          flush();
          out.addAll(_block(node, base));
          continue;
        }
        switch (tag) {
          case 'br':
            para.addBreak(style);
          case 'a':
            final href = resolveUrl(node.attributes['href'], baseUrl);
            walk(
              node.nodes,
              style.copyWith(
                color: palette.accent,
                decoration: TextDecoration.underline,
                decorationColor: palette.accent.withValues(alpha: 0.5),
              ),
              href ?? link,
            );
          case 'strong' || 'b':
            walk(node.nodes, style.copyWith(fontWeight: FontWeight.w700), link);
          case 'em' || 'i' || 'cite':
            walk(node.nodes, style.copyWith(fontStyle: FontStyle.italic), link);
          case 'code' || 'kbd' || 'samp' || 'tt':
            walk(
              node.nodes,
              style.copyWith(
                fontFamily: 'monospace',
                fontSize: (style.fontSize ?? fontSize) * 0.86,
                backgroundColor: palette.surfaceAlt,
              ),
              link,
            );
          case 'sub' || 'sup' || 'small':
            walk(
              node.nodes,
              style.copyWith(fontSize: (style.fontSize ?? fontSize) * 0.75),
              link,
            );
          case 's' || 'del' || 'strike':
            walk(
              node.nodes,
              style.copyWith(decoration: TextDecoration.lineThrough),
              link,
            );
          case 'mark':
            walk(
              node.nodes,
              style.copyWith(
                backgroundColor: palette.accent.withValues(alpha: 0.25),
              ),
              link,
            );
          default:
            walk(node.nodes, style, link);
        }
      }
    }

    walk(nodes, base, null);
    flush();
    return out;
  }

  List<Widget> _block(dom.Element node, TextStyle base) {
    final tag = node.localName ?? '';
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final scale = const {
          'h1': 1.55,
          'h2': 1.35,
          'h3': 1.2,
          'h4': 1.08,
          'h5': 1.0,
          'h6': 0.95,
        }[tag]!;
        return [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: blocks(
                node.nodes,
                style: base.copyWith(
                  fontSize: fontSize * scale,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ];
      case 'hr':
        return [_spaced(Divider(color: palette.border))];
      case 'img':
        final src = resolveUrl(imageSource(node), baseUrl);
        if (src == null) return const [];
        final alt = node.attributes['alt']?.trim();
        return [
          _spaced(
            Center(
              child: NetImage(
                src,
                fit: BoxFit.contain,
                zoomable: true,
                caption: alt,
              ),
            ),
          ),
        ];
      case 'picture':
        final img = node.querySelector('img');
        return img == null ? const [] : _block(img, base);
      case 'figure':
        return [
          _spaced(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: blocks(node.nodes),
            ),
          ),
        ];
      case 'figcaption':
        return blocks(
          node.nodes,
          style: base.copyWith(
            fontSize: fontSize * 0.82,
            color: palette.muted,
            fontStyle: FontStyle.italic,
            height: 1.45,
          ),
        );
      case 'blockquote':
        return [
          _spaced(
            Container(
              padding: const EdgeInsets.fromLTRB(16, 2, 0, 2),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: palette.accent, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: blocks(
                  node.nodes,
                  style: base.copyWith(color: palette.muted),
                ),
              ),
            ),
          ),
        ];
      case 'pre':
        return [
          _spaced(
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  node.text.replaceAll(RegExp(r'\s+$'), ''),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: palette.text,
                    fontSize: fontSize * 0.78,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ];
      case 'ul' || 'ol':
        final items = node.children.where((e) => e.localName == 'li').toList();
        final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        return [
          _spaced(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: fontSize * 1.6,
                          child: Text(
                            tag == 'ol' ? '${start + i}.' : '•',
                            style: base.copyWith(color: palette.accent),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _tight(
                              blocks(items[i].nodes, style: base),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ];
      case 'table':
        return [_spaced(_table(node, base))];
      default:
        // div, section, li, dd, etc.: just their content.
        return blocks(node.nodes, style: base);
    }
  }

  Widget _table(dom.Element table, TextStyle base) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return const SizedBox.shrink();
    final cellStyle = base.copyWith(fontSize: fontSize * 0.8, height: 1.35);
    final width = rows
        .map((r) => r.children.where(_isCell).length)
        .fold(0, (a, b) => a > b ? a : b);
    if (width == 0) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: palette.border),
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (var i = 0; i < width; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Builder(
                        builder: (_) {
                          final cells = row.children.where(_isCell).toList();
                          if (i >= cells.length) return const SizedBox.shrink();
                          final head = cells[i].localName == 'th';
                          return Text(
                            cells[i].text
                                .replaceAll(RegExp(r'\s+'), ' ')
                                .trim(),
                            style: head
                                ? cellStyle.copyWith(
                                    fontWeight: FontWeight.w700,
                                  )
                                : cellStyle,
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static bool _isCell(dom.Element e) =>
      e.localName == 'td' || e.localName == 'th';

  TapGestureRecognizer? _recognizer(String? url) {
    if (url == null) return null;
    final r = TapGestureRecognizer()..onTap = () => openLink(url);
    recognizers.add(r);
    return r;
  }

  Widget _spaced(Widget child) => Padding(
    padding: EdgeInsets.only(bottom: fontSize * 0.9),
    child: child,
  );

  /// List items don't need paragraph spacing inside them.
  List<Widget> _tight(List<Widget> widgets) => [
    for (final w in widgets)
      w is Padding && w.padding == EdgeInsets.only(bottom: fontSize * 0.9)
          ? w.child ?? const SizedBox.shrink()
          : w,
  ];
}

/// Collects inline text for one paragraph, collapsing whitespace the way a
/// browser does.
class _Paragraph {
  final _spans = <InlineSpan>[];
  bool _lineStart = true;
  bool _pendingSpace = false;

  void addText(String text, TextStyle style, GestureRecognizer? onTap) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return;
    var t = collapsed;
    if (t.startsWith(' ')) {
      if (!_lineStart) _pendingSpace = true;
      t = t.substring(1);
    }
    final trailing = t.endsWith(' ');
    if (trailing) t = t.substring(0, t.length - 1);
    if (t.isEmpty) return;
    // The space between words is its own span, so a link's underline
    // starts at the word.
    if (_pendingSpace) {
      _spans.add(
        TextSpan(
          text: ' ',
          style: style.copyWith(
            decoration: TextDecoration.none,
            backgroundColor: Colors.transparent,
          ),
        ),
      );
    }
    _spans.add(TextSpan(text: t, style: style, recognizer: onTap));
    _lineStart = false;
    _pendingSpace = trailing;
  }

  void addBreak(TextStyle style) {
    _spans.add(TextSpan(text: '\n', style: style));
    _lineStart = true;
    _pendingSpace = false;
  }

  Widget? build(TextStyle base) {
    // Drop trailing line breaks.
    while (_spans.isNotEmpty &&
        _spans.last is TextSpan &&
        (_spans.last as TextSpan).text == '\n') {
      _spans.removeLast();
    }
    if (_spans.isEmpty) return null;
    return Text.rich(TextSpan(style: base, children: List.of(_spans)));
  }

  void clear() {
    _spans.clear();
    _lineStart = true;
    _pendingSpace = false;
  }
}
