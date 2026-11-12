import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scry/data/app_database.dart';
import 'package:scry/data/novel_repository.dart';
import 'package:scry/models/feed.dart';
import 'package:scry/models/novel.dart';
import 'package:scry/models/passage.dart';
import 'package:scry/models/topic.dart';
import 'package:scry/services/epub.dart';
import 'package:scry/sync/library_sync.dart';
import 'package:scry/sync/sync_engine.dart';
import 'package:scry/sync/sync_merge.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

/// The shared file, as Drive would keep it.
class FakeDrive implements RemoteStore {
  String? body;
  int _version = 0;
  int writes = 0;

  /// Runs once, between reading and writing: another device's write.
  Future<void> Function()? meanwhile;

  @override
  Future<({String id, String version, Map<String, Object?>? content})?>
  read() async => body == null
      ? null
      : (
          id: 'file',
          version: '$_version',
          content: (jsonDecode(body!) as Map).cast<String, Object?>(),
        );

  @override
  Future<String?> version(String id) async {
    final m = meanwhile;
    meanwhile = null;
    await m?.call();
    return '$_version';
  }

  @override
  Future<void> write(String? id, Map<String, Object?> content) async {
    body = jsonEncode(content);
    _version++;
    writes++;
  }
}

/// One phone or tablet, with its own library and memory of the last sync.
class Device {
  Device._(this.db, this.repo, this.covers) {
    engine = SyncEngine(
      LibrarySync(db, repo),
      loadBase: () async => base,
      saveBase: (b) async => base = b,
    );
  }

  static Future<Device> open() async {
    sqfliteFfiInit();
    final db = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final covers = await Directory.systemTemp.createTemp('scry_sync');
    return Device._(db, NovelRepository(db, FakeFetcher({})), covers);
  }

  final AppDatabase db;
  final NovelRepository repo;
  final Directory covers;
  late final SyncEngine engine;
  SyncBase base = SyncBase.empty;

  Future<void> sync(FakeDrive drive) => engine.run(drive);

  Future<void> close() async {
    await db.close();
    await covers.delete(recursive: true);
  }

  Future<Novel> addSiteNovel() async {
    final id = await db.insertNovel(
      Novel(
        url: 'https://ranobes.net/novels/1201-the-tide-clock.html',
        bookId: 1201,
        title: 'The Tide Clock',
        author: 'R. Vell',
        chapterCount: 40,
        addedDate: DateTime(2026, 10, 1),
      ),
    );
    return (await db.getNovel(id))!;
  }

  Future<Novel> readTo(
    Novel novel,
    int chapter,
    double progress,
    DateTime at,
  ) async {
    final updated = novel.copyWith(
      chapterUrl: 'https://ranobes.net/chapters/1201/$chapter.html',
      chapterTitle: 'Chapter $chapter',
      chapterNumber: chapter,
      chapterProgress: progress,
      readAt: at,
    );
    await db.updateNovel(updated);
    return updated;
  }

  Future<Novel> only() async => (await db.listNovels()).single;
}

EpubBook _book() => EpubBook(
  title: 'The Lantern Below the Sea',
  author: 'M. Ostrava',
  chapters: [
    for (var i = 1; i <= 4; i++)
      EpubChapter(title: 'Chapter $i', paragraphs: ['Text of chapter $i.']),
  ],
);

Passage _passage(Novel novel, int chapter, {String? who}) => Passage(
  novelId: novel.id!,
  novelTitle: novel.title,
  chapterUrl: novel.isImported
      ? 'epub://${-novel.bookId}/$chapter'
      : 'https://ranobes.net/chapters/1201/$chapter.html',
  chapterNumber: chapter,
  chapterTitle: 'Chapter $chapter',
  from: 2,
  to: 3,
  text: 'Text of chapter $chapter.',
  savedAt: DateTime(2026, 11, chapter, 9),
  character: who,
);

