// Synthetic only, no PDFium (PDFium tests stay in overlay_test.dart).
import 'dart:convert';

import 'package:docstar_cli/transformed.dart';
import 'package:docstar_core/docstar_core.dart';
import 'package:docstar_core/testing.dart';
import 'package:test/test.dart';

void main() {
  test('transformed.json: tables per page, header + rows, empty cells null, page links', () {
    final out = transformed(layout(statement(pages: 2, wrapEvery: 3)));
    final tables = out['tables'] as List;
    expect(out['pages'], 2);
    expect(tables, hasLength(2));
    final first = tables[0] as Map, second = tables[1] as Map;
    expect(first['page'], 1);
    expect(first['header'], ['Date', 'Description', 'Debit', 'Credit', 'Balance']);
    expect((first['rows'] as List), hasLength(12));
    expect((first['rows'] as List).first, ['01/06/2026', 'UPI/1000/SHOP NAME CONTINUED 0', '10.00', null, '99,990.00']);
    expect(second['continues_from'], first['id']);
    expect(() => jsonEncode(out), returnsNormally);
  });

  test('logical_tables: one chain, every row the same length, credit stays at index 3', () {
    // Page 1: no header, no credits. Page 2: headless, credits every other row.
    final p1 = statement(pages: 1, firstHeader: false, creditEvery: 1000).single;
    final p2 = statement(pages: 2, rowsPerPage: 6, repeatHeader: false, creditEvery: 2)[1];
    final logical = (transformed(layout([p1, p2]))['logical_tables'] as List).single as Map;
    expect(logical['pages'], [1, 2]);
    expect(logical['same_columns'], isTrue);
    final rows = (logical['rows'] as List).cast<List>();
    expect(rows, hasLength(18));
    expect(rows.map((r) => r.length).toSet(), {5});
    final amount = RegExp(r'^[\d,]+\.\d\d$');
    for (final r in rows) {
      expect(r[2] == null || amount.hasMatch(r[2] as String), isTrue);
      expect(r[3] == null || amount.hasMatch(r[3] as String), isTrue);
      expect(amount.hasMatch(r[4] as String), isTrue, reason: 'balance always at index 4: $r');
    }
    expect(rows.take(12).map((r) => r[3]), everyElement(isNull), reason: 'page 1 has no credits');
    expect(rows.skip(12).where((r) => r[3] != null), hasLength(3));
  });
}
