/// Orderings offered for the inbox.
enum ArticleSort {
  newest('Newest first'),
  byFeed('By feed'),
  unreadFirst('Unread first'),

  /// By read time. Papers and teasers whose length isn't known go last.
  shortest('Quick reads first'),
  longest('Long reads first');

  const ArticleSort(this.label);

  final String label;
}
