/// Orderings offered for the inbox.
enum ArticleSort {
  newest('Newest first'),
  byFeed('By feed'),
  unreadFirst('Unread first');

  const ArticleSort(this.label);

  final String label;
}
