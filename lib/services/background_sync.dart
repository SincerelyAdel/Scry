import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../data/app_database.dart';
import '../data/feed_repository.dart';
import '../data/novel_repository.dart';
import '../state/settings_provider.dart';
import '../models/novel_download.dart';
import 'chapter_alerts.dart';
import 'feed_fetcher.dart';
import 'novel_downloader.dart';
import 'ranobes_session.dart';

const _uniqueName = 'scry-periodic-refresh';
const _taskName = 'refreshFeeds';
const _chaptersUniqueName = 'scry-chapter-check';
const _chaptersTaskName = 'checkChapters';
const _downloadsUniqueName = 'scry-downloads';
const _downloadsTaskName = 'downloadNovels';

/// Entry point for the background isolate Workmanager spins up. Must be a
/// top-level function annotated so tree shaking keeps it.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    AppDatabase? db;
    try {
      // Its own connection: closing a shared one would close the app's.
      db = await AppDatabase.open(singleInstance: false);
      if (task == _downloadsTaskName) {
        await RanobesSession.load();
        return await _runDownloads(db);
      }
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

/// Downloads for up to 8 minutes (Android stops a worker at 10), then
/// queues another run to carry on.
Future<bool> _runDownloads(AppDatabase db) async {
  var lastShown = DateTime(0);
  DownloadState? lastState;
  final downloader = NovelDownloader(
    db,
    DioFeedFetcher(),
    onProgress: (novel, download) {
      // The notification at most every second and a half, and on changes.
      final now = DateTime.now();
      if (download.state == lastState &&
          now.difference(lastShown) < const Duration(milliseconds: 1500)) {
        return;
      }
      lastShown = now;
      lastState = download.state;
      ChapterAlerts.downloadProgress(novel, download).ignore();
    },
  );
  final result = await downloader.run();
  switch (result) {
    case DownloadRun.outOfTime:
      await DownloadWorker.schedule();
      return true;
    case DownloadRun.offline:
      // Android tries again later, with a growing wait.
      return false;
    case DownloadRun.finished:
    case DownloadRun.needsCheck:
      // Done, or waiting for the person to pass the check in the app,
      // which queues another run.
      return true;
  }
}

/// Runs novel downloads in the background, so they carry on with the app
/// closed. Elsewhere than Android, they run in the app while it's open.
abstract final class DownloadWorker {
  /// Starts a run, or another after the one going now.
  static Future<void> schedule() async {
    if (!BackgroundSync.supported) return;
    await Workmanager().registerOneOffTask(
      _downloadsUniqueName,
      _downloadsTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      // After the current run, which then finds nothing to do or carries
      // on where it left off.
      existingWorkPolicy: ExistingWorkPolicy.append,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }
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
