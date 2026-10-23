import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/article.dart';
import '../models/article_sort.dart';
import '../models/feed.dart';

/// Thin wrapper over the SQLite database holding feeds and articles.
///
/// All SQL lives here so the rest of the app only deals with models.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const _fileName = 'feedviewer.db';
  static const _version = 1;

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
        favicon BLOB
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
        UNIQUE (feedId, guid)
      )
    ''');
    await db.execute('CREATE INDEX idx_articles_feed ON articles(feedId)');
    await db.execute(
      'CREATE INDEX idx_articles_date ON articles(isDeleted, pubDate)',
    );
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
    final rows = await _db.rawQuery(
      '''
      SELECT a.id, a.feedId, a.guid, a.title, a.author, a.url, a.pubDate,
             a.isRead, a.addedDate, f.title AS feedTitle
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
      SELECT a.*, f.title AS feedTitle
      FROM articles a
      JOIN feeds f ON f.id = a.feedId
      WHERE a.id = ?
    ''',
      [id],
    );
    return rows.isEmpty ? null : Article.fromMap(rows.first);
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
