/// A single entry from a feed.
class Article {
  const Article({
    this.id,
    required this.feedId,
    required this.guid,
    required this.title,
    this.author,
    this.url,
    this.pubDate,
    this.summary,
    this.content,
    this.isRead = false,
    required this.addedDate,
    this.feedTitle,
  });

  final int? id;
  final int feedId;

  /// Stable identity within its feed (guid/id, else link, else title+date).
  /// Used to avoid re-inserting articles on every refresh.
  final String guid;

  final String title;
  final String? author;
  final String? url;
  final DateTime? pubDate;

  /// Short description, usually HTML.
  final String? summary;

  /// Full body if the feed provides one, usually HTML. Not loaded by list
  /// queries to keep scrolling cheap.
  final String? content;

  final bool isRead;
  final DateTime addedDate;

  /// Joined in from the feeds table for display.
  final String? feedTitle;

  /// Best date to show and sort by.
  DateTime get displayDate => pubDate ?? addedDate;

  Article copyWith({bool? isRead}) {
    return Article(
      id: id,
      feedId: feedId,
      guid: guid,
      title: title,
      author: author,
      url: url,
      pubDate: pubDate,
      summary: summary,
      content: content,
      isRead: isRead ?? this.isRead,
      addedDate: addedDate,
      feedTitle: feedTitle,
    );
  }

  factory Article.fromMap(Map<String, Object?> map) {
    return Article(
      id: map['id'] as int?,
      feedId: map['feedId'] as int,
      guid: map['guid'] as String,
      title: map['title'] as String,
      author: map['author'] as String?,
      url: map['url'] as String?,
      pubDate: _dateFromMillis(map['pubDate']),
      summary: map['summary'] as String?,
      content: map['content'] as String?,
      isRead: map['isRead'] == 1,
      addedDate: _dateFromMillis(map['addedDate'])!,
      feedTitle: map['feedTitle'] as String?,
    );
  }

  /// Columns stored in the `articles` table.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'feedId': feedId,
      'guid': guid,
      'title': title,
      'author': author,
      'url': url,
      'pubDate': pubDate?.millisecondsSinceEpoch,
      'summary': summary,
      'content': content,
      'isRead': isRead ? 1 : 0,
      'addedDate': addedDate.millisecondsSinceEpoch,
    };
  }
}

DateTime? _dateFromMillis(Object? value) =>
    value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
