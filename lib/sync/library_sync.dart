import '../data/app_database.dart';
import '../data/novel_repository.dart';
import '../models/feed.dart';
import '../models/novel.dart';
import '../models/passage.dart';
import '../models/topic.dart';
import 'sync_merge.dart';

/// The parts of the library that sync, as kept in Drive.
class LibrarySnapshot {
  const LibrarySnapshot({
    this.novels = const {},
    this.passages = const {},
    this.feeds = const {},
  });

  static const format = 1;

  final Map<String, SyncItem> novels;
  final Map<String, SyncItem> passages;
  final Map<String, SyncItem> feeds;

  Map<String, Map<String, SyncItem>> get collections => {
    'novels': novels,
    'passages': passages,
    'feeds': feeds,
  };

  factory LibrarySnapshot.fromJson(Map<String, Object?> json) {
    Map<String, SyncItem> items(String name) => {
      for (final e in ((json[name] as Map?) ?? const {}).entries)
        e.key as String: (e.value as Map).cast<String, Object?>(),
    };
    return LibrarySnapshot(
      novels: items('novels'),
      passages: items('passages'),
      feeds: items('feeds'),
    );
  }

  Map<String, Object?> toJson() => {
    'format': format,
    'novels': novels,
    'passages': passages,
    'feeds': feeds,
  };
}

/// What a sync changed on this device.
class SyncOutcome {
  const SyncOutcome({
    this.novels = 0,
    this.passages = 0,
    this.feeds = 0,
    this.newFeeds = false,
  });

  final int novels;
  final int passages;
  final int feeds;

  /// Feeds were added, so their articles need fetching.
  final bool newFeeds;

  bool get any => novels + passages + feeds > 0;
}

/// Reads the library into sync items and writes merged changes back.
class LibrarySync {
  LibrarySync(this._db, this._novels);

  final AppDatabase _db;
  final NovelRepository _novels;

  // ------------------------------------------------------------------ keys

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// The same novel on every device: ranobes.net's number for the site's,
  /// title and author for imported books (their numbers are per device).
  static String novelKey(Novel n) => n.isImported
      ? 'book:${_norm(n.title)}|${_norm(n.author ?? '')}'
      : 'ranobes:${n.bookId}';

  static String passageKey(String novel, Passage p) =>
      '$novel|${p.chapterNumber}|${p.from}|${p.to}|'
      '${p.savedAt.millisecondsSinceEpoch}';

  static String? _web(String? url) =>
      url != null && url.startsWith('http') ? url : null;

  // ------------------------------------------------------------ snapshot

  static SyncItem novelItem(Novel n) => {
    'source': n.source.name,
    'title': n.title,
    'author': n.author,
    if (!n.isImported) 'url': n.url,
    if (!n.isImported) 'bookId': n.bookId,
    'cover': _web(n.cover),
    'added': n.addedDate.millisecondsSinceEpoch,
    'started': n.started,
    'chapter': n.chapterNumber,
    'chapterUrl': _web(n.chapterUrl),
    'chapterTitle': n.chapterTitle,
    // Rounded, so tiny scrolls don't count as changes.
    'progress': (n.chapterProgress * 1000).round() / 1000,
    'readAt': n.readAt?.millisecondsSinceEpoch,
    'reading': n.reading,
    'lastEnd': n.lastEnd,
    'meta': {
      'chapterCount': n.chapterCount,
      'seenCount': n.seenCount,
      'status': n.status,
      'description': n.description,
    },
  };

  static SyncItem passageItem(String novel, Passage p) => {
    'novel': novel,
    'novelTitle': p.novelTitle,
    'chapter': p.chapterNumber,
    'chapterUrl': _web(p.chapterUrl),
    'chapterTitle': p.chapterTitle,
    'from': p.from,
    'to': p.to,
    'text': p.text,
    'savedAt': p.savedAt.millisecondsSinceEpoch,
    'character': p.character,
    'reading': p.reading,
  };

  static SyncItem feedItem(Feed f) => {
    'url': f.url,
    'title': f.title,
    'siteUrl': f.siteUrl,
    'topics': topicsToString(f.topics),
  };

