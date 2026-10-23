import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/article.dart';
import '../models/article_sort.dart';
import '../models/feed.dart';
import '../models/paper_figure.dart';
import '../models/topic.dart';
import '../services/feed_fetcher.dart';
import '../services/feed_parser.dart';
import '../utils/arxiv.dart';
import '../utils/html_text.dart';
import '../utils/images.dart';
import '../utils/readable.dart';
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

/// What looking at an article's web page found.
class PageCheck {
  const PageCheck({this.imageUrl, this.wordCount});

  final String? imageUrl;

  /// The article's new length when its full text was fetched.
  final int? wordCount;
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
  /// The feed's [topics] are guessed when not given.
  Future<Feed> addFeed(String input, {Set<Topic>? topics}) async {
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
      topics: topics ?? guessTopics(feedUrl, parsed.title),
    );
    final id = await _db.insertFeed(feed);
    await _storeItems(id, parsed.items);
    return (await _db.getFeed(id))!;
  }

  Future<void> deleteFeed(int feedId) => _db.deleteFeed(feedId);

  Future<void> setFeedTopics(int feedId, Set<Topic> topics) =>
      _db.setFeedTopics(feedId, topics);

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
        topics: feed.topics,
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
        topics: feed.topics,
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
    bool starredOnly = false,
    int? feedId,
    Topic? topic,
    int limit = 100,
    int offset = 0,
  }) {
    return _db.listArticles(
      sort: sort,
      unreadOnly: unreadOnly,
      starredOnly: starredOnly,
      feedId: feedId,
      topic: topic,
      limit: limit,
      offset: offset,
    );
  }

  Future<Article?> getArticle(int id) => _db.getArticle(id);

  Future<int> unreadCount() => _db.unreadCount();

  Future<void> setRead(int articleId, bool isRead) =>
      _db.setRead(articleId, isRead);

  Future<void> setStarred(int articleId, bool starred) =>
      _db.setStarred(articleId, starred);

  /// Unread counts per feed among articles with [topic] (see
  /// AppDatabase.tagFeedCounts).
  Future<Map<int, int>> tagFeedCounts(Topic topic) => _db.tagFeedCounts(topic);

  Future<void> deleteArticle(int articleId) => _db.deleteArticle(articleId);

  Future<void> restoreArticle(int articleId) => _db.restoreArticle(articleId);

  // --------------------------------------------------------------- images

  /// Whether the feed sent only a teaser of an article that has a web page
  /// to read the rest from. arXiv papers are handled separately.
  static bool isTeaser(Article article) =>
      article.wordCount < minArticleWords &&
      article.url != null &&
      arxivId(article.url, article.guid) == null;

  /// Finds a picture for an article whose feed didn't supply one: the first
  /// figure for an arXiv paper, otherwise its page's preview image. For a
  /// teaser, the whole page is downloaded and the article's text taken from
  /// it as well; otherwise only the start of the page is read. Results are
  /// stored, including "none", so each article is checked once. Network
  /// failures aren't stored, so they're retried later.
  Future<PageCheck> checkPage(Article article) async {
    final id = article.id!;
    final paper = arxivId(article.url, article.guid);
    var image = article.imageUrl;
    int? words;
    try {
      if (paper != null) {
        if (image == null) {
          final page = await _fetcher.fetchPrefix(
            arxivHtmlUrl(paper),
            maxBytes: 600 * 1024,
            done: (text) => text.contains('ltx_graphics'),
          );
          image = arxivFirstFigure(page.body, pageUrl: page.url);
        }
      } else if (isTeaser(article)) {
        final page = await _fetcher.fetchPrefix(
          article.url!,
          maxBytes: 3 * 1024 * 1024,
        );
        final (preview, text) = await Isolate.run(
          () => (
            pagePreviewImage(page.body, pageUrl: page.url),
            extractArticle(page.body, pageUrl: page.url),
          ),
        );
        image ??= preview;
        if (text != null) {
          final count = countWords(htmlToPlainText(text));
          if (count > article.wordCount) {
            final tags = AppDatabase.articleTags(article.title, text);
            await _db.saveFullText(id, text, count, tags);
            words = count;
          }
        }
      } else if (image == null && article.url != null) {
        final page = await _fetcher.fetchPrefix(
          article.url!,
          done: pagePreviewFound,
        );
        image = pagePreviewImage(page.body, pageUrl: page.url);
      }
    } on FetchException catch (e) {
      // Missing pages won't appear later; anything else might.
      if (e.statusCode == null || e.statusCode! >= 500) {
        return PageCheck(imageUrl: article.imageUrl);
      }
    }
    await _db.setArticleImage(id, image);
    return PageCheck(imageUrl: image, wordCount: words);
  }

  /// The article's picture; see [checkPage].
  Future<String?> findImage(Article article) async =>
      (await checkPage(article)).imageUrl;

  /// A paper's figures, from storage or else from its arXiv HTML version.
  /// Throws [FetchException] when offline and nothing is stored yet.
  Future<(FiguresState, List<PaperFigure>)> loadFigures(Article article) async {
    final id = article.id!;
    final stored = await _db.getFigures(id);
    if (stored.$1 != FiguresState.unknown) return stored;
    final paper = arxivId(article.url, article.guid);
    if (paper == null) return (FiguresState.missing, const <PaperFigure>[]);
    try {
      final page = await _fetcher.fetchText(arxivHtmlUrl(paper));
      final figures = arxivFigures(page.body, pageUrl: page.url);
      await _db.saveFigures(id, FiguresState.found, figures);
      if (article.imageUrl == null && figures.isNotEmpty) {
        await _db.setArticleImage(id, figures.first.images.first);
      }
      return (FiguresState.found, figures);
    } on FetchException catch (e) {
      if (e.statusCode == 404) {
        await _db.saveFigures(id, FiguresState.missing, const []);
        return (FiguresState.missing, const <PaperFigure>[]);
      }
      rethrow;
    }
  }

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

  Future<int> _storeItems(int feedId, List<ParsedItem> items) async {
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
          imageUrl: item.imageUrl,
          wordCount: AppDatabase.bodyWordCount(item.content, item.summary),
          ownTags: topicsFromString(
            AppDatabase.articleTags(item.title, item.content ?? item.summary),
          ),
          addedDate: now,
        ),
    ];
    final added = await _db.insertArticles(articles);
    // Articles stored before images were picked up get theirs now.
    await _db.fillMissingImages(feedId, {
      for (final item in items)
        if (item.imageUrl != null) item.guid: item.imageUrl!,
    });
    return added;
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
