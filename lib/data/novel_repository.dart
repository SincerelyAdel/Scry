import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/novel.dart';
import '../services/chapter_matcher.dart';
import '../services/epub.dart';
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

  Future<void> removeNovel(Novel novel) async {
    await _db.deleteNovel(novel.id!);
    final cover = novel.cover;
    if (novel.isImported && cover != null && !cover.startsWith('http')) {
      try {
        await File(cover).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  /// Updates the novel's chapter count from the site. Returns the novel
  /// as stored afterwards.
  ///
  /// Checks made in the app count as announcing the new chapters, since
  /// the library shows them; background checks leave that to
  /// [chaptersToAnnounce].
  Future<Novel> checkForChapters(Novel novel, {bool inApp = true}) async {
    // An imported book has all its chapters already.
    if (novel.isImported) return novel;
    final page = await chapterPage(novel.bookId, 1, novelId: novel.id);
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
      if (!novel.started || novel.isImported) continue;
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

  /// One page of the novel's chapter list, newest first. With [novelId],
  /// its chapters are recorded so the list works offline later.
  Future<ChapterPage> chapterPage(int bookId, int page, {int? novelId}) async {
    final doc = await _fetcher.fetchText(Ranobes.chapterListUrl(bookId, page));
    final parsed = Ranobes.parseChapterList(doc.body);
    if (parsed == null) throw FetchException("Couldn't read the chapter list");
    if (novelId != null) await _db.saveIndex(novelId, parsed.chapters);
    return parsed;
  }

  /// The chapters recorded so far (from browsing the list or importing),
  /// oldest first.
  Future<List<ChapterRef>> chapterIndex(int novelId) =>
      _db.chapterIndex(novelId);

  /// The chapter at [url]: the saved copy when there is one, else fetched
  /// and saved. A saved last chapter is fetched again in case a newer one
  /// came out since; offline, the saved copy is used.
  ///
  /// Chapters added from an EPUB are always read from the phone, even when
  /// asked for by their site link.
  Future<ChapterText> chapter(Novel novel, String url) async {
    final id = novel.id!;
    if (novel.isImported) return _saved(url);
    final mixed = await _db.hasLocalChapters(id);
    if (mixed) {
      final ref = await _db.indexedChapterAt(id, url);
      if (ref != null && ref.url.startsWith('epub://')) {
        final saved = await _db.getChapter(ref.url);
        if (saved != null) return _linked(novel, saved, ref.number);
      }
    }
    if (!url.startsWith('http')) return _saved(url);

    final saved = await _db.getChapter(url);
    ChapterText result;
    if (saved != null && saved.nextUrl != null) {
      result = saved;
    } else {
      try {
        result = await _download(novel, url);
      } on Exception {
        if (saved == null) rethrow;
        result = saved;
      }
    }
    if (!mixed) return result;
    final ref =
        await _db.indexedChapterAt(id, result.url) ??
        await _db.indexedChapterAt(id, url);
    return ref == null ? result : _linked(novel, result, ref.number);
  }

  Future<ChapterText> _saved(String url) async {
    final saved = await _db.getChapter(url);
    if (saved != null) return saved;
    throw FetchException('This chapter is missing from the book');
  }

  /// [chapter] (number [number]) with its neighbours from the index, so
  /// moving on from a chapter from the EPUB reaches the site's next one,
  /// and back from a site chapter reaches the saved copy before it.
  Future<ChapterText> _linked(
    Novel novel,
    ChapterText chapter,
    int number,
  ) async {
    final id = novel.id!;
    var next = await _db.indexedChapter(id, number + 1);
    if (next == null && chapter.url.startsWith('epub://')) {
      // Past the book's last chapter: look the next one up in the site's
      // list (its newest page when it's past the known count).
      try {
        final count = novel.chapterCount;
        final page = number + 1 > count ? 1 : (count - (number + 1)) ~/ 25 + 1;
        await chapterPage(novel.bookId, page, novelId: id);
        next = await _db.indexedChapter(id, number + 1);
      } on Exception {
        // Offline; Check again in the reader tries once more.
      }
    }
    final previous = number > 1
        ? await _db.indexedChapter(id, number - 1)
        : null;
    return ChapterText(
      url: chapter.url,
      title: chapter.title,
      novelTitle: chapter.novelTitle,
      paragraphs: chapter.paragraphs,
      prevUrl: previous?.url ?? chapter.prevUrl,
      nextUrl: next?.url ?? chapter.nextUrl,
    );
  }

  /// The novel's first chapter: the saved one when it's known, else from
  /// the site (which redirects to it).
  Future<ChapterText> firstChapter(Novel novel) async {
    final first = await _db.indexedChapter(novel.id!, 1);
    if (first != null) {
      final saved = await _db.getChapter(first.url);
      if (saved != null || novel.isImported) return chapter(novel, first.url);
    }
    return _download(novel, Ranobes.firstChapterUrl(novel.bookId));
  }

  /// Saves the chapter at [url] ahead of time, if it isn't saved yet.
  /// Failures are ignored: it's fetched again when opened.
  Future<void> prefetch(Novel novel, String url) async {
    if (novel.isImported || await _db.getChapter(url) != null) return;
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

  /// Clears what's left of in-app downloads (see AppDatabase).
  Future<List<int>> clearDownloads() => _db.clearDownloads();

  // ---------------------------------------------------------------- import

  /// Adds the chapters of [book] (an EPUB of this novel, e.g. from
  /// QuickNovel) to [novel], matched by chapter number. Those are read
  /// from the phone from then on; the site is only asked about the rest
  /// and new ones. Replaces chapters added from an earlier EPUB.
  Future<ChapterMatch> attachBook(Novel novel, EpubBook book) async {
    final match = ChapterMatcher.match(book.chapters);
    if (match.chapters.isEmpty) {
      throw EpubException("Couldn't find the chapters' numbers in the book");
    }
    final id = novel.id!;
    await _db.attachChapters(id, {
      for (final e in match.chapters.entries)
        e.key: ChapterText(
          url: 'epub://novel$id/${e.key}',
          title: e.value.title,
          novelTitle: novel.title,
          paragraphs: e.value.paragraphs,
        ),
    });
    if (match.last > novel.chapterCount) {
      await _db.setChapterCount(id, match.last, DateTime.now());
    }
    return match;
  }

  /// Takes back the chapters added from an EPUB; they come from the site
  /// again.
  Future<void> detachBook(Novel novel) => _db.attachChapters(novel.id!, {});

  /// True when chapters from an EPUB were added to [novel].
  Future<bool> hasBook(Novel novel) => _db.hasLocalChapters(novel.id!);

  /// Adds [book] to the library with all its chapters. The cover is saved
  /// as a file in [coverDir].
  Future<Novel> importBook(EpubBook book, {required String coverDir}) async {
    // Imported books get negative numbers, so they never clash with the
    // site's.
    var bookId = -DateTime.now().millisecondsSinceEpoch;
    while (await _db.findNovelByBookId(bookId) != null) {
      bookId--;
    }
    String? coverPath;
    final cover = book.cover;
    if (cover != null && cover.isNotEmpty) {
      final file = File(
        p.join(coverDir, 'book${-bookId}.${book.coverExtension ?? 'jpg'}'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(cover);
      coverPath = file.path;
    }
    String url(int n) => 'epub://${-bookId}/$n';
    final count = book.chapters.length;
    final chapters = [
      for (var i = 0; i < count; i++)
        ChapterText(
          url: url(i + 1),
          title: book.chapters[i].title,
          novelTitle: book.title,
          paragraphs: book.chapters[i].paragraphs,
          prevUrl: i > 0 ? url(i) : null,
          nextUrl: i + 1 < count ? url(i + 2) : null,
        ),
    ];
    final now = DateTime.now();
    final id = await _db.insertNovelWithChapters(
      Novel(
        url: 'epub://${-bookId}',
        bookId: bookId,
        title: book.title,
        cover: coverPath,
        author: book.author,
        status: 'Imported book',
        description: book.description,
        chapterCount: count,
        addedDate: now,
        lastChecked: now,
        source: NovelSource.epub,
      ),
      chapters,
    );
    return (await _db.getNovel(id))!;
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
