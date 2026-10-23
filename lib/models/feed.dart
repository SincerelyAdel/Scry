import 'dart:typed_data';

import 'topic.dart';

/// Outcome of the most recent attempt to fetch a feed.
enum SyncStatus { never, ok, error }

/// A subscribed RSS/Atom feed.
class Feed {
  const Feed({
    this.id,
    required this.url,
    required this.title,
    this.siteUrl,
    this.lastUpdated,
    this.syncStatus = SyncStatus.never,
    this.lastError,
    this.favicon,
    this.topic,
    this.articleCount = 0,
    this.unreadCount = 0,
  });

  final int? id;
  final String url;
  final String title;

  /// Homepage of the site the feed belongs to, if the feed declares one.
  final String? siteUrl;

  /// When the feed was last fetched successfully.
  final DateTime? lastUpdated;

  final SyncStatus syncStatus;
  final String? lastError;
  final Uint8List? favicon;

  /// What the feed is about, for badges and the inbox filter.
  final Topic? topic;

  /// Derived counts, filled in by list queries. Not stored on the row.
  final int articleCount;
  final int unreadCount;

  factory Feed.fromMap(Map<String, Object?> map) {
    return Feed(
      id: map['id'] as int?,
      url: map['url'] as String,
      title: map['title'] as String,
      siteUrl: map['siteUrl'] as String?,
      lastUpdated: _dateFromMillis(map['lastUpdated']),
      syncStatus: SyncStatus.values.byName(
        (map['syncStatus'] as String?) ?? SyncStatus.never.name,
      ),
      lastError: map['lastError'] as String?,
      favicon: map['favicon'] as Uint8List?,
      topic: Topic.fromName(map['topic'] as String?),
      articleCount: (map['articleCount'] as int?) ?? 0,
      unreadCount: (map['unreadCount'] as int?) ?? 0,
    );
  }

  /// Columns stored in the `feeds` table.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'url': url,
      'title': title,
      'siteUrl': siteUrl,
      'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
      'syncStatus': syncStatus.name,
      'lastError': lastError,
      'favicon': favicon,
      'topic': topic?.name,
    };
  }
}

DateTime? _dateFromMillis(Object? value) =>
    value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
