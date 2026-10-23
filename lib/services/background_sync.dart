import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../data/app_database.dart';
import '../data/feed_repository.dart';
import '../data/novel_repository.dart';
import '../state/settings_provider.dart';
import 'chapter_alerts.dart';
import 'feed_fetcher.dart';
import 'ranobes_session.dart';

const _uniqueName = 'scry-periodic-refresh';
const _taskName = 'refreshFeeds';
const _chaptersUniqueName = 'scry-chapter-check';
const _chaptersTaskName = 'checkChapters';

/// Entry point for the background isolate Workmanager spins up. Must be a
/// top-level function annotated so tree shaking keeps it.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    AppDatabase? db;
    try {
      // Its own connection: closing a shared one would close the app's.
      db = await AppDatabase.open(singleInstance: false);
      if (task == _chaptersTaskName) {
        await RanobesSession.load();
        final novels = NovelRepository(db, DioFeedFetcher());
        for (final novel in await novels.chaptersToAnnounce()) {
          await ChapterAlerts.announce(novel);
        }
      } else {
        await FeedRepository(db, DioFeedFetcher()).refreshAll();
      }
      return true;
    } catch (e) {
      debugPrint('Background task $task failed: $e');
      // false asks Android to retry with backoff.
      return false;
    } finally {
      await db?.close();
    }
  });
}

/// Periodic feed refresh via Workmanager.
///
/// Only wired up for Android. iOS needs BGTaskScheduler entitlements and
/// AppDelegate registration (see README), and even then the OS decides when
/// to run, so the app just refreshes on launch and on pull-to-refresh there.
class BackgroundSync {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> initialize() async {
    if (!supported) return;
    await Workmanager().initialize(backgroundSyncDispatcher);
  }

  /// Schedules (or cancels, for [SyncInterval.off]) the periodic refresh.
  static Future<void> apply(SyncInterval interval) async {
    if (!supported) return;
    final frequency = interval.duration;
    if (frequency == null) {
      await Workmanager().cancelByUniqueName(_uniqueName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: frequency,
      // Let Android batch the run anywhere in the last half hour.
      flexInterval: const Duration(minutes: 30),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  /// Schedules (or cancels) the hourly check for new chapters.
  static Future<void> applyChapterAlerts(bool on) async {
    if (!supported) return;
    if (!on) {
      await Workmanager().cancelByUniqueName(_chaptersUniqueName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _chaptersUniqueName,
      _chaptersTaskName,
      frequency: const Duration(hours: 1),
      flexInterval: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}
