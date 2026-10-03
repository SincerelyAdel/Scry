import 'package:flutter/foundation.dart';

import '../data/feed_repository.dart';
import '../models/article.dart';
import '../models/article_sort.dart';

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
  bool _unreadOnly = false;
  int? _feedId;
  String? _feedTitle;
  bool _loading = false;
  bool _loaded = false;
  bool _hasMore = true;
  int _unreadCount = 0;

  /// Bumped on every reload so a slow page load can't overwrite newer data.
  int _generation = 0;

  List<Article> get articles => _articles;
  ArticleSort get sort => _sort;
  bool get unreadOnly => _unreadOnly;

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
    final rows = await _query(limit: limit, offset: 0);
    final unread = await _repo.unreadCount();
    if (generation != _generation) return;
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
    reload();
  }

  void setUnreadOnly(bool value) {
    if (value == _unreadOnly) return;
    _unreadOnly = value;
    _articles = const [];
    reload();
  }

  void showFeed(int? feedId, {String? title}) {
    if (feedId == _feedId) return;
    _feedId = feedId;
    _feedTitle = feedId == null ? null : title;
    _articles = const [];
    reload();
  }

  Future<void> setRead(Article article, bool isRead) async {
    if (article.isRead == isRead) return;
    await _repo.setRead(article.id!, isRead);
    _replace(article.id!, (a) => a.copyWith(isRead: isRead));
    _unreadCount += isRead ? -1 : 1;
    notifyListeners();
    onCountsChanged?.call();
  }

  Future<void> markAllRead() async {
    await _repo.markAllRead(feedId: _feedId);
    await reload();
    onCountsChanged?.call();
  }

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
      unreadOnly: _unreadOnly,
      feedId: _feedId,
      limit: limit,
      offset: offset,
    );
  }

  void _replace(int id, Article Function(Article) update) {
    _articles = [for (final a in _articles) a.id == id ? update(a) : a];
  }
}
