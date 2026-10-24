import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/novel.dart';
import '../../services/book_picker.dart';
import '../../services/chapter_matcher.dart';
import '../../services/feed_fetcher.dart';
import '../../services/ranobes.dart';
import '../../state/novels_provider.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/ui.dart';
import 'human_check_screen.dart';
import 'library_screen.dart';
import 'novel_cover.dart';

/// A novel's details and every chapter, oldest first, with the one you're
/// on marked. Chapters load a page at a time as they scroll into view.
class NovelScreen extends StatefulWidget {
  const NovelScreen({super.key, required this.novelId});

  final int novelId;

  @override
  State<NovelScreen> createState() => _NovelScreenState();
}

class _NovelScreenState extends State<NovelScreen> {
  static const _rowHeight = 58.0;

  final _scroll = ScrollController();
  final _headerKey = GlobalKey();

  /// Chapters found so far, by number.
  final Map<int, ChapterRef> _chapters = {};

  /// List pages loading or loaded (site pages are newest first).
  final Set<int> _requested = {};
  final Set<int> _failed = {};
  bool _askedHumanCheck = false;
  int _perPage = 25;

  /// The count the list is laid out for; follows the site when it changes.
  int _count = 0;

  /// Chapters recorded on this device (browsed, downloaded or imported),
  /// so the list works offline.
  final Map<int, ChapterRef> _index = {};

  /// Chapters from an EPUB were added to this ranobes.net novel.
  bool _hasBook = false;
  bool _attaching = false;

  /// A chapter read from the phone (an EPUB's).
  static bool _onPhone(ChapterRef? ref) =>
      ref != null && ref.url.startsWith('epub://');

  @override
  void initState() {
    super.initState();
    final novel = context.read<NovelsProvider>().byId(widget.novelId);
    _count = novel?.chapterCount ?? 0;
    _loadIndex(novel);
  }

