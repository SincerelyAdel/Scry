import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scry/data/app_database.dart';
import 'package:scry/data/novel_repository.dart';
import 'package:scry/models/novel.dart';
import 'package:scry/state/novels_provider.dart';
import 'package:scry/services/ranobes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';
import 'support/ranobes_fixtures.dart';

void main() {
  group('ranobes pages', () {
    test('novel numbers come from any kind of link', () {
      expect(Ranobes.bookId(novelUrl), 1205249);
      expect(Ranobes.bookId(chapter2Url), 1205249);
      expect(Ranobes.bookId(chapterListUrl), 1205249);
      expect(
        Ranobes.bookId('https://ranobes.net/chapters/1205249/page/3/'),
        1205249,
      );
      expect(Ranobes.bookId('https://example.com/novels/12-x.html'), isNull);
      expect(Ranobes.bookId('shadow slave'), isNull);
      expect(
        Ranobes.searchUrl(' reverend insanity '),
        'https://ranobes.net/search/reverend+insanity/',
      );
    });

    test('search results', () {
      final hits = Ranobes.parseSearch(searchPage);
      expect(hits, hasLength(1));
      expect(hits.single.title, 'Shadow Slave');
      expect(hits.single.url, novelUrl);
      expect(
        hits.single.cover,
        'https://ranobes.net/uploads/posts/2022-06/thumbs/shadow-slave.jpg',
      );
      expect(hits.single.genres, 'Action, Fantasy');
      expect(hits.single.blurb, startsWith('Growing up in poverty'));
    });

    test("a novel's page", () {
      final info = Ranobes.parseNovel(novelPage, novelUrl)!;
      expect(info.title, 'Shadow Slave');
      expect(info.bookId, 1205249);
      expect(info.author, 'Guiltythree');
      expect(info.status, 'Ongoing');
      expect(info.chapterCount, 3);
      expect(info.description, contains('\n\nTransported'));
    });

    test('a description with short and full versions keeps the full', () {
      final page = novelPage.replaceFirst(
        RegExp(r'<div class="moreless[^>]*>[\s\S]*?</div>'),
        '<div class="moreless cont-text">'
        '<div class="moreless__short">Growing up... <a href="#">Read more</a></div>'
        '<div class="moreless__full">Growing up in poverty.<br/><br/>Transported.</div>'
        '</div>',
      );
      final info = Ranobes.parseNovel(page, novelUrl)!;
      expect(info.description, 'Growing up in poverty.\n\nTransported.');
    });

    test('finished translations give their count as Translated', () {
      final page = novelPage.replaceFirst(
        '<li>Available: <span class="grey">3 chapters</li>',
        '<li>In original: <span class="grey">1432 chapters</li>'
            '<li>Translated: <span class="grey">1434 chapters</li>',
      );
      expect(Ranobes.parseNovel(page, novelUrl)!.chapterCount, 1434);
    });

    test('chapter list numbers count back from the newest', () {
      final page = Ranobes.parseChapterList(chapterListPage(count: 3))!;
      expect(page.chapterCount, 3);
      expect(page.bookUrl, novelUrl);
      expect([for (final c in page.chapters) c.number], [3, 2, 1]);
      expect(page.chapters.first.title, 'Chapter 3: Dead Ends');
      expect(page.chapters.first.date, DateTime(2026, 10, 22, 10));
    });

    test('chapter text comes without the ads, in whole paragraphs', () {
      final html = chapterPage(
        title: 'Chapter 2: Liberation',
        paragraphs: [
          'A figure fell from the lightless sky, streaking across its dark '
              'expanse like a star.',
          'Soon enough, there was silence once more.',
        ],
        prev: chapter1Url,
        next: chapter3Url,
      );
      final chapter = Ranobes.parseChapter(html, chapter2Url)!;
      expect(chapter.title, 'Chapter 2: Liberation');
      expect(chapter.novelTitle, 'Shadow Slave');
      expect(chapter.paragraphs, [
        'A figure fell from the lightless sky, streaking across its dark '
            'expanse like a star.',
        'Soon enough, there was silence once more.',
        'The end of the chapter.',
      ]);
      expect(chapter.prevUrl, chapter1Url);
      expect(chapter.nextUrl, chapter3Url);
    });

    test('the first and latest chapters have one neighbour', () {
      final first = Ranobes.parseChapter(
        chapterPage(
          title: 'Chapter 1',
          paragraphs: ['One.'],
          next: chapter2Url,
        ),
        chapter1Url,
      )!;
      expect(first.prevUrl, isNull);
      expect(first.nextUrl, chapter2Url);
    });
  });

  group('novel library', () {
    late AppDatabase db;
    late FakeFetcher fetcher;
    late NovelRepository repo;

    String chapter(String title, {String? prev, String? next}) => chapterPage(
      title: title,
      paragraphs: ['$title begins here and goes on for a while.'],
      prev: prev,
      next: next,
    );

    setUp(() async {
      db = await openTestDatabase();
      fetcher = FakeFetcher({
        novelUrl: novelPage,
        chapterListUrl: chapterListPage(count: 3),
        Ranobes.searchUrl('shadow'): searchPage,
        chapter1Url: chapter('Chapter 1', next: chapter2Url),
        chapter2Url: chapter('Chapter 2', prev: chapter1Url, next: chapter3Url),
        chapter3Url: chapter('Chapter 3', prev: chapter2Url),
      });
      fetcher.redirects['https://ranobes.net/chapters/1205249/first'] =
          chapter1Url;
      repo = NovelRepository(db, fetcher);
    });

    tearDown(() => db.close());

    test('search by name or by link', () async {
      expect((await repo.search('shadow')).single.title, 'Shadow Slave');
      final byLink = await repo.search(chapter2Url);
      expect(byLink.single.url, novelUrl);
      expect(
        () => repo.search('https://example.com/novel'),
        throwsA(isA<Exception>()),
      );
    });

    test('adding from a chapter link finds the novel, once', () async {
      final novel = await repo.addNovel(chapter2Url);
      expect(novel.title, 'Shadow Slave');
      expect(novel.author, 'Guiltythree');
      expect(novel.chapterCount, 3);
      expect(novel.started, isFalse);
      final again = await repo.addNovel(novelUrl);
      expect(again.id, novel.id);
      expect(await repo.listNovels(), hasLength(1));
    });

    test('a page without a chapter count takes it from the list', () async {
      fetcher.responses[novelUrl] = novelPage.replaceFirst(
        '<li>Available: <span class="grey">3 chapters</li>',
        '',
      );
      fetcher.responses[chapterListUrl] = chapterListPage(count: 3);
      expect((await repo.addNovel(novelUrl)).chapterCount, 3);
    });

    test('a background connection closing leaves the app open', () async {
      final dir = await Directory.systemTemp.createTemp('scry_bg');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/scry.db';
      final app = await AppDatabase.open(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      final background = await AppDatabase.open(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
        singleInstance: false,
      );
      await background.close();
      await NovelRepository(app, fetcher).addNovel(novelUrl);
      expect(await app.listNovels(), hasLength(1));
      await app.close();
    });

    test('new chapters are announced once, and not after reading', () async {
      var novel = await repo.addNovel(novelUrl);
      // Not started: nothing to announce.
      fetcher.responses[chapterListUrl] = chapterListPage(count: 4);
      expect(await repo.chaptersToAnnounce(), isEmpty);
      fetcher.responses[chapterListUrl] = chapterListPage(count: 3);

      final second = await repo.chapter(novel, chapter2Url);
      novel = await repo.saveProgress(
        novel,
        chapter: second,
        number: 2,
        progress: 1,
      );
      expect(await repo.chaptersToAnnounce(), isEmpty);

      fetcher.responses[chapterListUrl] = chapterListPage(count: 4);
      final fresh = await repo.chaptersToAnnounce();
      expect(fresh.single.newChapters, 1);
      // Announced already.
      expect(await repo.chaptersToAnnounce(), isEmpty);

      // Another one: the notification counts both since last read.
      fetcher.responses[chapterListUrl] = chapterListPage(count: 5);
      expect((await repo.chaptersToAnnounce()).single.newChapters, 2);

      // Seen in the library: not announced again in the background.
      fetcher.responses[chapterListUrl] = chapterListPage(count: 6);
      await repo.checkForChapters((await repo.listNovels()).single);
      expect(await repo.chaptersToAnnounce(), isEmpty);
    });

    test('novels with new chapters come first in the library', () async {
      Novel novel(int book, String title, {required int count, int? seen}) =>
          Novel(
            url: 'https://ranobes.net/novels/$book-x.html',
            bookId: book,
            title: title,
            chapterCount: count,
            addedDate: DateTime(2026, 10, 1),
            chapterUrl: seen == null
                ? null
                : 'https://ranobes.net/x-$book/1.html',
            chapterNumber: seen ?? 0,
            seenCount: seen ?? 0,
            readAt: DateTime(2026, 10, book),
          );
      // Read most recently first: C, then B, then A.
      await db.insertNovel(novel(1, 'A', count: 12, seen: 10));
      await db.insertNovel(novel(2, 'B', count: 10, seen: 10));
      await db.insertNovel(novel(3, 'C', count: 5, seen: 5));
      final library = NovelsProvider(repo);
      await library.load();
      expect([for (final n in library.novels) n.title], ['A', 'C', 'B']);
      library.dispose();
    });

    test('a check while reading keeps the place', () async {
      final novel = await repo.addNovel(novelUrl);
      final second = await repo.chapter(novel, chapter2Url);
      await repo.saveProgress(novel, chapter: second, number: 2, progress: 0.4);
      // The check started with the novel as it was before reading.
      await repo.checkForChapters(novel);
      final stored = (await repo.listNovels()).single;
      expect(stored.chapterUrl, chapter2Url);
      expect(stored.chapterProgress, 0.4);
    });

    test('chapters are saved, so reading them again works offline', () async {
      final novel = await repo.addNovel(novelUrl);
      final first = await repo.firstChapter(novel);
      expect(first.url, chapter1Url);
      expect(first.title, 'Chapter 1');

      await repo.prefetch(novel, chapter2Url);
      fetcher.responses.clear();
      fetcher.requested.clear();
      final second = await repo.chapter(novel, chapter2Url);
      expect(second.paragraphs.first, startsWith('Chapter 2 begins'));
      expect(fetcher.requested, isEmpty);
    });

    test('the latest chapter is fetched again to find a newer one', () async {
      final novel = await repo.addNovel(novelUrl);
      final latest = await repo.chapter(novel, chapter3Url);
      expect(latest.nextUrl, isNull);

      const chapter4 =
          'https://ranobes.net/shadow-slave-v741610-1205249/4001.html';
      fetcher.responses[chapter3Url] = chapter(
        'Chapter 3',
        prev: chapter2Url,
        next: chapter4,
      );
      expect((await repo.chapter(novel, chapter3Url)).nextUrl, chapter4);

      // Offline, the saved copy still opens.
      fetcher.responses.clear();
      expect((await repo.chapter(novel, chapter3Url)).title, 'Chapter 3');
    });

    test('progress and new chapters', () async {
      var novel = await repo.addNovel(novelUrl);
      final second = await repo.chapter(novel, chapter2Url);
      novel = await repo.saveProgress(
        novel,
        chapter: second,
        number: 2,
        progress: 0.5,
      );
      expect(novel.chapterUrl, chapter2Url);
      expect(novel.chaptersLeft, 1);
      expect(novel.newChapters, 0);
      expect(novel.progress, closeTo(1.5 / 3, 0.001));

      fetcher.responses[chapterListUrl] = chapterListPage(count: 4);
      novel = await repo.checkForChapters(novel);
      expect(novel.chapterCount, 4);
      expect(novel.chaptersLeft, 2);
      // One came out since it was last read.
      expect(novel.newChapters, 1);

      final stored = (await repo.listNovels()).single;
      expect(stored.chapterProgress, 0.5);
      expect(stored.chapterTitle, 'Chapter 2');
    });

    test('upgrading from version 6 keeps the library', () async {
      final dir = await Directory.systemTemp.createTemp('scry_v7');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/scry.db';
      var file = await AppDatabase.open(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      await NovelRepository(file, fetcher).addNovel(novelUrl);
      await file.close();

      final raw = await databaseFactoryFfiNoIsolate.openDatabase(path);
      await raw.execute('ALTER TABLE novels DROP COLUMN seenCount');
      await raw.execute('ALTER TABLE novels DROP COLUMN notifiedCount');
      await raw.setVersion(6);
      await raw.close();

      file = await AppDatabase.open(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      final novels = await NovelRepository(file, fetcher).listNovels();
      expect(novels.single.title, 'Shadow Slave');
      expect(novels.single.newChapters, 0);
      await file.close();
    });

    test('removing a novel removes its saved chapters', () async {
      final novel = await repo.addNovel(novelUrl);
      await repo.chapter(novel, chapter2Url);
      expect(await db.chapterCountSaved(novel.id!), 1);
      await repo.removeNovel(novel);
      expect(await repo.listNovels(), isEmpty);
      expect(await db.chapterCountSaved(novel.id!), 0);
    });
  });
}
