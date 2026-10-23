import 'package:flutter_test/flutter_test.dart';
import 'package:feedviewer/utils/date_parser.dart';
import 'package:feedviewer/utils/format.dart';
import 'package:feedviewer/utils/html_text.dart';

void main() {
  group('parseFeedDate', () {
    test('RFC 822 with GMT', () {
      expect(
        parseFeedDate('Mon, 09 Jun 2025 08:00:00 GMT'),
        DateTime.utc(2025, 6, 9, 8),
      );
    });

    test('RFC 822 with numeric offset', () {
      expect(
        parseFeedDate('Tue, 10 Jun 2025 16:00:00 +0200'),
        DateTime.utc(2025, 6, 10, 14),
      );
    });

    test('RFC 822 with named US zone, no weekday, no seconds', () {
      expect(
        parseFeedDate('10 Jun 2025 09:30 EST'),
        DateTime.utc(2025, 6, 10, 14, 30),
      );
    });

    test('RFC 822 with long month name and two-digit year', () {
      expect(parseFeedDate('3 June 25 00:00:00 UT'), DateTime.utc(2025, 6, 3));
    });

    test('ISO 8601', () {
      expect(
        parseFeedDate('2025-06-10T09:30:00+01:00'),
        DateTime.utc(2025, 6, 10, 8, 30),
      );
      expect(parseFeedDate('2025-06-10T09:30:00Z'), isNotNull);
    });

    test('garbage and empty give null', () {
      expect(parseFeedDate(null), isNull);
      expect(parseFeedDate('  '), isNull);
      expect(parseFeedDate('yesterday-ish'), isNull);
      expect(parseFeedDate('32 Foo 2025 10:00:00 GMT'), isNull);
    });
  });

  group('htmlToPlainText', () {
    test('keeps paragraphs and bullets, decodes entities', () {
      expect(
        htmlToPlainText(
          '<p>Hello&nbsp;<b>world</b> &amp; co</p>'
          '<ul><li>one</li><li>two</li></ul><p>End<br>line</p>',
        ),
        // Non-breaking spaces collapse like any other whitespace.
        'Hello world & co\n\n• one\n• two\n\nEnd\nline',
      );
    });

    test('drops scripts and styles, keeps image alt text', () {
      expect(
        htmlToPlainText(
          '<style>p{}</style><p>A <img src="x.png" alt="chart"></p>'
          '<script>alert(1)</script>',
        ),
        'A [chart]',
      );
    });

    test('collapses whitespace outside pre, keeps it inside', () {
      expect(
        htmlToPlainText('<p>  a\n   b </p><pre>x\n  y</pre>'),
        'a b\n\nx\n  y',
      );
    });

    test('plain text passes through', () {
      expect(htmlToPlainText('Just text'), 'Just text');
      expect(htmlToPlainText(null), '');
    });
  });

  group('relativeDate', () {
    final now = DateTime(2025, 6, 10, 12);

    test('recent times are relative', () {
      expect(relativeDate(now, now: now), 'just now');
      expect(
        relativeDate(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
      expect(
        relativeDate(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        relativeDate(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
    });

    test('older times are dates', () {
      expect(relativeDate(DateTime(2025, 1, 2), now: now), 'Jan 2, 2025');
    });
  });
}
