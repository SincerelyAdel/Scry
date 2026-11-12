import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scry/data/app_database.dart';
import 'package:scry/data/novel_repository.dart';
import 'package:scry/models/novel.dart';
import 'package:scry/models/passage.dart';
import 'package:scry/services/epub.dart';
import 'package:scry/state/novels_provider.dart';
import 'package:scry/theme.dart';
import 'package:scry/widgets/colour_words.dart';
import 'package:scry/widgets/reading_ribbons.dart';
import 'package:scry/widgets/veins.dart';

import 'support/fakes.dart';

EpubBook _book({String title = 'The Lantern Below the Sea'}) => EpubBook(
  title: title,
  author: 'M. Ostrava',
  chapters: [
    for (var i = 1; i <= 4; i++)
      EpubChapter(title: 'Chapter $i', paragraphs: ['Text of chapter $i.']),
  ],
);

Passage _passage(Novel novel, int chapter, {int reading = 1, String? who}) =>
    Passage(
      novelId: novel.id!,
      novelTitle: novel.title,
      chapterUrl: 'epub://${-novel.bookId}/$chapter',
      chapterNumber: chapter,
      chapterTitle: 'Chapter $chapter',
      from: 0,
      to: 0,
      text: 'Text of chapter $chapter.',
      savedAt: DateTime(2026, 11, chapter),
      character: who,
      reading: reading,
    );

