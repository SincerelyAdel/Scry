import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article_sort.dart';
import '../services/background_sync.dart';
import '../services/chapter_alerts.dart';
import '../state/settings_provider.dart';
import '../sync/drive_sync.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final c = context.palette;
    final pad = pagePadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 32),
        children: [
          const SectionLabel('APPEARANCE'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => settings.setThemeMode(s.first),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Article text size',
                        style: TextStyle(color: c.text, fontSize: 15),
                      ),
                    ),
                    Text(
                      '${settings.fontSize.round()}',
                      style: TextStyle(
                        color: c.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: settings.fontSize,
                  min: SettingsProvider.minFontSize,
                  max: SettingsProvider.maxFontSize,
                  divisions:
                      (SettingsProvider.maxFontSize -
                              SettingsProvider.minFontSize)
                          .round(),
                  label: '${settings.fontSize.round()}',
                  onChanged: settings.setFontSize,
                ),
                Text(
                  'The quick brown fox reads its feeds offline.',
                  style: TextStyle(
                    fontFamily: kSerif,
                    color: c.text,
                    fontSize: settings.fontSize,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('INBOX ORDER'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RadioGroup<ArticleSort>(
              groupValue: settings.sort,
              onChanged: (sort) {
                if (sort != null) settings.setSort(sort);
              },
              child: Column(
                children: [
                  for (final sort in ArticleSort.values)
                    RadioListTile<ArticleSort>(
                      value: sort,
                      title: Text(
                        sort.label,
                        style: TextStyle(color: c.text, fontSize: 15),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SectionLabel('SYNC'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Background refresh',
                        style: TextStyle(color: c.text, fontSize: 15),
                      ),
                    ),
                    DropdownButton<SyncInterval>(
                      value: settings.syncInterval,
                      underline: const SizedBox.shrink(),
                      dropdownColor: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        color: c.accent,
                        fontWeight: FontWeight.w600,
                      ),
                      onChanged: BackgroundSync.supported
                          ? (v) {
                              if (v != null) settings.setSyncInterval(v);
                            }
                          : null,
                      items: [
                        for (final interval in SyncInterval.values)
                          DropdownMenuItem(
                            value: interval,
                            child: Text(interval.label),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  BackgroundSync.supported
                      ? 'Fetches new articles while the app is closed, '
                            'on Wi-Fi or mobile data when the battery is not '
                            'low.'
                      : 'Not available on this platform. Feeds refresh when '
                            'the app opens and when you pull down in the '
                            'inbox.',
                  style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const _DriveCard(),
          const SectionLabel('NOVELS'),
          AppCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.chapterAlerts && ChapterAlerts.supported,
              onChanged: ChapterAlerts.supported
                  ? settings.setChapterAlerts
                  : null,
              title: Text(
                'New chapter alerts',
                style: TextStyle(color: c.text, fontSize: 15),
              ),
              subtitle: Text(
                ChapterAlerts.supported
                    ? 'Checks the novels you are reading about once an hour '
                          'and notifies you when new chapters come out.'
                    : 'Not available on this platform. New chapters show '
                          'in the library when it opens.',
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Syncing the library with Google Drive, between this device and others.
class _DriveCard extends StatelessWidget {
  const _DriveCard();

  static String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveSync?>();
    if (drive == null) return const SizedBox.shrink();
    final c = context.palette;
    final muted = TextStyle(color: c.muted, fontSize: 13, height: 1.4);
    final String about;
    if (!drive.available) {
      about = 'Needs a one-time Google setup before it can be turned on.';
    } else if (!drive.enabled) {
      about =
          'Keeps your novels, reading places, saved passages and feeds the '
          'same on every device you sign in on. Stored in a hidden folder in '
          'your Google Drive that only Scry can see.';
    } else {
      final last = drive.lastSync;
      about = [
        if (drive.email != null) drive.email!,
        drive.syncing
            ? 'Syncing…'
            : (last == null ? 'Not synced yet' : 'Synced ${_ago(last)}'),
      ].join('  ·  ');
    }
    final error = drive.enabled ? drive.error : null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: drive.enabled,
              onChanged: drive.available
                  ? (on) => on ? drive.enable() : drive.disable()
                  : null,
              title: Text(
                'Sync with Google Drive',
                style: TextStyle(color: c.text, fontSize: 15),
              ),
              subtitle: Text(about, style: muted),
            ),
            if (error != null)
              Text(error, style: muted.copyWith(color: c.accent)),
            if (drive.enabled)
              Align(
                alignment: Alignment.centerRight,
                child: drive.needsSignIn
                    ? TextButton(
                        onPressed: drive.enable,
                        child: const Text('Sign in'),
                      )
                    : TextButton(
                        onPressed: drive.syncing ? null : drive.sync,
                        child: const Text('Sync now'),
                      ),
              ),
            if (!drive.enabled && drive.available)
              Text(
                'Downloaded chapters stay on each device. Books imported '
                'from EPUB files sync their place and passages once the '
                'same book is imported on the other device.',
                style: muted,
              ),
          ],
        ),
      ),
    );
  }
}
