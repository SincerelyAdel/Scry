import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed.dart';
import '../models/topic.dart';
import '../state/feeds_provider.dart';
import '../theme.dart';
import 'ui.dart';

/// A starter feed in the add dialog.
class SuggestedFeed {
  const SuggestedFeed(this.name, this.url, this.topic);

  final String name;
  final String url;
  final Topic topic;
}

/// Starter feeds, picked for long reads: most send whole articles, and
/// Scry fetches the rest from the web page. Papers with Code shut down in
/// 2025 and Anthropic doesn't publish an RSS feed, so they aren't listed.
const suggestedFeeds = <SuggestedFeed>[
  // Machine learning
  SuggestedFeed(
    'Ahead of AI (Raschka)',
    'https://magazine.sebastianraschka.com/feed',
    Topic.ml,
  ),
  SuggestedFeed('Interconnects', 'https://www.interconnects.ai/feed', Topic.ml),
  SuggestedFeed('Import AI', 'https://importai.substack.com/feed', Topic.ml),
  SuggestedFeed(
    'Berkeley AI Research',
    'https://bair.berkeley.edu/blog/feed.xml',
    Topic.ml,
  ),
  SuggestedFeed(
    'Google Research',
    'https://research.google/blog/rss/',
    Topic.ml,
  ),
  SuggestedFeed(
    'Google DeepMind',
    'https://deepmind.google/blog/rss.xml',
    Topic.ml,
  ),
  SuggestedFeed('Eugene Yan', 'https://eugeneyan.com/rss/', Topic.ml),
  SuggestedFeed("Lil'Log", 'https://lilianweng.github.io/index.xml', Topic.ml),
  SuggestedFeed('Chip Huyen', 'https://huyenchip.com/feed.xml', Topic.ml),
  SuggestedFeed('Jay Alammar', 'https://jalammar.github.io/feed.xml', Topic.ml),
  SuggestedFeed(
    'MIT News: machine learning',
    'https://news.mit.edu/rss/topic/machine-learning',
    Topic.ml,
  ),
  SuggestedFeed(
    'Hugging Face blog',
    'https://huggingface.co/blog/feed.xml',
    Topic.ml,
  ),
  SuggestedFeed('arXiv cs.LG', 'https://rss.arxiv.org/rss/cs.LG', Topic.ml),
  SuggestedFeed('arXiv cs.CL', 'https://rss.arxiv.org/rss/cs.CL', Topic.ml),
  SuggestedFeed('arXiv cs.AI', 'https://rss.arxiv.org/rss/cs.AI', Topic.ml),
  SuggestedFeed('arXiv stat.ML', 'https://rss.arxiv.org/rss/stat.ML', Topic.ml),
  // Chips and IC design
  SuggestedFeed(
    'SemiAnalysis',
    'https://newsletter.semianalysis.com/feed',
    Topic.ic,
  ),
  SuggestedFeed(
    'Semiconductor Engineering',
    'https://semiengineering.com/feed/',
    Topic.ic,
  ),
  SuggestedFeed(
    'Chips and Cheese',
    'https://chipsandcheese.com/feed/',
    Topic.ic,
  ),
  SuggestedFeed(
    'The Chip Letter',
    'https://thechipletter.substack.com/feed',
    Topic.ic,
  ),
  SuggestedFeed(
    'Fabricated Knowledge',
    'https://www.fabricatedknowledge.com/feed',
    Topic.ic,
  ),
  SuggestedFeed(
    'IEEE Spectrum: semiconductors',
    'https://spectrum.ieee.org/feeds/topic/semiconductors.rss',
    Topic.ic,
  ),
  SuggestedFeed('SemiWiki', 'https://semiwiki.com/feed/', Topic.ic),
  SuggestedFeed(
    'Electronics Weekly',
    'https://www.electronicsweekly.com/feed/',
    Topic.ic,
  ),
  SuggestedFeed(
    'arXiv cs.AR (hardware)',
    'https://rss.arxiv.org/rss/cs.AR',
    Topic.ic,
  ),
];

/// Shows the add-feed dialog. Resolves to the new feed, or null if the user
/// cancelled.
Future<Feed?> showAddFeedDialog(BuildContext context) {
  return showDialog<Feed>(
    context: context,
    builder: (_) => const AddFeedDialog(),
  );
}

class AddFeedDialog extends StatefulWidget {
  const AddFeedDialog({super.key});

  @override
  State<AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<AddFeedDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit({Topic? topic}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final feed = await context.read<FeedsProvider>().addFeed(
        _controller.text,
        topics: topic == null ? null : {topic},
      );
      if (mounted) Navigator.of(context).pop(feed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is FormatException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscribed = {
      for (final feed in context.watch<FeedsProvider>().feeds) feed.url,
    };
    final suggestions = suggestedFeeds
        .where((f) => !subscribed.contains(f.url))
        .toList();

    return AlertDialog(
      title: const Text('Add feed'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Feed or website URL',
                hintText: 'https://example.com/feed.xml',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            for (final topic in Topic.values)
              if (suggestions.any((f) => f.topic == topic)) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Tag.topic(context, topic),
                    const SizedBox(width: 8),
                    Text(
                      topic.label,
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final feed in suggestions)
                      if (feed.topic == topic)
                        ActionChip(
                          label: Text(feed.name),
                          onPressed: _busy
                              ? null
                              : () {
                                  _controller.text = feed.url;
                                  _submit(topic: feed.topic);
                                },
                        ),
                  ],
                ),
              ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
