import 'dart:isolate';

import '../models/novel.dart';
import '../services/feed_fetcher.dart';
import '../services/ranobes.dart';
import 'app_database.dart';

/// Novels from ranobes.net: finding and adding them, checking for new
/// chapters, and reading chapters, which are kept for offline use.
class NovelRepository {
  NovelRepository(this._db, this._fetcher);

  final AppDatabase _db;
  final FeedFetcher _fetcher;

  Future<List<Novel>> listNovels() => _db.listNovels();

  Future<Novel?> getNovel(int id) => _db.getNovel(id);

  /// Novels matching [query], or the novel a pasted ranobes.net link
  /// belongs to.
  Future<List<NovelHit>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    if (Ranobes.bookId(text) != null) {
      final info = await _novelInfo(text);
      return [
        NovelHit(
          url: info.url,
          title: info.title,
          cover: info.cover,
          blurb: info.description,
        ),
      ];
    }
    if (text.contains('://')) {
      throw FetchException('Paste a link to a novel on ranobes.net');
    }
    final page = await _fetcher.fetchText(Ranobes.searchUrl(text));
    return Ranobes.parseSearch(page.body);
  }

  /// Adds the novel behind [url] (its page, a chapter or its chapter
  /// list) to the library, or returns it if it's already there.
  Future<Novel> addNovel(String url) async {
    final id = Ranobes.bookId(url);
    if (id == null) {
      throw FetchException("That isn't a ranobes.net novel link");
    }
    final existing = await _db.findNovelByBookId(id);
    if (existing != null) return existing;
    final info = await _novelInfo(url);
    final novel = Novel(
      url: info.url,
      bookId: info.bookId,
      title: info.title,
      cover: info.cover,
      author: info.author,
      status: info.status,
      description: info.description,
      chapterCount: info.chapterCount,
      addedDate: DateTime.now(),
      lastChecked: DateTime.now(),
    );
    final newId = await _db.insertNovel(novel);
    return (await _db.getNovel(newId))!;
  }

  Future<void> removeNovel(Novel novel) => _db.deleteNovel(novel.id!);

  /// Updates the novel's chapter count from the site. Returns the novel
  /// as stored afterwards.
  ///
  /// Checks made in the app count as announcing the new chapters, since
  /// the library shows them; background checks leave that to
  /// [chaptersToAnnounce].
  Future<Novel> checkForChapters(Novel novel, {bool inApp = true}) async {
    final page = await chapterPage(novel.bookId, 1);
    final count = page.chapterCount > 0
        ? page.chapterCount
        : novel.chapterCount;
    final now = DateTime.now();
    // Only these columns, so a check running while a chapter is read
    // can't undo the reader's place.
    await _db.setChapterCount(novel.id!, count, now);
    if (inApp) await _db.setNotified(novel.id!, count);
    return (await _db.getNovel(novel.id!)) ??
        novel.copyWith(chapterCount: count, lastChecked: now);
  }

  /// Checks the novels being read for new chapters, for the background
  /// check. Returns those with chapters not announced yet, and records
  /// them as announced.
  Future<List<Novel>> chaptersToAnnounce() async {
    final fresh = <Novel>[];
    for (final novel in await _db.listNovels()) {
      if (!novel.started) continue;
      try {
        final updated = await checkForChapters(novel, inApp: false);
        if (updated.unannounced > 0) {
          await _db.setNotified(updated.id!, updated.chapterCount);
          fresh.add(updated);
        }
      } on HumanCheckRequired {
        // Only the person can pass the site's check, in the app. Asking
        // about the other novels now would just get more 429s.
        break;
      } on Exception {
        // Offline or the site is down; the next check tries again.
      }
    }
    return fresh;
  }

  /// One page of the novel's chapter list, newest first.
  Future<ChapterPage> chapterPage(int bookId, int page) async {
    final doc = await _fetcher.fetchText(Ranobes.chapterListUrl(bookId, page));
    final parsed = Ranobes.parseChapterList(doc.body);
    if (parsed == null) throw FetchException("Couldn't read the chapter list");
    return parsed;
  }

  /// The chapter at [url]: the saved copy when there is one, else fetched
  /// and saved. A saved last chapter is fetched again in case a newer one
  /// came out since; offline, the saved copy is used.
  Future<ChapterText> chapter(Novel novel, String url) async {
    final saved = await _db.getChapter(url);
    if (saved != null && saved.nextUrl != null) return saved;
    try {
      return await _download(novel, url);
    } on Exception {
      if (saved != null) return saved;
      rethrow;
    }
  }

  /// The novel's first chapter (the site redirects to it).
  Future<ChapterText> firstChapter(Novel novel) =>
      _download(novel, Ranobes.firstChapterUrl(novel.bookId));

  /// Saves the chapter at [url] ahead of time, if it isn't saved yet.
  /// Failures are ignored: it's fetched again when opened.
  Future<void> prefetch(Novel novel, String url) async {
    if (await _db.getChapter(url) != null) return;
    try {
      await _download(novel, url);
    } on Exception {
      // Offline or the site is down; try again when it's opened.
    }
  }

  /// Remembers where the reader is.
  Future<Novel> saveProgress(
    Novel novel, {
    required ChapterText chapter,
    required int number,
    required double progress,
  }) async {
    // A chapter past the known count means new ones came out.
    final count = number > novel.chapterCount ? number : novel.chapterCount;
    final updated = novel.copyWith(
      chapterUrl: chapter.url,
      chapterTitle: chapter.title,
      chapterNumber: number,
      chapterProgress: progress.clamp(0.0, 1.0),
      readAt: DateTime.now(),
      chapterCount: count,
      seenCount: count,
    );
    await _db.updateNovel(updated);
    return updated;
  }

  Future<ChapterText> _download(Novel novel, String url) async {
    final doc = await _fetcher.fetchText(url);
    final body = doc.body;
    final finalUrl = doc.url;
    // Chapter pages are large; parse them off the UI thread.
    final chapter = await Isolate.run(
      () => Ranobes.parseChapter(body, finalUrl),
    );
    if (chapter == null) throw FetchException("Couldn't read this chapter");
    await _db.saveChapter(novel.id!, chapter);
    return chapter;
  }

  /// The novel's page details, found from any of its links. Chapter and
  /// chapter-list links go through the list, which names the novel's page.
  Future<NovelInfo> _novelInfo(String url) async {
    final id = Ranobes.bookId(url);
    if (id == null) {
      throw FetchException("That isn't a ranobes.net novel link");
    }
    var pageUrl = url;
    int? count;
    if (!url.contains('/novels/')) {
      final list = await chapterPage(id, 1);
      if (list.bookUrl == null) throw FetchException("Couldn't find the novel");
      pageUrl = list.bookUrl!;
      count = list.chapterCount;
    }
    final doc = await _fetcher.fetchText(pageUrl);
    final info = Ranobes.parseNovel(doc.body, doc.url);
    if (info == null) throw FetchException("Couldn't read the novel's page");
    if (info.chapterCount > 0) return info;
    // The page doesn't say how many chapters there are; the list does.
    count ??= await chapterPage(
      id,
      1,
    ).then((list) => list.chapterCount).catchError((Object _) => 0);
    return NovelInfo(
      url: info.url,
      bookId: info.bookId,
      title: info.title,
      cover: info.cover,
      author: info.author,
      status: info.status,
      description: info.description,
      chapterCount: count,
    );
  }
}
