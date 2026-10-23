import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/feed.dart';
import '../state/feeds_provider.dart';
import '../utils/format.dart';
import '../theme.dart';
import '../widgets/add_feed_dialog.dart';
import '../widgets/ui.dart';

/// Subscriptions: add, refresh, remove, and jump to one feed's articles.
class FeedsScreen extends StatelessWidget {
  const FeedsScreen({super.key, required this.onOpenFeed});

  final ValueChanged<Feed> onOpenFeed;

  @override
  Widget build(BuildContext context) {
    final feeds = context.watch<FeedsProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeds'),
        actions: [
          IconButton(
            tooltip: 'Refresh all',
            icon: const Icon(Icons.refresh),
            onPressed: feeds.refreshing || feeds.feeds.isEmpty
                ? null
                : feeds.refreshAll,
          ),
        ],
        bottom: feeds.refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add feed'),
      ),
      body: !feeds.loaded
          ? const Center(child: CircularProgressIndicator())
          : feeds.feeds.isEmpty
          ? const EmptyState(
              icon: Icons.rss_feed,
              title: 'No subscriptions yet',
              message: 'Tap Add feed to subscribe to a blog or feed.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final pad = pagePadding(context);
                final wide = constraints.maxWidth > 600;
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(pad, 8, pad, 96),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: wide ? 2 : 1,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 128,
                  ),
                  itemCount: feeds.feeds.length,
                  itemBuilder: (context, i) => _FeedTile(
                    feed: feeds.feeds[i],
                    onTap: () => onOpenFeed(feeds.feeds[i]),
                  ),
                );
              },
            ),
    );
  }

  static Future<void> _add(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final feed = await showAddFeedDialog(context);
    if (feed == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Added ${feed.title} (${feed.articleCount} articles)'),
      ),
    );
  }
}

class _FeedTile extends StatelessWidget {
  const _FeedTile({required this.feed, required this.onTap});

  final Feed feed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final failed = feed.syncStatus == SyncStatus.error;
    final updated = feed.lastUpdated == null
        ? 'Never updated'
        : 'Updated ${relativeDate(feed.lastUpdated!)}';

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FeedAvatar(title: feed.title, favicon: feed.favicon, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  feed.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (feed.unreadCount > 0) _UnreadPill(feed.unreadCount),
              PopupMenuButton<_FeedAction>(
                icon: Icon(Icons.more_horiz, color: c.muted, size: 20),
                tooltip: 'More',
                onSelected: (action) => _onAction(context, action),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _FeedAction.refresh,
                    child: Text('Refresh'),
                  ),
                  PopupMenuItem(
                    value: _FeedAction.copyUrl,
                    child: Text('Copy URL'),
                  ),
                  PopupMenuItem(
                    value: _FeedAction.delete,
                    child: Text('Unsubscribe'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              failed
                  ? 'Refresh failed: ${feed.lastError ?? 'unknown error'}'
                  : '${feed.articleCount} '
                        '${feed.articleCount == 1 ? 'article' : 'articles'} · '
                        '${feed.unreadCount} unread',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: failed ? c.danger : c.muted,
                fontSize: 13.5,
              ),
            ),
          ),
          const Spacer(),
          Text(updated, style: TextStyle(color: c.faint, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _onAction(BuildContext context, _FeedAction action) async {
    final provider = context.read<FeedsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _FeedAction.refresh:
        final result = await provider.refreshFeed(feed);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.ok
                  ? '${result.newArticles} new articles'
                  : 'Refresh failed: ${result.error}',
            ),
          ),
        );
      case _FeedAction.copyUrl:
        await Clipboard.setData(ClipboardData(text: feed.url));
        messenger.showSnackBar(
          const SnackBar(content: Text('Feed URL copied')),
        );
      case _FeedAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Unsubscribe from ${feed.title}?'),
            content: const Text(
              'Its saved articles will be deleted from this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Unsubscribe'),
              ),
            ],
          ),
        );
        if (confirmed == true) await provider.deleteFeed(feed);
    }
  }
}

enum _FeedAction { refresh, copyUrl, delete }

/// Gold count of unread articles.
class _UnreadPill extends StatelessWidget {
  const _UnreadPill(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.button,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 999 ? '999+' : '$count',
        style: TextStyle(
          color: c.onButton,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
