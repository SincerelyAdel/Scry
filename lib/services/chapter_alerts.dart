import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/novel.dart';

/// Notifications about new chapters. Tapping one opens the novel where it
/// was left. Android only, like the background checks that send them.
abstract final class ChapterAlerts {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Called with a novel's id when its notification is tapped while the
  /// app is running.
  static void Function(int novelId)? onOpen;

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
        final id = int.tryParse(response.payload ?? '');
        if (id != null) onOpen?.call(id);
      },
    );
    _ready = true;
  }

  /// The novel whose notification started the app, if one did.
  static Future<int?> launchNovelId() async {
    if (!supported) return null;
    await initialize();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return int.tryParse(details.notificationResponse?.payload ?? '');
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
}
