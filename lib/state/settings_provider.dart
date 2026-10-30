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

/// The app's two sides, switched from the header.
enum AppMode { feeds, novels }

/// Novel text: serif or sans.
enum NovelFont { serif, sans }

/// How quickly a living word grows to full strength.
enum LivingSpeed {
  slow('Slow', 40),
  normal('Normal', 18),
  fast('Fast', 6);

  const LivingSpeed(this.label, this.seconds);

  final String label;
  final double seconds;
}

/// User preferences, persisted with shared_preferences.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs)
    : _themeMode = _enumOr(
        ThemeMode.values,
        _prefs.getString(_kThemeMode),
        // Dark gold by default, like Tome.
        ThemeMode.dark,
      ),
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
      ),
      _mode = _enumOr(AppMode.values, _prefs.getString(_kMode), AppMode.feeds),
      _novelFontSize = (_prefs.getDouble(_kNovelFontSize) ?? 20.0).clamp(
        minNovelFontSize,
        maxNovelFontSize,
      ),
      _novelLineHeight = (_prefs.getDouble(_kNovelLineHeight) ?? 1.7).clamp(
        1.3,
        2.2,
      ),
      _novelFont = _enumOr(
        NovelFont.values,
        _prefs.getString(_kNovelFont),
        NovelFont.serif,
      ),
      _chapterAlerts = _prefs.getBool(_kChapterAlerts) ?? true,
      _novelCats = _prefs.getBool(_kNovelCats) ?? false,
      _livingWords = _prefs.getBool(_kLivingWords) ?? false,
      _livingMood = _prefs.getBool(_kLivingMood) ?? true,
      _livingSpeed = _enumOr(
        LivingSpeed.values,
        _prefs.getString(_kLivingSpeed),
        LivingSpeed.normal,
      );

  final SharedPreferences _prefs;

  static const _kThemeMode = 'themeMode';
  static const _kFontSize = 'articleFontSize';
  static const _kSort = 'articleSort';
  static const _kSyncInterval = 'syncInterval';
  static const _kMode = 'appMode';
  static const _kNovelFontSize = 'novelFontSize';
  static const _kNovelLineHeight = 'novelLineHeight';
  static const _kNovelFont = 'novelFont';
  static const _kChapterAlerts = 'chapterAlerts';
  static const _kNovelCats = 'novelCats';
  static const _kLivingWords = 'livingWords';
  static const _kLivingMood = 'livingMood';
  static const _kLivingSpeed = 'livingSpeed';

  static const minNovelFontSize = 14.0;
  static const maxNovelFontSize = 32.0;

  static const minFontSize = 13.0;
  static const maxFontSize = 26.0;
  static const defaultFontSize = 17.0;

  ThemeMode _themeMode;
  double _fontSize;
  ArticleSort _sort;
  SyncInterval _syncInterval;
  AppMode _mode;
  double _novelFontSize;
  double _novelLineHeight;
  NovelFont _novelFont;
  bool _chapterAlerts;
  bool _novelCats;
  bool _livingWords;
  bool _livingMood;
  LivingSpeed _livingSpeed;

  /// Words like "fire" and "venom" come alive in a chapter's text.
  bool get livingWords => _livingWords;

  Future<void> setLivingWords(bool on) async {
    if (on == _livingWords) return;
    _livingWords = on;
    notifyListeners();
    await _prefs.setBool(_kLivingWords, on);
  }

  /// The whole page takes on a living word's mood.
  bool get livingMood => _livingMood;

  Future<void> setLivingMood(bool on) async {
    if (on == _livingMood) return;
    _livingMood = on;
    notifyListeners();
    await _prefs.setBool(_kLivingMood, on);
  }

  LivingSpeed get livingSpeed => _livingSpeed;

  Future<void> setLivingSpeed(LivingSpeed speed) async {
    if (speed == _livingSpeed) return;
    _livingSpeed = speed;
    notifyListeners();
    await _prefs.setString(_kLivingSpeed, speed.name);
  }

  /// Cats wandering about behind a chapter's text.
  bool get novelCats => _novelCats;

  Future<void> setNovelCats(bool on) async {
    if (on == _novelCats) return;
    _novelCats = on;
    notifyListeners();
    await _prefs.setBool(_kNovelCats, on);
  }

  /// Notify about new chapters of novels being read.
  bool get chapterAlerts => _chapterAlerts;

  Future<void> setChapterAlerts(bool on) async {
    if (on == _chapterAlerts) return;
    _chapterAlerts = on;
    notifyListeners();
    await _prefs.setBool(_kChapterAlerts, on);
  }

  /// Feeds or novels.
  AppMode get mode => _mode;

  /// The novel reader's text.
  double get novelFontSize => _novelFontSize;
  double get novelLineHeight => _novelLineHeight;
  NovelFont get novelFont => _novelFont;

  Future<void> setMode(AppMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _prefs.setString(_kMode, mode.name);
  }

  Future<void> setNovelFontSize(double size) async {
    final clamped = size.clamp(minNovelFontSize, maxNovelFontSize);
    if (clamped == _novelFontSize) return;
    _novelFontSize = clamped;
    notifyListeners();
    await _prefs.setDouble(_kNovelFontSize, clamped);
  }

  Future<void> setNovelLineHeight(double height) async {
    if (height == _novelLineHeight) return;
    _novelLineHeight = height;
    notifyListeners();
    await _prefs.setDouble(_kNovelLineHeight, height);
  }

  Future<void> setNovelFont(NovelFont font) async {
    if (font == _novelFont) return;
    _novelFont = font;
    notifyListeners();
    await _prefs.setString(_kNovelFont, font.name);
  }

  ThemeMode get themeMode => _themeMode;

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
