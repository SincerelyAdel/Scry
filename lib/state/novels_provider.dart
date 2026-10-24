import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../data/novel_repository.dart';
import '../models/novel.dart';
import '../models/novel_download.dart';
import '../services/background_sync.dart';
import '../services/chapter_alerts.dart';
import '../services/epub.dart';
import '../services/feed_fetcher.dart';
import '../services/novel_downloader.dart';
import '../services/ranobes.dart';

/// The novel library: what's in it, and checking for new chapters.
class NovelsProvider extends ChangeNotifier {
  NovelsProvider(this._repo, {this.downloadInApp, this.coverDir});

  final NovelRepository _repo;

  /// Runs downloads in the app instead of the background worker; set
  /// where there's no worker (and in tests).
  final NovelDownloader? downloadInApp;

  /// Where imported books' covers are saved.
  final Future<String> Function()? coverDir;

  Map<int, NovelDownload> _downloads = const {};
  Timer? _downloadPoll;
  bool _downloadingInApp = false;

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
    // Downloads the check stopped carry on.
    _repo.resumeAfterCheck().then((_) => _startDownloads()).ignore();
  }

  Future<void> load() async {
    _novels = _ordered(await _repo.listNovels());
    final first = !_loaded;
    _loaded = true;
    await _loadDownloads();
    notifyListeners();
    // Picks up downloads left going when the app last closed.
    if (first && _downloads.values.any((d) => d.active)) {
      _startDownloads().ignore();
    }
  }

  // ------------------------------------------------------------- downloads

  /// The novel's download, if it's been downloaded or is being.
  NovelDownload? downloadOf(int? novelId) => _downloads[novelId];

  /// Downloads every chapter of [novel] for offline reading, or carries on
  /// with it.
  Future<void> download(Novel novel) async {
    await _repo.queueDownload(novel);
    await _loadDownloads();
    notifyListeners();
    await _startDownloads();
  }

  Future<void> pauseDownload(Novel novel) async {
    await _repo.pauseDownload(novel.id!);
    await ChapterAlerts.dismissDownload(novel.id!);
    await _loadDownloads();
    notifyListeners();
  }

  Future<void> removeDownload(Novel novel) async {
    await _repo.removeDownload(novel.id!);
    await ChapterAlerts.dismissDownload(novel.id!);
    await _loadDownloads();
    notifyListeners();
  }

  Future<void> _startDownloads() async {
    final local = downloadInApp;
    if (local == null) {
      await DownloadWorker.schedule();
    } else if (!_downloadingInApp) {
      _downloadingInApp = true;
      try {
        while (await local.run() == DownloadRun.outOfTime) {}
      } finally {
        _downloadingInApp = false;
      }
      await _loadDownloads();
      notifyListeners();
    }
  }

  /// Reads the downloads' progress, which the worker writes, and keeps
  /// reading it every couple of seconds while one is going.
  Future<void> _loadDownloads() async {
    final list = await _repo.downloads();
    final before = _downloads;
    _downloads = {for (final d in list) d.novelId: d};
    final going = list.any((d) => d.active);
    if (going) {
      _downloadPoll ??= Timer.periodic(const Duration(seconds: 2), (_) async {
        await _loadDownloads();
        notifyListeners();
      });
    } else {
      _downloadPoll?.cancel();
      _downloadPoll = null;
    }
    // The download corrects the chapter count; show it when one starts,
    // stops or finishes.
    if (before.isNotEmpty &&
        list.any((d) => before[d.novelId]?.state != d.state)) {
      _novels = _ordered(await _repo.listNovels());
    }
  }

  @override
  void dispose() {
    _downloadPoll?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- import

  /// Adds the EPUB book in [bytes] to the library.
  Future<Novel> importBook(Uint8List bytes) async {
    final book = await Isolate.run(() => Epub.parse(bytes));
    final dir = coverDir == null
        ? Directory.systemTemp.path
        : await coverDir!();
    final novel = await _repo.importBook(book, coverDir: dir);
    await load();
    return novel;
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
    final queue = [
      for (final n in _novels)
        if (!n.isImported) n,
    ];
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
    await ChapterAlerts.dismissDownload(novel.id!);
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
