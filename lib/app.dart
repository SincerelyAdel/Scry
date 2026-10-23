import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/feed_repository.dart';
import 'data/novel_repository.dart';
import 'screens/home_shell.dart';
import 'screens/novels/library_screen.dart';
import 'services/background_sync.dart';
import 'services/chapter_alerts.dart';
import 'state/article_images.dart';
import 'state/articles_provider.dart';
import 'state/feeds_provider.dart';
import 'state/novels_provider.dart';
import 'state/settings_provider.dart';
import 'theme.dart';
import 'widgets/app_header.dart';
import 'widgets/gold_glow_border.dart';

class ScryApp extends StatefulWidget {
  const ScryApp({
    super.key,
    required this.repository,
    required this.settings,
    required this.novels,
    this.refreshOnLaunch = true,
    this.openNovelId,
  });

  final FeedRepository repository;
  final NovelRepository novels;
  final SettingsProvider settings;

  /// Fetch all feeds when the app starts. Off in widget tests.
  final bool refreshOnLaunch;

  /// A novel to open on launch: the app was started from its new chapter
  /// notification.
  final int? openNovelId;

  @override
  State<ScryApp> createState() => _ScryAppState();
}

class _ScryAppState extends State<ScryApp> {
  late final FeedsProvider _feeds;
  late final ArticlesProvider _articles;
  late final ArticleImages _images;
  late final NovelsProvider _novels;
  late var _sort = widget.settings.sort;
  late var _syncInterval = widget.settings.syncInterval;
  late var _chapterAlerts = widget.settings.chapterAlerts;

  @override
  void initState() {
    super.initState();
    _feeds = FeedsProvider(widget.repository);
    _articles = ArticlesProvider(widget.repository, initialSort: _sort);
    _images = ArticleImages(widget.repository);
    _novels = NovelsProvider(widget.novels)..load();

    // The two lists depend on each other: new or deleted articles change
    // feed counts, and feed changes change the inbox.
    _feeds.onLibraryChanged = () {
      final filter = _articles.feedId;
      if (filter != null && !_feeds.feeds.any((f) => f.id == filter)) {
        _articles.showFeed(null);
      } else {
        _articles.reload();
      }
    };
    _articles.onCountsChanged = _feeds.load;

    widget.settings.addListener(_onSettingsChanged);

    _feeds.load();
    _articles.reload();
    if (widget.refreshOnLaunch) _feeds.refreshAll();

    ChapterAlerts.onOpen = _openNovel;
    final launchNovel = widget.openNovelId;
    if (launchNovel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openNovel(launchNovel);
      });
    }
  }

  /// Opens a novel where it was left, from its notification.
  Future<void> _openNovel(int id) async {
    final novel = await widget.novels.getNovel(id);
    if (novel == null) return;
    await widget.settings.setMode(AppMode.novels);
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await openReader(context, novel);
  }

  void _onSettingsChanged() {
    final settings = widget.settings;
    if (settings.sort != _sort) {
      _sort = settings.sort;
      _articles.applySort(_sort);
    }
    if (settings.syncInterval != _syncInterval) {
      _syncInterval = settings.syncInterval;
      BackgroundSync.apply(_syncInterval);
    }
    if (settings.chapterAlerts != _chapterAlerts) {
      _chapterAlerts = settings.chapterAlerts;
      BackgroundSync.applyChapterAlerts(_chapterAlerts);
      if (_chapterAlerts) ChapterAlerts.requestPermission();
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    if (ChapterAlerts.onOpen == _openNovel) ChapterAlerts.onOpen = null;
    _feeds.dispose();
    _articles.dispose();
    _images.dispose();
    _novels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: widget.repository),
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider.value(value: _feeds),
        ChangeNotifierProvider.value(value: _articles),
        ChangeNotifierProvider.value(value: _images),
        ChangeNotifierProvider.value(value: _novels),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: 'Scry',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: buildAppTheme(lightPalette),
          darkTheme: buildAppTheme(darkPalette),
          themeAnimationDuration: Duration.zero,
          navigatorKey: navigatorKey,
          // The header and the gold edge stay fixed above every page.
          builder: (context, child) => GoldGlowBorder(
            child: Column(
              children: [
                const AppHeader(),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          home: const HomeShell(),
        ),
      ),
    );
  }
}
