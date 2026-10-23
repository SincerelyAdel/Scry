import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/novel.dart';
import '../../services/chapter_alerts.dart';
import '../../state/novels_provider.dart';
import '../../theme.dart';
import '../../widgets/swipe_back.dart';
import '../../widgets/ui.dart';
import 'add_novel_screen.dart';
import 'chapter_reader_screen.dart';
import 'novel_cover.dart';
import 'novel_screen.dart';

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
    final failed = await context.read<NovelsProvider>().checkAll();
    if (failed > 0) {
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

  void _add() =>
      Navigator.of(context)
          .push(SwipeBackRoute<void>(builder: (_) => const AddNovelScreen()));

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
        message: "Search ranobes.net or paste a novel's link.",
        action: FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Add novel'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novels'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: SizedBox(
            height: 2,
            child: novels.checking
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
        ),
      ),
      body: body,
      floatingActionButton: novels.novels.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add novel'),
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
      onTap: () => Navigator.of(context).push(
        SwipeBackRoute<void>(builder: (_) => NovelScreen(novelId: novel.id!)),
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
                    if (fresh > 0) ...[
                      const SizedBox(width: 8),
                      Tag('$fresh new', color: c.accent),
                    ],
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
/// chapter [url] (number [number]) when given.
Future<void> openReader(
  BuildContext context,
  Novel novel, {
  String? url,
  int? number,
}) {
  // Its new chapters are being read; the notification has done its job.
  ChapterAlerts.dismiss(novel);
  return Navigator.of(context).push(
    SwipeBackRoute<void>(
      builder: (_) => ChapterReaderScreen(
        novelId: novel.id!,
        url: url ?? novel.chapterUrl,
        number: number ?? (url == null ? novel.chapterNumber : 0),
      ),
    ),
  );
}
