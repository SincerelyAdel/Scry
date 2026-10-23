import 'package:flutter_test/flutter_test.dart';
import 'package:snippefy/services/feed_parser.dart';

import 'support/fixtures.dart';

void main() {
  group('parseFeed', () {
    test('RSS 2.0', () {
      final feed = parseFeed(rss2Feed, feedUrl: 'https://example.com/feed');
      expect(feed.title, 'Example & Co Blog');
      expect(feed.siteUrl, 'https://example.com/');
      expect(feed.items, hasLength(2));

      final second = feed.items[0];
      expect(second.title, 'Second post');
      expect(second.guid, 'post-2');
      // Relative links resolve against the feed URL.
      expect(second.url, 'https://example.com/posts/2');
      expect(second.author, 'Ada');
      expect(second.pubDate, DateTime.utc(2025, 6, 10, 14));
      expect(second.summary, '<p>Short summary</p>');
      expect(second.content, contains('<b>body</b>'));

      final first = feed.items[1];
      // No guid: falls back to the link.
      expect(first.guid, 'https://example.com/posts/1');
      expect(first.content, isNull);
    });

    test('Atom', () {
      final feed = parseFeed(
        atomFeed,
        feedUrl: 'https://atom.example.org/feed.xml',
      );
      expect(feed.title, 'Atom Example');
      expect(feed.siteUrl, 'https://atom.example.org/');
      expect(feed.items, hasLength(2));

      final entry = feed.items[0];
      expect(entry.title, 'Entry & more');
      expect(entry.guid, 'tag:atom.example.org,2025:1');
      expect(entry.url, 'https://atom.example.org/1');
      // Inherits the feed-level author.
      expect(entry.author, 'Feed Author');
      expect(entry.pubDate, DateTime.utc(2025, 6, 11, 12));
      expect(entry.content, '<p>Entry content</p>');

      final updatedOnly = feed.items[1];
      expect(updatedOnly.author, 'Entry Author');
      expect(updatedOnly.pubDate, DateTime.utc(2025, 6, 10, 8, 30));
    });

    test('RSS 1.0 (RDF)', () {
      final feed = parseFeed(rdfFeed, feedUrl: 'https://rdf.example.net/rss');
      expect(feed.title, 'RDF Example');
      expect(feed.items.single.title, 'RDF item');
      expect(feed.items.single.author, 'Grace');
      expect(feed.items.single.guid, 'https://rdf.example.net/a');
      expect(feed.items.single.pubDate, DateTime.utc(2025, 6, 8, 10));
    });

    test('rejects HTML and other XML', () {
      expect(
        () => parseFeed(htmlPageWithFeedLink, feedUrl: 'https://x.com'),
        throwsA(isA<FeedFormatException>()),
      );
      expect(
        () => parseFeed('<svg></svg>', feedUrl: 'https://x.com'),
        throwsA(isA<FeedFormatException>()),
      );
    });
  });

  test('discoverFeedLinks finds alternate RSS/Atom links', () {
    expect(
      discoverFeedLinks(htmlPageWithFeedLink, pageUrl: 'https://example.com/'),
      ['https://example.com/feed.xml'],
    );
    expect(
      discoverFeedLinks(htmlPageWithoutFeed, pageUrl: 'https://example.com/'),
      isEmpty,
    );
  });
}
