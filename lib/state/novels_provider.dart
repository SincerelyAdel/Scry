import 'package:flutter/foundation.dart';

import '../data/novel_repository.dart';
import '../models/novel.dart';
import '../services/ranobes.dart';

/// The novel library: what's in it, and checking for new chapters.
class NovelsProvider extends ChangeNotifier {
  NovelsProvider(this._repo);

  final NovelRepository _repo;

  List<Novel> _novels = const [];
  bool _loaded = false;
  bool _checking = false;
  DateTime? _lastCheck;

  List<Novel> get novels => _novels;
  bool get loaded => _loaded;

  /// True while new chapters are being looked for.
  bool get checking => _checking;

  NovelRepository get repository => _repo;

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
    final queue = [..._novels];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final novel = queue.removeLast();
        try {
          final updated = await _repo.checkForChapters(novel);
          _replace(updated);
          notifyListeners();
        } on Exception {
          failed++;
        }
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
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
