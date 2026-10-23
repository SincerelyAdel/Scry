import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../state/article_images.dart';
import '../theme.dart';
import '../utils/arxiv.dart';
import '../utils/format.dart';
import 'net_image.dart';
import 'ui.dart';

/// One inbox card: feed name, title, badges, author and date, with a sample image
/// on the right when the article has one. Unread articles get a gold dot
/// and a gold edge; read ones are dimmed.
class ArticleTile extends StatelessWidget {
  const ArticleTile({super.key, required this.article, required this.onTap});

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final unread = !article.isRead;
    final meta = [
      if (article.author != null && article.author!.isNotEmpty) article.author!,
      relativeDate(article.displayDate),
    ].join('  ·  ');

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
    final tags = articleTags(
      context,
      topic: article.feedTopic,
      paper: arxivId(article.url, article.guid) != null,
      readMinutes: readMinutesFor(words),
    );
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
        Row(
          children: [
            for (final tag in tags) ...[
              Opacity(opacity: unread ? 1 : 0.6, child: tag),
              const SizedBox(width: 6),
            ],
            if (tags.isNotEmpty) const SizedBox(width: 2),
            Expanded(
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.faint, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );

    return AppCard(
      onTap: onTap,
      highlight: unread,
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
