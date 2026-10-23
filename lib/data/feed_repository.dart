import 'dart:async';
import 'dart:typed_data';

import '../models/article.dart';
import '../models/article_sort.dart';
import '../models/feed.dart';
import '../services/feed_fetcher.dart';
import '../services/feed_parser.dart';
import 'app_database.dart';

class DuplicateFeedException implements Exception {
  DuplicateFeedException(this.feed);

  final Feed feed;

  @override
  String toString() => 'Already subscribed to "${feed.title}"';
}

/// Result of refreshing one feed.
class RefreshResult {
  const RefreshResult({required this.feed, this.newArticles = 0, this.error});

  final Feed feed;
  final int newArticles;
  final String? error;

  bool get ok => error == null;
}

/// Ties fetching, parsing and storage together. The UI and the background
/// worker both go through this class.
class FeedRepository {
  FeedRepository(this._db, this._fetcher);

  final AppDatabase _db;
  final FeedFetcher _fetcher;

  /// How many feeds to fetch at once during a full refresh.
  static const _refreshConcurrency = 4;

  // ---------------------------------------------------------------- feeds

  Future<List<Feed>> listFeeds() => _db.listFeeds();

  /// Subscribes to the feed at [input], which may be a feed URL or a web
  /// page that links to one. Fetches and stores its articles straight away.
  Future<Feed> addFeed(String input) async {
    final url = normalizeUrl(input);
    await _ensureNotSubscribed(url);

    var document = await _fetcher.fetchText(url);
    ParsedFeed parsed;
    try {
      parsed = _parse(document);
    } on FeedFormatException {
      // Maybe it's a web page: look for an advertised feed and try that.
      final links = discoverFeedLinks(document.body, pageUrl: document.url);
      if (links.isEmpty) rethrow;
      await _ensureNotSubscribed(links.first);
      document = await _fetcher.fetchText(links.first);
      parsed = _parse(document);
    }

    // Redirects or discovery may have landed on a different URL.
    final feedUrl = document.url;
    if (feedUrl != url) await _ensureNotSubscribed(feedUrl);

    final feed = Feed(
      url: feedUrl,
      title: parsed.title,
      siteUrl: parsed.siteUrl,
      lastUpdated: DateTime.now(),
      syncStatus: SyncStatus.ok,
      favicon: await _fetchFavicon(parsed.siteUrl ?? feedUrl),
    );
    final id = await _db.insertFeed(feed);
    await _storeItems(id, parsed.items);
    return (await _db.getFeed(id))!;
  }

  Future<void> deleteFeed(int feedId) => _db.deleteFeed(feedId);

  Future<RefreshResult> refreshFeed(Feed feed) async {
    try {
      final document = await _fetcher.fetchText(feed.url);
      final parsed = _parse(document);
      final added = await _storeItems(feed.id!, parsed.items);
      final updated = Feed(
        id: feed.id,
        url: feed.url,
        // Keep the user's existing title stable; only fill it if missing.
        title: feed.title.isEmpty ? parsed.title : feed.title,
        siteUrl: parsed.siteUrl ?? feed.siteUrl,
        lastUpdated: DateTime.now(),
        syncStatus: SyncStatus.ok,
        favicon:
            feed.favicon ??
            await _fetchFavicon(parsed.siteUrl ?? feed.siteUrl ?? feed.url),
      );
      await _db.updateFeed(updated);
      return RefreshResult(feed: updated, newArticles: added);
    } catch (e) {
      final failed = Feed(
        id: feed.id,
        url: feed.url,
        title: feed.title,
        siteUrl: feed.siteUrl,
        lastUpdated: feed.lastUpdated,
        syncStatus: SyncStatus.error,
        lastError: e.toString(),
        favicon: feed.favicon,
      );
      await _db.updateFeed(failed);
      return RefreshResult(feed: failed, error: e.toString());
    }
  }

  /// Refreshes every feed, a few at a time. Never throws; failures are
  /// recorded per feed.
  Future<List<RefreshResult>> refreshAll() async {
    final queue = [...await _db.listFeeds()];
    final results = <RefreshResult>[];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        results.add(await refreshFeed(queue.removeLast()));
      }
    }

    await Future.wait(List.generate(_refreshConcurrency, (_) => worker()));
    return results;
  }

  // ------------------------------------------------------------- articles

  Future<List<Article>> listArticles({
    ArticleSort sort = ArticleSort.newest,
    bool unreadOnly = false,
    int? feedId,
    int limit = 100,
    int offset = 0,
  }) {
    return _db.listArticles(
      sort: sort,
      unreadOnly: unreadOnly,
      feedId: feedId,
      limit: limit,
      offset: offset,
    );
  }

  Future<Article?> getArticle(int id) => _db.getArticle(id);

  Future<int> unreadCount() => _db.unreadCount();

  Future<void> setRead(int articleId, bool isRead) =>
      _db.setRead(articleId, isRead);

  Future<void> markAllRead({int? feedId}) => _db.markAllRead(feedId: feedId);

  Future<void> deleteArticle(int articleId) => _db.deleteArticle(articleId);

  Future<void> restoreArticle(int articleId) => _db.restoreArticle(articleId);

  // -------------------------------------------------------------- helpers

  /// Adds a scheme when missing and trims whitespace.
  static String normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) throw const FormatException('Enter a feed URL');
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw const FormatException("That doesn't look like a web address");
    }
    return uri.toString();
  }

  Future<void> _ensureNotSubscribed(String url) async {
    final existing = await _db.findFeedByUrl(url);
    if (existing != null) throw DuplicateFeedException(existing);
  }

  ParsedFeed _parse(FetchedDocument document) {
    try {
      return parseFeed(document.body, feedUrl: document.url);
    } on FeedFormatException {
      rethrow;
    } catch (_) {
      // rss_dart throws ArgumentError/StateError on malformed feeds.
      throw FeedFormatException('Not a valid RSS or Atom feed');
    }
  }

  Future<int> _storeItems(int feedId, List<ParsedItem> items) {
    final now = DateTime.now();
    // Feeds list newest first. Inserting in reverse gives newer items higher
    // ids, which breaks ties correctly for items without a date.
    final articles = [
      for (final item in items.reversed)
        Article(
          feedId: feedId,
          guid: item.guid,
          title: item.title,
          author: item.author,
          url: item.url,
          pubDate: item.pubDate,
          summary: item.summary,
          content: item.content,
          addedDate: now,
        ),
    ];
    return _db.insertArticles(articles);
  }

  Future<Uint8List?> _fetchFavicon(String pageUrl) async {
    final page = Uri.tryParse(pageUrl);
    if (page == null || page.host.isEmpty) return null;
    final faviconUrl = Uri(
      scheme: page.scheme,
      host: page.host,
      port: page.port,
      path: '/favicon.ico',
    ).toString();
    final bytes = await _fetcher
        .fetchBytes(faviconUrl)
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    // Servers sometimes answer 200 with an HTML error page.
    if (bytes == null || bytes.isEmpty || bytes.first == 0x3C /* < */ ) {
      return null;
    }
    return bytes;
  }
}
