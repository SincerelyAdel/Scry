import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/chapter_alerts.dart';
import '../../services/ranobes.dart';
import '../../state/novels_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'novel_cover.dart';

/// Search ranobes.net by name, or paste a link to a novel or one of its
/// chapters, and add results to the library.
class AddNovelScreen extends StatefulWidget {
  const AddNovelScreen({super.key});

  @override
  State<AddNovelScreen> createState() => _AddNovelScreenState();
}

class _AddNovelScreenState extends State<AddNovelScreen> {
  final _query = TextEditingController();
  List<NovelHit>? _hits;
  String? _error;
  bool _searching = false;

  /// Results being added right now, by link.
  final Set<String> _adding = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final text = _query.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final hits = await context.read<NovelsProvider>().search(text);
      if (!mounted) return;
      setState(() => _hits = hits);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(NovelHit hit) async {
    final messenger = ScaffoldMessenger.of(context);
    final alerts = context.read<SettingsProvider>().chapterAlerts;
    setState(() => _adding.add(hit.url));
    try {
      final novel = await context.read<NovelsProvider>().add(hit.url);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added ${novel.title}')));
      // New chapter alerts need permission on Android 13 and later.
      if (alerts) await ChapterAlerts.requestPermission();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't add it: $e")));
    } finally {
      if (mounted) setState(() => _adding.remove(hit.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final pad = pagePadding(context);
    final novels = context.watch<NovelsProvider>();
    final hits = _hits;

    Widget results;
    if (_searching) {
      results = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      results = EmptyState(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't search",
        message: _error,
      );
    } else if (hits == null) {
      results = const EmptyState(
        icon: Icons.search,
        title: 'Find a novel',
        message:
            'Search by name, or paste a link to a novel or a chapter on '
            'ranobes.net.',
      );
    } else if (hits.isEmpty) {
      results = const EmptyState(
        icon: Icons.search_off,
        title: 'Nothing found',
        message: 'Try fewer words, or paste the novel\'s link.',
      );
    } else {
      results = ListView.separated(
        padding: EdgeInsets.fromLTRB(pad, 4, pad, 32),
        itemCount: hits.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final hit = hits[i];
          final inLibrary = novels.contains(hit.url);
          final adding = _adding.contains(hit.url);
          return AppCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NovelCover(url: hit.cover, title: hit.title, width: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.title,
                        style: TextStyle(
                          fontFamily: kSerif,
                          color: c.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hit.genres != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          hit.genres!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.accent, fontSize: 12),
                        ),
                      ],
                      if (hit.blurb != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          hit.blurb!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (inLibrary)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 18, color: c.success),
                        const SizedBox(width: 4),
                        Text(
                          'In library',
                          style: TextStyle(color: c.success, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton(
                    onPressed: adding ? null : () => _add(hit),
                    child: adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add'),
                  ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add novel')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 12),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search ranobes.net or paste a link',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
              ),
            ),
          ),
          Expanded(child: results),
        ],
      ),
    );
  }
}