void main() {
  late Device tablet, phone;
  late FakeDrive drive;

  setUp(() async {
    tablet = await Device.open();
    phone = await Device.open();
    drive = FakeDrive();
  });

  tearDown(() async {
    await tablet.close();
    await phone.close();
  });

  test('a new device gets the library, places and passages', () async {
    final novel = await tablet.readTo(
      await tablet.addSiteNovel(),
      12,
      0.4,
      DateTime(2026, 11, 3),
    );
    await tablet.db.insertPassage(_passage(novel, 12, who: 'Iselde'));
    await tablet.db.insertFeed(
      const Feed(
        url: 'https://example.org/feed.xml',
        title: 'Harbour Notes',
        topics: {Topic.ml},
      ),
    );

    await tablet.sync(drive);
    await phone.sync(drive);

    final there = await phone.only();
    expect(there.title, 'The Tide Clock');
    expect(there.chapterNumber, 12);
    expect(there.chapterProgress, 0.4);
    expect(there.chapterUrl, 'https://ranobes.net/chapters/1201/12.html');
    final passage = (await phone.db.listPassages()).single;
    expect(passage.character, 'Iselde');
    expect(passage.novelId, there.id);
    final feed = (await phone.db.listFeeds()).single;
    expect(feed.title, 'Harbour Notes');
    expect(feed.topics, {Topic.ml});
  });

  test('reading on one device moves the place on the other', () async {
    await tablet.readTo(
      await tablet.addSiteNovel(),
      3,
      0.5,
      DateTime(2026, 11, 1),
    );
    await tablet.sync(drive);
    await phone.sync(drive);

    await phone.readTo(await phone.only(), 9, 0.2, DateTime(2026, 11, 2));
    await phone.sync(drive);
    await tablet.sync(drive);

    final novel = await tablet.only();
    expect(novel.chapterNumber, 9);
    expect(novel.chapterProgress, 0.2);
  });

  test('when both read, the one read last wins', () async {
    await tablet.readTo(
      await tablet.addSiteNovel(),
      3,
      0.5,
      DateTime(2026, 11, 1),
    );
    await tablet.sync(drive);
    await phone.sync(drive);

    await tablet.readTo(await tablet.only(), 5, 0.1, DateTime(2026, 11, 4));
    await phone.readTo(await phone.only(), 4, 0.9, DateTime(2026, 11, 3));
    await phone.sync(drive);
    await tablet.sync(drive);
    await phone.sync(drive);

    expect((await phone.only()).chapterNumber, 5);
    expect((await tablet.only()).chapterNumber, 5);
  });

  test('removing and renaming carry over; nothing else comes back', () async {
    final novel = await tablet.addSiteNovel();
    final kept = await tablet.db.insertPassage(_passage(novel, 2));
    final gone = await tablet.db.insertPassage(_passage(novel, 5));
    await tablet.sync(drive);
    await phone.sync(drive);

    await tablet.db.deletePassage(gone);
    await tablet.db.setPassageCharacter(kept, 'Corwen');
    await tablet.sync(drive);
    await phone.sync(drive);

    final passages = await phone.db.listPassages();
    expect(passages.map((p) => p.chapterNumber), [2]);
    expect(passages.single.character, 'Corwen');

    // Syncing again changes nothing on either side.
    final writes = drive.writes;
    await phone.sync(drive);
    await tablet.sync(drive);
    expect(drive.writes, writes);
    expect(await tablet.db.listPassages(), hasLength(1));
  });

  test('a novel removed on one device goes from the other', () async {
    await tablet.addSiteNovel();
    await tablet.sync(drive);
    await phone.sync(drive);

    await phone.repo.removeNovel(await phone.only());
    await phone.sync(drive);
    await tablet.sync(drive);

    expect(await tablet.db.listNovels(), isEmpty);
  });

  test('turning sync on with two libraries joins them', () async {
    await tablet.addSiteNovel();
    await phone.db.insertFeed(
      const Feed(url: 'https://example.org/a.xml', title: 'A'),
    );
    await tablet.sync(drive);
    await phone.sync(drive);
    await tablet.sync(drive);

    expect(await tablet.db.listFeeds(), hasLength(1));
    expect(await phone.db.listNovels(), hasLength(1));
  });

  test('an imported book waits until the same book is on the device', () async {
    var book = await tablet.repo.importBook(
      _book(),
      coverDir: tablet.covers.path,
    );
    book = book.copyWith(
      chapterUrl: 'epub://${-book.bookId}/3',
      chapterTitle: 'Chapter 3',
      chapterNumber: 3,
      chapterProgress: 0.6,
      readAt: DateTime(2026, 11, 5),
    );
    await tablet.db.updateNovel(book);
    await tablet.db.insertPassage(_passage(book, 2, who: 'Iselde'));
    await tablet.sync(drive);

    // Not on the phone: nothing to show, and nothing lost either.
    await phone.sync(drive);
    expect(await phone.db.listNovels(), isEmpty);
    await phone.sync(drive);
    await tablet.sync(drive);
    expect(await tablet.db.listPassages(), hasLength(1));

    // Imported on the phone: its place and passage arrive.
    final copy = await phone.repo.importBook(
      _book(),
      coverDir: phone.covers.path,
    );
    await phone.sync(drive);
    final there = await phone.only();
    expect(there.id, copy.id);
    expect(there.chapterNumber, 3);
    expect(there.chapterUrl, 'epub://${-copy.bookId}/3');
    final passage = (await phone.db.listPassages()).single;
    expect(passage.character, 'Iselde');
    expect(passage.chapterUrl, 'epub://${-copy.bookId}/2');
  });

  test('a write from another device mid-sync is merged in', () async {
    await tablet.addSiteNovel();
    await tablet.sync(drive);
    await phone.sync(drive);

    final novel = await tablet.only();
    await tablet.db.insertPassage(_passage(novel, 7));
    // The phone saves a passage and syncs while the tablet is syncing.
    final there = await phone.only();
    await phone.db.insertPassage(_passage(there, 8));
    drive.meanwhile = () => phone.sync(drive);
    await tablet.sync(drive);
    await phone.sync(drive);

    expect(
      (await tablet.db.listPassages()).map((p) => p.chapterNumber).toSet(),
      {7, 8},
    );
    expect(
      (await phone.db.listPassages()).map((p) => p.chapterNumber).toSet(),
      {7, 8},
    );
  });

  test('fingerprints ignore key order and meta', () {
    expect(
      SyncMerge.print({
        'a': 1,
        'b': [1, 2],
        'meta': {'x': 1},
      }),
      SyncMerge.print({
        'b': [1, 2],
        'a': 1,
        'meta': {'x': 2},
      }),
    );
  });
}
