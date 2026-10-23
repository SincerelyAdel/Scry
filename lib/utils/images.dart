import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Image helpers: finding a picture to show for an article.

/// The first real image in feed HTML (an article body or summary), resolved
/// against [base]. Skips tracking pixels, icons and emoji.
String? firstImageInHtml(String? html, {String? base}) {
  if (html == null || !html.contains('<img')) return null;
  final fragment = html_parser.parseFragment(html);
  for (final img in fragment.querySelectorAll('img')) {
    final src = imageSource(img);
    if (src == null || _looksDecorative(img, src)) continue;
    final resolved = resolveUrl(src, base);
    if (resolved != null) return resolved;
  }
  return null;
}

/// The page's preview image from `og:image` / `twitter:image`, falling back
/// to the first sizeable image in an `<article>` or `<main>`. Works on a
/// partial page: the `<head>` is usually enough.
String? pagePreviewImage(String html, {required String pageUrl}) {
  final document = html_parser.parse(html);
  for (final selector in const [
    'meta[property="og:image"]',
    'meta[property="og:image:url"]',
    'meta[name="twitter:image"]',
    'meta[name="twitter:image:src"]',
  ]) {
    final content = document.querySelector(selector)?.attributes['content'];
    final resolved = resolveUrl(content, pageUrl);
    if (resolved != null) return resolved;
  }
  final body =
      document.querySelector('article') ?? document.querySelector('main');
  if (body == null) return null;
  for (final img in body.querySelectorAll('img')) {
    final src = imageSource(img);
    if (src == null || _looksDecorative(img, src)) continue;
    final resolved = resolveUrl(src, pageUrl);
    if (resolved != null) return resolved;
  }
  return null;
}

/// Whether a page prefix already holds what [pagePreviewImage] looks for,
/// so a download can stop early.
bool pagePreviewFound(String partialHtml) {
  final lower = partialHtml.toLowerCase();
  return lower.contains('og:image') ||
      lower.contains('twitter:image') ||
      lower.contains('</head>');
}

/// An `<img>`'s address, including common lazy-loading attributes.
String? imageSource(dom.Element img) {
  for (final attr in const [
    'src',
    'data-src',
    'data-original',
    'data-lazy-src',
  ]) {
    final value = img.attributes[attr]?.trim();
    if (value != null && value.isNotEmpty && !value.startsWith('data:')) {
      return value;
    }
  }
  final srcset = img.attributes['srcset']?.trim();
  if (srcset != null && srcset.isNotEmpty) {
    return srcset.split(',').first.trim().split(' ').first;
  }
  return null;
}

/// Resolves [href] against [base]; only http(s) results are returned.
String? resolveUrl(String? href, String? base) {
  final value = href?.trim();
  if (value == null || value.isEmpty) return null;
  var uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (!uri.hasScheme) {
    final baseUri = base == null ? null : Uri.tryParse(base);
    if (baseUri == null) return null;
    uri = baseUri.resolveUri(uri);
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri.toString();
}

bool _looksDecorative(dom.Element img, String src) {
  final w = int.tryParse(img.attributes['width'] ?? '');
  final h = int.tryParse(img.attributes['height'] ?? '');
  if ((w != null && w < 48) || (h != null && h < 48)) return true;
  final lower = src.toLowerCase();
  return lower.contains('emoji') ||
      lower.contains('pixel') ||
      lower.contains('feedburner') ||
      lower.contains('gravatar') ||
      lower.endsWith('.ico');
}
