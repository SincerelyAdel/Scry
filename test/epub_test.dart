import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scry/data/app_database.dart';
import 'package:scry/data/novel_repository.dart';
import 'package:scry/models/novel.dart';
import 'package:scry/services/chapter_matcher.dart';
import 'package:scry/services/epub.dart';

import 'support/fakes.dart';
import 'support/ranobes_fixtures.dart';

void main() {
  late AppDatabase db;
  late FakeFetcher fetcher;
  late NovelRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    fetcher = FakeFetcher();
    repo = NovelRepository(db, fetcher);
  });

  tearDown(() => db.close());

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

    group('added to a ranobes.net novel', () {
      late Novel novel;

      setUp(() async {
        fetcher.responses
          ..[novelUrl] = novelPage
          ..[chapterListUrl] = chapterListPage(count: 3)
          ..[chapter3Url] = chapterPage(
            title: 'Chapter 3',
            paragraphs: ['From the site, long enough to read.'],
            prev: chapter2Url,
          );
        novel = await repo.addNovel(novelUrl);
        // The list has been seen once, as when the novel page opens.
        await repo.chapterPage(novel.bookId, 1, novelId: novel.id);
      });

      test(
        'its chapters are read from the phone, the rest from the site',
        () async {
          final match = await repo.attachBook(novel, Epub.parse(book()));
          expect(match.chapters.keys, [1, 2]);
          expect(await repo.hasBook(novel), isTrue);
          fetcher.requested.clear();

          // By the site's link too, e.g. where the reader left off.
          final second = await repo.chapter(novel, chapter2Url);
          expect(second.paragraphs, ['The town was quiet.']);
          final first = await repo.firstChapter(novel);
          expect(first.paragraphs.first, 'They set off at dawn.');
          expect(first.nextUrl, second.url);
          expect(fetcher.requested, isEmpty);

          // Past the book's end: the site's next chapter...
          expect(second.nextUrl, chapter3Url);
          final third = await repo.chapter(novel, second.nextUrl!);
          expect(third.paragraphs.join(' '), contains('From the site'));
          expect(fetcher.requested, [chapter3Url]);
          // ...and back again to the saved copy.
          expect(third.prevUrl, second.url);

          // The list keeps the site's titles and the saved copies.
          final index = await repo.chapterIndex(novel.id!);
          expect(index[1].title, 'Chapter 2: Liberation');
          expect(index[1].url, startsWith('epub://'));
          expect(index[2].url, chapter3Url);

          // Seeing the list again doesn't point them back at the site.
          await repo.chapterPage(novel.bookId, 1, novelId: novel.id);
          expect(
            (await repo.chapterIndex(novel.id!))[0].url,
            startsWith('epub://'),
          );

          // New chapters are still looked for, on the list's first page.
          fetcher.requested.clear();
          fetcher.responses[chapterListUrl] = chapterListPage(count: 4);
          final checked = await repo.checkForChapters(novel);
          expect(checked.chapterCount, 4);
          expect(fetcher.requested, [chapterListUrl]);
        },
      );

      test('removing them sends their chapters back to the site', () async {
        await repo.attachBook(novel, Epub.parse(book()));
        await repo.detachBook(novel);
        expect(await repo.hasBook(novel), isFalse);
        final index = await repo.chapterIndex(novel.id!);
        expect(
          [for (final c in index) c.url],
          [chapter1Url, chapter2Url, chapter3Url],
        );
      });
    });
  });

  group('matching chapter numbers', () {
    EpubChapter ch(String title, [String text = 'x']) =>
        EpubChapter(title: title, paragraphs: [text]);

    test('numbers come from the titles', () {
      expect(ChapterMatcher.numberIn('Chapter 1205: The End'), 1205);
      expect(ChapterMatcher.numberIn('Shadow Slave - Ch. 12'), 12);
      expect(ChapterMatcher.numberIn('Episode 3'), 3);
      expect(ChapterMatcher.numberIn('1205 - The End'), 1205);
      expect(ChapterMatcher.numberIn('12. Leaving'), 12);
      expect(ChapterMatcher.numberIn('Volume 2 Chapter 15'), 15);
      expect(ChapterMatcher.numberIn('Prologue'), isNull);
      expect(ChapterMatcher.numberIn('1984 Revisited'), 1984);
    });

    test('parts are joined, gaps and extras reported', () {
      final match = ChapterMatcher.match([
        ch('Prologue'),
        ch('Chapter 1'),
        ch('Chapter 2 (1)', 'a'),
        ch('Chapter 2 (2)', 'b'),
        ch('Chapter 4'),
        ch('Afterword'),
        ch('Chapter 1: again'),
      ]);
      expect(match.byOrder, isFalse);
      expect(match.chapters.keys, [1, 2, 4]);
      expect(match.chapters[2]!.paragraphs, ['a', 'b']);
      expect(match.merged, 1);
      expect(match.gaps, [3]);
      expect(match.unnumbered, ['Prologue', 'Afterword']);
      expect(match.conflicts, ['Chapter 1: again']);
    });

    test('titles without numbers go by order', () {
      final match = ChapterMatcher.match([
        ch('The Beginning'),
        ch('A Turn'),
        ch('Chapter 3'),
      ]);
      expect(match.byOrder, isTrue);
      expect(match.chapters.keys, [1, 2, 3]);
      expect(match.chapters[1]!.title, 'The Beginning');
    });
  });
}
