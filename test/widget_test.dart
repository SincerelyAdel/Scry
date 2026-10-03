import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippefy/app.dart';
import 'package:snippefy/data/app_database.dart';
import 'package:snippefy/data/feed_repository.dart';
import 'package:snippefy/state/settings_provider.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

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
    await tester.pumpWidget(
      SnippefyApp(
        repository: repo,
        settings: SettingsProvider(prefs),
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
    expect(
      find.text('No feeds yet.\nAdd one to fill your inbox.'),
      findsOneWidget,
    );
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

    await tester.tap(find.text('Feeds'));
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

  testWidgets('dark mode and accent colour persist', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(prefs.getString('themeMode'), 'dark');

    await tester.tap(find.byTooltip('Teal'));
    await tester.pumpAndSettle();
    expect(prefs.getString('seedColor'), 'Teal');

    // A fresh settings object reads the saved values back.
    final reloaded = SettingsProvider(prefs);
    expect(reloaded.themeMode, ThemeMode.dark);
    expect(reloaded.seedName, 'Teal');
  });
}
