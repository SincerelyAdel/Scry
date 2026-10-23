import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'images.dart';

/// Reader mode: pulls an article's text out of its web page, for feeds that
/// only send a teaser or a link.

/// The page's article as HTML (links and images made absolute), or null
/// when no block of text long enough to be an article is found.
String? extractArticle(String html, {required String pageUrl}) {
  final document = html_parser.parse(html);
  final body = document.body;
  if (body == null) return null;
  _strip(body);

  final root = _bestRoot(body);
  if (root == null) return null;
  _dropLeadIn(root);
  _dropCrumbs(root);
  if (countWords(root.text) < minArticleWords) return null;
  _absolutize(root, pageUrl);
  return root.innerHtml;
}

/// Shorter than this, a feed body is a teaser worth replacing with the
/// page's text; an extracted body shorter than this isn't an article.
const minArticleWords = 150;

/// Words in plain text.
int countWords(String text) => RegExp(
  r"[\p{L}\p{N}][\p{L}\p{N}'’.-]*",
  unicode: true,
).allMatches(text).length;

const _junkTags = {
  'script',
  'style',
  'noscript',
  'iframe',
  'form',
  'button',
  'input',
  'select',
  'textarea',
  'nav',
  'aside',
  'footer',
  'header',
  'dialog',
  'svg',
  'template',
};

/// Class or id words of page furniture that may hold paragraphs of its own
/// (comments, related posts), removed whatever is inside.
final _junkName = RegExp(
  r'(^|[\s_-])(comments?|related|recommended|newsletter|subscribe|'
  r'subscription|signup|sidebar|footer|masthead|cookie|consent|popup|modal|'
  r'author-bio)($|[\s_-])',
  caseSensitive: false,
);

/// Class or id words of small furniture. Since article wrappers carry
/// names like "no-share" too, these only go when they hold little prose.
final _crumbName = RegExp(
  r'(^|[\s_-])(share|sharing|social|navbar|nav|menu|breadcrumbs?|promo|'
  r'advert|ads?|sponsor(ed)?|banner|toc|table-of-contents|byline|tags?|'
  r'pagination|skip)($|[\s_-])',
  caseSensitive: false,
);

/// Paragraphs of real prose under an element.
int _proseBlocks(dom.Element e) =>
    e.querySelectorAll('p').where((p) => countWords(p.text) >= 20).length;

void _strip(dom.Element body) {
  final total = countWords(body.text);
  // Server debug dumps and the like: no article quotes this much code.
  for (final pre in body.querySelectorAll('pre').toList()) {
    if (countWords(pre.text) > 3000) pre.remove();
  }
  for (final tag in _junkTags) {
    for (final e in body.querySelectorAll(tag).toList()) {
      // Keep a header that's inside the article itself (e.g. a figure's).
      if (tag == 'header' && e.querySelectorAll('p').length > 2) continue;
      e.remove();
    }
  }
  for (final e in body.querySelectorAll('[class], [id], [role]').toList()) {
    if (e.parent == null) continue; // Already removed with an ancestor.
    final role = e.attributes['role'] ?? '';
    final names = '${e.attributes['class'] ?? ''} ${e.attributes['id'] ?? ''}';
    final hidden =
        e.attributes.containsKey('hidden') ||
        e.attributes['aria-hidden'] == 'true';
    if (hidden ||
        role == 'navigation' ||
        role == 'complementary' ||
        role == 'banner' ||
        (!_isArticleish(e) &&
            // A wrapper named e.g. "has-sidebar" holds the whole page.
            countWords(e.text) < total * 0.4 &&
            (_junkName.hasMatch(names) ||
                (_crumbName.hasMatch(names) && _proseBlocks(e) < 2)))) {
      e.remove();
    }
  }
}

/// Elements that are clearly the article, whatever their class names say.
bool _isArticleish(dom.Element e) =>
    e.localName == 'article' ||
    e.localName == 'main' ||
    e.localName == 'body' ||
    e.attributes['itemprop'] == 'articleBody';

