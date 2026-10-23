import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../models/article_sort.dart';
import '../state/articles_provider.dart';
import '../state/feeds_provider.dart';
import '../state/settings_provider.dart';
import '../widgets/add_feed_dialog.dart';
import '../widgets/article_tile.dart';
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
        bottom: feeds.refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: _body(context, articles, feeds),
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
      return _EmptyState(
        icon: Icons.rss_feed,
        message: 'No feeds yet.\nAdd one to fill your inbox.',
        action: FilledButton.icon(
          onPressed: () => showAddFeedDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Add feed'),
        ),
      );
    }
    if (articles.articles.isEmpty) {
      return _EmptyState(
        icon: Icons.inbox,
        message: articles.unreadOnly
            ? 'All caught up.'
            : 'Nothing here yet. Pull down to refresh.',
      );
    }

    final items = articles.articles;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 800) articles.loadMore();
        return false;
      },
      child: ListView.separated(
        // Always scrollable so pull-to-refresh works on short lists.
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length + (articles.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 32),
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
    final scheme = Theme.of(context).colorScheme;
    final articles = context.read<ArticlesProvider>();
    return Dismissible(
      key: ValueKey(article.id),
      background: _swipeBackground(
        color: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        icon: article.isRead
            ? Icons.mark_email_unread_outlined
            : Icons.mark_email_read_outlined,
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _swipeBackground(
        color: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
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
    return ColoredBox(
      color: color,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A scroll view so RefreshIndicator still works when empty.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (action != null) ...[const SizedBox(height: 24), action!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
