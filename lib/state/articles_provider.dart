import 'package:flutter/foundation.dart';

import '../data/feed_repository.dart';
import '../models/article.dart';
import '../models/article_sort.dart';
import '../models/topic.dart';

/// Which articles the inbox lists.
enum InboxShow { all, unread, starred }

/// The unified inbox: every subscribed feed's articles in one paged list.
class ArticlesProvider extends ChangeNotifier {
  ArticlesProvider(this._repo, {ArticleSort initialSort = ArticleSort.newest})
    : _sort = initialSort;

  final FeedRepository _repo;

  /// Called when read state or visibility changes, so feed unread counts
  /// can update. Wired up in main.dart.
  VoidCallback? onCountsChanged;

  static const pageSize = 100;

  List<Article> _articles = const [];
  ArticleSort _sort;
  InboxShow _show = InboxShow.all;
  Map<int, int>? _topicFeeds;
  int? _feedId;
  Topic? _topic;
  String? _feedTitle;
  bool _loading = false;
  bool _loaded = false;
  bool _hasMore = true;
  int _unreadCount = 0;

  /// Bumped on every reload so a slow page load can't overwrite newer data.
  int _generation = 0;

  List<Article> get articles => _articles;
  ArticleSort get sort => _sort;
  InboxShow get show => _show;
  bool get unreadOnly => _show == InboxShow.unread;

  /// When set, the inbox shows only articles with this tag (their feed's or
  /// their own). Combines with [feedId].
  Topic? get topic => _topic;

  /// With a [topic]: unread counts of its articles per feed, for every feed
  /// that has some. Null without a topic.
  Map<int, int>? get topicFeeds => _topicFeeds;

  /// When set, the inbox shows a single feed.
  int? get feedId => _feedId;
  String? get feedTitle => _feedTitle;

  bool get loading => _loading;
  bool get loaded => _loaded;
  bool get hasMore => _hasMore;
  int get unreadCount => _unreadCount;

  /// Reloads from the database, keeping roughly as many rows as are
  /// currently shown so the scroll position survives.
  Future<void> reload() async {
    final generation = ++_generation;
    final limit = _articles.length > pageSize ? _articles.length : pageSize;
    _loading = true;
    notifyListeners();
    final topicFeeds = _topic == null
        ? null
        : await _repo.tagFeedCounts(_topic!);
    // A feed with nothing under the tag would leave the list empty.
    if (topicFeeds != null &&
        _feedId != null &&
        !topicFeeds.containsKey(_feedId)) {
      _feedId = null;
      _feedTitle = null;
    }
    final rows = await _query(limit: limit, offset: 0);
    final unread = await _repo.unreadCount();
    if (generation != _generation) return;
    _topicFeeds = topicFeeds;
    _articles = rows;
    _hasMore = rows.length == limit;
    _unreadCount = unread;
    _loading = false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    _loading = true;
    notifyListeners();
    final rows = await _query(limit: pageSize, offset: _articles.length);
    if (generation != _generation) return;
    _articles = [..._articles, ...rows];
    _hasMore = rows.length == pageSize;
    _loading = false;
    notifyListeners();
  }

  void applySort(ArticleSort sort) {
    if (sort == _sort) return;
    _sort = sort;
    _articles = const [];
    _view++;
    reload();
  }

  void setShow(InboxShow value) {
    if (value == _show) return;
    _show = value;
    _articles = const [];
    _view++;
    reload();
  }

  void showTopic(Topic? topic) {
    if (topic == _topic) return;
    _topic = topic;
    _articles = const [];
    _view++;
    reload();
  }

  void showFeed(int? feedId, {String? title}) {
    if (feedId == _feedId) return;
    _feedId = feedId;
    _feedTitle = feedId == null ? null : title;
    _articles = const [];
    _view++;
    reload();
  }

  Future<void> setRead(Article article, bool isRead) async {
    if (article.isRead == isRead) return;
    await _repo.setRead(article.id!, isRead);
    _replace(article.id!, (a) => a.copyWith(isRead: isRead));
    _unreadCount += isRead ? -1 : 1;
    final feeds = _topicFeeds;
    if (feeds != null && feeds.containsKey(article.feedId)) {
      feeds[article.feedId] = feeds[article.feedId]! + (isRead ? -1 : 1);
    }
    notifyListeners();
    onCountsChanged?.call();
  }

  /// Stars [article] to read later, or unstars it. In the Starred view an
  /// unstarred article stays until the list reloads, so it can be undone.
  Future<void> setStarred(Article article, bool starred) async {
    await _repo.setStarred(article.id!, starred);
    _replace(article.id!, (a) => a.copyWith(isStarred: starred));
    notifyListeners();
  }

  /// Bumped whenever the filters or sort change, so cards can replay their
  /// colour animation.
  int get view => _view;
  int _view = 0;

  /// Articles whose card has swept in its colours since the filters last
  /// changed, so scrolling back doesn't replay it.
  final Set<(int, int)> _swept = {};

  /// True the first time [articleId]'s card is shown in this view.
  bool claimSweep(int articleId) => _swept.add((_view, articleId));

  /// Hides [article]; returns its old index so [restore] can undo.
  Future<int> delete(Article article) async {
    final index = _articles.indexWhere((a) => a.id == article.id);
    if (index >= 0) {
      _articles = [..._articles]..removeAt(index);
      if (!article.isRead) _unreadCount--;
      notifyListeners();
    }
    await _repo.deleteArticle(article.id!);
    onCountsChanged?.call();
    return index;
  }

  Future<void> restore(Article article, int index) async {
    await _repo.restoreArticle(article.id!);
    if (index >= 0 && index <= _articles.length) {
      _articles = [..._articles]..insert(index, article);
      if (!article.isRead) _unreadCount++;
      notifyListeners();
    } else {
      await reload();
    }
    onCountsChanged?.call();
  }

  Future<List<Article>> _query({required int limit, required int offset}) {
    return _repo.listArticles(
      sort: _sort,
      unreadOnly: _show == InboxShow.unread,
      starredOnly: _show == InboxShow.starred,
      feedId: _feedId,
      topic: _topic,
      limit: limit,
      offset: offset,
    );
  }

  void _replace(int id, Article Function(Article) update) {
    _articles = [for (final a in _articles) a.id == id ? update(a) : a];
  }
}
