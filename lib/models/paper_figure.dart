import 'dart:convert';

/// One figure from a paper: its image(s) and caption. Sub-figures (a), (b)
/// share one caption, so a figure can hold several images.
class PaperFigure {
  const PaperFigure({required this.images, required this.caption});

  final List<String> images;
  final String caption;

  Map<String, Object?> toJson() => {'images': images, 'caption': caption};

  factory PaperFigure.fromJson(Map<String, Object?> json) => PaperFigure(
    images: [for (final i in json['images'] as List? ?? const []) '$i'],
    caption: json['caption'] as String? ?? '',
  );

  static String encodeList(List<PaperFigure> figures) =>
      jsonEncode([for (final f in figures) f.toJson()]);

  static List<PaperFigure> decodeList(String json) => [
    for (final f in jsonDecode(json) as List)
      PaperFigure.fromJson((f as Map).cast<String, Object?>()),
  ];
}

/// What happened when the app looked for a paper's figures.
enum FiguresState {
  /// Not looked for yet.
  unknown,

  /// Found; see the figures list (which may still be empty).
  found,

  /// The paper has no HTML version to take figures from.
  missing,
}
