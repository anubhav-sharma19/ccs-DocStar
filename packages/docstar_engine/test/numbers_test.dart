// Expected values come from running the Python reference (tests/test_docstar.py + docs/EDGE_CASES.md A*/D*).
import 'package:docstar_engine/src/dec.dart';
import 'package:docstar_engine/src/numbers.dart';
import 'package:docstar_engine/src/py.dart';
import 'package:test/test.dart';

void main() {
  group('Dec', () {
    test('keeps the printed scale, like Python Decimal', () {
      expect(Dec.parse('1000.50').toString(), '1000.50');
      expect(Dec.parse('007').toString(), '7');
      expect(Dec.parse('0.05').toString(), '0.05');
      expect((Dec.parse('1.5') + Dec.parse('2.25')).toString(), '3.75');
      expect((-Dec.parse('0.00')).toString(), '0.00'); // -Decimal("0.00") is +0
      expect(Dec.parse('1.0') == Dec.parse('1.00'), isTrue);
    });
    test('toFixed2 rounds half even and keeps the sign of tiny negatives', () {
      expect(Dec.parse('0.125').toFixed2(), '0.12');
      expect(Dec.parse('0.135').toFixed2(), '0.14');
      expect(Dec.parse('5').toFixed2(), '5.00');
      expect(Dec.parse('-0.001').toFixed2(), '-0.00');
      expect(Dec.parse('1234.5').toFixed2(), '1234.50');
    });
  });

  group('py helpers', () {
    test('pyRound is half-even on exact ties', () {
      expect(pyRound(0.125, 2), 0.12);
      expect(pyRound(0.375, 2), 0.38);
      expect(pyRound(2.25, 1), 2.2);
      expect(pyRound(2.35, 1), 2.4); // not a tie in binary
      expect(pyRound(0.6667, 2), 0.67);
    });
    test('stableSort keeps ties in order; median averages the middle pair', () {
      final l = [(1, 'a'), (0, 'b'), (1, 'c'), (0, 'd')];
      stableSort(l, (x, y) => x.$1 - y.$1);
      expect(l.map((e) => e.$2).join(), 'bdac');
      expect(median([3, 1, 2, 10]), 2.5);
    });
  });

  group('parseAmount', () {
    // token -> [signed, side, repaired, integer]
    final cases = <String, List<Object?>>{
      '1,234.56': ['1234.56', null, false, false],
      '1,02,942.60': ['102942.60', null, false, false], // A10 Indian grouping
      '.11': ['0.11', null, false, false],
      '100.00-': ['-100.00', null, false, false], // A3 trailing minus
      '100.00+': ['100.00', null, false, false],
      '(7.62)': ['-7.62', null, false, false], // A6
      '-R200.00': ['-200.00', null, false, false], // A2
      '-\$9.95': ['-9.95', null, false, false],
      '\$ -5': ['-5', null, false, true],
      '+ \$400.00': ['400.00', null, false, false],
      '123.45D': ['-123.45', 'dr', false, false], // A5
      '85.57(Cr)': ['85.57', 'cr', false, false], // A4
      '85.57 Dr': ['85.57', 'dr', false, false],
      '12.50(-)': ['-12.50', null, false, false], // A7
      '1,554,983,.87': ['1554983.87', null, true, false], // A12
      '9.710.87': ['9710.87', null, true, false],
      '49.,44': ['49.44', null, true, false],
      '10,885. 53': ['10885.53', null, false, false],
      '2 00.00': ['200.00', null, false, false],
      '1 234.56': ['1234.56', null, false, false],
      '1234.56': ['1234.56', null, false, false],
      '1234': ['1234', null, false, true],
      '0.00': ['0.00', null, false, false],
      '115515.630': ['115515.630', null, false, false],
      '1,234': ['1234', null, false, true],
      'Rs. 1,000.00': ['1000.00', null, false, false],
      '₹5,00,000.00': ['500000.00', null, false, false],
    };
    cases.forEach((tok, want) {
      test(tok, () {
        final a = parseAmount(tok)!;
        expect([a.signed.toString(), a.side, a.repaired, a.integer], want);
      });
    });
    // euro locale (1.234,56 / 1 234,56 / 120.000,00(+))
    const eu = {
      '1.234,56': '1234.56',
      '120.000,00(+)': '120000.00',
      '1 234,56': '1234.56',
      '12.345.678,90': '12345678.90',
      '1.234': '1234',
    };
    eu.forEach((tok, want) => test('$tok (eu)', () => expect(parseAmount(tok, 'eu')!.signed.toString(), want)));

    test('placeholders and non-amounts are null (A11)', () {
      for (final t in ['-', 'blank.', 'N/A', 'nil', '--', '', 'abc', r'$']) {
        expect(parseAmount(t), isNull, reason: t);
      }
    });
    test('looksLikeAmount / detectLocale', () {
      expect(looksLikeAmount('1,234.56'), isTrue);
      expect(looksLikeAmount('1234'), isFalse);
      expect(looksLikeAmount('1234', requireDecimals: false), isTrue);
      expect(looksLikeAmount('12.3.4'), isFalse);
      expect(looksLikeAmount('Cr'), isFalse);
      expect(detectLocale(['1.234,56', '12,50', '3,00']), 'eu');
      expect(detectLocale(['1,234.56', '12.50']), 'en');
      expect(detectLocale([]), 'en');
    });
  });

  group('findDates', () {
    (int?, int, int, int, int, String, bool) hit(String t, [DateConfig? c]) {
      final h = findDates(t, c).first;
      return (h.y, h.m, h.d, h.start, h.end, h.kind, h.invalid);
    }

    test('05Jan24 / JAN01 / glued and dotted (D1 D2 D6 D7)', () {
      expect(hit('05Jan24'), (2024, 1, 5, 0, 7, 'dmon', false));
      expect(hit('JAN01'), (null, 1, 1, 0, 5, 'mond', false));
      expect(hit('01 Aug 23.'), (2023, 8, 1, 0, 9, 'dmon', false));
      expect(hit('2024-01-05T10:30'), (2024, 1, 5, 0, 10, 'iso', false));
      expect(hit('5th March 2023'), (2023, 3, 5, 0, 14, 'dmon', false));
      expect(hit('Jan 5, 2024'), (2024, 1, 5, 0, 11, 'mond', false));
      expect(hit('10-Mar'), (null, 3, 10, 0, 6, 'dmon', false));
    });
    test('invalid dates are kept and flagged (D4)', () {
      expect(hit('2024-06-31'), (2024, 6, 31, 0, 10, 'iso', true));
      expect(hit('31/09'), (null, 9, 31, 0, 5, 'num2', true));
      expect(hit('30 Feb'), (null, 2, 30, 0, 6, 'dmon', true));
      expect(hit('04/31'), (null, 4, 31, 0, 5, 'num2', true));
      expect(hit('29/02/2023'), (2023, 2, 29, 0, 10, 'num3', true));
    });
    test('DMY vs MDY and dotted short dates (D3)', () {
      expect(hit('12/05/2024'), (2024, 5, 12, 0, 10, 'num3', false));
      expect(hit('12/05/2024', DateConfig(order: 'MDY')), (2024, 12, 5, 0, 10, 'num3', false));
      expect(findDates('15.03'), isEmpty);
      final h = findDates('15.03', DateConfig(allowDotShort: true)).single;
      expect((h.m, h.d, h.kind), (3, 15, 'num2dot'));
    });
    test('two dates in one line', () {
      final h = findDates('30 Jan 25 31 Jan 25');
      expect(h.map((e) => (e.y, e.d, e.start, e.end)), [(2025, 30, 0, 9), (2025, 31, 10, 19)]);
    });
    test('voteDateOrder', () {
      expect(voteDateOrder(['13/05/2024', '01/02/2024']), 'DMY');
      expect(voteDateOrder(['05/13/2024']), 'MDY');
      expect(voteDateOrder(['01/02/2024']), isNull);
      expect(voteDateOrder(['13.05']), isNull); // a '.' pair is usually money
      expect(voteDateOrder(['25/12']), 'DMY');
    });
  });

  group('year and period', () {
    final cfg = DateConfig(periodStart: DateTime.utc(2023, 12, 10), periodEnd: DateTime.utc(2024, 1, 9));
    DateTime? year(int m, int d, [DateConfig? c]) => resolveYear(DateHit(null, m, d, 0, 0, 'num2'), c ?? cfg).$1;
    test('Dec -> Jan rollover picks the year inside the period (D1)', () {
      expect(year(12, 20), DateTime.utc(2023, 12, 20));
      expect(year(1, 5), DateTime.utc(2024, 1, 5));
      expect(year(2, 29), DateTime.utc(2024, 2, 29));
    });
    test('default year, and unknown year', () {
      expect(year(12, 20, DateConfig(defaultYear: 2024)), DateTime.utc(2024, 12, 20));
      expect(resolveYear(DateHit(null, 12, 20, 0, 0, 'x'), DateConfig()), (null, true));
    });
    test('Axis period', () {
      final (a, b) = findPeriod(['Statement of Axis Account No :921 for the period (From : 23-08-2023 To : 24-01-2024)'], DateConfig());
      expect((isoDate(a!), isoDate(b!)), ('2023-08-23', '2024-01-24'));
    });
    test('period needs a year on the end date; order follows the config', () {
      expect(findPeriod(['Period 01 Jan - 31 Jan 2024'], DateConfig()), (null, null));
      final (a, b) = findPeriod(['from 03/10/2023 to 02/11/2023'], DateConfig());
      expect((isoDate(a!), isoDate(b!)), ('2023-10-03', '2023-11-02'));
      expect(findPeriod(['from 03/10/2023 to 02/11/2023'], DateConfig(order: 'MDY')), (null, null)); // Mar 10 -> Feb 11 is backwards
    });
  });
}
