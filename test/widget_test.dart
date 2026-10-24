import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scry/app.dart';
import 'package:scry/data/app_database.dart';
import 'package:scry/data/feed_repository.dart';
import 'package:scry/data/novel_repository.dart';
import 'package:scry/screens/article_detail_screen.dart';
import 'package:scry/widgets/article_tile.dart';
import 'package:scry/state/settings_provider.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';
import 'support/ranobes_fixtures.dart';

void main() {
  late AppDatabase db;
  late FakeFetcher fetcher;
  late FeedRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await openTestDatabase();
    fetcher = FakeFetcher();
    repo = FeedRepository(db, fetcher);
  });

  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    // A phone-sized screen, tall enough for every test article.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScryApp(
        repository: repo,
        settings: SettingsProvider(prefs),
        novels: NovelRepository(db, fetcher),
        refreshOnLaunch: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> seedFeeds(WidgetTester tester) async {
    await tester.runAsync(() async {
      fetcher.responses['https://example.com/feed'] = rss2Feed;
      fetcher.responses['https://atom.example.org/feed.xml'] = atomFeed;
      await repo.addFeed('https://example.com/feed');
      await repo.addFeed('https://atom.example.org/feed.xml');
    });
  }

  testWidgets('empty inbox invites adding a feed', (tester) async {
    await pumpApp(tester);
    expect(find.text('No feeds yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add feed'), findsOneWidget);
  });

  testWidgets('adding a feed fills the inbox', (tester) async {
    fetcher.responses['https://example.com/feed'] = rss2Feed;
    await pumpApp(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add feed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'example.com/feed');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Second post'), findsOneWidget);
    expect(find.text('First post'), findsOneWidget);
  });

  testWidgets('add dialog shows errors inline', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add feed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nothing.example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Server returned 404'), findsOneWidget);
  });

  testWidgets('unified inbox merges feeds newest first', (tester) async {
    await seedFeeds(tester);
    await pumpApp(tester);

    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where(
          (s) => const [
            'Entry & more',
            'Second post',
            'Updated only',
            'First post',
          ].contains(s),
        )
        .toList();
    expect(titles, [
      'Entry & more',
      'Second post',
      'Updated only',
      'First post',
    ]);
    // Badge on the Inbox tab shows the unread count.
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('opening an article shows its body and marks it read', (
    tester,
  ) async {
    await seedFeeds(tester);
    await pumpApp(tester);

    await tester.tap(find.text('Second post'));
    await tester.pumpAndSettle();

    expect(find.textContaining('By Ada'), findsOneWidget);
    expect(find.textContaining('Full body here.'), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
    expect(find.byTooltip('Mark as unread'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    final stored = await tester.runAsync(() => repo.unreadCount());
    expect(stored, 3);
  });

  testWidgets('swipe left deletes with undo', (tester) async {
    await seedFeeds(tester);
    await pumpApp(tester);

    await tester.drag(find.text('First post'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('First post'), findsNothing);
    expect(find.text('Article deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('First post'), findsOneWidget);
  });

  testWidgets('swipe right toggles read without removing', (tester) async {
    await seedFeeds(tester);
    await pumpApp(tester);

    await tester.drag(find.text('First post'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('First post'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('feeds tab lists feeds and filters the inbox', (tester) async {
    await seedFeeds(tester);
    await pumpApp(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Feeds'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Atom Example'), findsOneWidget);
    expect(find.text('Example & Co Blog'), findsOneWidget);
    expect(find.textContaining('2 articles · 2 unread'), findsNWidgets(2));

    await tester.tap(find.text('Atom Example'));
    await tester.pumpAndSettle();
    expect(find.text('Entry & more'), findsOneWidget);
    expect(find.text('Second post'), findsNothing);

    await tester.tap(find.byTooltip('Show all feeds'));
    await tester.pumpAndSettle();
    expect(find.text('Second post'), findsOneWidget);
  });

  testWidgets('starring keeps an article under Starred', (tester) async {
    await seedFeeds(tester);
    await pumpApp(tester);

    await tester.tap(find.text('Starred'));
    await tester.pumpAndSettle();
    expect(find.text('No starred articles'), findsOneWidget);

    // Everything seeded is unread, so Unread lists it all.
    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Star for later').at(1));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unstar'), findsOneWidget);

    await tester.tap(find.text('Starred'));
    await tester.pumpAndSettle();
    expect(find.text('Second post'), findsOneWidget);
    expect(find.text('First post'), findsNothing);
    expect(find.text('Mark all read'), findsNothing);
  });

  /// Two fingers pinching in (zooming out) over [at].
  Future<void> pinchIn(
    WidgetTester tester,
    Offset at, {
    double by = 120,
  }) async {
    final left = await tester.startGesture(at - const Offset(150, 0));
    final right = await tester.startGesture(at + const Offset(150, 0));
    for (var i = 0; i < 6; i++) {
      await left.moveBy(Offset(by / 6, 0));
      await right.moveBy(Offset(-by / 6, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
  }

  testWidgets('pinching out closes an article', (tester) async {
    await seedFeeds(tester);
    await pumpApp(tester);

    await tester.tap(find.text('Second post'));
    await tester.pumpAndSettle();
    expect(find.text('Open in browser'), findsOneWidget);

    await pinchIn(tester, tester.getCenter(find.textContaining('Full body')));
    expect(find.text('Open in browser'), findsNothing);
    expect(find.text('First post'), findsOneWidget);
  });

  testWidgets('a small pinch leaves the article open', (tester) async {
    await seedFeeds(tester);
    await pumpApp(tester);
    await tester.tap(find.text('Second post'));
    await tester.pumpAndSettle();

    await pinchIn(
      tester,
      tester.getCenter(find.textContaining('Full body')),
      by: 30,
    );
    expect(find.text('Open in browser'), findsOneWidget);
  });

  testWidgets('swiping sideways moves between articles', (tester) async {
    await seedFeeds(tester);
    await pumpApp(tester);
    // The inbox order, top to bottom.
    final tiles = find.byType(ArticleTile).evaluate().toList()
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a.widget))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
      );
    final titles = [
      for (final t in tiles) (t.widget as ArticleTile).article.title,
    ];
    final top = titles[0];
    final below = titles[1];

    // Titles on the open article (the inbox stays painted beneath it).
    Finder onPage(String title) => find.descendant(
      of: find.byType(ArticleDetailScreen),
      matching: find.text(title),
    );

    await tester.tap(find.text(top));
    await tester.pumpAndSettle();
    expect(onPage(top), findsOneWidget);

    // Left for the next. One big step, as a fast swipe arrives: text
    // selection, which also follows sideways drags, must not take it.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView).last),
    );
    await gesture.moveBy(const Offset(-400, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(onPage(below), findsOneWidget);
    expect(onPage(top), findsNothing);

    // Right goes back.
    await tester.fling(find.byType(ListView).last, const Offset(400, 0), 1500);
    await tester.pumpAndSettle();
    expect(onPage(top), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
  });

  testWidgets('a short sideways drag stays on the article', (tester) async {
    await seedFeeds(tester);
    await pumpApp(tester);
    await tester.tap(find.text('Second post'));
    await tester.pumpAndSettle();

    await tester.timedDrag(
      find.textContaining('Full body here.'),
      const Offset(-60, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open in browser'), findsOneWidget);
    expect(find.textContaining('Full body here.'), findsOneWidget);
  });

  testWidgets('novels: switch sides, continue reading, next chapter', (
    tester,
  ) async {
    final novels = NovelRepository(db, fetcher);
    await tester.runAsync(() async {
      String page(String title, {String? prev, String? next}) => chapterPage(
        title: title,
        paragraphs: ['$title text, long enough to read.'],
        prev: prev,
        next: next,
      );
      fetcher.responses
        ..[novelUrl] = novelPage
        ..[chapterListUrl] = chapterListPage(count: 3)
        ..[chapter2Url] = page(
          'Chapter 2',
          prev: chapter1Url,
          next: chapter3Url,
        )
        ..[chapter3Url] = page(
          'Chapter 3',
          prev: chapter2Url,
          next: 'https://ranobes.net/shadow-slave-v741610-1205249/4001.html',
        );
      final novel = await novels.addNovel(novelUrl);
      final second = await novels.chapter(novel, chapter2Url);
      await novels.chapter(novel, chapter3Url);
      await novels.saveProgress(novel, chapter: second, number: 2, progress: 0);
      // Nothing else is fetched while the test runs.
      fetcher.responses.clear();
    });
    await pumpApp(tester);

    await tester.tap(find.text('Novels'));
    await tester.pumpAndSettle();
    expect(find.text('Shadow Slave'), findsOneWidget);
    expect(find.text('2 of 3  ·  1 to go'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 2 text, long enough to read.'), findsOneWidget);

    // A swipe left is the next chapter, right the one before.
    await tester.fling(
      find.text('Chapter 2 text, long enough to read.'),
      const Offset(-400, 0),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.text('Chapter 3 text, long enough to read.'), findsOneWidget);
    await tester.fling(
      find.text('Chapter 3 text, long enough to read.'),
      const Offset(400, 0),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.text('Chapter 2 text, long enough to read.'), findsOneWidget);

    await tester.ensureVisible(find.text('Next chapter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next chapter'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 3 text, long enough to read.'), findsOneWidget);

    // Pinching out goes to the novel's page, under the reader.
    await pinchIn(
      tester,
      tester.getCenter(find.text('Chapter 3 text, long enough to read.')),
    );
    expect(find.text('Chapter 3 text, long enough to read.'), findsNothing);
    expect(find.text('CHAPTERS'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('All 3 read'), findsOneWidget);
    expect(prefs.getString('appMode'), 'novels');

    // And back to the feeds.
    await tester.tap(find.text('Feeds'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsWidgets);
  });

  testWidgets('starts dark; theme choice persists', (tester) async {
    await pumpApp(tester);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.text('Scry'), findsOneWidget);

    // Settings open from the gear in the header.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    expect(prefs.getString('themeMode'), 'light');

    // The header toggle flips straight back to dark.
    await tester.tap(find.byIcon(Icons.dark_mode_outlined).first);
    await tester.pumpAndSettle();
    expect(prefs.getString('themeMode'), 'dark');

    // A fresh settings object reads the saved value back.
    expect(SettingsProvider(prefs).themeMode, ThemeMode.dark);
  });
}
