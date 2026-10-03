import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/feed_repository.dart';
import '../models/article.dart';
import '../state/articles_provider.dart';
import '../state/settings_provider.dart';
import '../utils/format.dart';
import '../utils/html_text.dart';

/// Full article reader. Opening an article marks it read.
class ArticleDetailScreen extends StatefulWidget {
  const ArticleDetailScreen({super.key, required this.article});

  /// The lightweight row from the inbox; the full body is loaded here.
  final Article article;

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  late Article _article = widget.article;
  String? _body;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<FeedRepository>();
    final articles = context.read<ArticlesProvider>();
    final full = await repo.getArticle(widget.article.id!);
    if (!mounted) return;
    if (full != null) {
      _article = full;
      // Prefer the full content; many feeds only send a summary.
      final content = htmlToPlainText(full.content);
      _body = content.isNotEmpty ? content : htmlToPlainText(full.summary);
    }
    setState(() => _loading = false);
    if (!_article.isRead) await _setRead(articles, true);
  }

  Future<void> _setRead(ArticlesProvider articles, bool isRead) async {
    await articles.setRead(_article, isRead);
    if (mounted) setState(() => _article = _article.copyWith(isRead: isRead));
  }

  Future<void> _openInBrowser() async {
    final url = _article.url;
    if (url == null) return;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open the link")));
    }
  }

  Future<void> _share() async {
    final url = _article.url;
    if (url == null) return;
    await SharePlus.instance.share(
      ShareParams(text: '${_article.title}\n$url', subject: _article.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = context.select<SettingsProvider, double>(
      (s) => s.fontSize,
    );
    final hasLink = _article.url != null;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: _article.isRead ? 'Mark as unread' : 'Mark as read',
            icon: Icon(
              _article.isRead
                  ? Icons.mark_email_unread_outlined
                  : Icons.mark_email_read_outlined,
            ),
            onPressed: () =>
                _setRead(context.read<ArticlesProvider>(), !_article.isRead),
          ),
          if (hasLink)
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined),
              onPressed: _share,
            ),
          if (hasLink)
            IconButton(
              tooltip: 'Open in browser',
              icon: const Icon(Icons.open_in_browser),
              onPressed: _openInBrowser,
            ),
        ],
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (_article.feedTitle != null)
              Text(
                _article.feedTitle!.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: 0.8,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _article.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (_article.author != null) 'By ${_article.author}',
                fullDate(_article.displayDate),
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 32),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_body == null || _body!.isEmpty)
              Text(
                'This feed only provides a link for this article.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Text(
                _body!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: fontSize,
                  height: 1.55,
                ),
              ),
            if (hasLink) ...[
              const SizedBox(height: 32),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open in browser'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