/// The element holding the article: the deepest one that contains most of
/// the page's prose. Each paragraph counts by its words, less the words in
/// its links, so menus and link lists weigh little. A marked-up article
/// body wins outright.
dom.Element? _bestRoot(dom.Element body) {
  final marked = body.querySelector('[itemprop="articleBody"]');
  if (marked != null && countWords(marked.text) >= minArticleWords) {
    return marked;
  }

  final weights = <dom.Element, double>{};
  var total = 0.0;
  for (final p in body.querySelectorAll('p, pre, li, blockquote')) {
    // Nested blocks (a <p> in an <li>) count once, at the outer block.
    if (_hasAncestor(p, const {'p', 'pre', 'li', 'blockquote'}, body)) {
      continue;
    }
    final words = countWords(p.text);
    if (words < 6 && p.localName != 'pre') continue;
    final linkWords = p
        .querySelectorAll('a')
        .fold<int>(0, (n, a) => n + countWords(a.text));
    final weight = words * (1 - (linkWords / words).clamp(0, 1) * 0.9);
    total += weight;
    for (dom.Element? e = p.parent; e != null; e = e.parent) {
      weights[e] = (weights[e] ?? 0) + weight;
      if (identical(e, body)) break;
    }
  }
  if (total == 0) return null;

  // Walk down from the body while one child still holds most of the prose.
  var best = body;
  while (true) {
    dom.Element? next;
    for (final child in best.children) {
      if ((weights[child] ?? 0) >= total * 0.7) next = child;
    }
    if (next == null) return best;
    best = next;
  }
}

bool _hasAncestor(dom.Element e, Set<String> tags, dom.Element stop) {
  for (var p = e.parent; p != null && !identical(p, stop); p = p.parent) {
    if (tags.contains(p.localName)) return true;
  }
  return false;
}

/// Removes the page's own title and whatever comes before it (back links,
/// dates, share and vote buttons); the reader shows the title itself.
void _dropLeadIn(dom.Element root) {
  final h1 = root.querySelector('h1');
  if (h1 == null) return;
  // Only when the title is near the top, not a heading deep in the text.
  final before = _wordsBefore(root, h1);
  if (before > 80) return;
  for (dom.Node? node = h1; node != null && !identical(node, root);) {
    final parent = node.parent;
    if (parent == null) break;
    final siblings = parent.nodes.toList();
    for (final sibling in siblings.take(siblings.indexOf(node))) {
      sibling.remove();
    }
    node = parent;
  }
  h1.remove();
}

int _wordsBefore(dom.Element root, dom.Element target) {
  var words = 0;
  var found = false;
  void walk(dom.Node node) {
    if (found) return;
    if (identical(node, target)) {
      found = true;
      return;
    }
    if (node is dom.Text) words += countWords(node.text);
    for (final child in node.nodes) {
      walk(child);
    }
  }

  walk(root);
  return words;
}

/// Small blocks without prose or pictures: vote counts, "Published on",
/// "Sign in to comment", tag lists and the like.
void _dropCrumbs(dom.Element root) {
  const keep =
      'p, img, picture, figure, pre, table, h2, h3, h4, '
      'blockquote, ul, ol, video, math';
  for (final e in root.querySelectorAll('div, section, span, a, ul').toList()) {
    if (e.parent == null) continue;
    final words = countWords(e.text);
    if (words >= 15) continue;
    // Inline text inside a paragraph is content.
    if (_hasAncestor(e, const {
      'p',
      'li',
      'h2',
      'h3',
      'h4',
      'td',
      'pre',
      'code',
      'blockquote',
    }, root)) {
      continue;
    }
    if (e.localName != 'ul' && e.querySelector(keep) != null) continue;
    if (e.localName == 'ul') {
      // A short list of links is navigation; a short list of text is not.
      final links = e.querySelectorAll('a').length;
      if (links == 0) continue;
    }
    e.remove();
  }
}

void _absolutize(dom.Element root, String pageUrl) {
  for (final a in root.querySelectorAll('a[href]')) {
    final href = a.attributes['href']!;
    if (href.startsWith('#')) {
      a.attributes.remove('href');
      continue;
    }
    final resolved = resolveUrl(href, pageUrl);
    if (resolved == null) {
      a.attributes.remove('href');
    } else {
      a.attributes['href'] = resolved;
    }
  }
  for (final img in root.querySelectorAll('img')) {
    final resolved = resolveUrl(imageSource(img), pageUrl);
    if (resolved == null) {
      img.remove();
    } else {
      img.attributes
        ..remove('srcset')
        ..remove('data-src')
        ..['src'] = resolved;
    }
  }
}
