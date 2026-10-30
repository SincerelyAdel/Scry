import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/novel.dart';
import '../../services/book_picker.dart';
import '../../services/chapter_alerts.dart';
import '../../state/novels_provider.dart';
import '../../theme.dart';
import '../../widgets/page_gestures.dart';
import '../../widgets/ui.dart';
import 'add_novel_screen.dart';
import 'chapter_reader_screen.dart';
import 'human_check_screen.dart';
import 'novel_cover.dart';
import 'novel_screen.dart';
import 'passages_drawer.dart';

/// The novels side: your novels, most recently read first, each with where
/// you are and how many chapters are left.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    // New chapters come out daily; look when the library opens, at most
    // every half hour.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final novels = context.read<NovelsProvider>();
      if (!novels.loaded) await novels.load();
      novels.checkAll(ifOlderThan: const Duration(minutes: 30));
    });
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    final novels = context.read<NovelsProvider>();
    final failed = await novels.checkAll();
    // The banner explains a human check; only other failures need a note.
    if (failed > 0 && novels.humanCheck == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed == 1
                ? "Couldn't check one novel for new chapters"
                : "Couldn't check $failed novels for new chapters",
          ),
        ),
      );
    }
  }

  bool _importing = false;

  /// Adds a book from an EPUB file, then opens it.
  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final novels = context.read<NovelsProvider>();
    final navigator = Navigator.of(context);
    try {
      final bytes = await BookPicker.pick();
      if (bytes == null) return;
      setState(() => _importing = true);
      final novel = await novels.importBook(bytes);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${novel.title}: ${novel.chapterCount} chapters',
            ),
          ),
        );
      navigator.push(
        PinchBackRoute<void>(builder: (_) => NovelScreen(novelId: novel.id!)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't import it: $e")));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _add() =>
      Navigator.of(context)
          .push(PinchBackRoute<void>(builder: (_) => const AddNovelScreen()));

  @override
  Widget build(BuildContext context) {
    final novels = context.watch<NovelsProvider>();
    final pad = MediaQuery.sizeOf(context).width >= 900
        ? 24.0
        : pagePadding(context);

    Widget body;
    if (!novels.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (novels.novels.isEmpty) {
      body = EmptyState(
        icon: Icons.auto_stories_outlined,
        title: 'No novels yet',
        message:
            "Search ranobes.net or paste a novel's link, or import "
            'an EPUB book.',
        action: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add novel'),
            ),
            if (BookPicker.supported)
              OutlinedButton.icon(
                onPressed: _importing ? null : _import,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import EPUB'),
              ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 96),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 640,
            mainAxisExtent: 212,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: novels.novels.length,
          itemBuilder: (context, i) => NovelCard(novel: novels.novels[i]),
        ),
      );
    }

    // Saved passages sit behind the library, on the left.
    return PassagesDrawer(
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              tooltip: 'Saved passages',
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: () => PassagesDrawer.open(context),
            ),
          ),
          title: const Text('Novels'),
          actions: [
            if (BookPicker.supported)
              IconButton(
                tooltip: 'Import EPUB',
                icon: const Icon(Icons.file_open_outlined),
                onPressed: _importing ? null : _import,
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: SizedBox(
              height: 2,
              child: novels.checking || _importing
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
          ),
        ),
        body: novels.humanCheck == null
            ? body
            : Column(
                children: [
                  _HumanCheckBanner(
                    onVerify: () async {
                      final check = novels.humanCheck!;
                      if (await passHumanCheck(context, check.url)) {
                        novels.checkAll();
                      }
                    },
                  ),
                  Expanded(child: body),
                ],
              ),
        floatingActionButton: novels.novels.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Add novel'),
              ),
      ),
    );
  }
}

/// A novel in the library: cover, title, where you are, and Continue.
class NovelCard extends StatelessWidget {
  const NovelCard({super.key, required this.novel});

  final Novel novel;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final left = novel.chaptersLeft;
    final fresh = novel.newChapters;
    final where = !novel.started || novel.chapterNumber <= 0
        ? '${novel.chapterCount} chapters'
        : left == 0
        ? 'All ${novel.chapterCount} read'
        : '${novel.chapterNumber} of ${novel.chapterCount}  ·  $left to go';

    return AppCard(
      padding: const EdgeInsets.all(14),
      glow: fresh > 0,
      onTap: () => Navigator.of(context).push(
        PinchBackRoute<void>(builder: (_) => NovelScreen(novelId: novel.id!)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NovelCover(url: novel.cover, title: novel.title, width: 122),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  novel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kSerif,
                    color: c.text,
                    fontSize: 18,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (novel.author != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    novel.author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ],
                if (fresh > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: c.accent),
                      const SizedBox(width: 6),
                      Text(
                        fresh == 1 ? '1 new chapter' : '$fresh new chapters',
                        style: TextStyle(
                          color: c.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                if (novel.started && novel.chapterTitle != null)
                  Text(
                    novel.chapterTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.text, fontSize: 13.5),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        where,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                if (novel.started && novel.chapterNumber > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: novel.progress,
                      minHeight: 3,
                      backgroundColor: c.surfaceAlt,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => openReader(context, novel),
                  icon: Icon(
                    novel.started ? Icons.play_arrow_rounded : Icons.menu_book,
                    size: 18,
                  ),
                  label: Text(novel.started ? 'Continue' : 'Start reading'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the reader where [novel] was left, or at its first chapter, or at
/// chapter [url] (number [number]) when given. [focus] is a saved
/// passage's first and last paragraph, to show there.
///
/// The reader always sits on the novel's page, which pinching out of it
/// goes back to; [fromNovelPage] says it's open already.
Future<void> openReader(
  BuildContext context,
  Novel novel, {
  String? url,
  int? number,
  bool fromNovelPage = false,
  (int, int)? focus,
}) {
  // Its new chapters are being read; the notification has done its job.
  ChapterAlerts.dismiss(novel);
  final navigator = Navigator.of(context);
  if (!fromNovelPage) {
    navigator.push(
      PinchBackRoute<void>(builder: (_) => NovelScreen(novelId: novel.id!)),
    );
  }
  return navigator.push(
    PinchBackRoute<void>(
      builder: (_) => ChapterReaderScreen(
        novelId: novel.id!,
        url: url ?? novel.chapterUrl,
        number: number ?? (url == null ? novel.chapterNumber : 0),
        focus: focus,
      ),
    ),
  );
}

/// Shown when ranobes.net put up its human check during a chapter check.
class _HumanCheckBanner extends StatelessWidget {
  const _HumanCheckBanner({required this.onVerify});

  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accent.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, color: c.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "ranobes.net wants to check you're human before Scry can "
              'look for new chapters.',
              style: TextStyle(color: c.text, fontSize: 13.5, height: 1.35),
            ),
          ),
          TextButton(onPressed: onVerify, child: const Text('Verify')),
        ],
      ),
    );
  }
}
