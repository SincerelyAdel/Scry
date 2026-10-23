import 'package:flutter/foundation.dart';

import '../data/feed_repository.dart';
import '../models/article.dart';

/// Finds pictures for inbox articles whose feed didn't include one, as
/// they scroll into view. A few lookups run at once, newest request first,
/// so what's on screen comes before what was scrolled past.
class ArticleImages extends ChangeNotifier {
  ArticleImages(this._repo);

  final FeedRepository _repo;

  static const _concurrency = 3;

  /// Results found this session, by article id (null = none).
  final Map<int, String?> _found = {};
  final Set<int> _pending = {};
  final List<Article> _queue = [];
  int _running = 0;

  /// The article's picture, if known.
  String? imageFor(Article article) =>
      _found.containsKey(article.id) ? _found[article.id] : article.imageUrl;

  /// Whether a lookup for the article is queued or running.
  bool isLooking(Article article) => _pending.contains(article.id);

  /// Asks for the article's picture to be found, unless it's known or was
  /// already looked for.
  void request(Article article) {
    final id = article.id;
    if (id == null ||
        article.imageUrl != null ||
        article.imageChecked ||
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
          .findImage(article)
          .then((image) => _found[article.id!] = image, onError: (Object _) {})
          .whenComplete(() {
            _running--;
            _pending.remove(article.id);
            notifyListeners();
            _pump();
          });
    }
  }
}
