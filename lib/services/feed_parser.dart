import 'package:html/parser.dart' as html_parser;
import 'package:rss_dart/dart_rss.dart';
import 'package:rss_dart/domain/media/content.dart';
import 'package:rss_dart/domain/media/media.dart';
import 'package:rss_dart/domain/media/thumbnail.dart';
import 'package:rss_dart/domain/rss1_feed.dart';
import 'package:xml/xml.dart';

import '../utils/date_parser.dart';
import '../utils/html_text.dart';
import '../utils/images.dart';

/// Thrown when a document isn't a feed we can read.
class FeedFormatException implements Exception {
  FeedFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Feed-format-neutral result of parsing, before it becomes database rows.
class ParsedFeed {
  const ParsedFeed({required this.title, this.siteUrl, required this.items});

  final String title;
  final String? siteUrl;
  final List<ParsedItem> items;
}

class ParsedItem {
  const ParsedItem({
    required this.guid,
    required this.title,
    this.author,
    this.url,
    this.pubDate,
    this.summary,
    this.content,
    this.imageUrl,
  });

  final String guid;
  final String title;
  final String? author;
  final String? url;
  final DateTime? pubDate;
  final String? summary;
  final String? content;

  /// A picture for the item: media thumbnail or content, an image
  /// enclosure, or the first image in its body.
  final String? imageUrl;
}

/// Parses RSS 2.0, RSS 1.0 (RDF) and Atom documents.
///
/// [feedUrl] is used to resolve relative links and as a fallback title.
ParsedFeed parseFeed(String body, {required String feedUrl}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(body);
  } on XmlException {
    throw FeedFormatException('Not a valid RSS or Atom feed');
  }
  final base = Uri.tryParse(feedUrl);
  final root = document.rootElement.name.local.toLowerCase();
  return switch (root) {
    'rss' => _fromRss(RssFeed.parse(body), base, feedUrl),
    'feed' => _fromAtom(AtomFeed.parse(body), base, feedUrl),
    'rdf' => _fromRss1(Rss1Feed.parse(body), base, feedUrl),
    _ => throw FeedFormatException('Unsupported feed type <$root>'),
  };
}

/// Finds feed URLs advertised by an HTML page through
/// `<link rel="alternate" type="application/rss+xml" href="...">`, so users
/// can paste a blog's homepage instead of hunting for its feed.
List<String> discoverFeedLinks(String html, {required String pageUrl}) {
  final base = Uri.tryParse(pageUrl);
  final document = html_parser.parse(html);
  final links = <String>[];
  for (final link in document.querySelectorAll('link[rel~="alternate"]')) {
    final type = link.attributes['type']?.toLowerCase() ?? '';
    final href = link.attributes['href'];
    if (href == null || href.isEmpty) continue;
    if (type.contains('rss') || type.contains('atom')) {
      final resolved = _resolve(base, href);
      if (resolved != null && !links.contains(resolved)) links.add(resolved);
    }
  }
  return links;
}

ParsedFeed _fromRss(RssFeed feed, Uri? base, String feedUrl) {
  return ParsedFeed(
    title: _cleanTitle(feed.title) ?? feedUrl,
    siteUrl: _resolve(base, feed.link),
    items: [
      for (final item in feed.items)
        _item(
          base: base,
          id: item.guid,
          title: item.title,
          link: item.link,
          author: item.author ?? item.dc?.creator,
          date: item.pubDate ?? item.dc?.date,
          summary: item.description,
          content: item.content?.value,
          media: [
            ..._mediaImages(item.media),
            if (item.enclosure?.type?.startsWith('image/') ?? false)
              item.enclosure?.url,
          ],
        ),
    ],
  );
}

ParsedFeed _fromRss1(Rss1Feed feed, Uri? base, String feedUrl) {
  return ParsedFeed(
    title: _cleanTitle(feed.title) ?? feedUrl,
    siteUrl: _resolve(base, feed.link),
    items: [
      for (final item in feed.items)
        _item(
          base: base,
          id: null,
          title: item.title,
          link: item.link,
          author: item.dc?.creator,
          date: item.dc?.date,
          summary: item.description,
          content: item.content?.value,
        ),
    ],
  );
}

ParsedFeed _fromAtom(AtomFeed feed, Uri? base, String feedUrl) {
  final feedAuthor = feed.authors.map((a) => a.name).nonNulls.firstOrNull;
  return ParsedFeed(
    title: _cleanTitle(feed.title) ?? feedUrl,
    siteUrl: _resolve(base, _atomAlternate(feed.links)),
    items: [
      for (final item in feed.items)
        _item(
          base: base,
          id: item.id,
          title: item.title,
          link: _atomAlternate(item.links),
          author:
              item.authors.map((a) => a.name).nonNulls.firstOrNull ??
              feedAuthor,
          date: item.published ?? item.updated,
          summary: item.summary,
          content: item.content,
          media: _mediaImages(item.media),
        ),
    ],
  );
}

ParsedItem _item({
  required Uri? base,
  required String? id,
  required String? title,
  required String? link,
  required String? author,
  required String? date,
  required String? summary,
  required String? content,
  List<String?> media = const [],
}) {
  final url = _resolve(base, link);
  final pubDate = parseFeedDate(date);
  final cleanTitle = _cleanTitle(title) ?? '(untitled)';
  return ParsedItem(
    guid: _nonEmpty(id) ?? url ?? '$cleanTitle|${date ?? ''}',
    title: cleanTitle,
    author: _nonEmpty(author),
    url: url,
    pubDate: pubDate,
    summary: _nonEmpty(summary),
    content: _nonEmpty(content),
    imageUrl:
        media
            .map((m) => resolveUrl(m, url ?? base?.toString()))
            .nonNulls
            .firstOrNull ??
        firstImageInHtml(content, base: url ?? base?.toString()) ??
        firstImageInHtml(summary, base: url ?? base?.toString()),
  );
}

/// Image URLs from Media RSS (`media:thumbnail`, `media:content`), loose or
/// inside a `media:group`.
List<String?> _mediaImages(Media? media) {
  if (media == null) return const [];
  bool isImage(Content c) =>
      c.medium == 'image' || (c.type?.startsWith('image/') ?? false);
  return [
    for (final t in media.thumbnails) t.url,
    for (final c in media.contents.where(isImage)) c.url,
    for (final t in media.group?.thumbnails ?? const <Thumbnail>[]) t.url,
    for (final c in media.group?.contents.where(isImage) ?? const <Content>[])
      c.url,
  ];
}

/// Prefers `rel="alternate"` (or no rel) with an HTML type; falls back to
/// the first link with an href.
String? _atomAlternate(List<AtomLink> links) {
  final alternates = links.where(
    (l) => l.href != null && (l.rel == null || l.rel == 'alternate'),
  );
  return alternates
          .where((l) => l.type == null || l.type!.contains('html'))
          .firstOrNull
          ?.href ??
      alternates.firstOrNull?.href ??
      links.where((l) => l.href != null).firstOrNull?.href;
}

/// Titles sometimes carry markup or double-encoded entities.
String? _cleanTitle(String? title) {
  final trimmed = _nonEmpty(title);
  if (trimmed == null) return null;
  if (!trimmed.contains('<') && !trimmed.contains('&')) return trimmed;
  return _nonEmpty(htmlToPlainText(trimmed).replaceAll('\n', ' '));
}

String? _resolve(Uri? base, String? href) {
  final value = _nonEmpty(href);
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (uri.hasScheme || base == null) return uri.toString();
  return base.resolveUri(uri).toString();
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
