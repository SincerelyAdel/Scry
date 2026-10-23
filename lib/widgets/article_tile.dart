import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../state/article_images.dart';
import '../state/articles_provider.dart';
import '../theme.dart';
import '../utils/arxiv.dart';
import '../utils/format.dart';
import 'net_image.dart';
import 'tag_sweep.dart';
import 'ui.dart';

/// One inbox card: feed name, title, badges, author and date, with a sample image
/// on the right when the article has one. Unread articles get a gold dot
/// and a gold edge; read ones are dimmed.
class ArticleTile extends StatelessWidget {
  const ArticleTile({
    super.key,
    required this.article,
    required this.onTap,
    this.index = 0,
  });

  final Article article;
  final VoidCallback onTap;

  /// Position in the list; the first screenful sweeps in one after another.
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final unread = !article.isRead;

    // Ask for a picture if the feed didn't include one; the card updates
    // when it's found.
    final images = context.read<ArticleImages>();
    images.request(article);
    final image = context.select<ArticleImages, String?>(
      (i) => i.imageFor(article),
    );
    final looking = context.select<ArticleImages, bool>(
      (i) => i.isLooking(article),
    );
    final words = context.select<ArticleImages, int>(
      (i) => i.wordCountFor(article),
    );
    final paper = arxivId(article.url, article.guid) != null;
    final minutes = readMinutesFor(words);
    final meta = [
      if (article.author != null && article.author!.isNotEmpty) article.author!,
      relativeDate(article.displayDate),
      if (paper) 'Paper' else if (minutes != null) '$minutes min read',
    ].join('  ·  ');
    final articles = context.read<ArticlesProvider>();
    final wide = MediaQuery.sizeOf(context).width > 700;
    final thumbW = wide ? 176.0 : 96.0;
    final thumbH = wide ? 108.0 : 72.0;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.rss_feed, size: 15, color: c.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                article.feedTitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (unread)
              Semantics(
                label: 'Unread',
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.accentLight,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: c.accent.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          article.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: unread ? c.text : c.muted,
            fontSize: 16,
            height: 1.3,
            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
      ],
    );

    return TagSweepCard(
      // A new view (filter or sort) replays the sweep.
      key: ValueKey(articles.view),
      colors: [for (final tag in article.tags) topicColor(context, tag)],
      onTap: onTap,
      highlight: unread,
      dimmed: !unread,
      animate: articles.claimSweep(article.id!),
      delay: Duration(milliseconds: 70 * index.clamp(0, 12)),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: text),
          if (image != null) ...[
            const SizedBox(width: 14),
            Opacity(
              opacity: unread ? 1 : 0.6,
              child: NetImage(image, width: thumbW, height: thumbH),
            ),
          ] else if (looking) ...[
            const SizedBox(width: 14),
            Container(
              width: thumbW,
              height: thumbH,
              decoration: BoxDecoration(
                color: c.surfaceAlt.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
