// Synthetic only, no PDFium (PDFium tests stay in overlay_test.dart).
import 'dart:convert';

import 'package:docstar_cli/transformed.dart';
import 'package:docstar_core/docstar_core.dart';
import 'package:docstar_core/testing.dart';
import 'package:test/test.dart';

void main() {
  test('transformed.json: tables per page, header + rows of cell text, page links', () {
    final out = transformed(layout(statement(pages: 2, wrapEvery: 3)));
    final tables = out['tables'] as List;
    expect(out['pages'], 2);
    expect(tables, hasLength(2));
    final first = tables[0] as Map, second = tables[1] as Map;
    expect(first['page'], 1);
    expect(first['header'], ['Date', 'Description', 'Debit', 'Credit', 'Balance']);
    expect((first['rows'] as List), hasLength(12));
    expect((first['rows'] as List).first, ['01/06/2026', 'UPI/1000/SHOP NAME CONTINUED 0', '10.00', '', '99,990.00']);
    expect(second['continues_from'], first['id']);
    expect(() => jsonEncode(out), returnsNormally);
  });
}
