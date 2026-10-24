import 'dart:isolate';

import '../data/app_database.dart';
import '../models/novel.dart';
import '../models/novel_download.dart';
import 'feed_fetcher.dart';
import 'ranobes.dart';

/// How a download run ended.
enum DownloadRun {
  /// Nothing left to download.
  finished,

  /// Out of time with chapters left; run again to carry on.
  outOfTime,

  /// ranobes.net put up its human check; carries on once it's passed.
  needsCheck,

  /// Offline or the site is down; try again later.
  offline,
}

/// Downloads whole novels from ranobes.net for offline reading, one
/// chapter at a time at the pace the site allows (the fetcher spaces its
/// requests).
///
/// Everything it does is saved as it goes, so a run can stop at any point
/// (out of time, the site's check, no connection, the app closed) and the
/// next one carries on from there. On Android it runs in a background
/// worker; see DownloadWorker.
class NovelDownloader {
  NovelDownloader(this._db, this._fetcher, {this.onProgress});

  final AppDatabase _db;
  final FeedFetcher _fetcher;

  /// Called as chapters are saved, e.g. for a progress notification.
  final void Function(Novel novel, NovelDownload download)? onProgress;

  /// Works through the waiting downloads until they're all done or
  /// [budget] runs out.
  Future<DownloadRun> run({
    Duration budget = const Duration(minutes: 8),
  }) async {
    final stopAt = DateTime.now().add(budget);
    while (true) {
      final next = await _db.nextDownload();
      if (next == null) return DownloadRun.finished;
      final novel = await _db.getNovel(next.novelId);
      if (novel == null || novel.isImported) {
        await _db.removeDownload(next.novelId);
        continue;
      }
      final result = await _download(novel, next, stopAt);
      if (result != null) return result;
    }
  }

  /// Downloads [novel]. Returns null when it's done, cancelled or paused
  /// (move on to the next), otherwise why the run has to stop.
  Future<DownloadRun?> _download(
    Novel novel,
    NovelDownload start,
    DateTime stopAt,
  ) async {
    final id = novel.id!;
    var download = start.copyWith(
      state: DownloadState.running,
      message: 'Reading the chapter list',
    );
    if (!await _db.updateDownload(download)) return null;
    _report(novel, download);

    Future<bool> save(NovelDownload d) async {
      download = d;
      final ok = await _db.updateDownload(d);
      if (ok) _report(novel, d);
      return ok;
    }

    try {
      // 1. Every chapter's link, from the chapter list (25 to a page).
      final first = await _chapterPage(id, novel.bookId, 1);
      final count = first.chapterCount;
      if (count > 0) {
        await _db.setChapterCount(id, count, DateTime.now());
      }
      final known = {for (final c in await _db.chapterIndex(id)) c.number};
      final perPage = first.perPage > 0 ? first.perPage : 25;
      final pages = <int>{
        for (var n = 1; n <= count; n++)
          if (!known.contains(n)) (count - n) ~/ perPage + 1,
      }..remove(1);
      var listed = 0;
      // Oldest chapters first, so reading can start while the rest load.
      for (final page in pages.toList()..sort((a, b) => b - a)) {
        if (DateTime.now().isAfter(stopAt)) {
          await save(download.copyWith(state: DownloadState.queued));
          return DownloadRun.outOfTime;
        }
        await _chapterPage(id, novel.bookId, page);
        listed++;
        final ok = await save(
          download.copyWith(
            total: count,
            message: 'Reading the chapter list ($listed of ${pages.length})',
          ),
        );
        if (!ok) return null;
      }

      // 2. The chapters themselves, oldest first.
      var done = await _db.downloadedCount(id);
      final unreadable = <String>{};
      if (!await save(
        download.copyWith(total: count, done: done, clearMessage: true),
      )) {
        return null;
      }
      while (true) {
        final batch = [
          for (final c in await _db.chaptersToDownload(
            id,
            limit: 50 + unreadable.length,
          ))
            if (!unreadable.contains(c.url)) c,
        ];
        if (batch.isEmpty) break;
        for (final ref in batch) {
          if (DateTime.now().isAfter(stopAt)) {
            await save(download.copyWith(state: DownloadState.queued));
            return DownloadRun.outOfTime;
          }
          final chapter = await _fetchChapter(ref);
          if (chapter == null) {
            unreadable.add(ref.url);
            continue;
          }
          await _db.saveChapter(id, chapter, keep: true);
          done++;
          if (!await save(download.copyWith(done: done))) return null;
        }
      }
      await save(
        download.copyWith(
          state: DownloadState.done,
          done: done,
          total: done + unreadable.length,
          message: unreadable.isEmpty
              ? null
              : unreadable.length == 1
              ? "One chapter couldn't be read; it loads when you open it"
              : "${unreadable.length} chapters couldn't be read; they load "
                    'when you open them',
        ),
      );
      return null;
    } on HumanCheckRequired {
      download = download.copyWith(
        state: DownloadState.needsCheck,
        message: "ranobes.net wants to check you're human",
      );
      if (await _db.updateDownload(download)) _report(novel, download);
      return DownloadRun.needsCheck;
    } on Exception catch (e) {
      // Offline, or the site is down: wait and try again.
      download = download.copyWith(
        state: DownloadState.queued,
        message: 'Waiting to try again: ${e is FetchException ? e.message : e}',
      );
      if (await _db.updateDownload(download)) _report(novel, download);
      return DownloadRun.offline;
    }
  }

  Future<ChapterPage> _chapterPage(int novelId, int bookId, int page) async {
    final doc = await _fetcher.fetchText(Ranobes.chapterListUrl(bookId, page));
    final parsed = Ranobes.parseChapterList(doc.body);
    if (parsed == null) throw FetchException("Couldn't read the chapter list");
    await _db.saveIndex(novelId, parsed.chapters);
    return parsed;
  }

  /// The chapter, or null when its page can't be read.
  Future<ChapterText?> _fetchChapter(ChapterRef ref) async {
    final doc = await _fetcher.fetchText(ref.url);
    final body = doc.body;
    final url = doc.url;
    final parsed = await Isolate.run(() => Ranobes.parseChapter(body, url));
    if (parsed == null) return null;
    // Saved under the list's link, which is how the reader asks for it.
    return ChapterText(
      url: ref.url,
      title: parsed.title,
      novelTitle: parsed.novelTitle,
      paragraphs: parsed.paragraphs,
      prevUrl: parsed.prevUrl,
      nextUrl: parsed.nextUrl,
    );
  }

  void _report(Novel novel, NovelDownload download) =>
      onProgress?.call(novel, download);
}
