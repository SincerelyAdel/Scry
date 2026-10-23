import 'package:flutter/foundation.dart';

import '../data/feed_repository.dart';
import '../models/feed.dart';

/// Subscribed feeds plus add/remove/refresh actions.
class FeedsProvider extends ChangeNotifier {
  FeedsProvider(this._repo);

  final FeedRepository _repo;

  /// Called after anything that changes which articles exist, so the inbox
  /// can reload. Wired up in main.dart.
  VoidCallback? onLibraryChanged;

  List<Feed> _feeds = const [];
  bool _loaded = false;
  bool _refreshing = false;

  List<Feed> get feeds => _feeds;
  bool get loaded => _loaded;
  bool get refreshing => _refreshing;

  Future<void> load() async {
    _feeds = await _repo.listFeeds();
    _loaded = true;
    notifyListeners();
  }

  /// Throws on failure (bad URL, network error, not a feed, duplicate) with
  /// a message suitable for the UI.
  Future<Feed> addFeed(String url) async {
    final feed = await _repo.addFeed(url);
    await load();
    onLibraryChanged?.call();
    return feed;
  }

  Future<void> deleteFeed(Feed feed) async {
    await _repo.deleteFeed(feed.id!);
    await load();
    onLibraryChanged?.call();
  }

  Future<RefreshResult> refreshFeed(Feed feed) async {
    final result = await _repo.refreshFeed(feed);
    await load();
    if (result.newArticles > 0) onLibraryChanged?.call();
    return result;
  }

  /// Refreshes all feeds. Concurrent calls share the in-flight refresh by
  /// returning an empty result list.
  Future<List<RefreshResult>> refreshAll() async {
    if (_refreshing) return const [];
    _refreshing = true;
    notifyListeners();
    try {
      final results = await _repo.refreshAll();
      await load();
      onLibraryChanged?.call();
      return results;
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }
}
