import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/feed_repository.dart';
import '../models/article.dart';
import '../models/paper_figure.dart';
import '../state/article_images.dart';
import '../state/articles_provider.dart';
import '../state/settings_provider.dart';
import '../utils/format.dart';
import '../theme.dart';
import '../utils/arxiv.dart';
import '../utils/html_text.dart';
import '../widgets/html_view.dart';
import '../widgets/net_image.dart';
import '../widgets/page_gestures.dart';
import '../widgets/ui.dart';

/// Full article reader. Opening an article marks it read.
class ArticleDetailScreen extends StatefulWidget {
  const ArticleDetailScreen({
    super.key,
    required this.article,
    this.siblings = const [],
  });

  /// The lightweight row from the inbox; the full body is loaded here.
  final Article article;

  /// The inbox list it was opened from, as it was then; swiping sideways
  /// moves through it.
  final List<Article> siblings;

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  late Article _article = widget.article;

  /// The article body as HTML (full content, else the summary).
  String? _html;

  /// Set for arXiv papers: the summary split into id, type and abstract.
  ArxivSummary? _arxiv;

  /// The arXiv paper id, when this is a paper (even without a summary).
  String? _paperId;

  bool _loading = true;

  /// Fetching the rest of a teaser from its web page.
  bool _fetchingFull = false;