  Future<void> _loadIndex(Novel? novel) async {
    if (novel == null) return;
    final novels = context.read<NovelsProvider>();
    final refs = await novels.repository.chapterIndex(novel.id!);
    if (!mounted) return;
    setState(() {
      _index.clear();
      _chapters.removeWhere((_, ref) => _onPhone(ref));
      for (final ref in refs) {
        _index[ref.number] = ref;
        // The saved copy wins over the site's link.
        if (_onPhone(ref)) {
          _chapters[ref.number] = ref;
        } else {
          _chapters.putIfAbsent(ref.number, () => ref);
        }
        if (ref.number > _count) _count = ref.number;
      }
      _hasBook = !novel.isImported && refs.any(_onPhone);
    });
    // Shows the newest chapters' page first, which also corrects the
    // count. Imported books have nothing online.
    if (!novel.isImported) _loadPage(1);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadPage(int page) async {
    if (!_requested.add(page)) return;
    final novels = context.read<NovelsProvider>();
    final novel = novels.byId(widget.novelId);
    if (novel == null) return;
    try {
      final result = await novels.repository.chapterPage(
        novel.bookId,
        page,
        novelId: novel.id,
      );
      if (!mounted) return;
      setState(() {
        _failed.remove(page);
        _perPage = result.perPage;
        final changed = result.chapterCount != _count;
        if (changed && page != 1 && result.chapterCount < _count) {
          // Fetched before a newer chapter came out: numbers are off.
          _requested.remove(page);
          return;
        }
        if (changed) {
          // New chapters shift every page; start over with the new count.
          _count = result.chapterCount;
          _chapters
            ..clear()
            ..addAll(_index);
          _requested
            ..clear()
            ..add(page);
        }
        for (final ref in result.chapters) {
          // Chapters from the EPUB stay on the phone.
          if (_onPhone(_index[ref.number])) continue;
          _chapters[ref.number] = ref;
          _index[ref.number] = ref;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _requested.remove(page);
        _failed.add(page);
      });
      if (e is HumanCheckRequired && !_askedHumanCheck) {
        // Once per screen; the failed pages load again after it's passed.
        _askedHumanCheck = true;
        showHumanCheckSnack(context, e, () {
          _askedHumanCheck = false;
          final pages = [..._failed];
          setState(_failed.clear);
          pages.forEach(_loadPage);
        });
      }
    }
  }

  /// The site page holding chapter [number].
  int _pageOf(int number) => (_count - number) ~/ _perPage + 1;

  void _jumpTo(int number) {
    final header = _headerKey.currentContext?.size?.height ?? 0;
    final target = header + (number - 1) * _rowHeight - 120;
    _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
  }

  Future<void> _askChapter() async {
    final controller = TextEditingController();
    final number = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to chapter'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: '1 to $_count'),
          onSubmitted: (v) => Navigator.of(context).pop(int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (number != null && number > 0 && mounted) {
      _jumpTo(number.clamp(1, _count));
    }
  }

  /// Adds the chapters of an EPUB of this novel (from QuickNovel), so
  /// they're read from the phone; then says how they lined up.
  Future<void> _attach(Novel novel) async {
    final messenger = ScaffoldMessenger.of(context);
    final novels = context.read<NovelsProvider>();
    try {
      final bytes = await BookPicker.pick();
      if (bytes == null || !mounted) return;
      setState(() => _attaching = true);
      final match = await novels.attachBook(novel, bytes);
      if (!mounted) return;
      await _loadIndex(novels.byId(novel.id));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _MatchReport(match: match, siteCount: _count),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't add the chapters: $e")),
      );
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<void> _detach(Novel novel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the EPUB chapters?'),
        content: const Text(
          'They load from ranobes.net again when you read them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final novels = context.read<NovelsProvider>();
    await novels.detachBook(novel);
    if (!mounted) return;
    setState(() {
      _chapters.clear();
      _requested.clear();
      _failed.clear();
    });
    await _loadIndex(novels.byId(novel.id));
  }

  Future<void> _remove(Novel novel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${novel.title}?'),
        content: const Text(
          'Your place in it and its saved chapters are removed too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await context.read<NovelsProvider>().remove(novel);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final novels = context.watch<NovelsProvider>();
    final novel = novels.byId(widget.novelId);
    if (novel == null) return const Scaffold();
    final pad = pagePadding(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(novel.title),
        actions: [
          IconButton(
            tooltip: 'Go to chapter',
            icon: const Icon(Icons.pin_outlined),
            onPressed: _count > 0 ? _askChapter : null,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'web') {
                launchUrl(
                  Uri.parse(novel.url),
                  mode: LaunchMode.externalApplication,
                );
              } else if (v == 'remove') {
                _remove(novel);
              } else if (v == 'attach') {
                _attach(novel);
              } else if (v == 'detach') {
                _detach(novel);
              }
            },
            itemBuilder: (_) => [
              if (!novel.isImported && BookPicker.supported)
                PopupMenuItem(
                  value: 'attach',
                  enabled: !_attaching,
                  child: Text(
                    _hasBook
                        ? 'Replace chapters from EPUB'
                        : 'Add chapters from EPUB',
                  ),
                ),
              if (_hasBook)
                const PopupMenuItem(
                  value: 'detach',
                  child: Text('Remove EPUB chapters'),
                ),
              if (!novel.isImported)
                const PopupMenuItem(
                  value: 'web',
                  child: Text('Open on ranobes.net'),
                ),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove from library'),
              ),
            ],
          ),
        ],
      ),
      body: Scrollbar(
        controller: _scroll,
        interactive: true,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              key: _headerKey,
              child: _Header(
                novel: novel,
                count: _count,
                hasBook: _hasBook,
                padding: pad,
                onJump: novel.chapterNumber > 0
                    ? () => _jumpTo(novel.chapterNumber)
                    : null,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 32),
              sliver: SliverFixedExtentList(
                itemExtent: _rowHeight,
                delegate: SliverChildBuilderDelegate(childCount: _count, (
                  context,
                  i,
                ) {
                  final number = i + 1;
                  final ref = _chapters[number];
                  final page = _pageOf(number);
                  if (ref == null &&
                      !_failed.contains(page) &&
                      !novel.isImported) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _loadPage(page),
                    );
                  }
                  return _ChapterRow(
                    number: number,
                    chapter: ref,
                    failed: ref == null && _failed.contains(page),
                    onRetry: () => setState(() {
                      _failed.remove(page);
                    }),
                    current: novel.chapterNumber == number,
                    read: number < novel.chapterNumber,
                    onPhone: _onPhone(ref) && !novel.isImported,
                    onTap: ref == null
                        ? null
                        : () => openReader(
                            context,
                            novel,
                            url: ref.url,
                            number: number,
                            fromNovelPage: true,
                          ),
                  );
                }),
              ),
            ),
            if (_count == 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No chapters yet',
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header({
    required this.novel,
    required this.count,
    this.hasBook = false,
    required this.padding,
    this.onJump,
  });

  final Novel novel;
  final int count;
  final bool hasBook;
  final double padding;
  final VoidCallback? onJump;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final novel = widget.novel;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          novel.title,
          style: TextStyle(
            fontFamily: kSerif,
            color: c.text,
            fontSize: wide ? 28 : 22,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            ?novel.author,
            ?novel.status,
            '${widget.count} chapters',
          ].join('  ·  '),
          style: TextStyle(color: c.muted, fontSize: 13.5),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () => openReader(context, novel, fromNovelPage: true),
              icon: Icon(
                novel.started ? Icons.play_arrow_rounded : Icons.menu_book,
              ),
              label: Text(
                novel.started && novel.chapterNumber > 0
                    ? 'Continue chapter ${novel.chapterNumber}'
                    : novel.started
                    ? 'Continue'
                    : 'Start reading',
              ),
            ),
            if (widget.onJump != null)
              OutlinedButton.icon(
                onPressed: widget.onJump,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('Show in list'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _OfflineNote(novel: novel, hasBook: widget.hasBook),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(widget.padding, 16, widget.padding, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NovelCover(
                url: novel.cover,
                title: novel.title,
                width: wide ? 150 : 104,
              ),
              const SizedBox(width: 20),
              Expanded(child: info),
            ],
          ),
          if (novel.description != null && novel.description!.isNotEmpty) ...[
            const SizedBox(height: 18),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    novel.description!,
                    maxLines: _expanded ? null : 4,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: TextStyle(color: c.text, fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _expanded ? 'Less' : 'More',
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Divider(color: c.border, height: 1),
          const SizedBox(height: 8),
          const SectionLabel('CHAPTERS'),
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.number,
    required this.chapter,
    required this.failed,
    required this.onRetry,
    required this.current,
    required this.read,
    this.onPhone = false,
    this.onTap,
  });

  final int number;
  final ChapterRef? chapter;
  final bool failed;
  final VoidCallback onRetry;
  final bool current;
  final bool read;

  /// Read from the phone (from the EPUB) rather than the site.
  final bool onPhone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final chapter = this.chapter;
    final title = chapter?.title ?? (failed ? "Couldn't load" : '…');
    return Material(
      color: current ? c.surface : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: current
            ? BorderSide(color: c.accent.withValues(alpha: 0.7))
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: failed ? onRetry : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: current ? c.accent : c.faint,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: read || chapter == null ? c.muted : c.text,
                    fontSize: 15,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (current)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Tag('Reading', color: c.accent),
                )
              else if (failed)
                Icon(Icons.refresh, size: 18, color: c.muted)
              else if (onPhone)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.offline_pin_outlined,
                    size: 16,
                    color: c.faint,
                    semanticLabel: 'On this phone',
                  ),
                )
              else if (chapter?.date != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    relativeDate(chapter!.date!),
                    style: TextStyle(color: c.faint, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the novel's chapters live. Whole novels are downloaded with
/// QuickNovel and their EPUB added here; imported books say they're on the
/// phone.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote({required this.novel, required this.hasBook});

  final Novel novel;
  final bool hasBook;

  static final _quickNovel = Uri.parse(
    'https://github.com/LagradOst/QuickNovel/releases',
  );

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final offline = novel.isImported || hasBook;
    final text = novel.isImported
        ? 'Imported book: every chapter is on this phone'
        : hasBook
        ? 'Chapters marked with a pin are read from the EPUB on this phone; '
              'ranobes.net is only asked about the rest and new ones'
        : 'To read it all offline, download it in QuickNovel, then '
              '⋮ → Add chapters from EPUB';
    return Row(
      children: [
        Icon(
          offline ? Icons.offline_pin_outlined : Icons.info_outline,
          size: 18,
          color: c.muted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: c.muted, fontSize: 13.5)),
        ),
        if (!offline)
          TextButton(
            onPressed: () =>
                launchUrl(_quickNovel, mode: LaunchMode.externalApplication),
            child: const Text('Get QuickNovel'),
          ),
      ],
    );
  }
}

