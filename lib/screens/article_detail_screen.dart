import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/feed_repository.dart';
import '../models/article.dart';
import '../state/articles_provider.dart';
import '../state/settings_provider.dart';
import '../utils/format.dart';
import '../theme.dart';
import '../utils/html_text.dart';
import '../widgets/ui.dart';

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
    final c = context.palette;
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
          padding: EdgeInsets.fromLTRB(
            pagePadding(context) + 4,
            8,
            pagePadding(context) + 4,
            40,
          ),
          children: [
            if (_article.feedTitle != null)
              Row(
                children: [
                  Icon(Icons.rss_feed, size: 15, color: c.accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _article.feedTitle!.toUpperCase(),
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Text(
              _article.title,
              style: TextStyle(
                fontFamily: kSerif,
                color: c.text,
                fontSize: 28,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              [
                if (_article.author != null) 'By ${_article.author}',
                fullDate(_article.displayDate),
              ].join(' · '),
              style: TextStyle(color: c.muted, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Divider(color: c.border),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_body == null || _body!.isEmpty)
              Text(
                'This feed only provides a link for this article.',
                style: TextStyle(
                  fontFamily: kSerif,
                  fontStyle: FontStyle.italic,
                  color: c.muted,
                  fontSize: fontSize,
                ),
              )
            else
              Text(
                _body!,
                style: TextStyle(
                  fontFamily: kSerif,
                  color: c.text,
                  fontSize: fontSize,
                  height: 1.6,
                ),
              ),
            if (hasLink) ...[
              const SizedBox(height: 36),
              Center(
                child: FilledButton.icon(
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
