import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../models/article_sort.dart';
import '../models/topic.dart';
import '../state/articles_provider.dart';
import '../state/feeds_provider.dart';
import '../state/settings_provider.dart';
import '../widgets/add_feed_dialog.dart';
import '../theme.dart';
import '../widgets/article_tile.dart';
import '../widgets/ui.dart';
import 'article_detail_screen.dart';

/// Every subscribed feed's articles in one list.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final articles = context.watch<ArticlesProvider>();
    final feeds = context.watch<FeedsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(articles.feedTitle ?? 'Inbox'),
        leading: articles.feedId == null
            ? null
            : IconButton(
                tooltip: 'Show all feeds',
                icon: const Icon(Icons.close),
                onPressed: () => articles.showFeed(null),
              ),
        actions: [
          IconButton(
            tooltip: articles.unreadOnly ? 'Show all' : 'Show unread only',
            isSelected: articles.unreadOnly,
            icon: const Icon(Icons.mark_email_unread_outlined),
            selectedIcon: const Icon(Icons.mark_email_unread),
            onPressed: () => articles.setUnreadOnly(!articles.unreadOnly),
          ),
          PopupMenuButton<ArticleSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: articles.sort,
            // Sort is a saved preference; the app pushes it to the list.
            onSelected: context.read<SettingsProvider>().setSort,
            itemBuilder: (_) => [
              for (final sort in ArticleSort.values)
                CheckedPopupMenuItem(
                  value: sort,
                  checked: sort == articles.sort,
                  child: Text(sort.label),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all),
            onPressed: articles.unreadCount == 0
                ? null
                : () => articles.markAllRead(),
          ),
        ],
        bottom: _TopicBar(
          show: feeds.feeds.any((f) => f.topic != null),
          refreshing: feeds.refreshing,
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final list = RefreshIndicator(
            onRefresh: () => _refresh(context),
            child: _body(context, articles, feeds),
          );
          // Tablets get the feed list beside the articles.
          if (constraints.maxWidth < 900 || feeds.feeds.isEmpty) return list;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: list),
              const _FeedSidebar(),
            ],
          );
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ArticlesProvider articles,
    FeedsProvider feeds,
  ) {
    if (!articles.loaded || !feeds.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feeds.feeds.isEmpty) {
      return EmptyState(
        icon: Icons.rss_feed,
        title: 'No feeds yet',
        message: 'Add a feed or a blog to fill your inbox.',
        action: FilledButton.icon(
          onPressed: () => showAddFeedDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Add feed'),
        ),
      );
    }
    if (articles.articles.isEmpty) {
      return EmptyState(
        icon: articles.unreadOnly ? Icons.done_all : Icons.inbox_outlined,
        title: articles.unreadOnly ? 'All caught up' : 'Nothing here yet',
        message: articles.unreadOnly ? null : 'Pull down to refresh.',
      );
    }

    final items = articles.articles;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pad = wide ? 24.0 : pagePadding(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 800) articles.loadMore();
        return false;
      },
      child: ListView.separated(
        // Always scrollable so pull-to-refresh works on short lists.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
        itemCount: items.length + (articles.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _SwipeableArticle(article: items[index]);
        },
      ),
    );
  }

  static Future<void> _refresh(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final results = await context.read<FeedsProvider>().refreshAll();
    final failed = results.where((r) => !r.ok).toList();
    if (failed.isEmpty) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed.length == 1
              ? "Couldn't refresh ${failed.first.feed.title}: "
                    '${failed.first.error}'
              : "Couldn't refresh ${failed.length} feeds. "
                    'See the Feeds tab for details.',
        ),
      ),
    );
  }
}

