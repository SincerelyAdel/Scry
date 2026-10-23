import 'topic.dart';

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
    this.imageUrl,
    this.imageChecked = false,
    this.feedTopics = const {},
    this.ownTags = const {},
    this.wordCount = 0,
    this.fullContent,
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

  /// A picture to show for the article: from the feed, the article's own
  /// page (its preview image), or for arXiv papers the first figure.
  final String? imageUrl;

  /// True once the article's page has been checked for [imageUrl], so it
  /// isn't downloaded again when there's none.
  final bool imageChecked;

  /// The feed's tags, joined in.
  final Set<Topic> feedTopics;

  /// Tags from the article's own words (see tagsInText).
  final Set<Topic> ownTags;

  /// Every tag: the feed's and the article's own, in a fixed order.
  List<Topic> get tags => [
    for (final t in Topic.values)
      if (feedTopics.contains(t) || ownTags.contains(t)) t,
  ];

  /// Length of the best body we have: the page's text once fetched, else
  /// the feed's content or summary. Used for the read-time badge.
  final int wordCount;

  /// The article's text taken from its web page, for feeds that only send
  /// a teaser. Not loaded by list queries.
  final String? fullContent;

  int? get readMinutes => readMinutesFor(wordCount);

  /// Best date to show and sort by.
  DateTime get displayDate => pubDate ?? addedDate;

  Article copyWith({
    bool? isRead,
    String? imageUrl,
    bool? imageChecked,
    int? wordCount,
    String? fullContent,
  }) {
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
      imageUrl: imageUrl ?? this.imageUrl,
      imageChecked: imageChecked ?? this.imageChecked,
      feedTopics: feedTopics,
      ownTags: ownTags,
      wordCount: wordCount ?? this.wordCount,
      fullContent: fullContent ?? this.fullContent,
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
      imageUrl: map['imageUrl'] as String?,
      imageChecked: map['imageChecked'] == 1,
      feedTopics: topicsFromString(map['feedTopic'] as String?),
      ownTags: topicsFromString(map['tags'] as String?),
      wordCount: (map['wordCount'] as int?) ?? 0,
      fullContent: map['fullContent'] as String?,
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
      'imageUrl': imageUrl,
      'imageChecked': imageChecked ? 1 : 0,
      'wordCount': wordCount,
      'fullContent': fullContent,
      'tags': topicsToString(ownTags),
    };
  }
}

/// Minutes to read [words] at about 230 a minute, or null for a teaser.
int? readMinutesFor(int words) =>
    words < 150 ? null : (words / 230).ceil().clamp(1, 999);

DateTime? _dateFromMillis(Object? value) =>
    value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
