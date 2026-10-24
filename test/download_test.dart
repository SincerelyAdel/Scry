import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scry/data/app_database.dart';
import 'package:scry/data/novel_repository.dart';
import 'package:scry/models/novel.dart';
import 'package:scry/models/novel_download.dart';
import 'package:scry/services/epub.dart';
import 'package:scry/services/feed_fetcher.dart';
import 'package:scry/services/novel_downloader.dart';
import 'package:scry/services/ranobes.dart';

import 'support/fakes.dart';
import 'support/ranobes_fixtures.dart';

/// Answers like ranobes.net's human check for the links in [blocked].
class CheckingFetcher extends FakeFetcher {
  final Set<String> blocked = {};

  @override
  Future<FetchedDocument> fetchText(String url) {
    if (blocked.contains(url)) throw HumanCheckRequired(url);
    return super.fetchText(url);
  }
}

String chapterLink(int n) =>
    'https://ranobes.net/shadow-slave-v741610-1205249/$n.html';

/// A novel of [count] chapters, its list [perPage] to a page.
void serveNovel(FakeFetcher fetcher, {required int count, int perPage = 2}) {
  final pages = (count / perPage).ceil();
  for (var page = 1; page <= pages; page++) {
    final rows = [
      for (var i = 0; i < perPage; i++)
        if (count - (page - 1) * perPage - i >= 1)
          jsonEncode({
            'id': '${count - (page - 1) * perPage - i}',
            'title': 'Chapter ${count - (page - 1) * perPage - i}',
            'date': '2026-10-20 10:00:00',
            'link': chapterLink(count - (page - 1) * perPage - i),
          }),
    ];
    fetcher.responses[Ranobes.chapterListUrl(1205249, page)] =
        '<html><body><script>window.__DATA__ = {"book_title":"Shadow Slave",'
        '"book_link":"$novelUrl","book_id":1205249,"chapters":[${rows.join(',')}],'
        '"pages_count":$pages,"count_all":$count,"cstart":$page,'
        '"limit":$perPage,"search":""}</script></body></html>';
  }
  for (var n = 1; n <= count; n++) {
    fetcher.responses[chapterLink(n)] = chapterPage(
      title: 'Chapter $n',
      paragraphs: ['Text of chapter $n, long enough to read.'],
      prev: n > 1 ? chapterLink(n - 1) : null,
      next: n < count ? chapterLink(n + 1) : null,
    );
  }
}

