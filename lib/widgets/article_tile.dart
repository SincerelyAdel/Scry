import 'package:flutter/material.dart';

import '../models/article.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'ui.dart';

/// One inbox card: feed name, title, author and date. Unread articles get a
/// gold dot and a gold edge; read ones are dimmed.
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

    return AppCard(
      onTap: onTap,
      highlight: unread,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
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
            style: TextStyle(color: c.faint, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