  // Figures, for arXiv papers.
  bool _figuresLoading = false;
  String? _figuresError;
  FiguresState _figuresState = FiguresState.unknown;
  List<PaperFigure> _figures = const [];

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
      _paperId = arxivId(full.url, full.guid);
      _arxiv = parseArxivSummary(htmlToPlainText(full.summary));
      _pickBody();
    }
    setState(() => _loading = false);
    if (_paperId != null) _loadFigures();
    if (full != null &&
        full.fullContent == null &&
        !full.imageChecked &&
        FeedRepository.isTeaser(full)) {
      _fetchFullText();
    }
    if (!_article.isRead) await _setRead(articles, true);
  }

  /// The best body: the page's text when it was fetched, else the feed's
  /// full content, else its summary.
  void _pickBody() {
    final content = _article.content?.trim() ?? '';
    _html =
        _article.fullContent ??
        (content.isNotEmpty ? content : _article.summary);
    if (htmlToPlainText(_html).isEmpty) _html = null;
  }

  /// Reads the rest of a teaser from its web page.
  Future<void> _fetchFullText() async {
    final repo = context.read<FeedRepository>();
    setState(() => _fetchingFull = true);
    try {
      await repo.checkPage(_article);
      final full = await repo.getArticle(_article.id!);
      if (!mounted || full == null) return;
      setState(() {
        _article = full.copyWith(isRead: _article.isRead);
        _pickBody();
      });
    } catch (_) {
      // Offline: the teaser stays, and Open in browser still works.
    } finally {
      if (mounted) setState(() => _fetchingFull = false);
    }
  }

  Future<void> _loadFigures() async {
    setState(() {
      _figuresLoading = true;
      _figuresError = null;
    });
    try {
      final (state, figures) = await context.read<FeedRepository>().loadFigures(
        _article,
      );
      if (!mounted) return;
      setState(() {
        _figuresState = state;
        _figures = figures;
      });
    } catch (e) {
      if (mounted) setState(() => _figuresError = e.toString());
    } finally {
      if (mounted) setState(() => _figuresLoading = false);
    }
  }

  Future<void> _open(String url) async {
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

  Future<void> _setRead(ArticlesProvider articles, bool isRead) async {
    await articles.setRead(_article, isRead);
    if (mounted) setState(() => _article = _article.copyWith(isRead: isRead));
  }

  Future<void> _toggleStar() async {
    final starred = !_article.isStarred;
    await context.read<ArticlesProvider>().setStarred(_article, starred);
    if (mounted) {
      setState(() => _article = _article.copyWith(isStarred: starred));
    }
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

  /// The article [step] places along in the inbox list, if any.
  Article? _neighbour(int step) {
    final list = widget.siblings;
    final i = list.indexWhere((a) => a.id == _article.id);
    final j = i + step;
    return i < 0 || j < 0 || j >= list.length ? null : list[j];
  }

  void _go(int step) {
    final article = _neighbour(step);
    if (article == null) return;
    Navigator.of(context).pushReplacement(
      PinchBackRoute<void>(
        slideFrom: step,
        builder: (_) =>
            ArticleDetailScreen(article: article, siblings: widget.siblings),
      ),
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
            tooltip: _article.isStarred ? 'Unstar' : 'Star for later',
            icon: Icon(
              _article.isStarred
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: _article.isStarred ? c.accentLight : null,
            ),
            onPressed: _toggleStar,
          ),
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
      body: SwipeNav(
        onNext: _neighbour(1) == null ? null : () => _go(1),
        onPrevious: _neighbour(-1) == null ? null : () => _go(-1),
        nextLabel: 'Next article',
        previousLabel: 'Previous article',
        child: SelectionArea(
          child: SwipeNavArea(
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
                if (!_loading) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: articleTags(
                      context,
                      tags: _article.tags,
                      paper: _paperId != null,
                      readMinutes: _article.readMinutes,
                      linkOnly:
                          hasLink &&
                          _paperId == null &&
                          _html == null &&
                          !_fetchingFull,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Divider(color: c.border),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_paperId != null)
                  ..._paper(c, fontSize)
                else ...[
                  ..._leadImage(),
                  if (_fetchingFull) ...[
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Fetching the full article...',
                          style: TextStyle(
                            fontFamily: kSerif,
                            fontStyle: FontStyle.italic,
                            color: c.muted,
                            fontSize: fontSize * 0.9,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_html == null && !_fetchingFull)
                    Text(
                      'This feed only provides a link for this article.',
                      style: TextStyle(
                        fontFamily: kSerif,
                        fontStyle: FontStyle.italic,
                        color: c.muted,
                        fontSize: fontSize,
                      ),
                    )
                  else if (_html != null)
                    HtmlView(
                      html: _html!,
                      baseUrl: _article.url,
                      fontSize: fontSize,
                    ),
                ],
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
        ),
      ),
    );
  }

  /// The article's sample image above the text, when the text has no
  /// pictures of its own.
  List<Widget> _leadImage() {
    if (_html != null && _html!.contains('<img')) return const [];
    final image = context.select<ArticleImages, String?>(
      (i) => i.imageFor(_article),
    );
    if (image == null) return const [];
    return [
      Center(child: NetImage(image, fit: BoxFit.contain, zoomable: true)),
      const SizedBox(height: 24),
    ];
  }

  /// An arXiv paper: its id and type, the abstract, then its figures.
  List<Widget> _paper(AppPalette c, double fontSize) {
    final id = _arxiv?.id ?? _paperId!;
    final abstract = _arxiv?.abstract ?? htmlToPlainText(_html);
    Widget chip(String label, {bool gold = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: gold ? c.accent.withValues(alpha: 0.15) : c.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: gold ? c.accent : c.muted,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip('arXiv $id', gold: true),
          if (_arxiv?.type != null) chip(_arxiv!.type!),
          TextButton.icon(
            onPressed: () => _open(arxivPdfUrl(_paperId!)),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('PDF'),
          ),
        ],
      ),
      const SizedBox(height: 22),
      const SectionLabel('Abstract'),
      const SizedBox(height: 8),
      if (abstract.isNotEmpty)
        Text(
          abstract,
          style: TextStyle(
            fontFamily: kSerif,
            color: c.text,
            fontSize: fontSize,
            height: 1.6,
          ),
        ),
      const SizedBox(height: 30),
      SectionLabel(
        _figures.isEmpty ? 'Figures' : 'Figures (${_figures.length})',
      ),
      const SizedBox(height: 12),
      ..._figureSection(c, fontSize),
    ];
  }

  List<Widget> _figureSection(AppPalette c, double fontSize) {
    final note = TextStyle(
      fontFamily: kSerif,
      fontStyle: FontStyle.italic,
      color: c.muted,
      fontSize: fontSize * 0.9,
    );
    if (_figuresLoading) {
      return [
        Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('Loading figures from arXiv...', style: note),
          ],
        ),
      ];
    }
    if (_figuresError != null) {
      return [
        Text('Could not load the figures ($_figuresError).', style: note),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _loadFigures,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        ),
      ];
    }
    if (_figuresState == FiguresState.missing) {
      return [
        Text(
          'This paper has no web version on arXiv, so its figures can only '
          'be seen in the PDF.',
          style: note,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _open(arxivPdfUrl(_paperId!)),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Open the PDF'),
          ),
        ),
      ];
    }
    if (_figures.isEmpty) {
      return [Text('This paper has no figures.', style: note)];
    }
    return [
      for (final (i, f) in _figures.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final src in f.images)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: f.images.length == 1 ? 900 : 420,
                        maxHeight: 520,
                      ),
                      child: Container(
                        // Figures are drawn for white paper.
                        color: Colors.white,
                        padding: const EdgeInsets.all(6),
                        child: NetImage(
                          src,
                          fit: BoxFit.contain,
                          radius: 4,
                          zoomable: true,
                          caption: f.caption,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                f.caption.isEmpty ? 'Figure ${i + 1}' : f.caption,
                style: TextStyle(
                  color: c.muted,
                  fontSize: fontSize * 0.8,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
