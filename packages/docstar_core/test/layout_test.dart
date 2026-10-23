import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:docstar_core/docstar_core.dart';
import 'package:test/test.dart';

import 'package:docstar_core/testing.dart';

final dateStart = RegExp(r'\d\d/\d\d/\d{4}');
const stmtHeaders = ['Date', 'Description', 'Debit', 'Credit', 'Balance'];

String hash(DsDocument d) => sha256.convert(utf8.encode(d.toCanonicalJson())).toString();

Table onlyTable(DsDocument d, [int page = 1]) => d.pages[page - 1].tables.single;

/// The fixture corpus: every shape the tests use.
Map<String, List<PageInput>> corpus() => {
      'plain': statement(noise: false),
      'noise_3p': statement(pages: 3),
      'wrapped_after': statement(wrapEvery: 3),
      'wrapped_before': statement(wrapEvery: 3, before: true),
      'headless_3p': statement(pages: 3, repeatHeader: false),
      'rot90': statement(pages: 2, turn: 90),
      'rot180': statement(pages: 2, turn: 180),
      'rot270': statement(pages: 2, turn: 270),
      'empty_page': [const PageInput(1, 595, 842, [])],
      'stamp': statement(noise: false, extra: stamp),
      'watermark': statement(pages: 2, extra: watermark),
      'probe_on_row': statement(noise: false, extra: probe),
    };

const stamp = [T(150, 200, 'DUPLICATE', size: 40)];
const watermark = [T(60, 330, 'CONFIDENTIAL COPY', size: 14, slope: 0.6)];
const probe = [T(140, 176, 'PROBE-ALPHA', size: 15)]; // same baseline as row 4, 1.5x the font