/// How an EPUB's chapters lined up with the novel's, after adding them.
class _MatchReport extends StatelessWidget {
  const _MatchReport({required this.match, required this.siteCount});

  final ChapterMatch match;
  final int siteCount;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    String list(Iterable<Object> items) {
      final all = items.toList();
      final shown = all.take(8).join(', ');
      return all.length > 8 ? '$shown and ${all.length - 8} more' : shown;
    }

    final lines = <String>[
      'Chapters ${match.first} to ${match.last} (${match.chapters.length}) '
          'are now read from this phone.',
      if (match.byOrder)
        "The titles have no chapter numbers, so they were matched in order: "
            "the book's first chapter is chapter 1. If ranobes.net counts "
            'differently, remove them from the ⋮ menu.',
      if (match.merged > 0)
        '${match.merged} chapter parts were joined to the chapter before.',
      if (match.gaps.isNotEmpty)
        'Not in the book, so from ranobes.net: ${list(match.gaps)}.',
      if (match.unnumbered.isNotEmpty)
        'Left out, no chapter number: ${list(match.unnumbered)}.',
      if (match.conflicts.isNotEmpty)
        'Left out, the number came up twice (numbering that starts over '
            'each volume?): ${list(match.conflicts)}.',
      if (siteCount > match.last)
        'Chapters ${match.last + 1} to $siteCount come from ranobes.net.'
      else if (match.last > siteCount)
        'The book goes past the $siteCount chapters ranobes.net had at the '
            'last check; check its numbers match.',
    ];
    return AlertDialog(
      title: const Text('Chapters added'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  line,
                  style: TextStyle(color: c.text, fontSize: 14.5, height: 1.4),
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
