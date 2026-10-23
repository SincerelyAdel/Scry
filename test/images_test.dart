import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scry/data/app_database.dart';
import 'package:scry/data/feed_repository.dart';
import 'package:scry/models/paper_figure.dart';
import 'package:scry/services/feed_parser.dart';
import 'package:scry/utils/arxiv.dart';
import 'package:scry/utils/images.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

const _arxivFeed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>cs.CL updates on arXiv.org</title>
  <link>http://rss.arxiv.org/rss/cs.CL</link>
  <item>
    <title>A Paper</title>
    <link>https://arxiv.org/abs/2610.30158</link>
    <description>arXiv:2610.30158v1 Announce Type: new
Abstract: We study things.</description>
    <guid isPermaLink="false">oai:arXiv.org:2610.30158v1</guid>
  </item>
</channel></rss>''';

const _paperHtml = '''<html><head><title>Paper</title></head><body>
<figure id="S1.F1" class="ltx_figure">
  <img src="2610.30158v1/x1.png" class="ltx_graphics ltx_centering" width="400" height="200" alt="">
  <figcaption class="ltx_caption">Figure 1: Overview of the   method.</figcaption>
</figure>
<figure id="S2.F2" class="ltx_figure">
  <figure id="S2.F2.sf1" class="ltx_figure ltx_figure_panel">
    <img src="2610.30158v1/x2.png" class="ltx_graphics" alt="">
    <figcaption>(a) left</figcaption>
  </figure>
  <figure id="S2.F2.sf2" class="ltx_figure ltx_figure_panel">
    <img src="2610.30158v1/x3.png" class="ltx_graphics" alt="">
    <figcaption>(b) right</figcaption>
  </figure>
  <figcaption class="ltx_caption">Figure 2: Two panels.</figcaption>
</figure>
<figure id="S3.T1" class="ltx_table">
  <img src="2610.30158v1/table.png" class="ltx_graphics" alt="">
  <figcaption>Table 1</figcaption>
