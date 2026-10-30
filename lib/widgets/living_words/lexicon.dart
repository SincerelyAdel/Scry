/// The words that come alive, grouped by the effect they set off.
///
/// Each base word also matches its usual forms (-s, -ed, -ing, a doubled
/// last letter as in "charred"); odd forms ("froze", "bled") are listed
/// alongside. Matching is whole-word and ignores case.
enum LivingEffect {
  fire('Fire', [
    'fire', 'fiery', 'flame', 'blaze', 'ablaze', 'burn', 'burnt', 'inferno', //
    'ember', 'scorch', 'sear', 'ignite', 'kindle', 'smoulder', 'smolder',
    'char', 'pyre',
  ]),
  roar('Roar', ['roar', 'bellow', 'thunder', 'thunderous', 'boom', 'rumble']),
  slash('Slash', [
    'slash', 'slice', 'cleave', 'cleft', 'gash', 'hack', 'sever', 'rend', //
    'slit', 'carve',
  ]),
  bolt('Lightning', [
    'lightning', 'bolt', 'thunderbolt', 'spark', 'crackle', 'jolt', //
    'electrify',
  ]),
  shatter('Shatter', [
    'shatter', 'smash', 'splinter', 'fracture', 'burst', 'explode', //
    'explosion',
  ]),
  frost('Frost', [
    'frost', 'frosty', 'freeze', 'froze', 'frozen', 'ice', 'icy', 'chill', //
    'rime', 'frigid', 'glacial', 'sleet', 'blizzard',
  ]),
  echo('Echo', ['echo', 'echoes', 'reverberate', 'resound']),
  blood('Blood', [
    'blood', 'bloody', 'bloodied', 'bleed', 'bled', 'gore', 'gory', //
    'haemorrhage', 'hemorrhage',
  ]),
  vanish('Vanish', [
    'vanish',
    'disappear',
    'fade',
    'dissolve',
    'evaporate',
    'erase',
  ]),
  dread('Dread', [
    'dread', 'dreadful', 'terror', 'terrify', 'terrified', 'horror', //
    'horrify', 'horrified', 'fright', 'frightful', 'doom', 'ominous',
  ]),
  howl('Howl', ['howl', 'wail', 'shriek', 'scream', 'screech', 'gale']),
  drown('Drown', [
    'drown',
    'submerge',
    'flood',
    'deluge',
    'sink',
    'sank',
    'sunk',
    'sunken',
  ]),
  stone('Petrify', [
    'petrify', 'petrified', 'stone', 'stony', 'granite', 'calcify', //
    'calcified', 'ossify', 'ossified',
  ]),
  crush('Crush', [
    'crush', 'pulverise', 'pulverize', 'flatten', 'squash', 'trample', //
    'grind', 'collapse',
  ]),
  lunge('Lunge', [
    'lunge',
    'pounce',
    'charge',
    'thrust',
    'leap',
    'leapt',
    'lash',
  ]),
  tremble('Tremble', [
    'tremble', 'shake', 'shook', 'shaken', 'shiver', 'quake', 'quiver', //
    'shudder', 'tremor', 'rattle',
  ]),
  poison('Poison', [
    'poison', 'poisonous', 'venom', 'venomous', 'plague', 'toxin', 'toxic', //
    'taint', 'infect', 'contaminate', 'pestilence', 'miasma',
  ]),
  choke('Choke', [
    'choke', 'smoke', 'smoky', 'suffocate', 'smother', 'strangle', //
    'stifle', 'throttle', 'gasp', 'soot', 'sooty',
  ]),
  wither('Wither', [
    'wither',
    'wilt',
    'rot',
    'rotten',
    'decay',
    'shrivel',
    'blight',
    'wane',
  ]),
  plummet('Plummet', ['plummet', 'plunge', 'tumble', 'topple', 'crash']),
  devour('Devour', [
    'devour',
    'consume',
    'gobble',
    'swallow',
    'gnaw',
    'engulf',
    'feast',
  ]);

  const LivingEffect(this.label, this.words);

  /// Shown in the menu.
  final String label;

  /// Base words; their forms are added by [Lexicon].
  final List<String> words;
}

/// A run of a paragraph: plain text, or a word that comes alive.
class LivingRun {
  const LivingRun(this.text, [this.effect]);

  final String text;
  final LivingEffect? effect;
}

/// Finds living words in text.
class Lexicon {
  Lexicon._() {
    for (final effect in LivingEffect.values) {
      for (final word in effect.words) {
        for (final form in _forms(word)) {
          // The first effect to claim a form keeps it.
          _byForm.putIfAbsent(form, () => effect);
        }
      }
    }
    for (final form in _never) {
      _byForm.remove(form);
    }
    final forms = _byForm.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    _pattern = RegExp(
      "(?<![A-Za-z'])(${forms.map(RegExp.escape).join('|')})(?![A-Za-z'])",
      caseSensitive: false,
    );
  }

  static final instance = Lexicon._();

  final _byForm = <String, LivingEffect>{};
  late final RegExp _pattern;

  /// Forms that look like a match but mean something else.
  static const _never = {'stoned', 'fired', 'firing'};

  /// The effect [word] sets off, if any.
  LivingEffect? effectOf(String word) => _byForm[word.toLowerCase()];

  /// [text] split into plain runs and living words.
  List<LivingRun> split(String text) {
    final runs = <LivingRun>[];
    var at = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > at) runs.add(LivingRun(text.substring(at, m.start)));
      runs.add(LivingRun(m[0]!, _byForm[m[0]!.toLowerCase()]));
      at = m.end;
    }
    if (at < text.length) runs.add(LivingRun(text.substring(at)));
    return runs;
  }

  static Iterable<String> _forms(String w) sync* {
    yield w;
    final last = w[w.length - 1];
    const vowels = 'aeiou';
    yield '${w}s';
    if (last == 'e') {
      final stem = w.substring(0, w.length - 1);
      yield '${w}d';
      yield '${stem}ing';
    } else if (last == 'y' && !vowels.contains(w[w.length - 2])) {
      final stem = w.substring(0, w.length - 1);
      yield '${stem}ies';
      yield '${stem}ied';
      yield '${w}ing';
    } else {
      yield '${w}es';
      yield '${w}ed';
      yield '${w}ing';
      // A short word ending vowel + consonant doubles it: charred, rotting.
      if (w.length >= 3 &&
          !vowels.contains(last) &&
          'wxy'.contains(last) == false &&
          vowels.contains(w[w.length - 2]) &&
          !vowels.contains(w[w.length - 3])) {
        yield '$w${last}ed';
        yield '$w${last}ing';
      }
    }
  }
}
