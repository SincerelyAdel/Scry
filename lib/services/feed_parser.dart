import 'package:html/parser.dart' as html_parser;
import 'package:rss_dart/dart_rss.dart';
import 'package:rss_dart/domain/rss1_feed.dart';
import 'package:xml/xml.dart';

import '../utils/date_parser.dart';
import '../utils/html_text.dart';

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
  });

  final String guid;
  final String title;
  final String? author;
  final String? url;
  final DateTime? pubDate;
  final String? summary;
  final String? content;
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
  );
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
