import 'package:flutter/material.dart';

import '../models/article.dart';
import '../utils/format.dart';

/// One inbox row: unread dot, title, feed name and date.
class ArticleTile extends StatelessWidget {
  const ArticleTile({super.key, required this.article, required this.onTap});

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !article.isRead;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: unread
                    ? Semantics(
                        label: 'Unread',
                        child: CircleAvatar(
                          radius: 4,
                          backgroundColor: scheme.primary,
                        ),
                      )
                    : null,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      color: unread ? null : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${article.feedTitle ?? ''} · '
                    '${relativeDate(article.displayDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
