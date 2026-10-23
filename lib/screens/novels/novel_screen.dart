import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/novel.dart';
import '../../services/ranobes.dart';
import '../../state/novels_provider.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/ui.dart';
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
  int _perPage = 25;

  /// The count the list is laid out for; follows the site when it changes.
  int _count = 0;

  @override
  void initState() {
    super.initState();
    final novel = context.read<NovelsProvider>().byId(widget.novelId);
    _count = novel?.chapterCount ?? 0;
    // Shows the newest chapters' page first, which also corrects the count.
    _loadPage(1);
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
      final result = await novels.repository.chapterPage(novel.bookId, page);
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
          _chapters.clear();
          _requested
            ..clear()
            ..add(page);
        }
        for (final ref in result.chapters) {
          _chapters[ref.number] = ref;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requested.remove(page);
        _failed.add(page);
      });
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
    final novel = context.watch<NovelsProvider>().byId(widget.novelId);
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
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'web', child: Text('Open on ranobes.net')),
              PopupMenuItem(
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
                  if (ref == null && !_failed.contains(page)) {
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
                    onTap: ref == null
                        ? null
                        : () => openReader(
                            context,
                            novel,
                            url: ref.url,
                            number: number,
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
    required this.padding,
    this.onJump,
  });

  final Novel novel;
  final int count;
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
              onPressed: () => openReader(context, novel),
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
    this.onTap,
  });

  final int number;
  final ChapterRef? chapter;
  final bool failed;
  final VoidCallback onRetry;
  final bool current;
  final bool read;
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
