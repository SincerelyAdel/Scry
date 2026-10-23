import 'package:flutter/foundation.dart';

import '../data/feed_repository.dart';
import '../models/article.dart';
import '../utils/arxiv.dart';

/// Finds pictures for inbox articles whose feed didn't include one, and the
/// full text of teasers, as they scroll into view. A few lookups run at once, newest request first,
/// so what's on screen comes before what was scrolled past.
class ArticleImages extends ChangeNotifier {
  ArticleImages(this._repo);

  final FeedRepository _repo;

  static const _concurrency = 3;

  /// Results found this session, by article id (null = none).
  final Map<int, String?> _found = {};

  /// New lengths of articles whose full text was fetched this session.
  final Map<int, int> _words = {};
  final Set<int> _pending = {};
  final List<Article> _queue = [];
  int _running = 0;

  /// The article's picture, if known.
  String? imageFor(Article article) =>
      _found.containsKey(article.id) ? _found[article.id] : article.imageUrl;

  /// The article's length, including full text fetched this session.
  int wordCountFor(Article article) => _words[article.id] ?? article.wordCount;

  /// True when the article has no text to read, only its link: the feed
  /// sent next to nothing and its page gave no article either.
  bool isLinkOnly(Article article) {
    if (article.url == null || _pending.contains(article.id)) return false;
    if (arxivId(article.url, article.guid) != null) return false;
    final checked = article.imageChecked || _found.containsKey(article.id);
    return checked && wordCountFor(article) < linkOnlyWords;
  }

  /// Whether a lookup for the article is queued or running.
  bool isLooking(Article article) => _pending.contains(article.id);

  /// Asks for the article's picture to be found, unless it's known or was
  /// already looked for.
  void request(Article article) {
    final id = article.id;
    if (id == null ||
        article.imageChecked ||
        (article.imageUrl != null && !FeedRepository.isTeaser(article)) ||
        _found.containsKey(id) ||
        _pending.contains(id)) {
      return;
    }
    _pending.add(id);
    _queue.add(article);
    _pump();
  }

  void _pump() {
    while (_running < _concurrency && _queue.isNotEmpty) {
      final article = _queue.removeLast();
      _running++;
      _repo
          .checkPage(article)
          .then((check) {
            _found[article.id!] = check.imageUrl;
            if (check.wordCount != null) {
              _words[article.id!] = check.wordCount!;
            }
          }, onError: (Object _) {})
          .whenComplete(() {
            _running--;
            _pending.remove(article.id);
            notifyListeners();
            _pump();
          });
    }
  }
}
