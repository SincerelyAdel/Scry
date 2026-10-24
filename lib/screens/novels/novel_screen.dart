import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/novel.dart';
import '../../models/novel_download.dart';
import '../../services/chapter_alerts.dart';
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
      for (final ref in refs) {
        _index[ref.number] = ref;
        _chapters.putIfAbsent(ref.number, () => ref);
      }
      if (_index.length > _count) _count = _index.length;
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

  Future<void> _removeDownload(Novel novel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the download?'),
        content: const Text(
          'The saved chapters are deleted, apart from the ones you read '
          'last. Your place in the novel stays.',
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
    if (ok == true && mounted) {
      await context.read<NovelsProvider>().removeDownload(novel);
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
    final novels = context.watch<NovelsProvider>();
    final novel = novels.byId(widget.novelId);
    if (novel == null) return const Scaffold();
    final download = novels.downloadOf(novel.id);
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
              } else if (v == 'undownload') {
                _removeDownload(novel);
              }
            },
            itemBuilder: (_) => [
              if (!novel.isImported)
                const PopupMenuItem(
                  value: 'web',
                  child: Text('Open on ranobes.net'),
                ),
              if (download != null)
                const PopupMenuItem(
                  value: 'undownload',
                  child: Text('Remove download'),
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
        _DownloadPanel(novel: novel, count: widget.count),
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

/// Downloading the whole novel for offline reading: the button, then how
/// it's going. Imported books say they're on the device.
class _DownloadPanel extends StatelessWidget {
  const _DownloadPanel({required this.novel, required this.count});

  final Novel novel;
  final int count;

  Future<void> _start(BuildContext context) async {
    final novels = context.read<NovelsProvider>();
    // The site allows a chapter every second or two.
    final minutes = (count * 2.2 / 60).ceil();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download every chapter?'),
        content: Text(
          'All $count chapters are saved on this phone, to read without '
          'a connection. ranobes.net only allows a chapter every second or '
          'two, so this takes about '
          '${minutes <= 1 ? 'a minute' : '$minutes minutes'}. It carries '
          'on in the background, and if the site asks you to prove '
          "you're human, it waits until you do.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (context.mounted) await ChapterAlerts.requestPermission();
    await novels.download(novel);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final novels = context.watch<NovelsProvider>();
    final download = novels.downloadOf(novel.id);

    Widget line(IconData icon, String text, {Color? color}) => Row(
      children: [
        Icon(icon, size: 18, color: color ?? c.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color ?? c.muted, fontSize: 13.5),
          ),
        ),
      ],
    );

    if (novel.isImported) {
      return line(
        Icons.offline_pin_outlined,
        'Imported book: every chapter is on this phone',
      );
    }
    if (download == null) {
      return OutlinedButton.icon(
        onPressed: count > 0 ? () => _start(context) : null,
        icon: const Icon(Icons.download_outlined, size: 18),
        label: const Text('Download for offline'),
      );
    }
    final total = download.total > 0 ? download.total : count;
    switch (download.state) {
      case DownloadState.queued:
      case DownloadState.running:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    download.message ??
                        'Downloading: ${download.done} of $total chapters',
                    style: TextStyle(color: c.text, fontSize: 13.5),
                  ),
                ),
                TextButton(
                  onPressed: () => novels.pauseDownload(novel),
                  child: const Text('Pause'),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: download.total > 0 ? download.fraction : null,
                minHeight: 5,
              ),
            ),
          ],
        );
      case DownloadState.needsCheck:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line(
              Icons.pause_circle_outline,
              'Download paused at ${download.done} of $total: ranobes.net '
              "wants to check you're human",
              color: c.accent,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => passHumanCheck(
                context,
                Ranobes.chapterListUrl(novel.bookId, 1),
              ),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Verify and carry on'),
            ),
          ],
        );
      case DownloadState.paused:
        return Row(
          children: [
            Expanded(
              child: line(
                Icons.pause_circle_outline,
                'Download paused at ${download.done} of $total',
              ),
            ),
            TextButton(
              onPressed: () => novels.download(novel),
              child: const Text('Resume'),
            ),
          ],
        );
      case DownloadState.done:
        final missing = count - download.done;
        if (missing > 0) {
          return Row(
            children: [
              Expanded(
                child: line(
                  Icons.offline_pin_outlined,
                  '${download.done} of $count chapters saved',
                ),
              ),
              TextButton(
                onPressed: () => novels.download(novel),
                child: Text(
                  missing == 1 ? 'Get the new one' : 'Get $missing more',
                ),
              ),
            ],
          );
        }
        return line(
          Icons.offline_pin,
          download.message ?? 'All ${download.done} chapters saved for offline',
          color: c.success,
        );
    }
  }
}
