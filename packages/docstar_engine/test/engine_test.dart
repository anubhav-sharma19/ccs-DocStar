// extract / layout / rows / reconcile / engine on hand-built words (no PDF), plus the no-OCR policy tests.
import 'package:docstar_engine/docstar_engine.dart';
import 'package:docstar_engine/src/layout.dart';
import 'package:docstar_engine/src/reconcile.dart';
import 'package:test/test.dart';

Word w(String t, double x0, double x1, double top, {double size = 9, bool bold = false}) => Word(t, x0, x1, top, top + 8, size, bold);

/// Right-aligned money word ending at [x1].
Word m(String t, double x1, double top) => w(t, x1 - 6.0 * t.length, x1, top);

Page page(List<Word> words, {int n = 1}) => Page(n, 612, 792, words, []);

/// One statement page: header at y=100, then rows of (date, narration, debit, credit, balance).
List<Word> statement(List<(String, String, String?, String?, String?)> rows, {String? opening, String? closing}) {
  final ws = <Word>[
    w('ACME', 40, 70, 40), w('BANK', 75, 105, 40),
    w('Date', 40, 70, 100), w('Narration', 100, 160, 100), w('Debit', 300, 340, 100), w('Credit', 360, 400, 100), w('Balance', 430, 480, 100),
  ];
  var y = 120.0;
  if (opening != null) {
    ws.addAll([w('Opening', 100, 140, y), w('Balance', 145, 185, y), m(opening, 480, y)]);
    y += 15;
  }
  for (final (d, n, deb, cre, bal) in rows) {
    ws.add(w(d, 40, 95, y));
    ws.addAll([for (final (i, p) in n.split(' ').indexed) w(p, 100 + 40.0 * i, 135 + 40.0 * i, y)]);
    if (deb != null) ws.add(m(deb, 340, y));
    if (cre != null) ws.add(m(cre, 400, y));
    if (bal != null) ws.add(m(bal, 480, y));
    y += 15;
  }
  if (closing != null) {
    ws.addAll([w('Closing', 100, 140, y), w('Balance', 145, 185, y), m(closing, 480, y)]);
  }
  return ws;
}

String _money(int rupees) => '${rupees ~/ 1000},${(rupees % 1000).toString().padLeft(3, '0')}.00';

Map<String, dynamic> parse(List<Word> words) => parseDocument(makeDocument([page(words)]));

