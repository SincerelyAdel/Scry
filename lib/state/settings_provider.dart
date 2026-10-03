import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/article_sort.dart';

/// How often the background worker refreshes feeds.
enum SyncInterval {
  off('Off', null),
  every2Hours('Every 2 hours', Duration(hours: 2)),
  every4Hours('Every 4 hours', Duration(hours: 4));

  const SyncInterval(this.label, this.duration);

  final String label;
  final Duration? duration;
}

/// Accent colours offered in settings. Material 3 builds the full scheme
/// from the seed.
const themeSeedColors = <String, Color>{
  'Indigo': Colors.indigo,
  'Teal': Colors.teal,
  'Green': Colors.green,
  'Amber': Colors.amber,
  'Deep orange': Colors.deepOrange,
  'Pink': Colors.pink,
  'Purple': Colors.deepPurple,
  'Blue grey': Colors.blueGrey,
};

/// User preferences, persisted with shared_preferences.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs)
    : _themeMode = _enumOr(
        ThemeMode.values,
        _prefs.getString(_kThemeMode),
        ThemeMode.system,
      ),
      _seedName = themeSeedColors.containsKey(_prefs.getString(_kSeed))
          ? _prefs.getString(_kSeed)!
          : themeSeedColors.keys.first,
      _fontSize = (_prefs.getDouble(_kFontSize) ?? defaultFontSize).clamp(
        minFontSize,
        maxFontSize,
      ),
      _sort = _enumOr(
        ArticleSort.values,
        _prefs.getString(_kSort),
        ArticleSort.newest,
      ),
      _syncInterval = _enumOr(
        SyncInterval.values,
        _prefs.getString(_kSyncInterval),
        SyncInterval.every4Hours,
      );

  final SharedPreferences _prefs;

  static const _kThemeMode = 'themeMode';
  static const _kSeed = 'seedColor';
  static const _kFontSize = 'articleFontSize';
  static const _kSort = 'articleSort';
  static const _kSyncInterval = 'syncInterval';

  static const minFontSize = 13.0;
  static const maxFontSize = 26.0;
  static const defaultFontSize = 17.0;

  ThemeMode _themeMode;
  String _seedName;
  double _fontSize;
  ArticleSort _sort;
  SyncInterval _syncInterval;

  ThemeMode get themeMode => _themeMode;
  String get seedName => _seedName;
  Color get seedColor => themeSeedColors[_seedName]!;

  /// Body text size in the article reader.
  double get fontSize => _fontSize;

  ArticleSort get sort => _sort;
  SyncInterval get syncInterval => _syncInterval;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setSeed(String name) async {
    if (name == _seedName || !themeSeedColors.containsKey(name)) return;
    _seedName = name;
    notifyListeners();
    await _prefs.setString(_kSeed, name);
  }

  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(minFontSize, maxFontSize);
    if (clamped == _fontSize) return;
    _fontSize = clamped;
    notifyListeners();
    await _prefs.setDouble(_kFontSize, clamped);
  }

  Future<void> setSort(ArticleSort sort) async {
    if (sort == _sort) return;
    _sort = sort;
    notifyListeners();
    await _prefs.setString(_kSort, sort.name);
  }

  Future<void> setSyncInterval(SyncInterval interval) async {
    if (interval == _syncInterval) return;
    _syncInterval = interval;
    notifyListeners();
    await _prefs.setString(_kSyncInterval, interval.name);
  }

  static T _enumOr<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
