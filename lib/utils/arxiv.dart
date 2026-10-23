import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/paper_figure.dart';
import 'images.dart';

/// arXiv helpers. arXiv's feeds only carry the abstract, prefixed with the
/// paper id and announcement type; the figures live in the paper's HTML
/// version at `arxiv.org/html/<id>`.

/// The paper id (e.g. `2610.30344`, version dropped) from an arXiv link or
/// guid, or null when the article isn't an arXiv paper.
String? arxivId(String? url, [String? guid]) {
  for (final value in [url, guid]) {
    if (value == null) continue;
    final match = RegExp(
      r'arxiv\.org[:/](?:abs/|pdf/|html/)?(\d{4}\.\d{4,5})(?:v\d+)?',
      caseSensitive: false,
    ).firstMatch(value);
    if (match != null) return match.group(1);
  }
  return null;
}

/// Where the paper's HTML version and PDF live.
String arxivHtmlUrl(String id) => 'https://arxiv.org/html/$id';
String arxivPdfUrl(String id) => 'https://arxiv.org/pdf/$id';

/// A feed summary split into its parts.
class ArxivSummary {
  const ArxivSummary({this.id, this.type, required this.abstract});

  /// e.g. `2610.30344v1`
  final String? id;

  /// e.g. `New`, `Cross-list`, `Replace`
  final String? type;

  final String abstract;
}

/// Splits arXiv's "arXiv:2610.30344v1 Announce Type: new Abstract: ..."
/// summary prefix from the abstract. Returns null for any other text.
ArxivSummary? parseArxivSummary(String text) {
  final match = RegExp(
    r'^\s*arXiv:(\S+)\s+Announce Type:\s*([\w-]+)\s+Abstract:\s*',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final type = match.group(2)!;
  return ArxivSummary(
    id: match.group(1),
    type: type.isEmpty ? null : type[0].toUpperCase() + type.substring(1),
    abstract: text.substring(match.end).trim(),
  );
}

/// The figures in a paper's HTML version, in order. Tables are left out.
List<PaperFigure> arxivFigures(String html, {required String pageUrl}) {
  final document = html_parser.parse(html);
  final figures = <PaperFigure>[];
  for (final figure in document.querySelectorAll('figure.ltx_figure')) {
    // Sub-figures sit inside their parent figure; the parent covers them.
    if (_hasFigureAncestor(figure)) continue;
    final images = [
      for (final img in figure.querySelectorAll('img'))
        ?resolveUrl(imageSource(img), pageUrl),
    ];
    if (images.isEmpty) continue;
    final caption = figure.children
        .where((e) => e.localName == 'figcaption')
        .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((t) => t.isNotEmpty)
        .join(' ');
    figures.add(PaperFigure(images: images, caption: caption));
  }
  return figures;
}

/// The first figure image in a (possibly partial) paper page, for a
/// thumbnail. Cheaper than [arxivFigures]: no full parse.
String? arxivFirstFigure(String partialHtml, {required String pageUrl}) {
  final match = RegExp(
    r'<img\b[^>]*\bclass="[^"]*ltx_graphics[^"]*"[^>]*>',
    caseSensitive: false,
  ).firstMatch(partialHtml);
  if (match == null) return null;
  final src = RegExp(r'\bsrc="([^"]+)"').firstMatch(match.group(0)!);
  return resolveUrl(src?.group(1), pageUrl);
}

bool _hasFigureAncestor(dom.Element element) {
  for (var p = element.parent; p != null; p = p.parent) {
    if (p.localName == 'figure') return true;
  }
  return false;
}