/// Swipe right to toggle read, swipe left to delete (with undo).
class _SwipeableArticle extends StatelessWidget {
  const _SwipeableArticle({required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final articles = context.read<ArticlesProvider>();
    return Dismissible(
      key: ValueKey(article.id),
      background: _swipeBackground(
        color: c.button,
        foreground: c.onButton,
        icon: article.isRead
            ? Icons.mark_email_unread_outlined
            : Icons.mark_email_read_outlined,
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _swipeBackground(
        color: c.danger,
        foreground: Colors.white,
        icon: Icons.delete_outline,
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await articles.setRead(article, !article.isRead);
          return false; // Keep the row; it just changes style.
        }
        return true;
      },
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final index = await articles.delete(article);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('Article deleted'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => articles.restore(article, index),
              ),
            ),
          );
      },
      child: ArticleTile(
        article: article,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArticleDetailScreen(article: article),
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground({
    required Color color,
    required Color foreground,
    required IconData icon,
    required Alignment alignment,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Icon(icon, color: foreground),
        ),
      ),
    );
  }
}

/// "All · ML · IC" chips under the inbox title, plus the refresh bar.
class _TopicBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopicBar({required this.show, required this.refreshing});

  final bool show;
  final bool refreshing;

  @override
  Size get preferredSize => Size.fromHeight((show ? 48 : 0) + 2);

  @override
  Widget build(BuildContext context) {
    final articles = context.watch<ArticlesProvider>();
    final feeds = context.read<FeedsProvider>();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pad = wide ? 24.0 : pagePadding(context);
    Widget chip(String label, Topic? topic) {
      final selected = articles.topic == topic;
      final color = topic == null ? null : topicColor(context, topic);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? null : color,
          ),
          selectedColor: color?.withValues(alpha: 0.28),
          onSelected: (_) {
            // A feed about another topic would leave the list empty.
            final feed = feeds.feeds
                .where((f) => f.id == articles.feedId)
                .firstOrNull;
            if (topic != null && feed != null && feed.topic != topic) {
              articles.showFeed(null);
            }
            articles.showTopic(topic);
          },
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (show)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
              children: [
                chip('All', null),
                for (final topic in Topic.values) chip(topic.badge, topic),
              ],
            ),
          ),
        SizedBox(
          height: 2,
          child: refreshing
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
      ],
    );
  }
}

/// The feed list to the right of the inbox on tablets. Tapping a feed shows
/// only its articles; tapping it again, or All feeds, shows every feed. Only
/// feeds about the chosen topic are listed.
class _FeedSidebar extends StatelessWidget {
  const _FeedSidebar();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final articles = context.watch<ArticlesProvider>();
    final feeds = context.watch<FeedsProvider>().feeds;
    final topic = articles.topic;
    final shown = [
      for (final f in feeds)
        if (topic == null || f.topic == topic) f,
    ];
    final unread = shown.fold<int>(0, (n, f) => n + f.unreadCount);

    Widget row({
      required String title,
      required bool selected,
      required VoidCallback onTap,
      Widget? leading,
      int count = 0,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: selected ? c.surface : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: selected
                ? BorderSide(color: c.accent.withValues(alpha: 0.7))
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  ?leading,
                  if (leading != null) const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (count > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.button,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        count > 999 ? '999+' : '$count',
                        style: TextStyle(
                          color: c.onButton,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 290,
      margin: const EdgeInsets.only(right: 16),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Text(
              'FEEDS',
              style: TextStyle(
                color: c.faint,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          row(
            title: 'All feeds',
            selected: articles.feedId == null,
            count: unread,
            leading: Icon(Icons.all_inbox_outlined, size: 18, color: c.muted),
            onTap: () => articles.showFeed(null),
          ),
          for (final f in shown)
            row(
              title: f.title,
              selected: articles.feedId == f.id,
              count: f.unreadCount,
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  FeedAvatar(title: f.title, favicon: f.favicon, size: 22),
                  if (f.topic != null)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: topicColor(context, f.topic!),
                          shape: BoxShape.circle,
                          border: Border.all(color: c.bg, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              onTap: () => articles.feedId == f.id
                  ? articles.showFeed(null)
                  : articles.showFeed(f.id, title: f.title),
            ),
        ],
      ),
    );
  }
}