void main() {
  late AppDatabase db;
  late CheckingFetcher fetcher;
  late NovelRepository repo;
  late Novel novel;

  setUp(() async {
    db = await openTestDatabase();
    fetcher = CheckingFetcher();
    repo = NovelRepository(db, fetcher);
    fetcher.responses[novelUrl] = novelPage;
    serveNovel(fetcher, count: 5);
    novel = await repo.addNovel(novelUrl);
  });

  tearDown(() => db.close());

  NovelDownloader downloader() => NovelDownloader(db, fetcher);

  group('downloading a novel', () {
    test('saves every chapter from every list page', () async {
      await repo.queueDownload(novel);
      expect(await downloader().run(), DownloadRun.finished);

      final download = (await repo.download(novel.id!))!;
      expect(download.state, DownloadState.done);
      expect(download.done, 5);
      expect(download.total, 5);
      expect(
        [for (final c in await repo.chapterIndex(novel.id!)) c.number],
        [1, 2, 3, 4, 5],
      );
      expect(await db.chapterCountSaved(novel.id!), 5);
      expect((await repo.getNovel(novel.id!))!.chapterCount, 5);

      // Offline from here on: everything reads from the device.
      fetcher.responses.clear();
      final first = await repo.firstChapter(novel);
      expect(first.title, 'Chapter 1');
      expect(first.paragraphs.join(' '), contains('Text of chapter'));
      final last = await repo.chapter(novel, chapterLink(5));
      expect(last.title, 'Chapter 5');
    });

    test('downloaded chapters outlast the usual trim', () async {
      await repo.queueDownload(novel);
      await downloader().run();
      // Reading something else trims read chapters down to one...
      await db.saveChapter(
        novel.id!,
        const ChapterText(
          url: 'https://ranobes.net/shadow-slave-v741610-1205249/99.html',
          title: 'Other',
          paragraphs: ['x'],
        ),
        keepPerNovel: 1,
      );
      // ...but not the downloaded ones, even after reading one again.
      await db.saveChapter(
        novel.id!,
        (await db.getChapter(chapterLink(2)))!,
        keepPerNovel: 1,
      );
      expect(await db.chapterCountSaved(novel.id!), 6);
      expect(await db.downloadedCount(novel.id!), 5);

      // Removing the download lets them go again.
      await repo.removeDownload(novel.id!);
      expect(await repo.download(novel.id!), isNull);
      expect(await db.downloadedCount(novel.id!), 0);
    });

    test('carries on where it stopped when time ran out', () async {
      await repo.queueDownload(novel);
      expect(
        await downloader().run(budget: Duration.zero),
        DownloadRun.outOfTime,
      );
      expect((await repo.download(novel.id!))!.state, DownloadState.queued);

      fetcher.requested.clear();
      expect(await downloader().run(), DownloadRun.finished);
      expect(await db.downloadedCount(novel.id!), 5);
      // List page 1 again (for the count), not the chapters saved before.
      expect(
        fetcher.requested.where((u) => u == Ranobes.chapterListUrl(1205249, 1)),
        hasLength(1),
      );
    });

    test("waits at the site's human check, then carries on", () async {
      fetcher.blocked.add(chapterLink(3));
      await repo.queueDownload(novel);
      expect(await downloader().run(), DownloadRun.needsCheck);
      final paused = (await repo.download(novel.id!))!;
      expect(paused.state, DownloadState.needsCheck);
      expect(paused.done, 2);

      // Nothing to do until the check is passed.
      expect(await downloader().run(), DownloadRun.finished);
      expect((await repo.download(novel.id!))!.state, DownloadState.needsCheck);

      fetcher.blocked.clear();
      await repo.resumeAfterCheck();
      expect(await downloader().run(), DownloadRun.finished);
      expect((await repo.download(novel.id!))!.done, 5);
    });

    test('offline, it waits to try again', () async {
      fetcher.responses.remove(chapterLink(4));
      await repo.queueDownload(novel);
      // A missing page is a failed request, like being offline.
      expect(await downloader().run(), DownloadRun.offline);
      final waiting = (await repo.download(novel.id!))!;
      expect(waiting.state, DownloadState.queued);
      expect(waiting.done, 3);
    });

    test('a paused download is left alone', () async {
      await repo.queueDownload(novel);
      await repo.pauseDownload(novel.id!);
      expect(await downloader().run(), DownloadRun.finished);
      expect(await db.downloadedCount(novel.id!), 0);
      expect((await repo.download(novel.id!))!.state, DownloadState.paused);
    });

    test('new chapters download on the next go', () async {
      await repo.queueDownload(novel);
      await downloader().run();
      serveNovel(fetcher, count: 7);
      await repo.queueDownload(novel);
      expect(await downloader().run(), DownloadRun.finished);
      final download = (await repo.download(novel.id!))!;
      expect(download.done, 7);
      expect(download.state, DownloadState.done);
    });
  });

  group('EPUB books', () {
    List<int> book({bool epub3 = true, bool withCover = true}) {
      final zip = Archive();
      void add(String name, String text) =>
          zip.addFile(ArchiveFile.string(name, text));
      add('mimetype', 'application/epub+zip');
      add(
        'META-INF/container.xml',
        '<?xml version="1.0"?><container version="1.0" '
            'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles>'
            '</container>',
      );
      add(
        'OEBPS/content.opf',
        '<?xml version="1.0"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="${epub3 ? '3.0' : '2.0'}">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:title>The Long Road</dc:title>'
            '<dc:creator>A. Writer</dc:creator>'
            '<dc:description>&lt;p&gt;A trip.&lt;/p&gt;</dc:description>'
            '${epub3 ? '' : '<meta name="cover" content="img"/>'}'
            '</metadata><manifest>'
            '${epub3 ? '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' : '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'}'
            '${withCover ? '<item id="img" href="images/cover.jpg" media-type="image/jpeg"${epub3 ? ' properties="cover-image"' : ''}/>' : ''}'
            '<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="c1" href="text/one.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="c2" href="text/two%20b.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest><spine${epub3 ? '' : ' toc="ncx"'}>'
            '<itemref idref="cover"/><itemref idref="c1"/><itemref idref="c2"/>'
            '</spine></package>',
      );
      add(
        'OEBPS/nav.xhtml',
        '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
            '<nav epub:type="toc"><ol>'
            '<li><a href="text/one.xhtml">1. Leaving</a></li>'
            '<li><a href="text/two%20b.xhtml#start">2. Arriving</a></li>'
            '</ol></nav></body></html>',
      );
      add(
        'OEBPS/toc.ncx',
        '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">'
            '<navMap><navPoint id="a"><navLabel><text>One: Leaving</text></navLabel>'
            '<content src="text/one.xhtml"/></navPoint>'
            '<navPoint id="b"><navLabel><text>Two: Arriving</text></navLabel>'
            '<content src="text/two%20b.xhtml"/></navPoint></navMap></ncx>',
      );
      add(
        'OEBPS/cover.xhtml',
        '<html><body><img src="images/cover.jpg"/></body></html>',
      );
      add(
        'OEBPS/text/one.xhtml',
        '<html><head><title>one</title></head><body><h1>1. Leaving</h1>'
            '<p>They set off at dawn.</p><p>It was cold.</p></body></html>',
      );
      add(
        'OEBPS/text/two b.xhtml',
        '<html><body><h2 id="start">Arriving</h2>'
            '<p>The town was <em>quiet</em>.</p></body></html>',
      );
      if (withCover) {
        zip.addFile(ArchiveFile.bytes('OEBPS/images/cover.jpg', [1, 2, 3]));
      }
      return ZipEncoder().encode(zip);
    }

    test('an EPUB 3 book: details, cover and chapters in order', () {
      final parsed = Epub.parse(book());
      expect(parsed.title, 'The Long Road');
      expect(parsed.author, 'A. Writer');
      expect(parsed.description, 'A trip.');
      expect(parsed.cover, [1, 2, 3]);
      expect(parsed.coverExtension, 'jpg');
      // The cover page has no text, so it isn't a chapter.
      expect(
        [for (final c in parsed.chapters) c.title],
        ['1. Leaving', '2. Arriving'],
      );
      // The heading isn't repeated as the first paragraph.
      expect(parsed.chapters[0].paragraphs, [
        'They set off at dawn.',
        'It was cold.',
      ]);
      expect(parsed.chapters[1].paragraphs, ['The town was quiet.']);
    });

    test('an EPUB 2 book names chapters from its NCX', () {
      final parsed = Epub.parse(book(epub3: false));
      expect(
        [for (final c in parsed.chapters) c.title],
        ['One: Leaving', 'Two: Arriving'],
      );
      expect(parsed.cover, [1, 2, 3]);
    });

    test("a file that isn't a book says so", () {
      expect(
        () => Epub.parse(utf8.encode('hello')),
        throwsA(isA<EpubException>()),
      );
    });

    test('an imported book reads offline, without the site', () async {
      final dir = await Directory.systemTemp.createTemp('scry_covers');
      addTearDown(() => dir.delete(recursive: true));
      final imported = await repo.importBook(
        Epub.parse(book()),
        coverDir: dir.path,
      );
      expect(imported.isImported, isTrue);
      expect(imported.chapterCount, 2);
      expect(imported.status, 'Imported book');
      expect(File(imported.cover!).readAsBytesSync(), [1, 2, 3]);

      fetcher.responses.clear();
      fetcher.requested.clear();
      final first = await repo.firstChapter(imported);
      expect(first.title, '1. Leaving');
      final second = await repo.chapter(imported, first.nextUrl!);
      expect(second.title, '2. Arriving');
      expect(second.nextUrl, isNull);
      expect(second.prevUrl, first.url);
      // Nothing to check online.
      expect(await repo.checkForChapters(imported), same(imported));
      expect(fetcher.requested, isEmpty);
      expect(
        [for (final c in await repo.chapterIndex(imported.id!)) c.title],
        ['1. Leaving', '2. Arriving'],
      );

      await repo.removeNovel(imported);
      expect(File(imported.cover!).existsSync(), isFalse);
    });
  });
}
