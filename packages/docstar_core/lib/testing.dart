/// Synthetic fixtures for tests and benchmarks (not for production use).
/// Generated char streams with known geometry. They mimic what PDFium
// gives (probe 2026-10-23): tight glyph boxes on a Courier-like 6 pt advance,
// narrow boxes for , and ., real spaces with width, and a zero-width generated
// space after every separately placed text run. No real data.
library;

import 'docstar_core.dart';

const adv = 6.0;

/// Text whose baseline starts at (x, y) in the upright (reading) frame.
class T {
  final double x, y;
  final String s;
  const T(this.x, this.y, this.s);
}

/// Right-aligned text ending at [right].
T r(double right, double y, String s) => T(right - s.length * adv, y, s);

Box _glyph(String c, double x, double y) => switch (c) {
      ',' || '.' => Box(x + 2, y - 2, x + 4, y + 1),
      ' ' => Box(x, y, x + adv, y),
      _ => Box(x + 0.5, y - 7, x + 5.5, y),
    };

/// One page. [turn] rotates the text in the display frame (0/90/180/270), as a
/// sideways-scanned or landscape page would arrive from the reader.
PageInput page(int number, List<T> texts, {double w = 595, double h = 842, int turn = 0}) {
  final chars = <CharCell>[];
  for (final t in texts) {
    for (var i = 0; i < t.s.length; i++) {
      chars.add(CharCell(chars.length, t.s[i], _glyph(t.s[i], t.x + i * adv, t.y)));
    }
    final end = t.x + t.s.length * adv;
    chars.add(CharCell(chars.length, ' ', Box(end, t.y, end, t.y))); // generated space
  }
  if (turn == 0) return PageInput(number, w, h, chars);
  final dw = turn == 180 ? w : h, dh = turn == 180 ? h : w; // displayed size
  final shown = DsPage(number, dw, dh, 0, turn, const [], const [], const []);
  return PageInput(number, dw, dh, [for (final c in chars) CharCell(c.index, c.text, shown.toDisplay(c.box))]);
}

/// Column right edges / left edges of the statement fixture.
const xDate = 50.0, xDesc = 130.0, rDebit = 400.0, rCredit = 480.0, rBal = 560.0;

String amount(int paise) {
  final s = (paise ~/ 100).toString();
  // Indian grouping: last 3 digits, then groups of 2.
  final head = s.length > 3 ? s.substring(0, s.length - 3) : '';
  final tail = s.length > 3 ? s.substring(s.length - 3) : s;
  final groups = <String>[];
  for (var i = head.length; i > 0; i -= 2) {
    groups.insert(0, head.substring(i - 2 < 0 ? 0 : i - 2, i));
  }
  final rupees = [...groups, tail].join(',');
  return '$rupees.${(paise % 100).toString().padLeft(2, '0')}';
}

/// A statement-like document: page header + footer noise, a 5-column table
/// (Date | Description | Debit | Credit | Balance) with right-aligned amounts,
/// empty cells, ragged descriptions and optional wrapped description lines.
/// [wrapEvery]: every n-th row gets a second description line ([before] puts it
/// above the date line, IDFC First style). [repeatHeader]: header on every page,
/// else only on page 1 (later pages are headless continuations).
List<PageInput> statement({
  int pages = 1,
  int rowsPerPage = 12,
  bool repeatHeader = true,
  int wrapEvery = 0,
  bool before = false,
  bool noise = true,
  int turn = 0,
  double headlessShift = 0,
}) {
  final out = <PageInput>[];
  var row = 0;
  var balance = 10000000;
  for (var p = 1; p <= pages; p++) {
    final texts = <T>[];
    if (noise) {
      texts.add(const T(50, 40, 'DOCSTAR TEST BANK - ACCOUNT STATEMENT'));
      texts.add(T(50, 820, 'Page $p of $pages'));
    }
    var y = 120.0;
    final shift = p > 1 ? headlessShift : 0.0;
    if (p == 1 || repeatHeader) {
      texts.addAll([
        const T(xDate, 120, 'Date'),
        const T(xDesc, 120, 'Description'),
        r(rDebit, 120, 'Debit'),
        r(rCredit, 120, 'Credit'),
        r(rBal, 120, 'Balance'),
      ]);
      y = 134;
    } else {
      y = 100;
    }
    for (var i = 0; i < rowsPerPage; i++, row++) {
      final wrapped = wrapEvery > 0 && row % wrapEvery == 0;
      if (wrapped && before) {
        texts.add(T(xDesc + shift, y, 'NEFT/REF${row}X'));
        y += 12;
      }
      final debit = row % 3 != 2;
      final amt = 1000 + (row * 7919) % 12345678; // ragged lengths
      balance += debit ? -amt : amt;
      texts.add(T(xDate + shift, y, '${(row % 28 + 1).toString().padLeft(2, '0')}/06/2026'));
      texts.add(T(xDesc + shift, y, 'UPI/${1000 + row}/SHOP ${'X' * (row % 7)}'));
      if (debit) {
        texts.add(r(rDebit + shift, y, amount(amt)));
      } else {
        texts.add(r(rCredit + shift, y, amount(amt)));
      }
      texts.add(r(rBal + shift, y, amount(balance.abs())));
      if (wrapped && !before) {
        y += 12;
        texts.add(T(xDesc + shift, y, 'NAME CONTINUED $row'));
      }
      y += 14;
    }
    out.add(page(p, texts, turn: turn));
  }
  return out;
}

/// Everything except geometry-frame fields, for rotation comparisons.
Object? structure(DsDocument d) {
  Object? strip(Object? v) => switch (v) {
        Map m => {
            for (final e in m.entries)
              if (!const {'width', 'height', 'readingRotation', 'rotation'}.contains(e.key)) e.key: strip(e.value)
          },
        List l => [for (final x in l) strip(x)],
        _ => v,
      };
  return strip(d.toJson());
}

/// The non-gating layout benchmark (15-page statement-like document); returns one summary line.
String layoutBench({int runs = 20}) {
  final pages = statement(pages: 15, rowsPerPage: 40, wrapEvery: 4);
  final chars = pages.fold<int>(0, (n, p) => n + p.chars.length);
  for (var i = 0; i < 5; i++) {
    layout(pages);
  }
  final ms = <double>[];
  late DsDocument doc;
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    doc = layout(pages);
    ms.add(sw.elapsedMicroseconds / 1000);
  }
  ms.sort();
  final rows = doc.tables.fold<int>(0, (n, t) => n + t.rows);
  return 'layout_bench pages=15 chars=$chars tables=${doc.tables.length} rows=$rows runs=$runs '
      'median_ms=${ms[(runs - 1) ~/ 2].toStringAsFixed(1)} min_ms=${ms.first.toStringAsFixed(1)} '
      'max_ms=${ms.last.toStringAsFixed(1)}';
}
