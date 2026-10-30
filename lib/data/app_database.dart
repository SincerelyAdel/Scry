import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/article.dart';
import '../models/article_sort.dart';
import '../models/feed.dart';
import '../models/novel.dart';
import '../models/paper_figure.dart';
import '../models/passage.dart';
import '../models/topic.dart';
import '../utils/arxiv.dart';
import '../utils/html_text.dart';
import '../utils/images.dart';
import '../services/ranobes.dart';
import '../utils/readable.dart';

/// Thin wrapper over the SQLite database holding feeds and articles.
///
/// All SQL lives here so the rest of the app only deals with models.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const _fileName = 'scry.db';
  static const _version = 14;

  /// Opens (and creates or migrates) the database.
  ///
  /// [factory] and [path] exist for tests, which use an in-memory FFI
  /// database instead of the platform plugin.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
    bool singleInstance = true,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), _fileName);
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        // Background work opens its own connection: on Android a shared one
        // would be closed for the app too when that work finishes.
        singleInstance: singleInstance,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
        onUpgrade: _upgrade,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE feeds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        siteUrl TEXT,
        lastUpdated INTEGER,
        syncStatus TEXT NOT NULL DEFAULT 'never',
        lastError TEXT,
        favicon BLOB,
        topic TEXT
      )
    ''');
    // isDeleted hides an article the user swiped away while keeping its guid
    // around, so the next refresh doesn't bring it straight back.
    await db.execute('''
      CREATE TABLE articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feedId INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
        guid TEXT NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        url TEXT,
        pubDate INTEGER,
        summary TEXT,
        content TEXT,
        isRead INTEGER NOT NULL DEFAULT 0,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        addedDate INTEGER NOT NULL,
        $_imageColumns,
        $_textColumns,
        tags TEXT,
        starred INTEGER NOT NULL DEFAULT 0,
        UNIQUE (feedId, guid)
      )
    ''');
    await db.execute('CREATE INDEX idx_articles_feed ON articles(feedId)');
    await db.execute(
      'CREATE INDEX idx_articles_date ON articles(isDeleted, pubDate)',
    );
    await _createNovelTables(db);
    await _addDownloadTables(db);
    await _addSiteUrls(db);
    await _addPassages(db);
  }

  /// Added in version 7: the chapter count when the novel was last read,
  /// so the library can say how many came out since.
  static const _seenColumn = 'seenCount INTEGER NOT NULL DEFAULT 0';

  /// Added in version 8: the chapter count last announced in a
  /// notification, so each new chapter is announced once.
  static const _notifiedColumn = 'notifiedCount INTEGER NOT NULL DEFAULT 0';

  /// Added in version 6: novels from ranobes.net with the reader's place in
  /// each, and the chapters read or about to be read, kept for offline.
  static Future<void> _createNovelTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE novels (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL,
        bookId INTEGER NOT NULL UNIQUE,
        title TEXT NOT NULL,
        cover TEXT,
        author TEXT,
        status TEXT,
        description TEXT,
        chapterCount INTEGER NOT NULL DEFAULT 0,
        addedDate INTEGER NOT NULL,
        lastChecked INTEGER,
        chapterUrl TEXT,
        chapterTitle TEXT,
        chapterNumber INTEGER NOT NULL DEFAULT 0,
        chapterProgress REAL NOT NULL DEFAULT 0,
        readAt INTEGER,
        $_seenColumn,
        $_notifiedColumn
      )
    ''');
    // body is the chapter's paragraphs separated by blank lines.
    await db.execute('''
      CREATE TABLE chapters (
        url TEXT PRIMARY KEY,
        novelId INTEGER NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        novelTitle TEXT,
        body TEXT NOT NULL,
        prevUrl TEXT,
        nextUrl TEXT,
        fetchedAt INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_chapters_novel ON chapters(novelId)');
  }

  /// Added in version 2: a picture per article, and arXiv figures.
  /// figuresState is 0 not looked for, 1 found, 2 no HTML version.
  static const _imageColumns = '''
        imageUrl TEXT,
        imageChecked INTEGER NOT NULL DEFAULT 0,
        figures TEXT,
        figuresState INTEGER NOT NULL DEFAULT 0''';

  /// Added in version 3: the body's length for read-time badges, and the
  /// article's text from its web page when the feed only sends a teaser.
  static const _textColumns = '''
        wordCount INTEGER NOT NULL DEFAULT 0,
        fullContent TEXT''';

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      for (final column in _imageColumns.split(',')) {
        await db.execute('ALTER TABLE articles ADD COLUMN ${column.trim()}');
      }
      await _backfillImages(db);
    }
    if (from < 3) {
      await db.execute('ALTER TABLE feeds ADD COLUMN topic TEXT');
      for (final column in _textColumns.split(',')) {
        await db.execute('ALTER TABLE articles ADD COLUMN ${column.trim()}');
      }
      await _backfillTopicsAndLengths(db);
    }
    if (from < 4) {
      await db.execute('ALTER TABLE articles ADD COLUMN tags TEXT');
      await _backfillTags(db);
    }
    if (from < 5) {
      await db.execute(
        'ALTER TABLE articles ADD COLUMN starred INTEGER NOT NULL DEFAULT 0',
      );
      // Version 4 had a Mark all read button that was easy to hit by
      // mistake; this version removes it and gives every article back.
      await db.execute('UPDATE articles SET isRead = 0');
    }
    if (from < 6) {
      await _createNovelTables(db);
    } else {
      if (from < 7) {
        await db.execute('ALTER TABLE novels ADD COLUMN $_seenColumn');
      }
      if (from < 8) {
        await db.execute('ALTER TABLE novels ADD COLUMN $_notifiedColumn');
      }
    }
    // Versions 9 to 11 added the UVM and Bio tags and refined their words;
    // tag existing articles again.
    if (from >= 4 && from < 11) await _backfillTags(db);
    if (from < 12) await _addDownloadTables(db);
    if (from < 13) await _addSiteUrls(db);
    if (from < 14) await _addPassages(db);
  }

  /// Added in version 14: passages saved while reading, newest first in
  /// the library's drawer. They go with their novel.
  static Future<void> _addPassages(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE passages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        novelId INTEGER NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
        novelTitle TEXT NOT NULL,
        chapterUrl TEXT NOT NULL,
        chapterNumber INTEGER NOT NULL DEFAULT 0,
        chapterTitle TEXT NOT NULL,
        fromParagraph INTEGER NOT NULL,
        toParagraph INTEGER NOT NULL,
        body TEXT NOT NULL,
        savedAt INTEGER NOT NULL
      )
    ''');
  }

  /// Added in version 13: chapters from an EPUB added to a ranobes.net
  /// novel are read from the phone. Their index rows point at the saved
  /// copy (url) and keep the site's link (siteUrl), so a site link to one
  /// of them still opens the saved copy.
  static Future<void> _addSiteUrls(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE chapter_index ADD COLUMN siteUrl TEXT');
  }

  /// Added in version 12: novels imported from EPUB files, and (for a
  /// while) whole novels downloaded in the app.
  ///
  /// - novels.source is 'ranobes' or 'epub'.
  /// - chapters.keep is 1 for imported or downloaded chapters, which are
  ///   never trimmed.
  /// - chapter_index is every chapter's number, link and title, so the
  ///   chapter list works offline.
  /// - downloads was each download's progress; unused now that QuickNovel
  ///   does the downloading.
  static Future<void> _addDownloadTables(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE novels ADD COLUMN source TEXT NOT NULL DEFAULT 'ranobes'",
    );
    await db.execute(
      'ALTER TABLE chapters ADD COLUMN keep INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('''
      CREATE TABLE chapter_index (
        novelId INTEGER NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
        number INTEGER NOT NULL,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        date INTEGER,
        PRIMARY KEY (novelId, number)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_chapter_index_url ON chapter_index(url)',
    );
    await db.execute('''
      CREATE TABLE downloads (
        novelId INTEGER PRIMARY KEY REFERENCES novels(id) ON DELETE CASCADE,
        state TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL DEFAULT 0,
        message TEXT,
        updatedAt INTEGER NOT NULL
      )
    ''');
  }

  /// Added in version 4: tags from each article's own words.
  static Future<void> _backfillTags(Database db) async {
    final rows = await db.query(
      'articles',
      columns: ['id', 'title', 'summary', 'content', 'fullContent'],
    );
    final batch = db.batch();
    for (final row in rows) {
      final tags = articleTags(
        row['title'] as String,
        (row['fullContent'] ?? row['content'] ?? row['summary']) as String?,
      );
      // Always written, so tags the words no longer give are dropped.
      batch.update(
        'articles',
        {'tags': tags},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  /// The stored form of [tagsInText] for an article's title and HTML body.
  static String? articleTags(String title, String? html) =>
      topicsToString(tagsInText(title, htmlToPlainText(html)));

  /// Guesses topics for existing feeds and measures existing articles.
  /// Teasers that were already checked for a picture are checked again, so
  /// their full text gets fetched too.
  static Future<void> _backfillTopicsAndLengths(Database db) async {
    final batch = db.batch();
    for (final feed in await db.query(
      'feeds',
      columns: ['id', 'url', 'title'],
    )) {
      final topics = topicsToString(
        guessTopics(feed['url'] as String, feed['title'] as String),
      );
      if (topics != null) {
        batch.update(
          'feeds',
          {'topic': topics},
          where: 'id = ?',
          whereArgs: [feed['id']],
        );
      }
    }
    final rows = await db.query(
      'articles',
      columns: ['id', 'guid', 'url', 'summary', 'content'],
    );
    for (final row in rows) {
      final words = bodyWordCount(
        row['content'] as String?,
        row['summary'] as String?,
      );
      final url = row['url'] as String?;
      final teaser =
          words < minArticleWords &&
          url != null &&
          arxivId(url, row['guid'] as String?) == null;
      batch.update(
        'articles',
        {'wordCount': words, if (teaser) 'imageChecked': 0},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Words in a feed item's body: its content, else its summary.
  static int bodyWordCount(String? content, String? summary) {
    final body = (content?.trim().isNotEmpty ?? false) ? content : summary;
    return countWords(htmlToPlainText(body));
  }

  /// Gives articles stored before version 2 the first image in their body.
  static Future<void> _backfillImages(Database db) async {
    final rows = await db.rawQuery(
      "SELECT id, url, summary, content FROM articles "
      "WHERE imageUrl IS NULL AND (content LIKE '%<img%' OR summary LIKE '%<img%')",
    );
    final batch = db.batch();
    for (final row in rows) {
      final base = row['url'] as String?;
      final image =
          firstImageInHtml(row['content'] as String?, base: base) ??
          firstImageInHtml(row['summary'] as String?, base: base);
      if (image != null) {
        batch.update(
          'articles',
          {'imageUrl': image},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() => _db.close();

  // ---------------------------------------------------------------- feeds

  /// All feeds with their article and unread counts, or only feed [id].
  Future<List<Feed>> listFeeds({int? id}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT f.*,
             COUNT(a.id) AS articleCount,
             IFNULL(SUM(CASE WHEN a.isRead = 0 THEN 1 ELSE 0 END), 0)
               AS unreadCount
      FROM feeds f
      LEFT JOIN articles a ON a.feedId = f.id AND a.isDeleted = 0
      ${id == null ? '' : 'WHERE f.id = ?'}
      GROUP BY f.id
      ORDER BY f.title COLLATE NOCASE
    ''',
      [?id],
    );
    return rows.map(Feed.fromMap).toList();
  }

  Future<Feed?> getFeed(int id) async => (await listFeeds(id: id)).firstOrNull;

  Future<Feed?> findFeedByUrl(String url) async {
    final rows = await _db.query('feeds', where: 'url = ?', whereArgs: [url]);
    return rows.isEmpty ? null : Feed.fromMap(rows.first);
  }

  /// Inserts [feed] and returns its new id.
  Future<int> insertFeed(Feed feed) => _db.insert('feeds', feed.toMap());

  Future<void> updateFeed(Feed feed) async {
    await _db.update(
      'feeds',
      feed.toMap(),
      where: 'id = ?',
      whereArgs: [feed.id],
    );
  }

  /// Deletes the feed and, via the foreign key cascade, its articles.
  Future<void> deleteFeed(int id) async {
    await _db.delete('feeds', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------- articles

  /// Inserts articles that aren't stored yet; existing ones (same feed and
  /// guid) are left untouched so read state survives refreshes.
  ///
  /// Returns how many were new.
  Future<int> insertArticles(List<Article> articles) async {
    if (articles.isEmpty) return 0;
    final batch = _db.batch();
    for (final article in articles) {
      batch.insert(
        'articles',
        article.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    final results = await batch.commit();
    // Ignored inserts report 0 (or null on some platforms) instead of an id.
    return results.whereType<int>().where((id) => id > 0).length;
  }

  /// Lightweight rows for the inbox. Leaves out summary and content.
  Future<List<Article>> listArticles({
    ArticleSort sort = ArticleSort.newest,
    bool unreadOnly = false,
    bool starredOnly = false,
    int? feedId,
    Topic? topic,
    int limit = 100,
    int offset = 0,
  }) async {
    const date = 'COALESCE(a.pubDate, a.addedDate)';
    final orderBy = switch (sort) {
      ArticleSort.newest => '$date DESC, a.id DESC',
      ArticleSort.byFeed => 'f.title COLLATE NOCASE, $date DESC, a.id DESC',
      ArticleSort.unreadFirst => 'a.isRead ASC, $date DESC, a.id DESC',
      ArticleSort.shortest => '$_unknownLength, a.wordCount ASC, $date DESC',
      ArticleSort.longest => '$_unknownLength, a.wordCount DESC, $date DESC',
    };
    final where = <String>['a.isDeleted = 0'];
    final args = <Object?>[];
    if (unreadOnly) where.add('a.isRead = 0');
    if (starredOnly) where.add('a.starred = 1');
    if (feedId != null) {
      where.add('a.feedId = ?');
      args.add(feedId);
    }
    if (topic != null) {
      where.add(_hasTag);
      args.add('%,${topic.name},%');
    }
    final rows = await _db.rawQuery(
      '''
      SELECT a.id, a.feedId, a.guid, a.title, a.author, a.url, a.pubDate,
             a.isRead, a.addedDate, a.imageUrl, a.imageChecked, a.wordCount,
             a.tags, a.starred, f.title AS feedTitle, f.topic AS feedTopic
      FROM articles a
      JOIN feeds f ON f.id = a.feedId
      WHERE ${where.join(' AND ')}
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''',
      [...args, limit, offset],
    );
    return rows.map(Article.fromMap).toList();
  }

  /// Unread articles per feed among those with [topic], for every feed
  /// that has any. A feed can be missing the tag itself while some of its
  /// articles earn it from their own words.
  Future<Map<int, int>> tagFeedCounts(Topic topic) async {
    final rows = await _db.rawQuery(
      '''
      SELECT a.feedId AS feedId,
             SUM(CASE WHEN a.isRead = 0 THEN 1 ELSE 0 END) AS unread
      FROM articles a
      JOIN feeds f ON f.id = a.feedId
      WHERE a.isDeleted = 0 AND $_hasTag
      GROUP BY a.feedId
    ''',
      ['%,${topic.name},%'],
    );
    return {for (final r in rows) r['feedId'] as int: r['unread'] as int};
  }

  /// True when the article or its feed has the tag in the argument
  /// (`%,ml,%`).
  static const _hasTag =
      "(',' || IFNULL(f.topic, '') || ',' || IFNULL(a.tags, '') || ',') LIKE ?";

  /// Sorts articles without a read time (arXiv papers, teasers whose full
  /// text isn't fetched yet) after the rest. Matches readMinutesFor.
  static const _unknownLength =
      "CASE WHEN a.wordCount < $minArticleWords OR a.url LIKE '%arxiv.org/%' "
      'THEN 1 ELSE 0 END';

  /// The full article, including summary and content.
  Future<Article?> getArticle(int id) async {
    final rows = await _db.rawQuery(
      '''
      SELECT a.*, f.title AS feedTitle, f.topic AS feedTopic
      FROM articles a
      JOIN feeds f ON f.id = a.feedId
      WHERE a.id = ?
    ''',
      [id],
    );
    return rows.isEmpty ? null : Article.fromMap(rows.first);
  }

  /// Gives existing articles of [feedId] the images a refresh found, where
  /// they don't have one yet. Keyed by guid.
  Future<void> fillMissingImages(int feedId, Map<String, String> images) async {
    if (images.isEmpty) return;
    final batch = _db.batch();
    images.forEach((guid, url) {
      batch.update(
        'articles',
        {'imageUrl': url},
        where: 'feedId = ? AND guid = ? AND imageUrl IS NULL',
        whereArgs: [feedId, guid],
      );
    });
    await batch.commit(noResult: true);
  }

  /// Records the result of looking for an article's picture.
  Future<void> setArticleImage(int articleId, String? imageUrl) async {
    await _db.update(
      'articles',
      {'imageUrl': ?imageUrl, 'imageChecked': 1},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Stores an article's text from its web page and its new length.
  Future<void> saveFullText(
    int articleId,
    String html,
    int wordCount,
    String? tags,
  ) async {
    await _db.update(
      'articles',
      {'fullContent': html, 'wordCount': wordCount, 'tags': tags},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Sets a feed's tags.
  Future<void> setFeedTopics(int feedId, Set<Topic> topics) async {
    await _db.update(
      'feeds',
      {'topic': topicsToString(topics)},
      where: 'id = ?',
      whereArgs: [feedId],
    );
  }

  Future<(FiguresState, List<PaperFigure>)> getFigures(int articleId) async {
    final rows = await _db.query(
      'articles',
      columns: ['figures', 'figuresState'],
      where: 'id = ?',
      whereArgs: [articleId],
    );
    if (rows.isEmpty) return (FiguresState.unknown, const <PaperFigure>[]);
    final state = FiguresState.values[rows.first['figuresState'] as int];
    final json = rows.first['figures'] as String?;
    return (
      state,
      json == null ? const <PaperFigure>[] : PaperFigure.decodeList(json),
    );
  }

  Future<void> saveFigures(
    int articleId,
    FiguresState state,
    List<PaperFigure> figures,
  ) async {
    await _db.update(
      'articles',
      {'figures': PaperFigure.encodeList(figures), 'figuresState': state.index},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<int> unreadCount() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM articles WHERE isRead = 0 AND isDeleted = 0',
    );
    return rows.first['n'] as int;
  }

  Future<void> setRead(int articleId, bool isRead) async {
    await _db.update(
      'articles',
      {'isRead': isRead ? 1 : 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Stars an article to read later, or unstars it.
  Future<void> setStarred(int articleId, bool starred) async {
    await _db.update(
      'articles',
      {'starred': starred ? 1 : 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Hides an article from the inbox (see the schema note on isDeleted).
  Future<void> deleteArticle(int articleId) async {
    await _db.update(
      'articles',
      {'isDeleted': 1},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Undoes [deleteArticle].
  Future<void> restoreArticle(int articleId) async {
    await _db.update(
      'articles',
      {'isDeleted': 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  // --------------------------------------------------------------- novels

  /// The library, most recently read first.
  Future<List<Novel>> listNovels() async {
    final rows = await _db.query(
      'novels',
      orderBy: 'COALESCE(readAt, addedDate) DESC',
    );
    return rows.map(Novel.fromMap).toList();
  }

  Future<Novel?> getNovel(int id) async {
    final rows = await _db.query('novels', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Novel.fromMap(rows.first);
  }

  Future<Novel?> findNovelByBookId(int bookId) async {
    final rows = await _db.query(
      'novels',
      where: 'bookId = ?',
      whereArgs: [bookId],
    );
    return rows.isEmpty ? null : Novel.fromMap(rows.first);
  }

  Future<int> insertNovel(Novel novel) => _db.insert('novels', novel.toMap());

  Future<void> setChapterCount(int novelId, int count, DateTime checked) async {
    await _db.update(
      'novels',
      {'chapterCount': count, 'lastChecked': checked.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [novelId],
    );
  }

  /// Records that chapters up to [count] were announced.
  Future<void> setNotified(int novelId, int count) async {
    await _db.update(
      'novels',
      {'notifiedCount': count},
      where: 'id = ?',
      whereArgs: [novelId],
    );
  }

  Future<void> updateNovel(Novel novel) async {
    await _db.update(
      'novels',
      novel.toMap(),
      where: 'id = ?',
      whereArgs: [novel.id],
    );
  }

  /// Removes the novel and, via the cascade, its saved chapters.
  Future<void> deleteNovel(int id) async {
    await _db.delete('novels', where: 'id = ?', whereArgs: [id]);
  }

  Future<ChapterText?> getChapter(String url) async {
    final rows = await _db.query(
      'chapters',
      where: 'url = ?',
      whereArgs: [url],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ChapterText(
      url: url,
      title: row['title'] as String,
      novelTitle: row['novelTitle'] as String?,
      paragraphs: (row['body'] as String).split('\n\n'),
      prevUrl: row['prevUrl'] as String?,
      nextUrl: row['nextUrl'] as String?,
    );
  }

  /// Keeps a chapter for offline reading. Each novel keeps its
  /// [keepPerNovel] most recently fetched chapters, besides the ones kept
  /// for good ([keep]: imported, or downloaded by earlier versions).
  Future<void> saveChapter(
    int novelId,
    ChapterText chapter, {
    int keepPerNovel = 60,
    bool keep = false,
  }) async {
    // Reading a kept chapter again mustn't make it trimmable.
    await _db.rawInsert(
      '''
      INSERT OR REPLACE INTO chapters
        (url, novelId, title, novelTitle, body, prevUrl, nextUrl, fetchedAt,
         keep)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?,
        MAX(?, COALESCE((SELECT keep FROM chapters WHERE url = ?), 0)))
    ''',
      [
        chapter.url,
        novelId,
        chapter.title,
        chapter.novelTitle,
        chapter.paragraphs.join('\n\n'),
        chapter.prevUrl,
        chapter.nextUrl,
        DateTime.now().millisecondsSinceEpoch,
        keep ? 1 : 0,
        chapter.url,
      ],
    );
    if (!keep) await _trimChapters(novelId, keepPerNovel);
  }

  Future<void> _trimChapters(int novelId, int keepPerNovel) async {
    await _db.rawDelete(
      '''
      DELETE FROM chapters WHERE novelId = ? AND keep = 0 AND url NOT IN (
        SELECT url FROM chapters WHERE novelId = ? AND keep = 0
        ORDER BY fetchedAt DESC LIMIT ?
      )
    ''',
      [novelId, novelId, keepPerNovel],
    );
  }

  // --------------------------------------------------------- chapter index

  /// Records chapters from the novel's chapter list. Chapters added from
  /// an EPUB keep pointing at their saved copy; only their site link is
  /// noted.
  Future<void> saveIndex(int novelId, Iterable<ChapterRef> chapters) async {
    final local = await _localNumbers(novelId);
    final batch = _db.batch();
    for (final c in chapters) {
      if (local.contains(c.number)) {
        batch.update(
          'chapter_index',
          {'siteUrl': c.url},
          where: 'novelId = ? AND number = ?',
          whereArgs: [novelId, c.number],
        );
        continue;
      }
      batch.insert('chapter_index', {
        'novelId': novelId,
        'number': c.number,
        'url': c.url,
        'title': c.title,
        'date': c.date?.millisecondsSinceEpoch,
        'siteUrl': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Numbers of the novel's chapters added from an EPUB.
  Future<Set<int>> _localNumbers(int novelId) async {
    final rows = await _db.query(
      'chapter_index',
      columns: ['number'],
      where: "novelId = ? AND url LIKE 'epub://%'",
      whereArgs: [novelId],
    );
    return {for (final r in rows) r['number'] as int};
  }

  /// True when chapters from an EPUB were added to the novel.
  Future<bool> hasLocalChapters(int novelId) async {
    final rows = await _db.query(
      'chapter_index',
      columns: ['number'],
      where: "novelId = ? AND url LIKE 'epub://%'",
      whereArgs: [novelId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// The chapter whose link (saved or on the site) is [url].
  Future<ChapterRef?> indexedChapterAt(int novelId, String url) async {
    final rows = await _db.query(
      'chapter_index',
      where: 'novelId = ? AND (url = ? OR siteUrl = ?)',
      whereArgs: [novelId, url, url],
      limit: 1,
    );
    return rows.isEmpty ? null : _chapterRef(rows.first);
  }

  /// Puts [chapters] (by number) in place of the novel's chapters with
  /// those numbers, to read from the phone; [url] names each one's saved
  /// copy. Chapters added before from another EPUB are replaced.
  Future<void> attachChapters(
    int novelId,
    Map<int, ChapterText> chapters,
  ) async {
    await _db.transaction((txn) async {
      // The last EPUB's chapters go; their numbers point at the site again.
      await txn.rawDelete(
        "DELETE FROM chapters WHERE novelId = ? AND url LIKE 'epub://%'",
        [novelId],
      );
      await txn.rawUpdate(
        """
        UPDATE chapter_index SET url = siteUrl, siteUrl = NULL
        WHERE novelId = ? AND url LIKE 'epub://%' AND siteUrl IS NOT NULL
      """,
        [novelId],
      );
      await txn.rawDelete(
        "DELETE FROM chapter_index WHERE novelId = ? AND url LIKE 'epub://%'",
        [novelId],
      );
      final existing = {
        for (final r in await txn.query(
          'chapter_index',
          where: 'novelId = ?',
          whereArgs: [novelId],
        ))
          r['number'] as int: r,
      };
      final batch = txn.batch();
      final now = DateTime.now().millisecondsSinceEpoch;
      chapters.forEach((number, c) {
        batch.insert('chapters', {
          'url': c.url,
          'novelId': novelId,
          'title': c.title,
          'novelTitle': c.novelTitle,
          'body': c.paragraphs.join('\n\n'),
          'prevUrl': c.prevUrl,
          'nextUrl': c.nextUrl,
          'fetchedAt': now,
          'keep': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        final site = existing[number];
        batch.insert('chapter_index', {
          'novelId': novelId,
          'number': number,
          'url': c.url,
          // The site's title when known, so the list matches ranobes.net.
          'title': (site?['title'] as String?) ?? c.title,
          'date': site?['date'],
          'siteUrl': site?['url'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await batch.commit(noResult: true);
    });
  }

  /// Every chapter recorded for the novel, oldest first.
  Future<List<ChapterRef>> chapterIndex(int novelId) async {
    final rows = await _db.query(
      'chapter_index',
      where: 'novelId = ?',
      whereArgs: [novelId],
      orderBy: 'number',
    );
    return rows.map(_chapterRef).toList();
  }

  /// The recorded chapter [number] of the novel.
  Future<ChapterRef?> indexedChapter(int novelId, int number) async {
    final rows = await _db.query(
      'chapter_index',
      where: 'novelId = ? AND number = ?',
      whereArgs: [novelId, number],
    );
    return rows.isEmpty ? null : _chapterRef(rows.first);
  }

  static ChapterRef _chapterRef(Map<String, Object?> row) => ChapterRef(
    url: row['url'] as String,
    title: row['title'] as String,
    number: row['number'] as int,
    date: row['date'] is int
        ? DateTime.fromMillisecondsSinceEpoch(row['date'] as int)
        : null,
  );

  /// Clears what's left of downloads made in the app, which QuickNovel
  /// does now. Their chapters stay saved. Returns the novels they were for.
  Future<List<int>> clearDownloads() async {
    final rows = await _db.query('downloads', columns: ['novelId']);
    await _db.delete('downloads');
    return [for (final r in rows) r['novelId'] as int];
  }

  /// Adds a novel along with all its chapters, as when importing a book.
  /// Returns its id.
  Future<int> insertNovelWithChapters(Novel novel, List<ChapterText> chapters) {
    return _db.transaction((txn) async {
      final id = await txn.insert('novels', novel.toMap());
      final batch = txn.batch();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < chapters.length; i++) {
        final c = chapters[i];
        batch.insert('chapters', {
          'url': c.url,
          'novelId': id,
          'title': c.title,
          'novelTitle': c.novelTitle,
          'body': c.paragraphs.join('\n\n'),
          'prevUrl': c.prevUrl,
          'nextUrl': c.nextUrl,
          'fetchedAt': now,
          'keep': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        batch.insert('chapter_index', {
          'novelId': id,
          'number': i + 1,
          'url': c.url,
          'title': c.title,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      return id;
    });
  }

  Future<int> chapterCountSaved(int novelId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM chapters WHERE novelId = ?',
      [novelId],
    );
    return rows.first['n'] as int;
  }

  // ------------------------------------------------------------ passages

  /// Every saved passage, newest first.
  Future<List<Passage>> listPassages() async {
    final rows = await _db.query('passages', orderBy: 'savedAt DESC, id DESC');
    return rows.map(Passage.fromMap).toList();
  }

  Future<int> insertPassage(Passage passage) =>
      _db.insert('passages', passage.toMap());

  Future<void> deletePassage(int id) async {
    await _db.delete('passages', where: 'id = ?', whereArgs: [id]);
  }
}
