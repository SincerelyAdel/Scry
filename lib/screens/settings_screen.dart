import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article_sort.dart';
import '../services/background_sync.dart';
import '../services/chapter_alerts.dart';
import '../state/settings_provider.dart';
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
