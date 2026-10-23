import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/feed_repository.dart';
import 'services/background_sync.dart';
import 'services/feed_fetcher.dart';
import 'state/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Full screen, like RepoViewer: swiping in from an edge shows the system
  // bars for a moment, then they hide again.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));

  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsProvider(prefs);
  final db = await AppDatabase.open();
  final repository = FeedRepository(db, DioFeedFetcher());

  await BackgroundSync.initialize();
  unawaited(BackgroundSync.apply(settings.syncInterval));

  runApp(ScryApp(repository: repository, settings: settings));
}
