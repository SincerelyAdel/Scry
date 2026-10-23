import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../utils/html_text.dart';

/// Reads novels from ranobes.net: search, a novel's details, its chapter
/// list and chapter text. Everything here is parsing; fetching lives in
/// NovelRepository so tests can feed in saved pages.
abstract final class Ranobes {
  static const origin = 'https://ranobes.net';

  /// Search results for [query]. The site redirects its search form here.
  static String searchUrl(String query) =>
      '$origin/search/${Uri.encodeQueryComponent(query.trim())}/';

  /// One page of a novel's chapters, newest first, 25 to a page.
  static String chapterListUrl(int bookId, int page) => page <= 1
      ? '$origin/chapters/$bookId/'
      : '$origin/chapters/$bookId/page/$page/';

  /// Redirects to the novel's first chapter.
  static String firstChapterUrl(int bookId) => '$origin/chapters/$bookId/first';

  /// The novel's number in a novel, chapter or chapter-list link:
  /// `/novels/1205249-shadow-slave.html`, `/shadow-slave-1205249/3317893.html`
  /// or `/chapters/1205249/`.
  static int? bookId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.host.endsWith('ranobes.net')) return null;
    final path = uri.path;
    final match =
        RegExp(r'^/novels/(\d+)-').firstMatch(path) ??
        RegExp(r'^/chapters/(\d+)').firstMatch(path) ??
        RegExp(r'-(\d+)/\d+\.html$').firstMatch(path);
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// True for a link to one chapter.
  static bool isChapterUrl(String url) =>
      RegExp(r'ranobes\.net/[^/]+-\d+/\d+\.html').hasMatch(url);

  // ---------------------------------------------------------------- search

  static List<NovelHit> parseSearch(String html) {
    final doc = html_parser.parse(html);
    final hits = <NovelHit>[];
    for (final story in doc.querySelectorAll('article.shortstory.mod-poster')) {
      final link = story.querySelector('h2.title a');
      final url = link?.attributes['href'];
      if (link == null || url == null || bookId(url) == null) continue;
      final blurb = story.querySelector('.cont-in > div');
      final genres = story.querySelector('.r-rate .grey.small');
      hits.add(
        NovelHit(
          url: _absolute(url),
          title: _clean(link.text),
          cover: _backgroundUrl(story.querySelector('figure.cover')),
          blurb: blurb == null ? null : _clean(blurb.text),
          genres: genres == null ? null : _clean(genres.text),
        ),
      );
    }
    return hits;
  }

  // ----------------------------------------------------------------- novel

  static NovelInfo? parseNovel(String html, String url) {
    final id = bookId(url);
    if (id == null) return null;
    final doc = html_parser.parse(html);
    String? meta(String property) => doc
        .querySelector('meta[property="og:$property"]')
        ?.attributes['content']
        ?.trim();
    final title = meta('title') ?? _clean(doc.querySelector('h1')?.text ?? '');
    if (title.isEmpty) return null;

    String? spec(String label) {
      for (final li in doc.querySelectorAll('.r-fullstory-spec li')) {
        final text = _clean(li.text);
        if (text.startsWith(label)) {
          return text.substring(label.length).replaceFirst(':', '').trim();
        }
      }
      return null;
    }

    // Some pages split the description into a short and a full version.
    final description =
        doc.querySelector('.moreless .moreless__full') ??
        doc.querySelector('.moreless');
    final chapters = RegExp(r'\d+').firstMatch(spec('Available') ?? '');
    return NovelInfo(
      url: meta('url') ?? url,
      bookId: id,
      title: title,
      cover: meta('image'),
      author: spec('Authors'),
      status: spec('Status in COO'),
      description: description == null
          ? meta('description')
          : htmlToPlainText(description.innerHtml),
      chapterCount: chapters == null ? 0 : int.parse(chapters.group(0)!),
    );
  }

  // ---------------------------------------------------------- chapter list

  /// The chapter list page's data, which the site embeds as JSON.
  static ChapterPage? parseChapterList(String html) {
    final match = RegExp(
      r'window\.__DATA__\s*=\s*(\{[\s\S]*?\})\s*;?\s*</script>',
    ).firstMatch(html);
    if (match == null) return null;
    final Object? data;
    try {
      data = jsonDecode(match.group(1)!);
    } on FormatException {
      return null;
    }
    if (data is! Map<String, dynamic>) return null;
    final countAll = _int(data['count_all']);
    final page = _int(data['cstart'], 1);
    final limit = _int(data['limit'], 25);
    final rows = data['chapters'];
    final chapters = <ChapterRef>[];
    if (rows is List) {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row is! Map) continue;
        final link = row['link'];
        if (link is! String) continue;
        chapters.add(
          ChapterRef(
            url: link,
            title: _clean('${row['title'] ?? ''}'),
            // Newest first: the first row of page 1 is the last chapter.
            number: countAll - ((page - 1) * limit + i),
            date: DateTime.tryParse('${row['date'] ?? ''}'),
          ),
        );
      }
    }
    final link = data['book_link'];
    return ChapterPage(
      bookUrl: link is String ? link : null,
      chapters: chapters,
      page: page,
      pageCount: _int(data['pages_count'], 1),
      perPage: limit,
      chapterCount: countAll,
    );
  }

  // --------------------------------------------------------------- chapter

  static ChapterText? parseChapter(String html, String url) {
    final body = _chapterBody(html);
    if (body == null) return null;
    final paragraphs = htmlToPlainText(body)
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return null;

    final doc = html_parser.parse(html);
    final heading = doc.querySelector('h1.title');
    final title = heading == null
        ? ''
        : _clean(
            heading.nodes.whereType<dom.Text>().map((t) => t.text).join(' '),
          );
    String? link(String id) {
      final href = doc.querySelector('a#$id')?.attributes['href'];
      return href == null || !isChapterUrl(_absolute(href))
          ? null
          : _absolute(href);
    }

    return ChapterText(
      url: url,
      title: title.isEmpty ? 'Chapter' : title,
      novelTitle: _nullIfEmpty(
        _clean(doc.querySelector('h1.title a[rel="up"]')?.text ?? ''),
      ),
      paragraphs: paragraphs,
      prevUrl: link('prev'),
      nextUrl: link('next'),
    );
  }

  /// The chapter's text as HTML, without the ads the site drops into it.
  ///
  /// The ads sit inside paragraphs and leave stray closing tags behind,
  /// which would end the text early if parsed as is. So the text is cut
  /// out of the raw page first, scripts and ad boxes removed, and any
  /// leftover div tags turned into paragraph breaks.
  static String? _chapterBody(String html) {
    final start = RegExp(r'<div[^>]*id="arrticle"[^>]*>').firstMatch(html);
    if (start == null) return null;
    final rest = html.substring(start.end);
    final end = [
      rest.indexOf('<div class="category'),
      rest.indexOf('<div class="story_tools'),
      rest.indexOf('</article>'),
    ].where((i) => i >= 0).fold<int>(rest.length, (a, b) => a < b ? a : b);
    var body = rest.substring(0, end);
    body = body.replaceAll(
      RegExp(
        r'<(script|style|ins|iframe)\b[\s\S]*?</\1>',
        caseSensitive: false,
      ),
      '',
    );
    // Ad boxes are empty once their scripts are gone; nested ones empty
    // out one level at a time.
    final emptyDiv = RegExp(r'<div\b[^>]*>\s*</div>');
    while (emptyDiv.hasMatch(body)) {
      body = body.replaceAll(emptyDiv, '');
    }
    return body
        .replaceAll(RegExp(r'</div\s*>'), '')
        .replaceAll(RegExp(r'<div\b[^>]*>'), '<br><br>');
  }

  // --------------------------------------------------------------- helpers

  static String _absolute(String href) => href.startsWith('http')
      ? href
      : Uri.parse(origin).resolve(href).toString();

  static String? _backgroundUrl(dom.Element? element) {
    final style = element?.attributes['style'] ?? '';
    final match = RegExp(r'''url\(\s*['"]?([^'")]+)''').firstMatch(style);
    return match == null ? null : _absolute(match.group(1)!.trim());
  }

  static String _clean(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _nullIfEmpty(String text) => text.isEmpty ? null : text;

  static int _int(Object? value, [int fallback = 0]) => switch (value) {
    final int v => v,
    final String v => int.tryParse(v) ?? fallback,
    _ => fallback,
  };
}