</figure>
</body></html>''';

void main() {
  group('arXiv summaries', () {
    test('split into id, type and abstract', () {
      final s = parseArxivSummary(
        'arXiv:2610.30344v1 Announce Type: new Abstract: Training Arabic models.',
      )!;
      expect(s.id, '2610.30344v1');
      expect(s.type, 'New');
      expect(s.abstract, 'Training Arabic models.');
    });

    test('handle cross-lists and line breaks', () {
      final s = parseArxivSummary(
        'arXiv:2610.1v2 Announce Type: cross-list \nAbstract:\nText.',
      )!;
      expect(s.type, 'Cross-list');
      expect(s.abstract, 'Text.');
    });

    test('ignore other text', () {
      expect(parseArxivSummary('Just a normal summary.'), isNull);
    });

    test('paper ids come from links or guids', () {
      expect(arxivId('https://arxiv.org/abs/2610.30344'), '2610.30344');
      expect(arxivId('https://arxiv.org/pdf/2610.30344v3'), '2610.30344');
      expect(arxivId(null, 'oai:arXiv.org:2610.30158v1'), '2610.30158');
      expect(arxivId('https://example.com/post'), isNull);
    });
  });

  group('arXiv figures', () {
    const page = 'https://arxiv.org/html/2610.30158';

    test('one entry per figure, sub-figures grouped, tables left out', () {
      final figures = arxivFigures(_paperHtml, pageUrl: page);
      expect(figures, hasLength(2));
      expect(figures[0].images, ['https://arxiv.org/html/2610.30158v1/x1.png']);
      expect(figures[0].caption, 'Figure 1: Overview of the method.');
      expect(figures[1].images, hasLength(2));
      expect(figures[1].caption, 'Figure 2: Two panels.');
    });

    test('the first figure can be found in part of a page', () {
      final partial = _paperHtml.substring(0, _paperHtml.indexOf('</figure>'));
      expect(
        arxivFirstFigure(partial, pageUrl: page),
        'https://arxiv.org/html/2610.30158v1/x1.png',
      );
    });

    test('figures survive a round trip through JSON', () {
      final figures = arxivFigures(_paperHtml, pageUrl: page);
      final back = PaperFigure.decodeList(PaperFigure.encodeList(figures));
      expect(back[1].images, figures[1].images);
      expect(back[1].caption, figures[1].caption);
    });
  });

  group('page images', () {
    test('first image in HTML skips icons and pixels', () {
      const html =
          '<p><img src="/emoji/smile.png"><img src="x.gif" width="1" height="1">'
          '<img src="/media/chart.png" alt="Chart"></p>';
      expect(
        firstImageInHtml(html, base: 'https://blog.example.com/post/1'),
        'https://blog.example.com/media/chart.png',
      );
      expect(firstImageInHtml('<p>No pictures</p>'), isNull);
    });

    test('lazy-loaded images use their real address', () {
      const html = '<img src="data:image/gif;base64,AAAA" data-src="/big.jpg">';
      expect(
        firstImageInHtml(html, base: 'https://a.com/'),
        'https://a.com/big.jpg',
      );
    });

    test('preview image comes from og:image, else the article', () {
      const withOg =
          '<html><head><meta property="og:image" content="/card.png"></head>';
      expect(
        pagePreviewImage(withOg, pageUrl: 'https://site.com/a/b'),
        'https://site.com/card.png',
      );
      const withoutOg =
          '<html><body><article><img src="hero.jpg"></article></body></html>';
      expect(
        pagePreviewImage(withoutOg, pageUrl: 'https://site.com/a/b'),
        'https://site.com/a/hero.jpg',
      );
    });
  });

  group('feed images', () {
    test(
      'media thumbnails, image enclosures and body images are picked up',
      () {
        const feed = '''<?xml version="1.0"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel>
  <title>T</title><link>https://t.com/</link>
  <item><title>A</title><link>https://t.com/a</link>
    <media:thumbnail url="https://t.com/a.jpg"/></item>
  <item><title>B</title><link>https://t.com/b</link>
    <enclosure url="https://t.com/b.png" type="image/png" length="1"/></item>
  <item><title>C</title><link>https://t.com/c</link>
    <description>&lt;p&gt;&lt;img src="/c.webp"&gt;&lt;/p&gt;</description></item>
  <item><title>D</title><link>https://t.com/d</link>
    <enclosure url="https://t.com/d.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>''';
        final items = parseFeed(feed, feedUrl: 'https://t.com/feed').items;
        expect(items.map((i) => i.imageUrl), [
          'https://t.com/a.jpg',
          'https://t.com/b.png',
          'https://t.com/c.webp',
          null,
        ]);
      },
    );
  });

  group('repository', () {
    late AppDatabase db;
    late FakeFetcher fetcher;
    late FeedRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      fetcher = FakeFetcher({'https://rss.arxiv.org/rss/cs.CL': _arxivFeed});
      repo = FeedRepository(db, fetcher);
      await repo.addFeed('https://rss.arxiv.org/rss/cs.CL');
    });

    tearDown(() => db.close());

    test("a paper's first figure becomes its picture, stored", () async {
      fetcher.responses['https://arxiv.org/html/2610.30158'] = _paperHtml;
      final article = (await repo.listArticles()).single;
      expect(article.imageUrl, isNull);

      final image = await repo.findImage(article);
      expect(image, 'https://arxiv.org/html/2610.30158v1/x1.png');

      final stored = (await repo.listArticles()).single;
      expect(stored.imageUrl, image);
      expect(stored.imageChecked, isTrue);
    });

    test('figures are fetched once, then read from storage', () async {
      fetcher.responses['https://arxiv.org/html/2610.30158'] = _paperHtml;
      final article = (await repo.listArticles()).single;

      final (state, figures) = await repo.loadFigures(article);
      expect(state, FiguresState.found);
      expect(figures, hasLength(2));

      fetcher.responses.remove('https://arxiv.org/html/2610.30158');
      final (again, cached) = await repo.loadFigures(article);
      expect(again, FiguresState.found);
      expect(cached, hasLength(2));
    });

    test('a paper without an HTML version is marked missing', () async {
      final article = (await repo.listArticles()).single;
      final (state, figures) = await repo.loadFigures(article);
      expect(state, FiguresState.missing);
      expect(figures, isEmpty);
      // ...and the thumbnail lookup doesn't try again either.
      await repo.findImage(article);
      expect((await repo.listArticles()).single.imageChecked, isTrue);
    });
  });

  test('upgrading from version 1 adds the columns and finds images', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('scry_upgrade');
    final path = p.join(dir.path, 'v1.db');
    final v1 = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE feeds (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'url TEXT NOT NULL UNIQUE, title TEXT NOT NULL, siteUrl TEXT, '
            'lastUpdated INTEGER, syncStatus TEXT NOT NULL DEFAULT \'never\', '
            'lastError TEXT, favicon BLOB)',
          );
          await db.execute(
            'CREATE TABLE articles (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'feedId INTEGER NOT NULL, guid TEXT NOT NULL, title TEXT NOT NULL, '
            'author TEXT, url TEXT, pubDate INTEGER, summary TEXT, '
            'content TEXT, isRead INTEGER NOT NULL DEFAULT 0, '
            'isDeleted INTEGER NOT NULL DEFAULT 0, addedDate INTEGER NOT NULL, '
            'UNIQUE (feedId, guid))',
          );
          await db.insert('feeds', {'url': 'https://b.com/feed', 'title': 'B'});
          await db.insert('articles', {
            'feedId': 1,
            'guid': 'g1',
            'title': 'Has a picture',
            'url': 'https://b.com/posts/1',
            'content': '<p><img src="/img/one.png"></p>',
            'addedDate': 1,
          });
        },
      ),
    );
    await v1.close();

    final db = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: path,
    );
    final article = (await db.listArticles()).single;
    expect(article.imageUrl, 'https://b.com/img/one.png');
    expect(article.imageChecked, isFalse);
    await db.close();
    await dir.delete(recursive: true);
  });
}
