import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../utils/html_text.dart';

/// A book read from an EPUB file.
class EpubBook {
  const EpubBook({
    required this.title,
    this.author,
    this.description,
    this.cover,
    this.coverExtension,
    required this.chapters,
  });

  final String title;
  final String? author;
  final String? description;

  /// The cover picture's bytes and file extension ('jpg', 'png'…).
  final Uint8List? cover;
  final String? coverExtension;

  final List<EpubChapter> chapters;
}

class EpubChapter {
  const EpubChapter({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

/// The file isn't an EPUB, or one this can't read.
class EpubException implements Exception {
  EpubException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads EPUB 2 and 3 books: the details, the cover, and each chapter's
/// text in reading order. Pictures and styling inside chapters are left
/// out, like chapters from ranobes.net.
abstract final class Epub {
  static EpubBook parse(List<int> bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw EpubException("That file isn't an EPUB book");
    }
    String? text(String path) {
      final file = zip.find(path);
      return file == null
          ? null
          : utf8.decode(file.content, allowMalformed: true);
    }

    // Where the book's package file is.
    final container = text('META-INF/container.xml');
    if (container == null) throw EpubException("That file isn't an EPUB book");
    final opfPath = _elements(
      _xml(container),
      'rootfile',
    ).map((e) => e.getAttribute('full-path')).nonNulls.firstOrNull;
    final opfText = opfPath == null ? null : text(opfPath);
    if (opfPath == null || opfText == null) {
      throw EpubException("Couldn't find the book's contents");
    }
    final opf = _xml(opfText);
    final base = p.posix.dirname(opfPath);
    String resolve(String from, String href) {
      final clean = Uri.decodeFull(href.split('#').first);
      return p.posix.normalize(p.posix.join(from == '.' ? '' : from, clean));
    }

    // Details.
    String? meta(String name) {
      final value = _elements(
        opf,
        name,
      ).map((e) => e.innerText.trim()).where((v) => v.isNotEmpty).firstOrNull;
      return value;
    }

    final title = meta('title') ?? 'Untitled book';
    final author = meta('creator');
    final rawDescription = meta('description');
    final description = rawDescription == null
        ? null
        : htmlToPlainText(rawDescription);

    // Every file in the book, by id.
    final items = <String, _Item>{};
    for (final e in _elements(opf, 'item')) {
      final id = e.getAttribute('id');
      final href = e.getAttribute('href');
      if (id == null || href == null) continue;
      items[id] = _Item(
        path: resolve(base, href),
        type: e.getAttribute('media-type') ?? '',
        properties: (e.getAttribute('properties') ?? '').split(' ').toSet(),
      );
    }

    // Cover: EPUB 3 marks it, EPUB 2 names it in a meta tag.
    var coverItem = items.values
        .where((i) => i.properties.contains('cover-image'))
        .firstOrNull;
    if (coverItem == null) {
      final id = _elements(opf, 'meta')
          .where((e) => e.getAttribute('name') == 'cover')
          .map((e) => e.getAttribute('content'))
          .nonNulls
          .firstOrNull;
      coverItem = id == null ? null : items[id];
    }
    coverItem ??= items.entries
        .where(
          (e) =>
              e.key.toLowerCase().contains('cover') &&
              e.value.type.startsWith('image/'),
        )
        .map((e) => e.value)
        .firstOrNull;
    final coverFile = coverItem != null && coverItem.type.startsWith('image/')
        ? zip.find(coverItem.path)
        : null;

    // Chapter names from the table of contents, by file.
    final names = <String, String>{};
    final nav = items.values
        .where((i) => i.properties.contains('nav'))
        .firstOrNull;
    final navText = nav == null ? null : text(nav.path);
    if (nav != null && navText != null) {
      final doc = html_parser.parse(navText);
      final from = p.posix.dirname(nav.path);
      final toc =
          doc
              .querySelectorAll('nav')
              .where((n) => n.attributes['epub:type'] == 'toc')
              .firstOrNull ??
          doc.querySelector('nav');
      for (final a in toc?.querySelectorAll('a[href]') ?? const []) {
        final name = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (name.isEmpty) continue;
        names.putIfAbsent(resolve(from, a.attributes['href']!), () => name);
      }
    }
    final spine = _elements(opf, 'spine').firstOrNull;
    final ncxItem = items[spine?.getAttribute('toc') ?? ''];
    final ncxText = ncxItem == null ? null : text(ncxItem.path);
    if (ncxItem != null && ncxText != null) {
      final from = p.posix.dirname(ncxItem.path);
      for (final point in _elements(_xml(ncxText), 'navPoint')) {
        final label = _elements(point, 'text').firstOrNull?.innerText.trim();
        final src = _elements(
          point,
          'content',
        ).firstOrNull?.getAttribute('src');
        if (label == null || label.isEmpty || src == null) continue;
        names.putIfAbsent(resolve(from, src), () => label);
      }
    }

    // The chapters, in reading order.
    final chapters = <EpubChapter>[];
    for (final ref
        in spine == null ? <XmlElement>[] : _elements(spine, 'itemref')) {
      final item = items[ref.getAttribute('idref') ?? ''];
      if (item == null || item.properties.contains('nav')) continue;
      final source = text(item.path);
      if (source == null) continue;
      final chapter = _chapter(source, names[item.path], chapters.length + 1);
      if (chapter != null) chapters.add(chapter);
    }
    if (chapters.isEmpty) throw EpubException('The book has no text in it');

    return EpubBook(
      title: title,
      author: author,
      description: description == null || description.isEmpty
          ? null
          : description,
      cover: coverFile?.content,
      coverExtension: coverItem == null
          ? null
          : _extension(coverItem.type, coverItem.path),
      chapters: chapters,
    );
  }

  /// One chapter file's text, or null when it has none (a cover page or
  /// a picture).
  static EpubChapter? _chapter(String source, String? name, int number) {
    final doc = html_parser.parse(source);
    final body = doc.body;
    if (body == null) return null;
    final paragraphs = htmlToPlainText(body.innerHtml)
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return null;
    final heading = body
        .querySelector('h1, h2, h3')
        ?.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final docTitle = doc.querySelector('title')?.text.trim();
    final title = [name, heading, docTitle].whereType<String>().firstWhere(
      (t) => t.isNotEmpty,
      orElse: () => 'Chapter $number',
    );
    // The heading is usually the chapter's first line; the reader shows
    // the title already.
    final firstLine = paragraphs.first.toLowerCase();
    if (firstLine == title.toLowerCase() ||
        (heading != null && firstLine == heading.toLowerCase())) {
      paragraphs.removeAt(0);
    }
    if (paragraphs.isEmpty) return null;
    return EpubChapter(title: title, paragraphs: paragraphs);
  }

  static XmlDocument _xml(String text) {
    try {
      return XmlDocument.parse(text);
    } on XmlException {
      throw EpubException("Couldn't read the book's contents");
    }
  }

  /// Elements named [local] under [node], whatever their namespace prefix.
  static Iterable<XmlElement> _elements(XmlNode node, String local) =>
      node.descendantElements.where((e) => e.name.local == local);

  static String _extension(String type, String path) {
    final ext = p.posix.extension(path).replaceFirst('.', '').toLowerCase();
    if (ext.isNotEmpty) return ext;
    return switch (type) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
  }
}

class _Item {
  const _Item({
    required this.path,
    required this.type,
    required this.properties,
  });

  final String path;
  final String type;
  final Set<String> properties;
}