  /// This device's library. Where two imported copies of one book are
  /// here, the one read last speaks for both.
  Future<LibrarySnapshot> snapshot() async {
    final novels = <String, SyncItem>{};
    final keyOf = <int, String>{};
    for (final n in await _db.listNovels()) {
      final key = novelKey(n);
      keyOf[n.id!] = key;
      novels.putIfAbsent(key, () => novelItem(n));
    }
    final passages = <String, SyncItem>{};
    for (final p in await _db.listPassages()) {
      final novel = keyOf[p.novelId];
      if (novel == null) continue;
      passages[passageKey(novel, p)] = passageItem(novel, p);
    }
    return LibrarySnapshot(
      novels: novels,
      passages: passages,
      feeds: {for (final f in await _db.listFeeds()) f.url: feedItem(f)},
    );
  }

  // ---------------------------------------------------------------- apply

  /// Picks between two versions of a novel: the one read last.
  static SyncItem resolveNovel(SyncItem local, SyncItem remote) {
    final l = (local['readAt'] as int?) ?? 0;
    final r = (remote['readAt'] as int?) ?? 0;
    return l > r ? local : remote;
  }

  /// Applies [changes] by collection. Returns what changed, and the keys
  /// that couldn't be kept here (books not on this device).
  Future<(SyncOutcome, Map<String, Set<String>>)> apply(
    Map<String, Map<String, SyncItem?>> changes,
  ) async {
    final held = <String, Set<String>>{
      'novels': {},
      'passages': {},
      'feeds': {},
    };
    var novels = 0, passages = 0, feeds = 0;
    var newFeeds = false;

    // Novels first, so passages can find theirs.
    var local = <String, List<Novel>>{};
    Future<void> index() async {
      local = {};
      for (final n in await _db.listNovels()) {
        (local[novelKey(n)] ??= []).add(n);
      }
    }

    await index();
    for (final MapEntry(:key, :value) in (changes['novels'] ?? {}).entries) {
      final here = local[key] ?? const [];
      if (value == null) {
        for (final n in here) {
          await _novels.removeNovel(n);
          novels++;
        }
        continue;
      }
      if (here.isEmpty) {
        if (value['source'] == NovelSource.ranobes.name) {
          await _db.insertNovel(await _newNovel(value));
          novels++;
        } else {
          held['novels']!.add(key);
        }
        continue;
      }
      final novel = here.first;
      final placed = await _placed(novel, value);
      if (placed == null) {
        // Tried again next time, rather than this device's place winning.
        held['novels']!.add(key);
        continue;
      }
      await _db.updateNovel(placed);
      novels++;
    }
    await index();

    final passagesHere = <String, Passage>{};
    for (final p in await _db.listPassages()) {
      final novel = await _db.getNovel(p.novelId);
      if (novel == null) continue;
      passagesHere[passageKey(novelKey(novel), p)] = p;
    }
    final moved = <Passage>[];
    for (final MapEntry(:key, :value) in (changes['passages'] ?? {}).entries) {
      final here = passagesHere[key];
      if (value == null) {
        if (here != null) {
          await _db.deletePassage(here.id!);
          passages++;
        }
        continue;
      }
      final novel = (local[value['novel']] ?? const []).firstOrNull;
      if (novel == null) {
        held['passages']!.add(key);
        continue;
      }
      final passage = Passage(
        id: here?.id,
        novelId: novel.id!,
        novelTitle: here?.novelTitle ?? novel.title,
        chapterUrl:
            here?.chapterUrl ??
            await _chapterUrl(
              novel,
              value['chapter'] as int,
              value['chapterUrl'] as String?,
            ) ??
            novel.url,
        chapterNumber: value['chapter'] as int,
        chapterTitle: value['chapterTitle'] as String,
        from: value['from'] as int,
        to: value['to'] as int,
        text: value['text'] as String,
        savedAt: DateTime.fromMillisecondsSinceEpoch(value['savedAt'] as int),
        character: value['character'] as String?,
        reading: (value['reading'] as int?) ?? 1,
      );
      if (here == null) {
        await _db.insertPassage(passage);
      } else {
        moved.add(passage);
      }
      passages++;
    }
    await _db.movePassages(moved);

    final feedsHere = {for (final f in await _db.listFeeds()) f.url: f};
    for (final MapEntry(:key, :value) in (changes['feeds'] ?? {}).entries) {
      final here = feedsHere[key];
      if (value == null) {
        if (here != null) {
          await _db.deleteFeed(here.id!);
          feeds++;
        }
        continue;
      }
      final topics = topicsFromString(value['topics'] as String?);
      if (here == null) {
        await _db.insertFeed(
          Feed(
            url: key,
            title: value['title'] as String,
            siteUrl: value['siteUrl'] as String?,
            topics: topics,
          ),
        );
        newFeeds = true;
      } else {
        await _db.updateFeed(
          Feed(
            id: here.id,
            url: here.url,
            title: value['title'] as String,
            siteUrl: (value['siteUrl'] as String?) ?? here.siteUrl,
            lastUpdated: here.lastUpdated,
            syncStatus: here.syncStatus,
            lastError: here.lastError,
            favicon: here.favicon,
            topics: topics,
          ),
        );
      }
      feeds++;
    }

    return (
      SyncOutcome(
        novels: novels,
        passages: passages,
        feeds: feeds,
        newFeeds: newFeeds,
      ),
      held,
    );
  }