void main() {
  pageBreakTests();
  pageBreakRefTests();
  group('extract', () {
    test('buildLines groups by baseline, orders left to right, and keeps overlapping text on another line', () {
      final doc = makeDocument([
        page([w('b', 50, 60, 100), w('a', 10, 20, 100.5), w('c', 10, 20, 130), w('over', 12, 30, 100.4)])
      ]);
      expect(doc.pages.first.lines.map((l) => l.text), ['over b', 'a', 'c']);
    });
    test('unreadable: <8 words, or >30% cid/replacement glyphs', () {
      expect(unreadable(page([for (var i = 0; i < 7; i++) w('word$i', 10.0 * i, 10.0 * i + 8, 10)])), isTrue);
      final ok = [for (var i = 0; i < 8; i++) w('word$i', 10.0 * i, 10.0 * i + 8, 10)];
      expect(unreadable(page(ok)), isFalse);
      // (cid:N) text is mostly alphanumerics, so it never reaches 30% on its own; replacement glyphs do (T2)
      expect(unreadable(page([...ok, for (var i = 0; i < 8; i++) w('(cid:$i)(cid:$i)', 10.0 * i, 10.0 * i + 8, 30)])), isFalse);
      expect(unreadable(page([for (var i = 0; i < 8; i++) w('\uFFFDa\uFFFD\uFFFD', 10.0 * i, 10.0 * i + 8, 10)])), isTrue);
    });
    test('words.json round trip', () {
      final doc = makeDocument([page(statement([('01/01/2024', 'ATM', '5.00', null, '95.00')]))]);
      final again = loadWords(dumpWords(doc));
      expect(again.pages.first.lines.map((l) => l.text), doc.pages.first.lines.map((l) => l.text));
    });
  });

  group('page furniture', () {
    test('a repeated account block with a dated line, on a page with no column header, stays out of the neighbouring narration', () {
      List<Word> block() => [
            w('Account', 40, 85, 40), w('Number', 90, 130, 40), w('1234567', 200, 250, 40),
            w('Period', 40, 80, 52), w('From', 85, 110, 52), w('01/06/2026', 115, 170, 52), w('To', 175, 190, 52), w('30/06/2026', 195, 250, 52),
          ];
      final p1 = [...statement([for (var i = 0; i < 5; i++) ('0${i + 1}/06/2026', 'ROW$i', '5.00', null, _money(10000 - 100 * (i + 1)))], opening: '10,000.00'), ...block()];
      final p2 = <Word>[
        ...block(),
        for (var i = 5; i < 10; i++) ...[
          w('0${i + 1}/06/2026', 40, 95, 64.0 + 15 * (i - 5)), w('ROW$i', 100, 135, 64.0 + 15 * (i - 5)), m('5.00', 340, 64.0 + 15 * (i - 5)), m(_money(10000 - 100 * (i + 1)), 480, 64.0 + 15 * (i - 5)),
        ],
      ];
      final res = parseDocument(makeDocument([page(p1, n: 1), page(p2, n: 2)]));
      final txns = (res['sections'] as List).expand((s) => s['transactions'] as List).toList();
      expect(txns.map((t) => t['description']), [for (var i = 0; i < 10; i++) 'ROW$i']);
    });
  });

  group('column_headers', () {
    test('keeps the printed header next to the standardized role', () {
      final res = parse(statement([('01/01/2024', 'ATM', '5.00', null, '95.00'), ('02/01/2024', 'POS', '5.00', null, '90.00')], opening: '100.00'));
      final s = (res['sections'] as List).first as Map;
      expect(s['column_headers'], [
        {'role': 'date', 'header': 'Date'}, {'role': 'desc', 'header': 'Narration'},
        {'role': 'debit', 'header': 'Debit'}, {'role': 'credit', 'header': 'Credit'}, {'role': 'balance', 'header': 'Balance'},
      ]);
      expect((s['column_headers'] as List).map((c) => (c as Map)['role']), s['columns']);
    });
  });

  group('column cuts', () {
    test('no empty gutter before the Ref column (one row touches it): the cut still falls in the least-covered gap, not mid-narration', () {
      final ws = <Word>[
        w('ACME', 40, 70, 40), w('BANK', 75, 105, 40),
        w('Date', 40, 70, 100), w('Narration', 100, 160, 100), w('Chq./Ref.No.', 285, 345, 100), w('Debit', 400, 440, 100), w('Balance', 500, 540, 100),
      ];
      for (var i = 0; i < 5; i++) {
        final y = 120.0 + 15 * i;
        ws.addAll([
          w('0${i + 1}/06/26', 40, 85, y),
          w('UPI-SHOP', 100, 150, y), w('LONG', 155, 190, y), w('NARRATION', 195, 225, y), w('ARE', 230, 252, y),
          if (i == 2) w('TOUCH', 254, 284, y), // fills the gutter in one row
          w('0000123456', 285, 340, y), m('100.00', 440, y), m(_money(10000 - 100 * (i + 1)), 540, y),
        ]);
      }
      final txns = (parse(ws)['sections'] as List).expand((s) => s['transactions'] as List).toList();
      expect(txns.map((t) => t['description']), [
        'UPI-SHOP LONG NARRATION ARE', 'UPI-SHOP LONG NARRATION ARE', 'UPI-SHOP LONG NARRATION ARE TOUCH',
        'UPI-SHOP LONG NARRATION ARE', 'UPI-SHOP LONG NARRATION ARE',
      ]);
      expect(txns.map((t) => t['reference']).toSet(), {'0000123456'});
    });
  });

  group('layout', () {
    test('detectHeaders finds the roles of a plain header line', () {
      final doc = makeDocument([page(statement([('01/01/2024', 'ATM', '5.00', null, '95.00')]))]);
      final h = detectHeaders(doc).values.single;
      expect(h.roles(), ['date', 'desc', 'debit', 'credit', 'balance']);
    });
    test('joinNumericFragments re-joins split amounts and detached suffixes (A12)', () {
      String j(List<Word> ws, {bool grouped = false}) => joinNumericFragments(ws, grouped).map((x) => x.text).join('|');
      expect(j([w('10,885.', 0, 36, 0), w('53', 38, 50, 0)]), '10,885. 53');
      expect(j([w('1', 0, 6, 0), w('234.56', 8, 44, 0)], grouped: true), '1 234.56');
      expect(j([w('85.57', 0, 30, 0), w('Cr', 32, 44, 0)]), '85.57 Cr');
      expect(j([w('+', 0, 6, 0), w('400.00', 8, 44, 0)]), '+400.00'); // a lone sign closer to the next number is its prefix
      expect(j([w('Foo', 0, 20, 0), w('bar', 60, 80, 0)]), 'Foo|bar');
    });
  });

  group('reconcile', () {
    Txn t(String mag, {int? sign, String? bal}) => Txn(null, null, '', '', null, null, bal == null ? null : Dec.parse(bal), 1, 0,
        magnitude: Dec.parse(mag), sign: sign);
    Map<String, dynamic> open(String b) => {'kind': 'open', 'balance': Dec.parse(b), 'values': <String, List<String>>{}, 'text': '', 'index': 0, 'date': null};

    test('a gap between two balances is solved when exactly one sign pattern fits', () {
      final xs = [t('10'), t('30'), t('5', bal: '135')];
      final c = reconcileSection(xs, [open('100')], 'asc');
      expect(xs.map((x) => x.sign), [1, 1, -1]);
      expect(c['gap_solved'], 1);
      expect(c['balanced'], isTrue);
    });
    test('ambiguous gaps are flagged, not guessed', () {
      final xs = [t('10'), t('10', bal: '100')];
      reconcileSection(xs, [open('100')], 'asc');
      expect(xs.every((x) => x.flags.contains('sign_ambiguous')), isTrue);
    });
    test('a column sign that contradicts the balance is overruled and flagged (A15)', () {
      final xs = [t('50', sign: -1, bal: '150')];
      final c = reconcileSection(xs, [open('100')], 'asc');
      expect(xs.single.sign, 1);
      expect(xs.single.flags, contains('column_sign_conflict'));
      expect(c['conflicts'], 1);
    });
    test('a broken chain is a balance_break', () {
      final xs = [t('50', sign: 1, bal: '175')];
      final c = reconcileSection(xs, [open('100')], 'asc');
      expect(xs.single.flags, contains('balance_break'));
      expect(c['balanced'], isFalse);
    });
    test('detectOrder: dates decide, same-day falls back to the chain (R8, R10)', () {
      Txn d(int day) => Txn(DateTime.utc(2024, 1, day), null, '', '', null, null, null, 1, 0);
      expect(detectOrder([d(3), d(2), d(1)]), 'desc');
      expect(detectOrder([d(1), d(2), d(3)]), 'asc');
      final a = t('10', bal: '90'), b = t('20', bal: '110');
      expect(detectOrder([a, b]), 'asc');
    });
    test('smartJoin glues wrapped narration after / or -', () {
      expect(smartJoin(['UPI/1234/', 'ABC', 'PAYMENT', '-X']), 'UPI/1234/ABC PAYMENT-X');
    });
  });

  group('engine', () {
    test('plain statement is verified and reconciles', () {
      final r = parse(statement([
        ('01/01/2024', 'ATM WITHDRAWAL', '200.00', null, '800.00'),
        ('02/01/2024', 'SALARY JAN', null, '500.00', '1,300.00'),
        ('03/01/2024', 'GROCERY STORE', '50.25', null, '1,249.75'),
      ], opening: '1,000.00', closing: '1,249.75'));
      expect(r['quality']['status'], 'verified');
      final s = (r['sections'] as List).single;
      expect(s['opening'], '1000.00');
      expect(s['closing'], '1249.75');
      expect(s['checks']['balanced'], isTrue);
      expect([for (final t in s['transactions']) (t['date'], t['amount'], t['balance'], t['description'])], [
        ('2024-01-01', '-200.00', '800.00', 'ATM WITHDRAWAL'),
        ('2024-01-02', '500.00', '1300.00', 'SALARY JAN'),
        ('2024-01-03', '-50.25', '1249.75', 'GROCERY STORE'),
      ]);
    });
    test('credit printed in the debit column: the balance wins and the row is flagged (A15)', () {
      final r = parse(statement([
        ('01/01/2024', 'ATM WITHDRAWAL', '200.00', null, '800.00'),
        ('02/01/2024', 'SALARY JAN', '500.00', null, '1,300.00'),
      ], opening: '1,000.00'));
      final tx = (r['sections'] as List).single['transactions'] as List;
      expect(tx[1]['amount'], '500.00');
      expect(tx[1]['flags'], contains('column_sign_conflict'));
    });
    test('a wrapped narration line joins its row (R1)', () {
      final ws = statement([
        ('01/01/2024', 'ATM WITHDRAWAL', '200.00', null, '800.00'),
        ('02/01/2024', 'SALARY JAN', null, '500.00', '1,300.00'),
      ], opening: '1,000.00');
      ws.add(w('REF123', 100, 140, 150)); // below the last row, no date or money
      final tx = (parse(ws)['sections'] as List).single['transactions'] as List;
      expect(tx.last['description'], 'SALARY JAN REF123');
    });
    test('tampered balance is not verified', () {
      final r = parse(statement([('01/01/2024', 'ATM WITHDRAWAL', '200.00', null, '700.00')], opening: '1,000.00'));
      expect(r['quality']['status'], isNot('verified'));
      expect(r['quality']['balance_breaks'], 1);
    });

    // tests/test_docstar.py: test_image_only_page_is_refused, test_text_page_plus_blank_page_is_not_verified
    test('image-only pages are refused (no OCR)', () {
      final q = parseDocument(makeDocument([page([], n: 1), page([], n: 2)]))['quality'];
      expect(q['status'], 'unsupported_scanned_pdf');
      expect(q['score'], 0);
      expect(q['reason'], noOcrNotice);
      expect(parseDocument(makeDocument([]))['quality']['status'], 'unsupported_scanned_pdf');
    });
    test('a text page plus a blank page is never verified', () {
      final text = page([for (var i = 0; i < 12; i++) w('Statement line number $i of the sample', 50, 300, 700.0 - 20 * i)]);
      final res = parseDocument(makeDocument([text, page([], n: 2)]));
      expect(res['quality']['status'], isNot('verified'));
      expect(res['quality']['status'], isNot('unsupported_scanned_pdf'));
      expect(res['warnings'], contains('page 2: no readable text layer'));
    });
    test('a verified statement with one unreadable page is downgraded to review', () {
      final pg1 = page(statement([('01/01/2024', 'ATM', '200.00', null, '800.00')], opening: '1,000.00', closing: '800.00'));
      final res = parseDocument(makeDocument([pg1, page([], n: 2)]));
      expect(res['quality']['status'], 'review');
      expect(res['quality']['unreadable_pages'], 1);
    });
  });
}

