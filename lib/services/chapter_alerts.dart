import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/novel.dart';
import '../models/novel_download.dart';

/// Notifications about new chapters and novel downloads. Tapping a new
/// chapter one opens the novel where it was left; a download one opens the
/// novel's page. Android only, like the background work that sends them.
abstract final class ChapterAlerts {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Called with a novel's id when its notification is tapped while the
  /// app is running.
  static void Function(int novelId)? onOpen;

  /// Called with a novel's id when its download notification is tapped.
  static void Function(int novelId)? onOpenPage;

  static const _pagePrefix = 'page:';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'new-chapters',
      'New chapters',
      channelDescription: 'When novels you read get new chapters',
      icon: 'ic_stat_scry',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  static Future<void> initialize() async {
    if (!supported || _ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_scry'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final target = parseTarget(response.payload);
        if (target == null) return;
        (target.page ? onOpenPage : onOpen)?.call(target.novelId);
      },
    );
    _ready = true;
  }

  /// The novel whose notification started the app, if one did, and
  /// whether to open its page (a download) rather than the reader.
  static Future<({int novelId, bool page})?> launchTarget() async {
    if (!supported) return null;
    await initialize();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return parseTarget(details.notificationResponse?.payload);
  }

  static ({int novelId, bool page})? parseTarget(String? payload) {
    if (payload == null) return null;
    final page = payload.startsWith(_pagePrefix);
    final id = int.tryParse(
      page ? payload.substring(_pagePrefix.length) : payload,
    );
    return id == null ? null : (novelId: id, page: page);
  }

  /// Asks to show notifications (Android 13 and later ask once).
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Says [novel] has new chapters, replacing its earlier notification.
  static Future<void> announce(Novel novel) async {
    if (!supported) return;
    await initialize();
    final count = novel.newChapters;
    await _plugin.show(
      id: novel.id!,
      title: novel.title,
      body: count == 1
          ? 'A new chapter is out'
          : '$count new chapters since you last read',
      notificationDetails: _details,
      payload: '${novel.id}',
    );
  }

  /// Clears [novel]'s notification, once its new chapters are opened.
  static Future<void> dismiss(Novel novel) async {
    if (!supported || novel.id == null) return;
    await initialize();
    await _plugin.cancel(id: novel.id!);
  }

  // ------------------------------------------------------------ downloads

  /// Download notifications don't share ids with new chapter ones.
  static int _downloadId(int novelId) => (1 << 24) + novelId;

  /// Shows how [novel]'s download is going, replacing the last one.
  static Future<void> downloadProgress(
    Novel novel,
    NovelDownload download,
  ) async {
    if (!supported) return;
    await initialize();
    final active = download.active;
    final total = download.total;
    final String body;
    switch (download.state) {
      case DownloadState.queued:
      case DownloadState.running:
        body = total > 0 && download.message == null
            ? 'Chapter ${download.done} of $total'
            : download.message ?? 'Starting';
      case DownloadState.needsCheck:
        body =
            "Paused: ranobes.net wants to check you're human. Tap to verify.";
      case DownloadState.paused:
        body = 'Paused';
      case DownloadState.done:
        body = download.message ?? 'All ${download.done} chapters saved';
    }
    await _plugin.show(
      id: _downloadId(novel.id!),
      title: download.state == DownloadState.done
          ? 'Downloaded ${novel.title}'
          : 'Downloading ${novel.title}',
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'downloads',
          'Downloads',
          channelDescription: 'Novels being saved for offline reading',
          icon: 'ic_stat_scry',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: active,
          maxProgress: total > 0 ? total : 1,
          progress: download.done.clamp(0, total > 0 ? total : 1),
          indeterminate: active && total <= 0,
          onlyAlertOnce: true,
          ongoing: active,
          autoCancel: !active,
        ),
      ),
      payload: '$_pagePrefix${novel.id}',
    );
  }

  /// Clears [novelId]'s download notification.
  static Future<void> dismissDownload(int novelId) async {
    if (!supported) return;
    await initialize();
    await _plugin.cancel(id: _downloadId(novelId));
  }
}
