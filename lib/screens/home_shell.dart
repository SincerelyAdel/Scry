import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/feed.dart';
import '../state/articles_provider.dart';
import '../state/feeds_provider.dart';
import '../state/settings_provider.dart';
import 'feeds_screen.dart';
import 'inbox_screen.dart';
import 'novels/library_screen.dart';

/// The feeds side (bottom navigation between the inbox and feed
/// management) or the novel library, as chosen in the header. Settings live
/// in the header.
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
        // Android can bring the system bars back while we're in the background.
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    final mode = context.select<SettingsProvider, AppMode>((s) => s.mode);
    if (mode == AppMode.novels) return const LibraryScreen();
    final unread = context.select<ArticlesProvider, int>((a) => a.unreadCount);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const InboxScreen(),
          FeedsScreen(onOpenFeed: _openFeed),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: NavigationBar(
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
          ],
        ),
      ),
    );
  }
}
