import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed.dart';
import '../state/articles_provider.dart';
import '../state/feeds_provider.dart';
import 'feeds_screen.dart';
import 'inbox_screen.dart';
import 'settings_screen.dart';

/// Bottom navigation between the inbox, feed management and settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // The background worker writes to the database from another isolate;
    // pick up whatever it fetched when the app comes back to the front.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!mounted) return;
        context.read<FeedsProvider>().load();
        context.read<ArticlesProvider>().reload();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _openFeed(Feed feed) {
    context.read<ArticlesProvider>().showFeed(feed.id, title: feed.title);
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.select<ArticlesProvider, int>((a) => a.unreadCount);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const InboxScreen(),
          FeedsScreen(onOpenFeed: _openFeed),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 999 ? '999+' : '$unread'),
              child: const Icon(Icons.inbox_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 999 ? '999+' : '$unread'),
              child: const Icon(Icons.inbox),
            ),
            label: 'Inbox',
          ),
          const NavigationDestination(
            icon: Icon(Icons.rss_feed_outlined),
            selectedIcon: Icon(Icons.rss_feed),
            label: 'Feeds',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
