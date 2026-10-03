import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/feed.dart';
import '../state/feeds_provider.dart';
import '../utils/format.dart';
import '../widgets/add_feed_dialog.dart';

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
          ? const Center(child: Text('No subscriptions yet.'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: feeds.feeds.length,
              itemBuilder: (context, i) => _FeedTile(
                feed: feeds.feeds[i],
                onTap: () => onOpenFeed(feeds.feeds[i]),
              ),
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
    final theme = Theme.of(context);
    final failed = feed.syncStatus == SyncStatus.error;
    final updated = feed.lastUpdated == null
        ? 'never updated'
        : 'updated ${relativeDate(feed.lastUpdated!)}';

    return ListTile(
      onTap: onTap,
      leading: _FeedIcon(feed: feed),
      title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        failed
            ? 'Refresh failed: ${feed.lastError ?? 'unknown error'}'
            : '${feed.articleCount} articles · ${feed.unreadCount} unread · '
                  '$updated',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: failed ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      trailing: PopupMenuButton<_FeedAction>(
        onSelected: (action) => _onAction(context, action),
        itemBuilder: (_) => const [
          PopupMenuItem(value: _FeedAction.refresh, child: Text('Refresh')),
          PopupMenuItem(value: _FeedAction.copyUrl, child: Text('Copy URL')),
          PopupMenuItem(value: _FeedAction.delete, child: Text('Unsubscribe')),
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

/// Favicon if we have one, otherwise the feed's initial.
class _FeedIcon extends StatelessWidget {
  const _FeedIcon({required this.feed});

  final Feed feed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: 18,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Text(
        feed.title.isEmpty ? '?' : feed.title.characters.first.toUpperCase(),
      ),
    );
    final favicon = feed.favicon;
    if (favicon == null) return fallback;
    return CircleAvatar(
      radius: 18,
      backgroundColor: scheme.surfaceContainerHighest,
      child: ClipOval(
        child: Image.memory(
          favicon,
          width: 22,
          height: 22,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}
