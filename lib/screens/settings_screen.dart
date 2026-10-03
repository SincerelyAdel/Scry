import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article_sort.dart';
import '../services/background_sync.dart';
import '../state/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _Section('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
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
          ),
          const ListTile(title: Text('Accent colour')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in themeSeedColors.entries)
                  _ColorSwatch(
                    name: entry.key,
                    color: entry.value,
                    selected: entry.key == settings.seedName,
                    onTap: () => settings.setSeed(entry.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Article text size'),
            trailing: Text('${settings.fontSize.round()}'),
          ),
          Slider(
            value: settings.fontSize,
            min: SettingsProvider.minFontSize,
            max: SettingsProvider.maxFontSize,
            divisions:
                (SettingsProvider.maxFontSize - SettingsProvider.minFontSize)
                    .round(),
            label: '${settings.fontSize.round()}',
            onChanged: settings.setFontSize,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'The quick brown fox reads its feeds offline.',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: settings.fontSize,
                height: 1.55,
              ),
            ),
          ),
          const _Section('Inbox'),
          RadioGroup<ArticleSort>(
            groupValue: settings.sort,
            onChanged: (sort) {
              if (sort != null) settings.setSort(sort);
            },
            child: Column(
              children: [
                for (final sort in ArticleSort.values)
                  RadioListTile<ArticleSort>(
                    value: sort,
                    title: Text(sort.label),
                  ),
              ],
            ),
          ),
          const _Section('Sync'),
          ListTile(
            title: const Text('Background refresh'),
            subtitle: Text(
              BackgroundSync.supported
                  ? 'Fetches new articles while the app is closed, '
                        'on Wi-Fi or mobile data when the battery is not low.'
                  : 'Not available on this platform. Feeds refresh when '
                        'the app opens and when you pull down in the inbox.',
            ),
            trailing: DropdownButton<SyncInterval>(
              value: settings.syncInterval,
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
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Tooltip(
        message: name,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        ),
      ),
    );
  }
}