// Page-break repro: last row of page 1 continues at the top of page 2 under a repeated header.
void pageBreakRefTests() {
  group('page break narration with a reference column', () {
    // Date | Narration | Chq./Ref.No. | Debit | Credit | Balance; ref filled only on some rows.
    List<Word> pg(int from, int n, {Set<int> refs = const {}, String? head, double stretch = 36.0}) {
      final ws = <Word>[
        w('ACME', 40, 70, 40), w('BANK', 75, 105, 40),
        w('Date', 40, 70, 100), w('Narration', 100, 160, 100), w('Chq./Ref.No.', 285, 345, 100),
        w('Debit', 400, 440, 100), w('Credit', 450, 490, 100), w('Balance', 520, 560, 100),
      ];
      var y = 120.0;
      if (head != null) {
        ws.addAll([for (final (i, p) in head.split(' ').indexed) w(p, 100 + 40.0 * i, 135 + 40.0 * i, y)]);
        y += 10;
      }
      for (var i = from; i < from + n; i++) {
        ws.addAll([
          w('${(i % 28 + 1).toString().padLeft(2, '0')}/06/2026', 40, 95, y),
          for (final (k, p) in ['NEFT', 'CR-XXXXXX-TLG', 'YYYYY', 'OOOOOOOO', 'LI'].indexed) w(p, 100 + stretch * k, 130 + stretch * k, y),
          if (refs.contains(i)) w('46558767476', 285, 345, y),
          m('100.00', 440, y), m(_money(10000 - 100 * (i + 1)), 560, y),
        ]);
        y += 10;
      }
      return ws;
    }

    for (final (refs, stretch) in [(<int>{7}, 36.0), (<int>{1, 4, 7}, 36.0), (<int>{7}, 38.0), (<int>{1, 4, 7}, 38.0), (<int>{7}, 37.0), (<int>{1, 4, 7}, 37.0)]) {
      test('last row of page 1 has a ref, narration continues on page 2 (refs on rows $refs, stretch $stretch)', () {
        final res = parseDocument(makeDocument([
          page(pg(0, 8, refs: refs, stretch: stretch), n: 1),
          page(pg(8, 8, head: 'SECONDHALF', stretch: stretch), n: 2),
        ]));
        final txns = (res['sections'] as List).expand((s) => s['transactions'] as List).toList();
        expect(txns.length, 16);
        expect(txns[7]['description'], 'NEFT CR-XXXXXX-TLG YYYYY OOOOOOOO LI SECONDHALF');
        expect(txns[7]['reference'], '46558767476');
        expect(txns[8]['description'], 'NEFT CR-XXXXXX-TLG YYYYY OOOOOOOO LI');
      });
    }
  });
}

