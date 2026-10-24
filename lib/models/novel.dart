/// A novel in the library, with where the reader is in it.
class Novel {
  const Novel({
    this.id,
    required this.url,
    required this.bookId,
    required this.title,
    this.cover,
    this.author,
    this.status,
    this.description,
    this.chapterCount = 0,
    required this.addedDate,
    this.lastChecked,
    this.chapterUrl,
    this.chapterTitle,
    this.chapterNumber = 0,
    this.chapterProgress = 0,
    this.readAt,
    this.seenCount = 0,
    this.notifiedCount = 0,
    this.source = NovelSource.ranobes,
  });

  final int? id;

  /// The novel's page on ranobes.net; `epub://…` for imported books.
  final String url;

  /// The site's number for the novel, used in its chapter-list links.
  /// Negative for imported books.
  final int bookId;

  final String title;
  final String? cover;
  final String? author;
  final String? status;
  final String? description;

  /// Chapters on the site when it was last checked.
  final int chapterCount;

  final DateTime addedDate;

  /// When the chapter count was last checked.
  final DateTime? lastChecked;

  /// The chapter being read, null before the first one is opened.
  final String? chapterUrl;
  final String? chapterTitle;

  /// Its position in the novel from 1, or 0 when not known.
  final int chapterNumber;

  /// How far down that chapter, from 0 to 1.
  final double chapterProgress;

  /// When it was last read; the library lists the latest first.
  final DateTime? readAt;

  /// Chapters there were when it was last read.
  final int seenCount;

  /// Chapters there were when new ones were last announced. Written only
  /// by the database's setNotified, so saving a novel doesn't undo it.
  final int notifiedCount;

  /// Where the novel comes from.
  final NovelSource source;

  /// Imported from a file: everything is saved, nothing to check online.
  bool get isImported => source == NovelSource.epub;

  /// Chapters out since it was last read that haven't been announced.
  int get unannounced {
    if (!started || seenCount <= 0) return 0;
    final known = seenCount > notifiedCount ? seenCount : notifiedCount;
    return chapterCount > known ? chapterCount - known : 0;
  }

  bool get started => chapterUrl != null;

  /// Chapters released since it was last read.
  int get newChapters =>
      started && seenCount > 0 ? (chapterCount - seenCount).clamp(0, 9999) : 0;

  /// Chapters after the one being read.
  int get chaptersLeft => chapterNumber <= 0
      ? 0
      : (chapterCount - chapterNumber).clamp(0, chapterCount);

  /// Share of the novel read, counting the current chapter's progress.
  double get progress => chapterCount <= 0 || chapterNumber <= 0
      ? 0
      : ((chapterNumber - 1 + chapterProgress) / chapterCount).clamp(0, 1);

  Novel copyWith({
    String? title,
    String? cover,
    String? author,
    String? status,
    String? description,
    int? chapterCount,
    DateTime? lastChecked,
    String? chapterUrl,
    String? chapterTitle,
    int? chapterNumber,
    double? chapterProgress,
    DateTime? readAt,
    int? seenCount,
  }) {
    return Novel(
      id: id,
      url: url,
      bookId: bookId,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      author: author ?? this.author,
      status: status ?? this.status,
      description: description ?? this.description,
      chapterCount: chapterCount ?? this.chapterCount,
      addedDate: addedDate,
      lastChecked: lastChecked ?? this.lastChecked,
      chapterUrl: chapterUrl ?? this.chapterUrl,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      chapterProgress: chapterProgress ?? this.chapterProgress,
      readAt: readAt ?? this.readAt,
      seenCount: seenCount ?? this.seenCount,
      notifiedCount: notifiedCount,
      source: source,
    );
  }

  factory Novel.fromMap(Map<String, Object?> map) {
    DateTime? date(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return Novel(
      id: map['id'] as int?,
      url: map['url'] as String,
      bookId: map['bookId'] as int,
      title: map['title'] as String,
      cover: map['cover'] as String?,
      author: map['author'] as String?,
      status: map['status'] as String?,
      description: map['description'] as String?,
      chapterCount: (map['chapterCount'] as int?) ?? 0,
      addedDate: date(map['addedDate'])!,
      lastChecked: date(map['lastChecked']),
      chapterUrl: map['chapterUrl'] as String?,
      chapterTitle: map['chapterTitle'] as String?,
      chapterNumber: (map['chapterNumber'] as int?) ?? 0,
      chapterProgress: ((map['chapterProgress'] as num?) ?? 0).toDouble(),
      readAt: date(map['readAt']),
      seenCount: (map['seenCount'] as int?) ?? 0,
      notifiedCount: (map['notifiedCount'] as int?) ?? 0,
      source:
          NovelSource.values.asNameMap()[map['source']] ?? NovelSource.ranobes,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'url': url,
      'bookId': bookId,
      'title': title,
      'cover': cover,
      'author': author,
      'status': status,
      'description': description,
      'chapterCount': chapterCount,
      'addedDate': addedDate.millisecondsSinceEpoch,
      'lastChecked': lastChecked?.millisecondsSinceEpoch,
      'chapterUrl': chapterUrl,
      'chapterTitle': chapterTitle,
      'chapterNumber': chapterNumber,
      'chapterProgress': chapterProgress,
      'readAt': readAt?.millisecondsSinceEpoch,
      'seenCount': seenCount,
      'source': source.name,
    };
  }
}

/// Where a novel comes from: ranobes.net, or an EPUB file.
enum NovelSource { ranobes, epub }
