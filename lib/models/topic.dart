/// What a feed is about. Shown as a badge on the feed and its articles,
/// and used to filter the inbox.
enum Topic {
  ml('ML', 'Machine learning'),
  ic('IC', 'Chips and IC design');

  const Topic(this.badge, this.label);

  /// Short text for badges and filter chips.
  final String badge;

  /// Longer name for menus.
  final String label;

  static Topic? fromName(String? name) =>
      Topic.values.where((t) => t.name == name).firstOrNull;
}

/// arXiv categories by topic.
const _arxivIc = {'cs.AR', 'cs.ET', 'eess.SP', 'eess.SY', 'physics.app-ph'};
const _arxivMl = {
  'cs.AI',
  'cs.LG',
  'cs.CL',
  'cs.CV',
  'cs.NE',
  'cs.IR',
  'cs.RO',
  'stat.ML',
};

final _icWords = RegExp(
  r'semi|chip|silicon|\beda\b|circuit|asic|fpga|vlsi|\bee ?times\b|'
  r'electronics|foundry|fabricated knowledge|\bsoc\b|risc-?v',
  caseSensitive: false,
);

final _mlWords = RegExp(
  r'\bai\b|\bml\b|machine learning|deep ?learning|deepmind|hugging ?face|'
  r'neural|\bllms?\b|lil.?log|interconnects|import ai|bair|raschka|'
  r'ahead of ai|alammar|huyen|karpathy|openai|anthropic|research\.google',
  caseSensitive: false,
);

/// A first guess at a new feed's topic from its address and title. The
/// user can change it from the feed's menu.
Topic? guessTopic(String url, String title) {
  final category = RegExp(
    r'arxiv\.org/rss/([\w.-]+)',
    caseSensitive: false,
  ).firstMatch(url)?.group(1);
  if (category != null) {
    final cats = category.split('+');
    if (cats.any(_arxivIc.contains)) return Topic.ic;
    if (cats.any(_arxivMl.contains)) return Topic.ml;
    return null;
  }
  final text = '$title $url';
  if (_icWords.hasMatch(text)) return Topic.ic;
  if (_mlWords.hasMatch(text)) return Topic.ml;
  return null;
}