void pageBreakTests() {
  group('page break narration', () {
    List<Word> pg(int from, int n, {String? tail, String? head}) {
      final ws = <Word>[
        w('ACME', 40, 70, 40), w('BANK', 75, 105, 40),
        w('Date', 40, 70, 100), w('Narration', 100, 160, 100), w('Debit', 300, 340, 100), w('Credit', 360, 400, 100), w('Balance', 430, 480, 100),
      ];
      var y = 120.0;
      if (head != null) {
        ws.addAll([for (final (i, p) in head.split(' ').indexed) w(p, 100 + 40.0 * i, 135 + 40.0 * i, y)]);
        y += 10;
      }
      for (var i = from; i < from + n; i++) {
        ws.addAll([w('${(i % 28 + 1).toString().padLeft(2, '0')}/06/2026', 40, 95, y), w('ROW$i', 100, 135, y), m('100.00', 340, y), m(_money(10000 - 100 * (i + 1)), 480, y)]);
        if (i == from + n - 1 && tail != null) {
          ws.addAll([for (final (k, p) in tail.split(' ').indexed) w(p, 140 + 40.0 * k, 175 + 40.0 * k, y)]);
        }
        y += 10;
      }
      return ws;
    }

    for (final tail in [null, 'FIRSTHALF']) {
      test('continuation at top of page 2 joins the last row of page 1 (tail on date line: $tail)', () {
        final res = parseDocument(makeDocument([
          page(pg(0, 8, tail: tail), n: 1),
          page(pg(8, 8, head: 'SECONDHALF REF99'), n: 2),
        ]));
        final txns = (res['sections'] as List).expand((s) => s['transactions'] as List).toList();
        expect(txns.length, 16);
        expect(txns[7]['description'], contains('SECONDHALF'));
        expect(txns[8]['description'], 'ROW8');
      });
    }
  });
}
