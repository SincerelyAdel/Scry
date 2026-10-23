import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/article.dart';
import '../models/article_sort.dart';
import '../models/feed.dart';
import '../models/paper_figure.dart';
import '../models/topic.dart';
import '../utils/arxiv.dart';
import '../utils/html_text.dart';
import '../utils/images.dart';
import '../utils/readable.dart';

/// Thin wrapper over the SQLite database holding feeds and articles.
///
/// All SQL lives here so the rest of the app only deals with models.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const _fileName = 'scry.db';
  static const _version = 3;

  /// Opens (and creates or migrates) the database.
  ///
  /// [factory] and [path] exist for tests, which use an in-memory FFI
  /// database instead of the platform plugin.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), _fileName);
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
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
        UNIQUE (feedId, guid)
      )
    ''');
    await db.execute('CREATE INDEX idx_articles_feed ON articles(feedId)');
    await db.execute(
      'CREATE INDEX idx_articles_date ON articles(isDeleted, pubDate)',
    );
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
  }

  /// Guesses topics for existing feeds and measures existing articles.
  /// Teasers that were already checked for a picture are checked again, so
  /// their full text gets fetched too.
  static Future<void> _backfillTopicsAndLengths(Database db) async {
    final batch = db.batch();
    for (final feed in await db.query(
      'feeds',
      columns: ['id', 'url', 'title'],
    )) {
      final topic = guessTopic(feed['url'] as String, feed['title'] as String);
      if (topic != null) {
        batch.update(
          'feeds',
          {'topic': topic.name},
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
    };
    final where = <String>['a.isDeleted = 0'];
    final args = <Object?>[];
    if (unreadOnly) where.add('a.isRead = 0');
    if (feedId != null) {
      where.add('a.feedId = ?');
      args.add(feedId);
    }
    if (topic != null) {
      where.add('f.topic = ?');
      args.add(topic.name);
    }
    final rows = await _db.rawQuery(
      '''
      SELECT a.id, a.feedId, a.guid, a.title, a.author, a.url, a.pubDate,
             a.isRead, a.addedDate, a.imageUrl, a.imageChecked, a.wordCount,
             f.title AS feedTitle, f.topic AS feedTopic
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
  Future<void> saveFullText(int articleId, String html, int wordCount) async {
    await _db.update(
      'articles',
      {'fullContent': html, 'wordCount': wordCount},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Sets a feed's topic, or clears it with null.
  Future<void> setFeedTopic(int feedId, Topic? topic) async {
    await _db.update(
      'feeds',
      {'topic': topic?.name},
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

  /// Marks every article read, or just one feed's when [feedId] is given.
  Future<void> markAllRead({int? feedId}) async {
    await _db.update(
      'articles',
      {'isRead': 1},
      where: feedId == null ? 'isRead = 0' : 'isRead = 0 AND feedId = ?',
      whereArgs: feedId == null ? null : [feedId],
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
}
