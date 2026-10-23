import 'dart:ui' show Color;

/// A tag: what a feed or an article is about. Cards are coloured by their
/// tags, and the inbox filters by them. Add a tag by adding a value here
/// with its colours and the words that give it to an article.
enum Topic {
  ml(
    'ML',
    'Machine learning',
    dark: Color(0xFFB39DFF),
    light: Color(0xFF6A4FC4),
  ),
  ic(
    'IC',
    'Chips and IC design',
    dark: Color(0xFF5CCFC0),
    light: Color(0xFF1F7F73),
  ),
  uvm(
    'UVM',
    'UVM and verification',
    dark: Color(0xFF7FB2FF),
    light: Color(0xFF2F62B8),
  ),
  bio(
    'Bio',
    'Biology and medicine',
    dark: Color(0xFFF28DB2),
    light: Color(0xFFB23A6B),
  ),
  claude('Claude', 'Claude', dark: Color(0xFFE48D69), light: Color(0xFFB4532F));

  const Topic(
    this.badge,
    this.label, {
    required this.dark,
    required this.light,
  });

  /// Short text for chips and badges.
  final String badge;

  /// Longer name for menus.
  final String label;

  /// Colour on the dark and the light theme.
  final Color dark, light;

  Color color({required bool isDark}) => isDark ? dark : light;

  static Topic? fromName(String? name) =>
      Topic.values.where((t) => t.name == name).firstOrNull;
}

/// Tags stored as a comma list (`ml,ic`), in a fixed order.
Set<Topic> topicsFromString(String? value) => {
  for (final name in (value ?? '').split(',')) ?Topic.fromName(name.trim()),
};

String? topicsToString(Iterable<Topic> topics) {
  final sorted = topics.toSet().toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  return sorted.isEmpty ? null : sorted.map((t) => t.name).join(',');
}

/// arXiv categories by tag.
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

final _icFeedWords = RegExp(
  r'semi|chip|silicon|\beda\b|circuit|asic|fpga|vlsi|\bee ?times\b|'
  r'electronics|foundry|fabricated knowledge|\bsoc\b|risc-?v',
  caseSensitive: false,
);

final _mlFeedWords = RegExp(
  r'\bai\b|\bml\b|machine learning|deep ?learning|deepmind|hugging ?face|'
  r'neural|\bllms?\b|lil.?log|interconnects|import ai|bair|raschka|'
  r'ahead of ai|alammar|huyen|karpathy|openai|research\.google',
  caseSensitive: false,
);

final _uvmFeedWords = RegExp(
  r'\buvm|verification|amiq|vlsi ?verify',
  caseSensitive: false,
);

final _bioFeedWords = RegExp(
  r'biolog|biotech|medic|health|neuroscien|life sciences?|transmitter|'
  r'asimov press|sciencenews\.org/topic/life',
  caseSensitive: false,
);

final _claudeFeedWords = RegExp(r'anthropic|claude', caseSensitive: false);

/// A first guess at a new feed's tags from its address and title. The user
/// can change them from the feed's menu.
Set<Topic> guessTopics(String url, String title) {
  final category = RegExp(
    r'arxiv\.org/rss/([\w.+-]+)',
    caseSensitive: false,
  ).firstMatch(url)?.group(1);
  if (category != null) {
    final cats = category.split('+');
    return {
      if (cats.any(_arxivMl.contains)) Topic.ml,
      if (cats.any(_arxivIc.contains)) Topic.ic,
    };
  }
  final text = '$title $url';
  if (_claudeFeedWords.hasMatch(text)) return {Topic.claude};
  if (_uvmFeedWords.hasMatch(text)) return {Topic.uvm, Topic.ic};
  if (_bioFeedWords.hasMatch(text)) return {Topic.bio};
  if (_icFeedWords.hasMatch(text)) return {Topic.ic};
  if (_mlFeedWords.hasMatch(text)) return {Topic.ml};
  return {};
}

/// Words that tag an article, whatever its feed.
final _articleWords = <Topic, RegExp>{
  Topic.ml: RegExp(
    r'\b(ai|llms?|large language models?|language models?|machine learning|'
    r'deep learning|neural (?:net|network)s?|inference|fine-?tun\w*|'
    r'transformer (?:models?|architecture)|diffusion models?|'
    r'reinforcement learning|genai|generative ai|gpt-?\w*|agentic)\b',
    caseSensitive: false,
  ),
  Topic.ic: RegExp(
    r'\b(semiconductors?|chips?(?! huyen)|chiplets?|silicon|asics?|fpgas?|'
    r'gpus?|tpus?|npus?|hbm\w*|dram|sram|wafers?|foundr(?:y|ies)|tsmc|'
    r'lithography|eda|rtl|verilog|systemverilog|tape-?outs?|accelerators?|'
    r'transistors?|cmos|trainium|inferentia|risc-?v)\b',
    caseSensitive: false,
  ),
  Topic.uvm: RegExp(
    r'\b(uvm(?:_\w+)?|uvcs?|universal verification methodology)\b',
    caseSensitive: false,
  ),
  Topic.bio: RegExp(
    // "neurons" only: AWS's chip software is called Neuron.
    r'\b(biology|biologists?|biotech\w*|neurons|neuronal|neuroscien\w*|brains?|'
    r'organoids?|genes?|genetic\w*|genom\w*|dna|rna|crispr|proteins?|'
    r'(?:stem|cancer|brain|immune|blood) cells|cancers?|tumou?rs?|vaccines?|'
    r'diseases?|patients?|clinical trials?|drugs?|medicine|medical|'
    r'bacteri\w*|microb(?:es?|ial|iomes?|iolog\w*)|pathogens?|infections?|'
    r'antibod\w*|immune|'
    r'alzheimer\w*|parkinson\w*|diabetes|malaria|enzymes?|species)\b',
    caseSensitive: false,
  ),
  Topic.claude: RegExp(r'\b(claude|anthropic)\b', caseSensitive: false),
};

/// How often a tag's words must appear in an article's text (not its
/// title) to count; a passing mention doesn't make an article about it.
const _bodyHits = {
  Topic.ml: 4,
  Topic.ic: 4,
  Topic.uvm: 2,
  Topic.bio: 4,
  Topic.claude: 2,
};

/// Tags an article earns from its own words: any match in the title, or
/// several in the text.
Set<Topic> tagsInText(String title, String body) {
  final sample = body.length > 6000 ? body.substring(0, 6000) : body;
  return {
    for (final MapEntry(key: topic, value: words) in _articleWords.entries)
      if (words.hasMatch(title) ||
          words.allMatches(sample).length >= _bodyHits[topic]!)
        topic,
  };
}