void main() {
  group('readings', () {
    late AppDatabase db;
    late NovelRepository repo;
    late NovelsProvider library;
    late Directory covers;

    setUp(() async {
      db = await openTestDatabase();
      repo = NovelRepository(db, FakeFetcher({}));
      library = NovelsProvider(repo);
      covers = await Directory.systemTemp.createTemp('scry_rereads');
    });

    tearDown(() async {
      await db.close();
      await covers.delete(recursive: true);
    });

    Future<Novel> read(Novel novel, int chapter, double progress) async {
      final text = await repo.chapter(
        novel,
        'epub://${-novel.bookId}/$chapter',
      );
      return repo.saveProgress(
        novel,
        chapter: text,
        number: chapter,
        progress: progress,
      );
    }

    test('a finished book earns a ribbon and starts again', () async {
      var novel = await repo.importBook(_book(), coverDir: covers.path);
      expect(novel.reading, 1);
      expect(novel.ribbons, 0);

      novel = await read(novel, 4, 0.5);
      expect(novel.finished, isFalse);
      novel = await read(novel, 4, 1);
      expect(novel.finished, isTrue);
      expect(novel.ribbons, 1);

      novel = await repo.readAgain(novel);
      expect(novel.reading, 2);
      expect(novel.lastEnd, 4);
      expect(novel.started, isFalse);
      expect(novel.chapterNumber, 0);
      expect(novel.ribbons, 1);

      // Kept across a restart of the app.
      final stored = (await db.getNovel(novel.id!))!;
      expect(stored.reading, 2);
      expect(stored.lastEnd, 4);
      expect(stored.chapterUrl, isNull);
    });

    test('stopping partway still marks where the reading got to', () async {
      var novel = await repo.importBook(_book(), coverDir: covers.path);
      novel = await read(novel, 2, 0.3);
      novel = await repo.readAgain(novel);
      novel = await read(novel, 1, 0.1);
      expect(novel.lastEndShare, 0.5);
      expect(novel.ribbons, 1);
    });

    test('a novel on the site never counts as finished', () {
      final novel = Novel(
        url: 'https://ranobes.net/novels/1-x.html',
        bookId: 1,
        title: 'Ongoing',
        chapterCount: 3,
        addedDate: DateTime(2026),
        chapterUrl: 'https://ranobes.net/chapters/1/3.html',
        chapterNumber: 3,
        chapterProgress: 1,
      );
      expect(novel.finished, isFalse);
      expect(novel.ribbons, 0);
    });

    test('passages remember their reading', () async {
      final novel = await repo.importBook(_book(), coverDir: covers.path);
      await repo.savePassage(_passage(novel, 2, reading: 3));
      expect((await repo.listPassages()).single.reading, 3);
    });

    test('a second copy of a book is found by title and author', () async {
      await library.addBook(_book());
      expect(library.copyOf(_book()), isNotNull);
      expect(
        library.copyOf(_book(title: 'the lantern below the sea!')),
        isNotNull,
      );
      expect(library.copyOf(_book(title: 'Another Book')), isNull);
    });

    test('merging copies keeps every reading in order', () async {
      final first = await repo.importBook(_book(), coverDir: covers.path);
      var second = await repo.importBook(_book(), coverDir: covers.path);
      await repo.savePassage(_passage(first, 3, who: 'Iselde'));
      await repo.savePassage(_passage(second, 1));
      // The first copy was read through; the second is being read now.
      await read(first, 4, 1);
      second = await read(second, 2, 0.4);
      await library.load();
      expect(library.copiesOf(library.byId(first.id)!), hasLength(1));

      final merged = await library.mergeCopies(
        library.byId(second.id)!,
        library.byId(first.id)!,
      );
      expect(merged.id, first.id);
      expect(merged.reading, 2);
      expect(merged.lastEnd, 4);
      expect(merged.chapterNumber, 2);
      expect(merged.chapterUrl, 'epub://${-first.bookId}/2');
      expect(library.novels, hasLength(1));
      expect(library.copiesOf(merged), isEmpty);

      final passages = await repo.listPassages();
      expect(passages, hasLength(2));
      expect(
        {for (final p in passages) p.chapterNumber: p.reading},
        {3: 1, 1: 2},
      );
      expect(passages.every((p) => p.novelId == first.id), isTrue);
      expect(
        passages.every(
          (p) => p.chapterUrl.startsWith('epub://${-first.bookId}/'),
        ),
        isTrue,
      );
      // Its chapter still opens.
      final chapter = await repo.chapter(merged, merged.chapterUrl!);
      expect(chapter.title, 'Chapter 2');
    });
  });

  group('readings colours and names', () {
    test('ribbons go pink, purple, crimson, indigo, gold, then again', () {
      expect(Readings.colour(1), const Color(0xFFF0559E));
      expect(Readings.colour(5), const Color(0xFFE6A817));
      expect(Readings.colour(6), Readings.colour(1));
    });

    test('readings are named in words, then numbers', () {
      expect(Readings.label(2), 'Second reading');
      expect(Readings.ordinal(10), 'tenth');
      expect(Readings.ordinal(11), '11th');
      expect(Readings.ordinal(22), '22nd');
      expect(Readings.ordinal(113), '113th');
    });
  });

  group('veins', () {
    test('pink, gold and purple come up about half the time', () {
      final random = math.Random(7);
      var common = 0;
      for (var i = 0; i < 2000; i++) {
        if (Veins.pick(random) == Veins.palettes.first) common++;
      }
      expect(common / 2000, closeTo(0.5, 0.05));
    });

    test('colour words are found whole, in any case', () {
      final spans = ColourWords.instance.spans(
        'A Crimson sky over goldenrod fields, golden light; she rose.',
        ink: Colors.black,
      );
      final veined = [
        for (final s in spans.cast<TextSpan>())
          if (s.style?.foreground != null) s.text,
      ];
      expect(veined, ['Crimson', 'golden']);
      expect(
        spans.cast<TextSpan>().map((s) => s.text).join(),
        'A Crimson sky over goldenrod fields, golden light; she rose.',
      );
    });

    testWidgets('colour words drift only when there is one to move', (
      tester,
    ) async {
      Widget page(String text) => MaterialApp(
        home: Scaffold(
          body: ColourParagraph(
            text,
            ink: Colors.black,
            style: const TextStyle(fontSize: 18),
          ),
        ),
      );
      Paint? paint() {
        final rich = tester.widget<RichText>(find.byType(RichText));
        Paint? found;
        rich.text.visitChildren((span) {
          found = span.style?.foreground;
          return found == null;
        });
        return found;
      }

      DriftClock.enabled = true;
      addTearDown(() => DriftClock.enabled = false);
      await tester.pumpWidget(page('A grey sea under a crimson sky.'));
      final before = paint();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paint(), isNot(same(before)));
      expect(tester.binding.hasScheduledFrame, isTrue);

      await tester.pumpWidget(page('Nothing coloured here.'));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('titles and ribbons draw', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(lightPalette),
          home: const Scaffold(
            body: Column(
              children: [
                VeinText(
                  'The Lantern Below the Sea',
                  style: TextStyle(fontSize: 20),
                ),
                RibbonedCover(
                  width: 100,
                  ribbons: 3,
                  cover: ColoredBox(color: Colors.blueGrey),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('The Lantern Below the Sea'), findsOneWidget);
      expect(find.byType(Ribbon), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });
}
