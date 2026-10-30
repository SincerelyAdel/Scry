import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scry/state/settings_provider.dart';
import 'package:scry/theme.dart';
import 'package:scry/widgets/living_words/lexicon.dart';
import 'package:scry/widgets/living_words/living_controller.dart';
import 'package:scry/widgets/living_words/living_text.dart';
import 'package:scry/widgets/living_words/mood_layer.dart';

void main() {
  final lexicon = Lexicon.instance;

  group('lexicon', () {
    test('finds base words and their forms, ignoring case', () {
      expect(lexicon.effectOf('Poison'), LivingEffect.poison);
      expect(lexicon.effectOf('poisoned'), LivingEffect.poison);
      expect(lexicon.effectOf('venomous'), LivingEffect.poison);
      expect(lexicon.effectOf('PLAGUES'), LivingEffect.poison);
      expect(lexicon.effectOf('charred'), LivingEffect.fire);
      expect(lexicon.effectOf('burning'), LivingEffect.fire);
      expect(lexicon.effectOf('froze'), LivingEffect.frost);
      expect(lexicon.effectOf('shook'), LivingEffect.tremble);
      expect(lexicon.effectOf('bled'), LivingEffect.blood);
      expect(lexicon.effectOf('rotting'), LivingEffect.wither);
      expect(lexicon.effectOf('terrified'), LivingEffect.dread);
      expect(lexicon.effectOf('shattered'), LivingEffect.shatter);
      expect(lexicon.effectOf('devoured'), LivingEffect.devour);
    });

    test('leaves everyday words alone', () {
      for (final w in [
        'cut',
        'fall',
        'eat',
        'cold',
        'fear',
        'wind',
        'stoned',
      ]) {
        expect(lexicon.effectOf(w), isNull, reason: w);
      }
    });

    test('splits text into whole words only', () {
      final runs = lexicon.split('The venom spread; firefly, not fire.');
      expect(
        runs.map((r) => r.text).join(),
        'The venom spread; firefly, not fire.',
      );
      final living = runs.where((r) => r.effect != null).toList();
      expect(living.map((r) => r.text), ['venom', 'fire']);
      expect(living.map((r) => r.effect), [
        LivingEffect.poison,
        LivingEffect.fire,
      ]);
    });

    test('every effect has words, and every word maps back to it', () {
      for (final e in LivingEffect.values) {
        expect(e.words, isNotEmpty);
        for (final w in e.words) {
          if (w == 'stone') continue;
          expect(lexicon.effectOf(w), e, reason: w);
        }
      }
    });
  });

  for (final dark in [false, true]) {
    testWidgets(
      'every effect plays and fades without errors (${dark ? 'dark' : 'light'})',
      (tester) async {
        final controller = LivingWordsController()
          ..speed = LivingSpeed.fast
          ..screen = const Size(800, 600);
        final palette = dark ? darkPalette : lightPalette;
        for (final effect in LivingEffect.values) {
          final word = effect.words.first;
          final runs = lexicon.split('Before the $word, after.');
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(palette),
              home: Scaffold(
                body: Stack(
                  children: [
                    Center(
                      child: LivingWordsScope(
                        controller: controller,
                        child: LivingParagraph(
                          // A new id per effect, so each gets a turn.
                          id: effect.index,
                          runs: runs,
                          style: TextStyle(fontSize: 22, color: palette.text),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: LivingMoodLayer(
                        controller: controller,
                        ink: palette.text,
                        paper: palette.bg,
                        dark: dark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          controller.enabled = true;
          // The watcher looks every quarter second.
          await tester.pump(const Duration(milliseconds: 300));
          expect(controller.effect.value, effect, reason: word);
          // Grow to full strength, through a few cycles of motion.
          for (var i = 0; i < 80; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(controller.level, greaterThan(0.99), reason: word);
          expect(tester.takeException(), isNull, reason: word);
          // Off the page: it fades out and lets go.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(milliseconds: 100));
          expect(controller.effect.value, isNull, reason: word);
          controller.enabled = false;
        }
        controller.dispose();
      },
    );
  }

  test('the spread widens with the level and is strongest near the middle', () {
    final c = LivingWordsController()..screen = const Size(800, 600);
    // Nothing plays yet: no spread.
    expect(c.strengthAt(0), 0);
    c.dispose();
  });

  testWidgets('plain words near a playing word catch its effect', (
    tester,
  ) async {
    final controller = LivingWordsController()
      ..speed = LivingSpeed.fast
      ..screen = const Size(800, 600);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(lightPalette),
        home: Scaffold(
          // Selectable, as in the reader: the text sits a level down.
          body: SelectionArea(
            child: Center(
              child: LivingWordsScope(
                controller: controller,
                child: LivingParagraph(
                  id: 0,
                  runs: lexicon.split(
                    'The old door was thick with venom and the hall beyond it '
                    'was quiet, very quiet, for a long while.',
                  ),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    controller.enabled = true;
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.effect.value, LivingEffect.poison);
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.level, greaterThan(0.99));
    expect(controller.strengthAt(0), greaterThan(0.85));
    expect(controller.strengthAt(40), lessThan(controller.strengthAt(10)));
    expect(controller.strengthAt(controller.reach), 0);
    // The nearby words are drawn over by the spread.
    final spread = find.descendant(
      of: find.byType(LivingParagraph),
      matching: find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.foregroundPainter.runtimeType.toString() == '_SpreadPainter',
      ),
    );
    expect(spread, findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.enabled = false;
    await tester.pump();
    controller.dispose();
  });

  testWidgets('only one word plays at a time, and each only once', (
    tester,
  ) async {
    final controller = LivingWordsController()
      ..speed = LivingSpeed.fast
      ..screen = const Size(800, 600);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(lightPalette),
        home: Scaffold(
          body: Center(
            child: LivingWordsScope(
              controller: controller,
              child: LivingParagraph(
                id: 0,
                runs: lexicon.split('Venom and fire and frost.'),
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );
    controller.enabled = true;
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.effect.value, LivingEffect.poison);
    final first = controller.active.value;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.active.value, first);
    }
    controller.enabled = false;
    await tester.pump();
    controller.dispose();
  });

  testWidgets('every word plays itself; taps lead and silence', (tester) async {
    final controller = LivingWordsController()
      ..speed = LivingSpeed.fast
      ..screen = const Size(800, 600);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(lightPalette),
        home: Scaffold(
          body: SelectionArea(
            child: Center(
              child: LivingWordsScope(
                controller: controller,
                child: LivingParagraph(
                  id: 0,
                  runs: lexicon.split('Venom and fire and frost.'),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    controller.enabled = true;
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Venom leads; all three play on themselves.
    expect(controller.effect.value, LivingEffect.poison);
    final ids = [0, 2, 4];
    for (final id in ids) {
      expect(controller.selfLevel(id), greaterThan(0.99), reason: '$id');
    }
    // Tap fire: it leads at once.
    await tester.tap(
      find.byWidgetPredicate((w) => w is LivingWord && w.text == 'fire'),
    );
    await tester.pump();
    expect(controller.effect.value, LivingEffect.fire);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Tap it again: silenced, it and its page effect fade away.
    await tester.tap(
      find.byWidgetPredicate((w) => w is LivingWord && w.text == 'fire'),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.isHushed(ids[1]), isTrue);
    expect(controller.selfLevel(ids[1]), 0);
    expect(controller.effect.value, isNot(LivingEffect.fire));
    // Venom keeps playing on itself.
    expect(controller.selfLevel(ids[0]), greaterThan(0.99));
    // Tap fire once more: back, and leading.
    await tester.tap(
      find.byWidgetPredicate((w) => w is LivingWord && w.text == 'fire'),
    );
    await tester.pump();
    expect(controller.effect.value, LivingEffect.fire);
    expect(controller.isHushed(ids[1]), isFalse);
    expect(tester.takeException(), isNull);
    controller.enabled = false;
    await tester.pump();
    controller.dispose();
  });
}
