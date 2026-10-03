import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'header',
  'footer',
  'blockquote',
  'pre',
  'ul',
  'ol',
  'li',
  'table',
  'tr',
  'figure',
  'figcaption',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
};

const _skipTags = {'script', 'style', 'noscript', 'iframe', 'svg'};

/// Converts feed HTML into readable plain text, keeping paragraph breaks
/// and list bullets. Plain text input passes through unchanged apart from
/// entity decoding and whitespace cleanup.
String htmlToPlainText(String? html) {
  if (html == null || html.trim().isEmpty) return '';
  final fragment = html_parser.parseFragment(html);
  final out = _TextSink();
  _walk(fragment.nodes, out, preformatted: false);
  return out
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

void _walk(List<dom.Node> nodes, _TextSink out, {required bool preformatted}) {
  for (final node in nodes) {
    if (node is dom.Text) {
      if (preformatted) {
        out.write(node.text);
        continue;
      }
      final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
      // Avoid a leading space at the start of a line.
      out.write(out.trailingNewlines > 0 ? text.trimLeft() : text);
    } else if (node is dom.Element) {
      final tag = node.localName ?? '';
      if (_skipTags.contains(tag)) continue;
      if (tag == 'br') {
        out.write('\n');
        continue;
      }
      if (tag == 'img') {
        final alt = node.attributes['alt']?.trim();
        if (alt != null && alt.isNotEmpty) out.write('[$alt]');
        continue;
      }
      final isBlock = _blockTags.contains(tag);
      final lineBreaks = (tag == 'li' || tag == 'tr') ? 1 : 2;
      if (isBlock) out.ensureNewlines(lineBreaks);
      if (tag == 'li') out.write('• ');
      _walk(node.nodes, out, preformatted: preformatted || tag == 'pre');
      if (isBlock) out.ensureNewlines(lineBreaks);
    }
  }
}

/// StringBuffer that remembers how many newlines it currently ends with,
/// so block breaks can be added without re-reading the whole buffer.
class _TextSink {
  final _buffer = StringBuffer();

  /// Newlines at the end of the buffer. Starts high so nothing is emitted
  /// before the first text.
  int trailingNewlines = 2;

  void write(String text) {
    if (text.isEmpty) return;
    _buffer.write(text);
    final trimmed = text.replaceFirst(RegExp(r'\n+$'), '');
    final added = text.length - trimmed.length;
    trailingNewlines = trimmed.isEmpty ? trailingNewlines + added : added;
  }

  void ensureNewlines(int count) {
    if (trailingNewlines < count) write('\n' * (count - trailingNewlines));
  }

  @override
  String toString() => _buffer.toString();
}
