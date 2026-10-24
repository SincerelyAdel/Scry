import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scry/theme.dart';
import 'package:scry/widgets/cats/cat_layer.dart';
import 'package:scry/widgets/cats/cat_menu.dart';
import 'package:scry/widgets/cats/cat_sim.dart';

void main() {
  menuTests();
  const page = Size(400, 800);

  /// Runs the pack for [seconds] at 60 frames a second.
  void run(CatPack pack, double seconds) {
    for (var i = 0; i < seconds * 60; i++) {
      pack.tick(1 / 60, page);
    }
  }

  bool finite(Offset o) => o.dx.isFinite && o.dy.isFinite;

  test('cats wander about the middle of the page', () {
    final pack = CatPack();
    run(pack, 40);
    expect(pack.cats, hasLength(6));
    for (final c in pack.cats) {
      expect(finite(c.p), isTrue);
      expect(c.pose, isNotNull);
      expect(finite(c.pose!.head), isTrue);
      expect(c.pose!.outline.getBounds().isFinite, isTrue);
      // Within the page, give or take a body length.
      expect(c.p.dx, inInclusiveRange(-150, page.width + 150));
      expect(c.p.dy, inInclusiveRange(-150, page.height + 150));
    }
  });

  test('beside a text column, they keep to the margins', () {
    const tablet = Size(1280, 800);
    final pack = CatPack()..textWidth = 700;
    // Text from 290 to 990; margins either side.
    for (var i = 0; i < 60 * 60; i++) {
      pack.tick(1 / 60, tablet);
      if (i % 30 != 0) continue;
      for (final c in pack.cats) {
        if (c.fleeing) continue;
        expect(
          c.p.dx < 290 || c.p.dx > 990,
          isTrue,
          reason: '${c.b.id} at ${c.p} after ${i ~/ 60}s',
        );
      }
    }
    // A scared cat leaves through its own side, not across the text.
    final cat = pack.cats.first;
    final from = cat.p;
    pack.tap(cat.hit);
    for (var i = 0; i < 60; i++) {
      pack.tick(1 / 60, tablet);
    }
    expect(cat.p.dx, lessThan(from.dx + 5));
  });

  test('paused, they sit or lie down and stay put', () {
    final pack = CatPack();
    run(pack, 5);
    pack.resting = true;
    run(pack, 3);
    final before = [for (final c in pack.cats) c.p];
    run(pack, 5);
    for (final (i, c) in pack.cats.indexed) {
      expect((c.p - before[i]).distance, lessThan(1));
      expect(c.sit + c.lie, greaterThan(0.9));
    }
  });

  test('shooed, they hide at the edges with only their heads in', () {
    final pack = CatPack();
    run(pack, 5);
    pack.shooed = true;
    run(pack, 15);
    for (final c in pack.cats) {
      expect(c.peeking, isTrue);
      final head = c.pose!.head;
      final toEdge = [
        head.dx,
        head.dy,
        page.width - head.dx,
        page.height - head.dy,
      ].reduce((a, b) => a < b ? a : b);
      expect(toEdge, lessThan(30), reason: '${c.b.id} at $head');
    }
    // Called back, they come in again.
    pack.shooed = false;
    run(pack, 20);
    for (final c in pack.cats) {
      expect(c.peeking, isFalse);
    }
  });

  test('a tapped cat runs off the page, then comes back', () {
    final pack = CatPack(count: 1);
    run(pack, 3);
    final cat = pack.cats.single;
    expect(pack.tap(cat.hit), isTrue);
    expect(cat.fleeing, isTrue);
    run(pack, 3);
    final p = cat.p;
    expect(
      p.dx < 0 || p.dy < 0 || p.dx > page.width || p.dy > page.height,
      isTrue,
    );
    run(pack, 15);
    expect(cat.fleeing, isFalse);
    // Taps elsewhere don't count.
    expect(pack.tap(const Offset(-500, -500)), isFalse);
  });

  testWidgets('the layer paints and leaves the page usable', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CatLayer(
          child: Center(
            child: TextButton(
              onPressed: () => tapped++,
              child: const Text('Under the cats'),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.tap(find.text('Under the cats'));
    expect(tapped, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

class _MenuHarness extends StatefulWidget {
  const _MenuHarness();

  @override
  State<_MenuHarness> createState() => _MenuHarnessState();
}

class _MenuHarnessState extends State<_MenuHarness> {
  bool on = false, resting = false, shooed = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        CatMenuButton(
          on: on,
          resting: resting,
          shooed: shooed,
          onChanged: (v) => setState(() => on = v),
          onRest: (v) => setState(() => resting = v),
          onShoo: (v) => setState(() => shooed = v),
        ),
      ],
    ),
  );
}

void menuTests() {
  testWidgets('the cat button opens every cat option', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(darkPalette),
        home: const _MenuHarness(),
      ),
    );
    await tester.tap(find.byTooltip('Cats'));
    await tester.pumpAndSettle();
    expect(find.text('Wandering behind the text'), findsOneWidget);
    expect(find.text('Rest'), findsNothing);

    // Switched on, the rest of the options open up.
    await tester.tap(find.text('Wandering behind the text'));
    await tester.pumpAndSettle();
    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('Shoo away'), findsOneWidget);
    await tester.tap(find.text('Shoo away'));
    await tester.pumpAndSettle();
    final state = tester.state<_MenuHarnessState>(find.byType(_MenuHarness));
    expect(state.on, isTrue);
    expect(state.shooed, isTrue);

    // A tap elsewhere closes it.
    await tester.tapAt(const Offset(200, 500));
    await tester.pumpAndSettle();
    expect(find.text('Rest'), findsNothing);
  });
}
