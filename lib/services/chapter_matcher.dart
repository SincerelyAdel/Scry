import 'epub.dart';

/// How an EPUB's chapters lined up with the novel's chapter numbers.
class ChapterMatch {
  const ChapterMatch({
    required this.chapters,
    required this.byOrder,
    this.unnumbered = const [],
    this.merged = 0,
    this.conflicts = const [],
    this.gaps = const [],
  });

  /// The book's chapters by the novel's chapter number.
  final Map<int, EpubChapter> chapters;

  /// True when the titles had no numbers, so chapters were matched by
  /// their order in the book (the first is chapter 1).
  final bool byOrder;

  /// Titles without a chapter number, left out (a prologue, notes).
  final List<String> unnumbered;

  /// Parts of one chapter (the same number, one after another) joined.
  final int merged;

  /// Titles whose number came up again later in the book, left out: the
  /// numbering likely starts over each volume.
  final List<String> conflicts;

  /// Numbers missing between the first and last; those come from the site.
  final List<int> gaps;

  int get first => chapters.isEmpty ? 0 : chapters.keys.first;
  int get last => chapters.isEmpty ? 0 : chapters.keys.last;
}

/// Lines a book's chapters up with a novel's chapter numbers, from the
/// number in each title ("Chapter 1205: …", "1205 - …"). QuickNovel's
/// books come from other sites than ranobes.net, which may split chapters
/// or add notes differently, so the numbers are what's trusted, not the
/// order.
abstract final class ChapterMatcher {
  static final _named = RegExp(
    r'\b(?:chapter|chap|ch|episode|ep)\.?\s*(\d{1,5})\b',
    caseSensitive: false,
  );
  static final _leading = RegExp(r'^\s*(\d{1,5})(?=\s*[:.\-–—)]|\s|$)');

  /// The chapter number in [title], if there is one.
  static int? numberIn(String title) {
    final m = _named.firstMatch(title) ?? _leading.firstMatch(title);
    final n = m == null ? null : int.parse(m.group(1)!);
    return n == null || n <= 0 ? null : n;
  }

  static ChapterMatch match(List<EpubChapter> book) {
    final numbers = [for (final c in book) numberIn(c.title)];
    final numbered = numbers.whereType<int>().length;
    // Mostly without numbers: go by order instead.
    if (numbered * 2 < book.length) {
      return ChapterMatch(
        chapters: {for (var i = 0; i < book.length; i++) i + 1: book[i]},
        byOrder: true,
      );
    }

    final chapters = <int, EpubChapter>{};
    final unnumbered = <String>[];
    final conflicts = <String>[];
    var merged = 0;
    int? previous;
    for (var i = 0; i < book.length; i++) {
      final n = numbers[i];
      final chapter = book[i];
      if (n == null) {
        unnumbered.add(chapter.title);
        previous = null;
        continue;
      }
      final earlier = chapters[n];
      if (earlier == null) {
        chapters[n] = chapter;
      } else if (previous == n) {
        // "Chapter 12 (1)", "Chapter 12 (2)": one chapter in parts.
        chapters[n] = EpubChapter(
          title: earlier.title,
          paragraphs: [...earlier.paragraphs, ...chapter.paragraphs],
        );
        merged++;
      } else {
        conflicts.add(chapter.title);
      }
      previous = n;
    }

    final sorted = Map.fromEntries(
      chapters.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final gaps = <int>[];
    if (sorted.isNotEmpty) {
      for (var n = sorted.keys.first; n <= sorted.keys.last; n++) {
        if (!sorted.containsKey(n)) gaps.add(n);
      }
    }
    return ChapterMatch(
      chapters: sorted,
      byOrder: false,
      unnumbered: unnumbered,
      merged: merged,
      conflicts: conflicts,
      gaps: gaps,
    );
  }
}
