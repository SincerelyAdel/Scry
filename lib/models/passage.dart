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
    this.character,
    this.reading = 1,
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

  /// Who speaks or is meant, typed by the reader; null when not given.
  final String? character;

  /// Which reading of the book it was saved on, from 1.
  final int reading;

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
    'character': character,
    'reading': reading,
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
    character: row['character'] as String?,
    reading: (row['reading'] as int?) ?? 1,
  );

  /// A copy; [character] '' clears the name.
  Passage copyWith({int? id, String? character}) => Passage(
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
    character: character == null
        ? this.character
        : (character.isEmpty ? null : character),
    reading: reading,
  );

  /// The same passage in another copy of the book: [novelId], its title
  /// and chapter link, and [reading] there.
  Passage movedTo({
    required int novelId,
    required String novelTitle,
    required String chapterUrl,
    required int reading,
  }) => Passage(
    id: id,
    novelId: novelId,
    novelTitle: novelTitle,
    chapterUrl: chapterUrl,
    chapterNumber: chapterNumber,
    chapterTitle: chapterTitle,
    from: from,
    to: to,
    text: text,
    savedAt: savedAt,
    character: character,
    reading: reading,
  );
}
