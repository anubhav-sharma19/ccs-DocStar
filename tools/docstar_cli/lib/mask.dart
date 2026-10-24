// mask.json (written with --mask <pages>): word geometry with the text masked (letters -> X, digits -> 9,
// punctuation kept), plus what the layout made of each page's tables. Safe to share: no real text.
import 'package:docstar_core/docstar_core.dart';

String _mask(String s) => s.replaceAll(RegExp(r'\p{L}', unicode: true), 'X').replaceAll(RegExp(r'\p{N}', unicode: true), '9');

double _r(double v) => (v * 10).round() / 10;

Map<String, Object?> maskDump(DsDocument doc, Set<int> pages) => {
      'pages': [
        for (final p in doc.pages)
          if (pages.contains(p.number))
            {
              'page': p.number,
              'width': _r(p.width),
              'height': _r(p.height),
              'tables': [
                for (final t in p.tables)
                  {'id': t.id, 'continues_from': t.continuesFrom, 'continues_row': t.continuesRow, 'cols': t.cols, 'rows': t.rows}
              ],
              // [x0, x1, top, bottom, masked text]
              'words': [for (final w in p.words) [_r(w.box.left), _r(w.box.right), _r(w.box.top), _r(w.box.bottom), _mask(w.text)]],
            }
      ],
    };

/// Keys whose string values carry statement content; everything else (roles, flags, pages, counts) stays.
const _content = {
  'description', 'reference', 'text', 'debit', 'credit', 'amount', 'balance', 'account_last4', 'file', 'name', 'opening',
  'closing', 'computed_closing', 'credits', 'debits', 'value_date', 'date', 'from', 'to',
};

/// A copy of the engine JSON with content strings masked (letters -> X, digits -> 9, punctuation kept), safe to share.
Object? maskEngine(Object? v, [String? key, bool all = false]) => switch (v) {
      Map m => {for (final e in m.entries) e.key: maskEngine(e.value, e.key as String, all || e.key == 'extra')},
      List l => [for (final x in l) maskEngine(x, key, all)],
      String s when all || (key != null && _content.contains(key)) => _mask(s),
      _ => v,
    };
