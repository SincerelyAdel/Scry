import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/novel.dart';
import '../../models/passage.dart';
import '../../services/ranobes.dart';
import '../../state/novels_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme.dart';
import '../../widgets/cats/cat_layer.dart';
import '../../widgets/cats/cat_menu.dart';
import '../../widgets/living_words/lexicon.dart';
import '../../widgets/living_words/living_controller.dart';
import '../../widgets/living_words/living_menu.dart';
import '../../widgets/living_words/living_text.dart';
import '../../widgets/living_words/mood_layer.dart';
import '../../widgets/page_gestures.dart';
import '../../widgets/ui.dart';
import 'human_check_screen.dart';
import 'passage_selection.dart';

/// Reads a novel chapter by chapter. Remembers how far down the chapter
/// you are, keeps the screen on, and has the next chapter ready before you
/// reach the end.
class ChapterReaderScreen extends StatefulWidget {
  const ChapterReaderScreen({
    super.key,
    required this.novelId,
    this.url,
    this.number = 0,
    this.focus,
  });

  final int novelId;

  /// The chapter to open; null for the novel's first.
  final String? url;

  /// Its position in the novel, or 0 when not known.
  final int number;

  /// A saved passage's first and last paragraph: the reader scrolls to it
  /// and lifts it off the page for a moment.
  final (int, int)? focus;

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

  /// Living words: which one plays, and the chapter split into runs.
  final _living = LivingWordsController();
  List<List<LivingRun>>? _runs;
  ChapterText? _runsFor;

  /// Saving passages: the paragraphs held, and one just opened from the
  /// saved passages, shown briefly.
  final _passage = PassageSelectionController();
  (int, int)? _pendingFocus;

  /// How far down the chapter, 0 to 1; drives the bar at the bottom.
  final _progress = ValueNotifier<double>(0);
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _novels = context.read<NovelsProvider>();
    _novel = _novels.byId(widget.novelId)!;
    _scroll.addListener(_onScroll);
    _pendingFocus = widget.focus;
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
    _living.dispose();
    _passage.dispose();
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
      _living.reset();
      _passage.clear();
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
        // Opened from a saved passage: go to it once laid out.
        final focus = _pendingFocus;
        _pendingFocus = null;
        if (focus != null) _passage.reveal(focus.$1, focus.$2);
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

  String _textOf(int from, int to) =>
      _chapter!.paragraphs.sublist(from, to + 1).join('\n\n');

  /// Saves the held paragraphs as a passage.
  Future<void> _savePassage(int from, int to) async {
    final chapter = _chapter;
    if (chapter == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final passage = await _novels.savePassage(
      Passage(
        novelId: _novel.id!,
        novelTitle: _novel.title,
        chapterUrl: chapter.url,
        chapterNumber: _number,
        chapterTitle: chapter.title,
        from: from,
        to: to,
        text: _textOf(from, to),
        savedAt: DateTime.now(),
      ),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            passage.paragraphCount == 1
                ? 'Passage saved'
                : 'Passage saved: ${passage.paragraphCount} paragraphs',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _novels.removePassage(passage),
          ),
        ),
      );
  }

  Future<void> _copyPassage(int from, int to) async {
    if (_chapter == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _textOf(from, to)));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied')));
  }

  void _textSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _TextSettingsSheet(),
    );
  }

  /// The chapter's paragraphs split into plain text and living words.
  List<List<LivingRun>> _runsOf(ChapterText chapter) {
    if (_runsFor != chapter || _runs == null) {
      _runsFor = chapter;
      _runs = [for (final p in chapter.paragraphs) Lexicon.instance.split(p)];
    }
    return _runs!;
  }

  /// Keeps the controller in step with the settings. Turning it off stops
  /// a playing word, which rebuilds widgets, so that waits for the frame.
  void _syncLiving(SettingsProvider settings) {
    _living
      ..speed = settings.livingSpeed
      ..screen = MediaQuery.sizeOf(context)
      ..still = MediaQuery.disableAnimationsOf(context);
    if (_living.enabled != settings.livingWords) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _living.enabled = context.read<SettingsProvider>().livingWords;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final settings = context.watch<SettingsProvider>();
    final chapter = _chapter;
    _syncLiving(settings);
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
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 48),
              child: SwipeNavArea(
                child: PassageSelection(
                  controller: _passage,
                  scroll: _scroll,
                  gutter: pad,
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
                      for (final (i, paragraph) in chapter.paragraphs.indexed)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: settings.novelFontSize * 0.9,
                          ),
                          child: PassageParagraph(
                            controller: _passage,
                            index: i,
                            child: settings.livingWords
                                ? LivingParagraph(
                                    id: i,
                                    runs: _runsOf(chapter)[i],
                                    style: textStyle,
                                  )
                                : Text(paragraph, style: textStyle),
                          ),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: _passage,
      builder: (context, page) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          end: _passage.selection == null
              ? c.bg
              : dark
              ? Colors.black
              : Color.lerp(c.bg, Colors.black, 0.07),
        ),
        duration: const Duration(milliseconds: 450),
        builder: (context, bg, _) => Scaffold(backgroundColor: bg, body: page),
      ),
      child: SwipeNav(
        onNext: canMove && chapter.nextUrl != null ? _next : null,
        onPrevious: canMove && chapter.prevUrl != null ? _previous : null,
        nextLabel: 'Next chapter',
        previousLabel: 'Previous chapter',
        // While a living word plays, the cats step out of its way.
        child: ValueListenableBuilder<LivingEffect?>(
          valueListenable: _living.effect,
          builder: (context, playing, page) => CatLayer(
            enabled: settings.novelCats,
            resting: _catsResting,
            shooed: _catsShooed || playing != null,
            // Over the page now, so at full strength; they keep to the
            // margins beside the text (the column is at most 760 wide).
            textWidth: math.min(MediaQuery.sizeOf(context).width, 760) - 24,
            child: page!,
          ),
          child: Stack(
            children: [
              LivingWordsScope(
                controller: _living,
                child: CustomScrollView(
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
                        LivingWordsMenuButton(
                          on: settings.livingWords,
                          mood: settings.livingMood,
                          speed: settings.livingSpeed,
                          playing: _living.effect,
                          onChanged: settings.setLivingWords,
                          onMood: settings.setLivingMood,
                          onSpeed: settings.setLivingSpeed,
                        ),
                        CatMenuButton(
                          on: settings.novelCats,
                          resting: _catsResting,
                          shooed: _catsShooed,
                          onChanged: settings.setNovelCats,
                          onRest: (v) => setState(() => _catsResting = v),
                          onShoo: (v) => setState(() => _catsShooed = v),
                        ),
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
              ),
              if (settings.livingWords && settings.livingMood)
                Positioned.fill(
                  child: LivingMoodLayer(
                    controller: _living,
                    ink: c.text,
                    paper: c.bg,
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
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
                left: 12,
                right: 12,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: PassageToolbar(
                    controller: _passage,
                    onSave: _savePassage,
                    onCopy: _copyPassage,
                  ),
                ),
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
            ],
          ),
        ),
      ),
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
