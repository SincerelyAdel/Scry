/// A passage saved while reading: one paragraph or a run of them, with
/// where it came from so it can be opened there again.
class Passage {
  const Passage({
    this.id,
    required this.novelId,
    required this.novelTitle,
    required this.chapterUrl,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.from,
    required this.to,
    required this.text,
    required this.savedAt,
  });

  final int? id;
  final int novelId;
  final String novelTitle;
  final String chapterUrl;

  /// The chapter's position in the novel, or 0 when not known.
  final int chapterNumber;
  final String chapterTitle;

  /// The first and last paragraph, by index in the chapter.
  final int from;
  final int to;

  /// The paragraphs, separated by blank lines.
  final String text;
  final DateTime savedAt;

  int get paragraphCount => to - from + 1;

  List<String> get paragraphs => text.split('\n\n');

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'novelId': novelId,
    'novelTitle': novelTitle,
    'chapterUrl': chapterUrl,
    'chapterNumber': chapterNumber,
    'chapterTitle': chapterTitle,
    'fromParagraph': from,
    'toParagraph': to,
    'body': text,
    'savedAt': savedAt.millisecondsSinceEpoch,
  };

  static Passage fromMap(Map<String, Object?> row) => Passage(
    id: row['id'] as int,
    novelId: row['novelId'] as int,
    novelTitle: row['novelTitle'] as String,
    chapterUrl: row['chapterUrl'] as String,
    chapterNumber: row['chapterNumber'] as int,
    chapterTitle: row['chapterTitle'] as String,
    from: row['fromParagraph'] as int,
    to: row['toParagraph'] as int,
    text: row['body'] as String,
    savedAt: DateTime.fromMillisecondsSinceEpoch(row['savedAt'] as int),
  );

  Passage copyWith({int? id}) => Passage(
    id: id ?? this.id,
    novelId: novelId,
    novelTitle: novelTitle,
    chapterUrl: chapterUrl,
    chapterNumber: chapterNumber,
    chapterTitle: chapterTitle,
    from: from,
    to: to,
    text: text,
    savedAt: savedAt,
  );
}