  /// A novel from the site, as another device has it. Its chapters come
  /// from the site when opened.
  Future<Novel> _newNovel(SyncItem v) async {
    final meta = ((v['meta'] as Map?) ?? const {}).cast<String, Object?>();
    final base = Novel(
      url: v['url'] as String,
      bookId: v['bookId'] as int,
      title: v['title'] as String,
      cover: v['cover'] as String?,
      author: v['author'] as String?,
      status: meta['status'] as String?,
      description: meta['description'] as String?,
      chapterCount: (meta['chapterCount'] as int?) ?? 0,
      addedDate: DateTime.fromMillisecondsSinceEpoch(v['added'] as int),
      seenCount: (meta['seenCount'] as int?) ?? 0,
    );
    return _position(base, v, v['chapterUrl'] as String?);
  }

  /// [novel] at the place [v] gives, or null when that place can't be
  /// found on this device.
  Future<Novel?> _placed(Novel novel, SyncItem v) async {
    String? url;
    if (v['started'] == true) {
      url = await _chapterUrl(
        novel,
        v['chapter'] as int,
        v['chapterUrl'] as String?,
      );
      if (url == null) return null;
    }
    final meta = ((v['meta'] as Map?) ?? const {}).cast<String, Object?>();
    final seen = (meta['seenCount'] as int?) ?? 0;
    final count = (meta['chapterCount'] as int?) ?? 0;
    final base = Novel(
      id: novel.id,
      url: novel.url,
      bookId: novel.bookId,
      title: novel.title,
      cover: novel.cover,
      author: novel.author,
      status: novel.status,
      description: novel.description,
      chapterCount: novel.isImported
          ? novel.chapterCount
          : (count > novel.chapterCount ? count : novel.chapterCount),
      addedDate: novel.addedDate,
      lastChecked: novel.lastChecked,
      seenCount: seen > novel.seenCount ? seen : novel.seenCount,
      notifiedCount: novel.notifiedCount,
      source: novel.source,
    );
    return _position(base, v, url);
  }

  static Novel _position(Novel base, SyncItem v, String? url) {
    final started = v['started'] == true && url != null;
    final readAt = v['readAt'] as int?;
    return Novel(
      id: base.id,
      url: base.url,
      bookId: base.bookId,
      title: base.title,
      cover: base.cover,
      author: base.author,
      status: base.status,
      description: base.description,
      chapterCount: base.chapterCount,
      addedDate: base.addedDate,
      lastChecked: base.lastChecked,
      chapterUrl: started ? url : null,
      chapterTitle: started ? v['chapterTitle'] as String? : null,
      chapterNumber: started ? (v['chapter'] as int?) ?? 0 : 0,
      chapterProgress: started ? ((v['progress'] as num?) ?? 0).toDouble() : 0,
      readAt: readAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(readAt),
      seenCount: base.seenCount,
      notifiedCount: base.notifiedCount,
      source: base.source,
      reading: (v['reading'] as int?) ?? 1,
      lastEnd: (v['lastEnd'] as int?) ?? 0,
    );
  }

  /// This device's link to chapter [number] of [novel]: its own copy for
  /// an imported book, else [web] (the site's link), else what the chapter
  /// list knows.
  Future<String?> _chapterUrl(Novel novel, int number, String? web) async {
    if (novel.isImported) {
      return number > 0 ? 'epub://${-novel.bookId}/$number' : null;
    }
    if (web != null) return web;
    if (number <= 0) return null;
    return (await _db.indexedChapter(novel.id!, number))?.url;
  }
}
