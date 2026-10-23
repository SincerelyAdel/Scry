import 'package:flutter/foundation.dart';

import '../data/novel_repository.dart';
import '../models/novel.dart';
import '../services/feed_fetcher.dart';
import '../services/ranobes.dart';

/// The novel library: what's in it, and checking for new chapters.
class NovelsProvider extends ChangeNotifier {
  NovelsProvider(this._repo);

  final NovelRepository _repo;

  List<Novel> _novels = const [];
  bool _loaded = false;
  bool _checking = false;
  DateTime? _lastCheck;
  HumanCheckRequired? _humanCheck;

  List<Novel> get novels => _novels;
  bool get loaded => _loaded;

  /// True while new chapters are being looked for.
  bool get checking => _checking;

  NovelRepository get repository => _repo;

  /// Set when ranobes.net showed its human check during the last check
  /// for new chapters; the library offers to pass it.
  HumanCheckRequired? get humanCheck => _humanCheck;

  /// Called once the check is passed in the in-app browser.
  void humanCheckPassed() {
    _humanCheck = null;
    _lastCheck = null;
    notifyListeners();
  }

  Future<void> load() async {
    _novels = _ordered(await _repo.listNovels());
    _loaded = true;
    notifyListeners();
  }

  /// Looks for new chapters of every novel. Skipped when the last check
  /// was within [ifOlderThan]. Returns how many novels couldn't be checked.
  Future<int> checkAll({Duration ifOlderThan = Duration.zero}) async {
    final last = _lastCheck;
    if (_checking ||
        (last != null && DateTime.now().difference(last) < ifOlderThan)) {
      return 0;
    }
    _checking = true;
    notifyListeners();
    var failed = 0;
    _humanCheck = null;
    // One at a time: the site rate-limits, and a burst is what brings up
    // its human check.
    final queue = [..._novels];
    for (var i = 0; i < queue.length; i++) {
      final novel = queue[i];
      try {
        final updated = await _repo.checkForChapters(novel);
        _replace(updated);
        notifyListeners();
      } on HumanCheckRequired catch (e) {
        // Everything after this would fail the same way.
        _humanCheck = e;
        failed += queue.length - i;
        break;
      } on Exception {
        failed++;
      }
    }
    // Reordered once at the end, so cards don't jump around mid-check.
    _novels = _ordered(_novels);
    _lastCheck = DateTime.now();
    _checking = false;
    notifyListeners();
    return failed;
  }

  Future<List<NovelHit>> search(String query) => _repo.search(query);

  Future<Novel> add(String url) async {
    final novel = await _repo.addNovel(url);
    await load();
    return novel;
  }

  Future<void> remove(Novel novel) async {
    await _repo.removeNovel(novel);
    await load();
  }

  bool contains(String url) {
    final id = Ranobes.bookId(url);
    return id != null && _novels.any((n) => n.bookId == id);
  }

  Novel? byId(int? id) => _novels.where((n) => n.id == id).firstOrNull;

  /// Remembers where the reader is in [novel].
  Future<Novel> saveProgress(
    Novel novel, {
    required ChapterText chapter,
    required int number,
    required double progress,
  }) async {
    final updated = await _repo.saveProgress(
      novel,
      chapter: chapter,
      number: number,
      progress: progress,
    );
    _replace(updated);
    // Most recently read first.
    _novels = _ordered([
      updated,
      for (final n in _novels)
        if (n.id != updated.id) n,
    ]);
    notifyListeners();
    return updated;
  }

  /// Novels with new chapters first; otherwise the order is kept (most
  /// recently read first).
  static List<Novel> _ordered(List<Novel> novels) => [
    for (final n in novels)
      if (n.newChapters > 0) n,
    for (final n in novels)
      if (n.newChapters == 0) n,
  ];

  void _replace(Novel novel) {
    _novels = [for (final n in _novels) n.id == novel.id ? novel : n];
  }
}
