import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/feed_repository.dart';
import 'screens/home_shell.dart';
import 'services/background_sync.dart';
import 'state/articles_provider.dart';
import 'state/feeds_provider.dart';
import 'state/settings_provider.dart';

class SnippefyApp extends StatefulWidget {
  const SnippefyApp({
    super.key,
    required this.repository,
    required this.settings,
    this.refreshOnLaunch = true,
  });

  final FeedRepository repository;
  final SettingsProvider settings;

  /// Fetch all feeds when the app starts. Off in widget tests.
  final bool refreshOnLaunch;

  @override
  State<SnippefyApp> createState() => _SnippefyAppState();
}

class _SnippefyAppState extends State<SnippefyApp> {
  late final FeedsProvider _feeds;
  late final ArticlesProvider _articles;
  late var _sort = widget.settings.sort;
  late var _syncInterval = widget.settings.syncInterval;

  @override
  void initState() {
    super.initState();
    _feeds = FeedsProvider(widget.repository);
    _articles = ArticlesProvider(widget.repository, initialSort: _sort);

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
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _feeds.dispose();
    _articles.dispose();
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
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: 'Snippefy',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: _theme(settings.seedColor, Brightness.light),
          darkTheme: _theme(settings.seedColor, Brightness.dark),
          home: const HomeShell(),
        ),
      ),
    );
  }

  static ThemeData _theme(Color seed, Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
