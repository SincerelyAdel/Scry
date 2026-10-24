import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:scry/widgets/cats/cat_sim.dart';

void main() {
  for (final (name, size, text, most) in [
    ('tablet', const Size(1280, 800), 736.0, 0.5),
    ('phone', const Size(400, 850), 376.0, 2.5),
  ]) {
    test('cats rarely overlap on a $name', () {
      var samples = 0, overlaps = 0;
      for (var run = 0; run < 5; run++) {
        final pack = CatPack()..textWidth = text;
        for (var i = 0; i < 60 * 120; i++) {
          pack.tick(1 / 60, size);
          if (i < 120 || i % 10 != 0) continue;
          for (var a = 0; a < pack.cats.length; a++) {
            for (var b = a + 1; b < pack.cats.length; b++) {
              final x = pack.cats[a], y = pack.cats[b];
              if (x.fleeing || y.fleeing || x.peeking || y.peeking) continue;
              samples++;
              if ((x.hit - y.hit).distance < 32) overlaps++;
            }
          }
        }
      }
      // Percent of the time two cats are on top of each other: walking
      // past is fine, sitting on each other isn't.
      expect(100 * overlaps / samples, lessThan(most));
    });
  }
}
