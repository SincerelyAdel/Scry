import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/novel.dart';
import '../../services/ranobes.dart';
import '../../state/novels_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme.dart';
import '../../widgets/cats/cat_layer.dart';
import '../../widgets/page_gestures.dart';
import '../../widgets/ui.dart';
import 'human_check_screen.dart';

/// Reads a novel chapter by chapter. Remembers how far down the chapter
/// you are, keeps the screen on, and has the next chapter ready before you
/// reach the end.
class ChapterReaderScreen extends StatefulWidget {
  const ChapterReaderScreen({
    super.key,
    required this.novelId,
    this.url,
    this.number = 0,
  });

  final int novelId;

  /// The chapter to open; null for the novel's first.
  final String? url;

  /// Its position in the novel, or 0 when not known.
  final int number;

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen> {
  late final NovelsProvider _novels;
  late Novel _novel;
  final _scroll = ScrollController();

  ChapterText? _chapter;
  int _number = 0;
  bool _loading = true;
  String? _error;
  Object? _failure;
  String? _pendingUrl;

  /// The cats (when on): lying down, or chased to the edges.
  bool _catsResting = false;
  bool _catsShooed = false;

  /// How far down the chapter, 0 to 1; drives the bar at the bottom.
  final _progress = ValueNotifier<double>(0);
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _novels = context.read<NovelsProvider>();
    _novel = _novels.byId(widget.novelId)!;
    _scroll.addListener(_onScroll);
    WakelockPlus.enable().ignore();
    _open(widget.url, widget.number, restore: true);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _save();
    WakelockPlus.disable().ignore();
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _open(String? url, int number, {bool restore = false}) async {
    _saveTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _pendingUrl = url;
    });
    final repo = _novels.repository;
    try {
      final chapter = url == null
          ? await repo.firstChapter(_novel)
          : await repo.chapter(_novel, url);
      if (!mounted) return;
      final resume = restore && chapter.url == _novel.chapterUrl
          ? _novel.chapterProgress
          : 0.0;
      setState(() {
        _chapter = chapter;
        _number = url == null ? 1 : number;
        _loading = false;
      });
      _progress.value = resume;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(resume * max);
      });
      await _save(progress: resume);
      final next = chapter.nextUrl;
      if (next != null) repo.prefetch(_novel, next).ignore();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
          _failure = e;
        });
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _progress.value = max <= 0 ? 1 : (_scroll.offset / max).clamp(0.0, 1.0);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  }

  Future<void> _save({double? progress}) async {
    final chapter = _chapter;
    if (chapter == null) return;
    _novel = await _novels.saveProgress(
      _novel,
      chapter: chapter,
      number: _number,
      progress: progress ?? _progress.value,
    );
  }

  void _next() {
    final url = _chapter?.nextUrl;
    if (url != null) _open(url, _number > 0 ? _number + 1 : 0);
  }

  void _previous() {
    final url = _chapter?.prevUrl;
    if (url != null) _open(url, _number > 1 ? _number - 1 : 0);
  }

  void _textSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _TextSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final settings = context.watch<SettingsProvider>();
    final chapter = _chapter;
    // The column below already limits the width, so a plain margin.
    const pad = 20.0;

    final textStyle = TextStyle(
      fontFamily: settings.novelFont == NovelFont.serif ? kSerif : null,
      color: c.text,
      fontSize: settings.novelFontSize,
      height: settings.novelLineHeight,
    );

    Widget content;
    if (_loading && chapter == null) {
      content = const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      content = SliverFillRemaining(
        child: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: "Couldn't load the chapter",
          message: _error,
          action:
              humanCheckAction(
                context,
                _failure,
                () => _open(_pendingUrl, _number),
              ) ??
              FilledButton(
                onPressed: () => _open(_pendingUrl, _number),
                child: const Text('Try again'),
              ),
        ),
      );
    } else {
      content = SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            // Full reading width, not just as wide as the first line.
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(pad, 12, pad, 48),
              child: SelectionArea(
                child: SwipeNavArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _number > 0
                            ? '${_novel.title}  ·  $_number of ${_novel.chapterCount}'
                            : _novel.title,
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        chapter!.title,
                        style: TextStyle(
                          fontFamily: kSerif,
                          color: c.text,
                          fontSize: settings.novelFontSize + 6,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: settings.novelFontSize * 1.4),
                      for (final paragraph in chapter.paragraphs)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: settings.novelFontSize * 0.9,
                          ),
                          child: Text(paragraph, style: textStyle),
                        ),
                      const SizedBox(height: 24),
                      _ChapterNav(
                        chapter: chapter,
                        loading: _loading,
                        onPrevious: _previous,
                        onNext: _next,
                        onCheckAgain: () => _open(chapter.url, _number),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final canMove = chapter != null && !_loading;
    return Scaffold(
      body: SwipeNav(
        onNext: canMove && chapter.nextUrl != null ? _next : null,
        onPrevious: canMove && chapter.prevUrl != null ? _previous : null,
        nextLabel: 'Next chapter',
        previousLabel: 'Previous chapter',
        child: CatLayer(
          enabled: settings.novelCats,
          resting: _catsResting,
          shooed: _catsShooed,
          opacity: c.isDark ? 0.82 : 0.9,
          child: Stack(
            children: [
              CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    title: Text(
                      chapter?.title ?? _novel.title,
                      style: const TextStyle(fontSize: 16),
                    ),
                    actions: [
                      IconButton(
                        tooltip: 'Text',
                        icon: const Icon(Icons.text_fields),
                        onPressed: _textSettings,
                      ),
                      IconButton(
                        tooltip: 'Chapters',
                        icon: const Icon(Icons.format_list_numbered),
                        // The novel's page is always under the reader.
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      if (chapter != null && chapter.url.startsWith('http'))
                        IconButton(
                          tooltip: 'Open on ranobes.net',
                          icon: const Icon(Icons.open_in_browser),
                          onPressed: () => launchUrl(
                            Uri.parse(chapter.url),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                    ],
                  ),
                  content,
                ],
              ),
              // Loading the next chapter over the current one.
              if (_loading && chapter != null)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  // Gold running into the icon's purple as you read on.
                  builder: (_, value, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: c.goldViolet(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (settings.novelCats)
                Positioned(
                  right: 14,
                  bottom: 14 + MediaQuery.paddingOf(context).bottom,
                  child: _CatButtons(
                    resting: _catsResting,
                    shooed: _catsShooed,
                    onRest: () => setState(() => _catsResting = !_catsResting),
                    onShoo: () => setState(() => _catsShooed = !_catsShooed),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two small round buttons for the cats: lie down (or get up), and shoo
/// them to the edges (or call them back).
class _CatButtons extends StatelessWidget {
  const _CatButtons({
    required this.resting,
    required this.shooed,
    required this.onRest,
    required this.onShoo,
  });

  final bool resting;
  final bool shooed;
  final VoidCallback onRest;
  final VoidCallback onShoo;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    Widget button(IconData icon, String tip, bool on, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: Material(
            color: on ? c.button : c.surface.withValues(alpha: 0.92),
            shape: CircleBorder(side: BorderSide(color: c.border)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, size: 20, color: on ? c.onButton : c.muted),
              ),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          Icons.pets,
          resting ? 'Let the cats roam' : 'Let the cats rest',
          resting,
          onRest,
        ),
        const SizedBox(width: 10),
        button(
          shooed ? Icons.visibility : Icons.visibility_off_outlined,
          shooed ? 'Call the cats back' : 'Shoo the cats away',
          shooed,
          onShoo,
        ),
      ],
    );
  }
}

/// Previous and next chapter at the end of the text. At the latest
/// chapter, says so and offers to look again.
class _ChapterNav extends StatelessWidget {
  const _ChapterNav({
    required this.chapter,
    required this.loading,
    required this.onPrevious,
    required this.onNext,
    required this.onCheckAgain,
  });

  final ChapterText chapter;
  final bool loading;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Column(
      children: [
        Divider(color: c.border),
        const SizedBox(height: 16),
        if (chapter.nextUrl == null) ...[
          Text(
            "You're caught up. This is the latest chapter.",
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 14),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            if (chapter.prevUrl != null)
              OutlinedButton.icon(
                onPressed: loading ? null : onPrevious,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
            const Spacer(),
            if (chapter.nextUrl != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
                onPressed: loading ? null : onNext,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next chapter'),
              )
            else
              OutlinedButton.icon(
                onPressed: loading ? null : onCheckAgain,
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Text size, line spacing and font for novels.
class _TextSettingsSheet extends StatelessWidget {
  const _TextSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final settings = context.watch<SettingsProvider>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Size', style: TextStyle(color: c.text, fontSize: 15)),
                Expanded(
                  child: Slider(
                    value: settings.novelFontSize,
                    min: SettingsProvider.minNovelFontSize,
                    max: SettingsProvider.maxNovelFontSize,
                    divisions:
                        (SettingsProvider.maxNovelFontSize -
                                SettingsProvider.minNovelFontSize)
                            .round(),
                    label: '${settings.novelFontSize.round()}',
                    onChanged: settings.setNovelFontSize,
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${settings.novelFontSize.round()}',
                    style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 1.5, label: Text('Tight')),
                ButtonSegment(value: 1.7, label: Text('Normal')),
                ButtonSegment(value: 1.95, label: Text('Loose')),
              ],
              selected: {_nearest(settings.novelLineHeight)},
              onSelectionChanged: (v) => settings.setNovelLineHeight(v.first),
            ),
            const SizedBox(height: 12),
            SegmentedButton<NovelFont>(
              segments: const [
                ButtonSegment(value: NovelFont.serif, label: Text('Serif')),
                ButtonSegment(value: NovelFont.sans, label: Text('Sans')),
              ],
              selected: {settings.novelFont},
              onSelectionChanged: (v) => settings.setNovelFont(v.first),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.pets, color: c.muted),
              title: Text('Cats', style: TextStyle(color: c.text)),
              subtitle: Text(
                'Wander about behind the text. Tap one to scare it off.',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
              value: settings.novelCats,
              onChanged: settings.setNovelCats,
            ),
          ],
        ),
      ),
    );
  }

  static double _nearest(double height) => const [
    1.5,
    1.7,
    1.95,
  ].reduce((a, b) => (a - height).abs() <= (b - height).abs() ? a : b);
}