/// A search result.
class NovelHit {
  const NovelHit({
    required this.url,
    required this.title,
    this.cover,
    this.blurb,
    this.genres,
  });

  final String url;
  final String title;
  final String? cover;
  final String? blurb;
  final String? genres;
}

/// A novel's page.
class NovelInfo {
  const NovelInfo({
    required this.url,
    required this.bookId,
    required this.title,
    this.cover,
    this.author,
    this.status,
    this.description,
    this.chapterCount = 0,
  });

  final String url;
  final int bookId;
  final String title;
  final String? cover;
  final String? author;

  /// Whether the original is finished, e.g. "Ongoing" or "Completed".
  final String? status;
  final String? description;
  final int chapterCount;
}

/// One chapter in a novel's chapter list.
class ChapterRef {
  const ChapterRef({
    required this.url,
    required this.title,
    required this.number,
    this.date,
  });

  final String url;
  final String title;

  /// Position in the novel, from 1.
  final int number;
  final DateTime? date;
}

/// One page of a novel's chapter list (newest first).
class ChapterPage {
  const ChapterPage({
    this.bookUrl,
    required this.chapters,
    required this.page,
    required this.pageCount,
    required this.perPage,
    required this.chapterCount,
  });

  /// The novel's own page.
  final String? bookUrl;
  final List<ChapterRef> chapters;
  final int page;
  final int pageCount;
  final int perPage;
  final int chapterCount;
}

/// A chapter's text, ready to read.
class ChapterText {
  const ChapterText({
    required this.url,
    required this.title,
    required this.paragraphs,
    this.novelTitle,
    this.prevUrl,
    this.nextUrl,
  });

  final String url;
  final String title;
  final String? novelTitle;
  final List<String> paragraphs;

  /// Neighbouring chapters; null at the start and the end.
  final String? prevUrl;
  final String? nextUrl;
}