void main() {
  group('(a) every char lands in exactly one word', () {
    for (final e in corpus().entries) {
      test(e.key, () {
        final doc = layout(e.value);
        for (var i = 0; i < doc.pages.length; i++) {
          final input = e.value[i];
          final seen = <int>[for (final w in doc.pages[i].words) ...w.charIndices];
          expect(seen.toSet().length, seen.length, reason: 'a char is in two words');
          final glyphs = {for (final c in input.chars) if (!c.isSpace) c.index};
          expect(seen.toSet(), glyphs, reason: 'non-space chars lost or whitespace kept');
          // and every word is in exactly one line, every line in exactly one block
          final inLines = [for (final l in doc.pages[i].lines) ...l.words.map((w) => w.id)];
          expect(inLines.toSet().length, inLines.length);
          expect(inLines.toSet(), {for (final w in doc.pages[i].words) w.id});
          final inBlocks = [for (final b in doc.pages[i].blocks) ...b.lines.map((l) => l.id)];
          expect(inBlocks..sort(), [for (final l in doc.pages[i].lines) l.id]..sort());
        }
      });
    }
  });

  group('words', () {
    test('a comma hanging below the baseline stays in its amount (one word, one line)', () {
      // Proportional-font comma: mostly below the baseline (43% overlap with the digits' band).
      var x = 0.0;
      final chars = <CharCell>[];
      for (final ch in '246,348.58'.split('')) {
        final box = ch == ','
            ? Box(x + 1, 98.5, x + 2.5, 102)
            : ch == '.'
                ? Box(x + 1, 98.8, x + 2.5, 100)
                : Box(x + 0.5, 93, x + 5.5, 100);
        chars.add(CharCell(chars.length, ch, box));
        x += ch == ',' || ch == '.' ? 3 : 6;
      }
      final page = layout([PageInput(1, 595, 842, chars)]).pages.single;
      expect(page.lines, hasLength(1));
      expect(page.words.map((w) => w.text), ['246,348.58']);
    });

    // Proportional-font style: a narrow space (2 pt) leaves a 3 pt gap, under one pitch.
    CharCell g(int i, String s, double x) => CharCell(i, s, s == ' ' ? Box(x, 100, x + 2, 100) : Box(x + 0.5, 93, x + 5.5, 100));
    test('an explicit space splits words even when the gap is narrow', () {
      final chars = [g(0, 'A', 0), g(1, 'B', 6), g(2, ' ', 12), g(3, 'C', 14), g(4, 'D', 20)];
      final words = layout([PageInput(1, 595, 842, chars)]).pages.single.words;
      expect(words.map((w) => w.text), ['AB', 'CD']);
    });
    test('without a space char, a gap wider than one pitch still splits (fallback)', () {
      final chars = [g(0, 'A', 0), g(1, 'B', 6), g(2, 'C', 20), g(3, 'D', 26)];
      expect(layout([PageInput(1, 595, 842, chars)]).pages.single.words.map((w) => w.text), ['AB', 'CD']);
    });
    test('stream-adjacent glyphs with a sub-pitch gap stay one word', () {
      final chars = [g(0, 'A', 0), g(1, 'B', 6), g(2, 'C', 14), g(3, 'D', 20)];
      expect(layout([PageInput(1, 595, 842, chars)]).pages.single.words.map((w) => w.text), ['ABCD']);
    });
  });

  group('(b) determinism', () {
    test('same input -> identical output hash, also with shuffled char order', () {
      for (final pages in corpus().values) {
        final a = hash(layout(pages));
        expect(hash(layout(pages)), a);
        final shuffled = [
          for (final p in pages.reversed)
            PageInput(p.number, p.width, p.height, [...p.chars]..shuffle(Random(7)), rotation: p.rotation)
        ];
        expect(hash(layout(shuffled)), a);
      }
    });
  });

  group('(c) rotation invariance (A-C8)', () {
    final upright = structure(layout(statement(pages: 2)));
    for (final turn in [90, 180, 270]) {
      test('text turned $turn -> same structure', () {
        final doc = layout(statement(pages: 2, turn: turn));
        expect(doc.pages.map((p) => p.readingRotation), everyElement(turn));
        expect(structure(doc), upright);
      });
    }
    test('toDisplay maps reading boxes back onto the turned chars', () {
      final input = statement(turn: 90);
      final doc = layout(input);
      final page = doc.pages.single;
      final byIndex = {for (final c in input.single.chars) c.index: c.box};
      final w = page.words.first;
      final shown = page.toDisplay(w.box);
      for (final i in w.charIndices) {
        final c = byIndex[i]!;
        expect(c.left >= shown.left - 0.01 && c.right <= shown.right + 0.01, isTrue);
        expect(c.top >= shown.top - 0.01 && c.bottom <= shown.bottom + 0.01, isTrue);
      }
    });
  });

  group('tables', () {
    test('plain table: 5 columns, header row, every row has a date and a balance', () {
      final t = onlyTable(layout(statement(noise: false)));
      expect(t.cols, 5);
      expect(t.rows, 13);
      expect(t.headerRow, 0);
      expect(t.rowTexts(0), stmtHeaders);
      for (var r = 1; r < t.rows; r++) {
        expect(dateStart.hasMatch(t.cell(r, 0).text), isTrue, reason: 'row $r');
        expect(t.cell(r, 4).text, isNotEmpty);
      }
    });

    test('right-aligned numbers of ragged length stay in their column, intact (A-C10 core half)', () {
      final t = onlyTable(layout(statement(noise: false)));
      final debits = [for (var r = 1; r < t.rows; r++) t.cell(r, 2).text].where((s) => s.isNotEmpty).toList();
      expect(debits.map((s) => s.length).toSet().length, greaterThan(1), reason: 'fixture has ragged amounts');
      for (final s in [...debits, for (var r = 1; r < t.rows; r++) t.cell(r, 4).text]) {
        expect(RegExp(r'^[\d,]+\.\d\d$').hasMatch(s), isTrue, reason: s);
      }
    });

    test('A-C10 core half: 1,23,456.78 is one word and one cell', () {
      final doc = layout([
        page(1, [
          const T(50, 100, 'Date'), const T(130, 100, 'Item'), r(400, 100, 'Amount'),
          const T(50, 114, '01/06/2026'), const T(130, 114, 'ONE'), r(400, 114, '1,23,456.78'),
          const T(50, 128, '02/06/2026'), const T(130, 128, 'TWO'), r(400, 128, '5.00'),
          const T(50, 142, '03/06/2026'), const T(130, 142, 'THREE'), r(400, 142, '12,000.00'),
        ])
      ]);
      expect(doc.pages.single.words.where((w) => w.text == '1,23,456.78'), hasLength(1));
      expect(onlyTable(doc).cell(1, 2).text, '1,23,456.78');
    });

    test('sparse column (credits in 1 of 8 rows, < 20%) keeps its own column', () {
      final t = onlyTable(layout(statement(noise: false, creditEvery: 8)));
      expect(t.cols, 5);
      expect(t.rowTexts(0), stmtHeaders);
      // fixture row 7 (table row 8) is the only credit
      expect(t.cell(8, 2).text, '');
      expect(t.cell(8, 3).text, matches(RegExp(r'^[\d,]+\.\d\d$')));
      expect(t.cell(8, 4).text, matches(RegExp(r'^[\d,]+\.\d\d$')));
      for (var r = 1; r < t.rows; r++) {
        if (r != 8) expect(t.cell(r, 3).text, '', reason: 'row $r');
      }
    });

    test('empty cells exist with empty text', () {
      final t = onlyTable(layout(statement(noise: false)));
      expect(t.cells, hasLength(t.rows * t.cols));
      // row 3 (fixture row 2) is a credit: debit cell empty
      expect(t.cell(3, 2).text, '');
      expect(t.cell(3, 3).text, isNotEmpty);
      expect(t.cell(1, 3).text, '');
    });

    test('wrapped multi-line cells, continuation after (default)', () {
      final t = onlyTable(layout(statement(wrapEvery: 3, noise: false)));
      expect(t.rows, 13);
      expect(t.cell(1, 1).text, 'UPI/1000/SHOP NAME CONTINUED 0');
      expect(t.cell(4, 1).text, 'UPI/1003/SHOP XXX NAME CONTINUED 3');
      expect(t.cell(2, 1).text, 'UPI/1001/SHOP X');
    });

    test('wrapped lines spaced like rows (gap > 1 line height) still join their row', () {
      for (final before in [false, true]) {
        final hints = before
            ? TableHints(headerWords: stmtHeaders, rowStart: dateStart, continuation: Continuation.before)
            : null;
        final doc = layout(statement(wrapEvery: 3, before: before, rowPitch: 20, wrapPitch: 20, noise: false), hints: hints);
        final t = onlyTable(doc);
        expect(t.rows, 13, reason: 'before=$before');
        expect(t.cell(1, 1).text, before ? 'NEFT/REF0X UPI/1000/SHOP' : 'UPI/1000/SHOP NAME CONTINUED 0');
        expect(t.cell(4, 1).text, before ? 'NEFT/REF3X UPI/1003/SHOP XXX' : 'UPI/1003/SHOP XXX NAME CONTINUED 3');
      }
    });

    test('negative: a note one blank line below the table stays text, not part of the last row', () {
      final doc = layout(statement(noise: false, extra: const [T(xDesc, 318, 'NOTE BELOW THE TABLE')]));
      expect(onlyTable(doc).rows, 13);
      expect(onlyTable(doc).cells.where((c) => c.text.contains('NOTE')), isEmpty);
      expect(doc.pages.single.blocks.where((b) => b.label == BlockLabel.text).map((b) => b.lines.single.text),
          contains('NOTE BELOW THE TABLE'));
    });

    test('wrapped multi-line cells, continuation before (IDFC style) via hints', () {
      final hints = TableHints(headerWords: stmtHeaders, rowStart: dateStart, continuation: Continuation.before);
      final t = onlyTable(layout(statement(wrapEvery: 3, before: true, noise: false), hints: hints));
      expect(t.rows, 13);
      expect(t.method, TableMethod.headerAnchored);
      expect(t.cell(1, 1).text, 'NEFT/REF0X UPI/1000/SHOP');
      expect(t.cell(4, 1).text, 'NEFT/REF3X UPI/1003/SHOP XXX');
      expect(t.cell(3, 1).text, 'UPI/1002/SHOP XX');
    });

    test('same before-layout read with the default (after) direction mis-joins: the hint matters', () {
      final t = onlyTable(layout(statement(wrapEvery: 3, before: true, noise: false)));
      expect(t.cell(1, 1).text, isNot('NEFT/REF0X UPI/1000/SHOP'));
    });

    test('header-anchored: a stray gap inside descriptions does not add a column', () {
      final texts = [
        const T(50, 100, 'Date'), const T(130, 100, 'Description'), r(400, 100, 'Amount'),
        for (var i = 0; i < 5; i++) ...[
          T(50, 114.0 + 14 * i, '0${i + 1}/06/2026'),
          T(130, 114.0 + 14 * i, 'UPI/$i'),
          T(230, 114.0 + 14 * i, 'MERCHANT'), // second chunk of the description
          r(400, 114.0 + 14 * i, '${i + 1}0.00'),
        ],
      ];
      expect(onlyTable(layout([page(1, texts)])).cols, 4, reason: 'whitespace sees 4 columns');
      final t = onlyTable(layout([page(1, texts)], hints: const TableHints(headerWords: ['Date', 'Description', 'Amount'])));
      expect(t.cols, 3);
      expect(t.cell(1, 1).text, 'UPI/0 MERCHANT');
    });

    test('summary box with two columns is not a table (X-TABLE negative)', () {
      final doc = layout([
        page(1, [
          for (final (i, label) in ['Opening balance', 'Total debits', 'Total credits', 'Closing balance'].indexed) ...[
            T(50, 100.0 + 14 * i, label),
            r(300, 100.0 + 14 * i, '1,000.00'),
          ]
        ])
      ]);
      expect(doc.tables, isEmpty);
    });

    test('section title from hints ends a table and is its own block', () {
      final texts = [
        const T(50, 100, 'Date'), const T(130, 100, 'Description'), r(400, 100, 'Amount'),
        for (var i = 0; i < 3; i++) ...[T(50, 114.0 + 14 * i, '0${i + 1}/06/2026'), T(130, 114.0 + 14 * i, 'DOM $i'), r(400, 114.0 + 14 * i, '1.00')],
        const T(50, 160, 'International Transactions'),
        for (var i = 0; i < 3; i++) ...[T(50, 174.0 + 14 * i, '0${i + 4}/06/2026'), T(130, 174.0 + 14 * i, 'INTL $i'), r(400, 174.0 + 14 * i, '2.00')],
      ];
      final doc = layout([page(1, texts)], hints: const TableHints(sectionTitles: ['International Transactions']));
      final labels = doc.pages.single.blocks.map((b) => b.label).toList();
      expect(labels, [BlockLabel.table, BlockLabel.sectionHeader, BlockLabel.table]);
    });
  });

  group('overlay: stamps and watermarks never enter tables', () {
    final clean = onlyTable(layout(statement(noise: false)));
    List<String> overlays(DsDocument d) =>
        [for (final b in d.pages.first.blocks) if (b.label == BlockLabel.overlay) b.lines.map((l) => l.text).join(' ')];
    for (final (name, extra) in [
      ('rule 1: large DUPLICATE stamp across the table', stamp),
      ('rule 2: slanted watermark across the table', watermark),
      ('rule 3: 1.5x label overprinted on a row baseline', probe),
    ]) {
      test(name, () {
        final doc = layout(statement(noise: false, extra: extra));
        expect(onlyTable(doc).cells.map((c) => c.text), clean.cells.map((c) => c.text));
        expect(overlays(doc), [extra.single.s]);
      });
    }
    test('rule 1 alone: a DUPLICATE stamp below the table (outside any table) is an overlay', () {
      final doc = layout(statement(noise: false, extra: const [T(150, 600, 'DUPLICATE', size: 40)]));
      expect(overlays(doc), ['DUPLICATE']);
    });
    test('overlay words keep provenance and are in page.words', () {
      final doc = layout(statement(noise: false, extra: stamp));
      final block = doc.pages.single.blocks.singleWhere((b) => b.label == BlockLabel.overlay);
      final ids = {for (final w in doc.pages.single.words) w.id};
      expect(block.lines.single.words.single.charIndices, hasLength(9));
      expect(ids.containsAll(block.lines.single.words.map((w) => w.id)), isTrue);
    });
    test('control: a slightly taller (1.15x) header row is not an overlay', () {
      final doc = layout(statement(noise: false, headerSize: 11.5));
      expect(overlays(doc), isEmpty);
      expect(onlyTable(doc).rowTexts(0), ['Date', 'Description', 'Debit', 'Credit', 'Balance']);
    });
    test('negative: a large title above the table stays a text block', () {
      final doc = layout(statement(noise: false, extra: const [T(50, 80, 'ACCOUNT STATEMENT', size: 16)]));
      expect(overlays(doc), isEmpty);
      expect(doc.pages.single.blocks.where((b) => b.label == BlockLabel.text).map((b) => b.lines.first.text),
          contains('ACCOUNT STATEMENT'));
      expect(onlyTable(doc).cells.map((c) => c.text), clean.cells.map((c) => c.text));
    });
  });

  group('multi-page', () {
    test('repeated header per page links tables (continuesFrom + repeatedHeader)', () {
      final tables = layout(statement(pages: 3)).tables.toList();
      expect(tables, hasLength(3));
      expect(tables[0].continuesFrom, isNull);
      expect(tables[1].continuesFrom, tables[0].id);
      expect(tables[1].repeatedHeader, isTrue);
      expect(tables[2].continuesFrom, tables[1].id);
    });

    test('headless continuation links by column positions', () {
      final tables = layout(statement(pages: 3, repeatHeader: false)).tables.toList();
      expect(tables, hasLength(3));
      expect(tables[1].headerRow, isNull);
      expect(tables[1].continuesFrom, tables[0].id);
      expect(tables[2].continuesFrom, tables[1].id);
      expect(tables[1].repeatedHeader, isFalse);
    });

    test('headless page with only 2 rows still links (short continuation)', () {
      final p1 = statement(pages: 1, repeatHeader: false).single;
      final p2 = statement(pages: 2, rowsPerPage: 2, repeatHeader: false)[1];
      final tables = layout([p1, p2]).tables.toList();
      expect(tables, hasLength(2));
      expect(tables[1].continuesFrom, tables[0].id);
    });

    test('headless table whose columns moved by 3 pitches does not link', () {
      final tables = layout(statement(pages: 2, repeatHeader: false, headlessShift: 3 * adv)).tables.toList();
      expect(tables[1].continuesFrom, isNull);
    });

    test('headless table starting low on the page does not link', () {
      final p1 = statement(pages: 1, noise: false).single;
      final low = [
        for (var i = 0; i < 4; i++) ...[
          T(xDate, 500.0 + 14 * i, '0${i + 1}/07/2026'),
          T(xDesc, 500.0 + 14 * i, 'UPI/LOW$i'),
          r(rDebit, 500.0 + 14 * i, '9.00'),
          r(rBal, 500.0 + 14 * i, '99.00'),
        ]
      ];
      final tables = layout([p1, page(2, low)]).tables.toList();
      expect(tables, hasLength(2));
      expect(tables[1].continuesFrom, isNull);
    });

    test('tight columns (long credit 8 pt from the balance) do not split the table; 15 pages chain', () {
      final tables = layout(statement(pages: 15, rowsPerPage: 40, wrapEvery: 4)).tables.toList();
      expect(tables, hasLength(15));
      for (var i = 1; i < 15; i++) {
        expect(tables[i].continuesFrom, tables[i - 1].id);
        expect(tables[i].rows, 41);
      }
    });

    test('X-HDRFTR negative: table rows reaching the bottom band stay table rows', () {
      final doc = layout(statement(pages: 3, rowsPerPage: 40, wrapEvery: 4));
      for (final p in doc.pages) {
        expect(p.tables.single.rows, 41, reason: 'page ${p.number}');
        final furniture = p.blocks.where((b) => b.label == BlockLabel.pageFooter).map((b) => b.lines.single.text);
        expect(furniture, ['Page ${p.number} of 3']);
      }
    });

    test('A-C12: repeated header/footer noise is labelled and produces no table rows', () {
      final doc = layout(statement(pages: 3));
      for (final p in doc.pages) {
        final labels = p.blocks.map((b) => b.label).toList();
        expect(labels.first, BlockLabel.pageHeader);
        expect(labels.last, BlockLabel.pageFooter);
        final t = p.tables.single;
        for (final c in t.cells) {
          expect(c.text, isNot(contains('Page')));
          expect(c.text, isNot(contains('STATEMENT')));
        }
      }
    });
  });

  group('reading order and provenance', () {
    test('blocks: page header, body top-to-bottom, page footer; word ids follow it', () {
      final p = layout(statement(pages: 2)).pages.first;
      final tops = [for (final b in p.blocks.skip(1).take(p.blocks.length - 2)) b.box.top];
      expect(tops, [...tops]..sort());
      final ids = [for (final b in p.blocks) for (final l in b.lines) for (final w in l.words) w.id];
      expect(ids, [for (final w in p.words) w.id]);
    });

    test('cell -> words -> char indices reproduce the cell text', () {
      final input = statement(wrapEvery: 3, noise: false);
      final doc = layout(input);
      final chars = {for (final c in input.single.chars) c.index: c.text};
      final words = {for (final w in doc.pages.single.words) w.id: w};
      for (final c in onlyTable(doc).cells) {
        final rebuilt = c.wordIds.map((id) => words[id]!.charIndices.map((i) => chars[i]).join()).join(' ');
        expect(rebuilt, c.text);
      }
    });
  });
}
