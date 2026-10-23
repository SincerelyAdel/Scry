import 'package:flutter_test/flutter_test.dart';
import 'package:scry/data/app_database.dart';
import 'package:scry/data/feed_repository.dart';
import 'package:scry/models/article_sort.dart';
import 'package:scry/models/feed.dart';
import 'package:scry/services/feed_fetcher.dart';
import 'package:scry/services/feed_parser.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

void main() {
  late AppDatabase db;
  late FakeFetcher fetcher;
  late FeedRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    fetcher = FakeFetcher();
    repo = FeedRepository(db, fetcher);
  });

  tearDown(() => db.close());

  test('normalizeUrl adds a scheme and rejects junk', () {
    expect(
      FeedRepository.normalizeUrl('  example.com/feed '),
      'https://example.com/feed',
    );
    expect(
      FeedRepository.normalizeUrl('http://example.com/rss'),
      'http://example.com/rss',
    );
    expect(() => FeedRepository.normalizeUrl(''), throwsFormatException);
    expect(
      () => FeedRepository.normalizeUrl('ftp://example.com'),
      throwsFormatException,
    );
  });

  test('addFeed stores the feed and its articles', () async {
    fetcher.responses['https://example.com/feed'] = rss2Feed;

    final feed = await repo.addFeed('example.com/feed');

    expect(feed.title, 'Example & Co Blog');
    expect(feed.articleCount, 2);
    expect(feed.unreadCount, 2);
    expect(feed.syncStatus, SyncStatus.ok);
    expect(feed.lastUpdated, isNotNull);

    final articles = await repo.listArticles();
    expect(articles.map((a) => a.title), ['Second post', 'First post']);
    expect(articles.first.feedTitle, 'Example & Co Blog');
    // List rows skip the heavy columns...
    expect(articles.first.content, isNull);
    // ...which the detail query includes.
    final full = await repo.getArticle(articles.first.id!);
    expect(full!.content, contains('<b>body</b>'));
    expect(full.summary, '<p>Short summary</p>');
  });

  test('addFeed rejects duplicates, including after redirects', () async {
    fetcher.responses['https://example.com/feed'] = rss2Feed;
    await repo.addFeed('https://example.com/feed');

    expect(
      () => repo.addFeed('https://example.com/feed'),
      throwsA(isA<DuplicateFeedException>()),
    );

    fetcher.redirects['https://example.com/old'] = 'https://example.com/feed';
    expect(
      () => repo.addFeed('https://example.com/old'),
      throwsA(isA<DuplicateFeedException>()),
    );
  });

  test('addFeed discovers the feed from a web page', () async {
    fetcher.responses['https://example.com/'] = htmlPageWithFeedLink;
    fetcher.responses['https://example.com/feed.xml'] = rss2Feed;

    final feed = await repo.addFeed('https://example.com/');

    expect(feed.url, 'https://example.com/feed.xml');
    expect(feed.articleCount, 2);
  });

  test('addFeed surfaces useful errors', () async {
    fetcher.responses['https://example.com/'] = htmlPageWithoutFeed;
    await expectLater(
      repo.addFeed('https://example.com/'),
      throwsA(isA<FeedFormatException>()),
    );
    await expectLater(
      repo.addFeed('https://missing.example.com/'),
      throwsA(isA<FetchException>()),
    );
    expect(await repo.listFeeds(), isEmpty);
  });

  test('refresh adds new articles and keeps read state', () async {
    const url = 'https://example.com/a';
    fetcher.responses[url] = rssWithItems('a', 3);
    final feed = await repo.addFeed(url);

    final first = (await repo.listArticles()).first;
    await repo.setRead(first.id!, true);

    // Same three items plus two new ones.
    fetcher.responses[url] = rssWithItems('a', 5);
    final result = await repo.refreshFeed(feed);

    expect(result.ok, isTrue);
    expect(result.newArticles, 2);
    final articles = await repo.listArticles();
    expect(articles, hasLength(5));
    expect(articles.firstWhere((a) => a.id == first.id).isRead, isTrue);
    expect(await repo.unreadCount(), 4);
  });

  test('a failed refresh records the error and keeps articles', () async {
    const url = 'https://example.com/a';
    fetcher.responses[url] = rssWithItems('a', 2);
    final feed = await repo.addFeed(url);

    fetcher.responses.remove(url);
    final result = await repo.refreshFeed(feed);

    expect(result.ok, isFalse);
    final stored = (await repo.listFeeds()).single;
    expect(stored.syncStatus, SyncStatus.error);
    expect(stored.lastError, contains('404'));
    expect(stored.lastUpdated, feed.lastUpdated);
    expect(stored.articleCount, 2);
  });

  test('refreshAll handles several feeds and reports each', () async {
    for (final name in ['a', 'b', 'c', 'd', 'e']) {
      fetcher.responses['https://example.com/$name'] = rssWithItems(name, 2);
      await repo.addFeed('https://example.com/$name');
    }
    fetcher.responses['https://example.com/c'] = 'not xml';

    final results = await repo.refreshAll();

    expect(results, hasLength(5));
    expect(results.where((r) => !r.ok).single.feed.title, 'c');
    expect(await repo.listArticles(), hasLength(10));
  });

  test(
    'deleted articles stay hidden after refresh and can be restored',
    () async {
      const url = 'https://example.com/a';
      fetcher.responses[url] = rssWithItems('a', 3);
      final feed = await repo.addFeed(url);
      final victim = (await repo.listArticles()).first;

      await repo.deleteArticle(victim.id!);
      await repo.refreshFeed(feed);

      var articles = await repo.listArticles();
      expect(articles, hasLength(2));
      expect(articles.any((a) => a.id == victim.id), isFalse);
      expect((await repo.listFeeds()).single.articleCount, 2);

      await repo.restoreArticle(victim.id!);
      articles = await repo.listArticles();
      expect(articles, hasLength(3));
    },
  );

  test('deleting a feed removes its articles', () async {
    fetcher.responses['https://example.com/a'] = rssWithItems('a', 3);
    fetcher.responses['https://example.com/b'] = rssWithItems('b', 2);
    final a = await repo.addFeed('https://example.com/a');
    await repo.addFeed('https://example.com/b');

    await repo.deleteFeed(a.id!);

    final articles = await repo.listArticles();
    expect(articles, hasLength(2));
    expect(articles.every((x) => x.feedTitle == 'b'), isTrue);
  });

  group('listArticles', () {
    setUp(() async {
      // Feed "b" has the newest items, feed "a" the oldest.
      fetcher.responses['https://example.com/a'] = rssWithItems('a', 3);
      fetcher.responses['https://example.com/b'] = rssWithItems(
        'b',
        3,
        startId: 10,
      );
      await repo.addFeed('https://example.com/a');
      await repo.addFeed('https://example.com/b');
    });

    test('newest first merges feeds by date', () async {
      final titles = (await repo.listArticles()).map((a) => a.title);
      expect(titles, [
        'b item 12',
        'b item 11',
        'b item 10',
        'a item 2',
        'a item 1',
        'a item 0',
      ]);
    });

    test('by feed groups alphabetically, newest first within', () async {
      final titles = (await repo.listArticles(
        sort: ArticleSort.byFeed,
      )).map((a) => a.title);
      expect(titles, [
        'a item 2',
        'a item 1',
        'a item 0',
        'b item 12',
        'b item 11',
        'b item 10',
      ]);
    });

    test('unread first, then unread only', () async {
      final all = await repo.listArticles();
      await repo.setRead(all[0].id!, true); // b item 12
      await repo.setRead(all[1].id!, true); // b item 11

      final unreadFirst = (await repo.listArticles(
        sort: ArticleSort.unreadFirst,
      )).map((a) => a.title);
      expect(unreadFirst.take(4), [
        'b item 10',
        'a item 2',
        'a item 1',
        'a item 0',
      ]);

      final unreadOnly = await repo.listArticles(unreadOnly: true);
      expect(unreadOnly, hasLength(4));
    });

    test('paging and per-feed filtering', () async {
      final page1 = await repo.listArticles(limit: 4);
      final page2 = await repo.listArticles(limit: 4, offset: 4);
      expect(page1, hasLength(4));
      expect(page2.map((a) => a.title), ['a item 1', 'a item 0']);

      final feedA = (await repo.listFeeds()).firstWhere((f) => f.title == 'a');
      final onlyA = await repo.listArticles(feedId: feedA.id);
      expect(onlyA.every((a) => a.feedId == feedA.id), isTrue);
    });

    test('markAllRead for one feed or everything', () async {
      final feedA = (await repo.listFeeds()).firstWhere((f) => f.title == 'a');
      await repo.markAllRead(feedId: feedA.id);
      expect(await repo.unreadCount(), 3);
      await repo.markAllRead();
      expect(await repo.unreadCount(), 0);
    });
  });
}
