// transformed.json (written with --visual only): every table as header + rows of
// cell text, page by page, to check against the overlay PNGs; plus logical_tables,
// each chain of linked tables (one table continuing over pages) as one list of rows
// with stable column positions. Empty cells are null. Contains document text, so it
// lives next to the PNGs, never in metrics.json.
import 'package:docstar_core/docstar_core.dart';

List<String?> _row(Table t, int r) => [for (final c in t.rowTexts(r)) c.isEmpty ? null : c];

List<List<String?>> _rows(Table t) => [
      for (var r = 0; r < t.rows; r++)
        if (r != t.headerRow) _row(t, r)
    ];

Map<String, Object?> transformed(DsDocument doc) {
  final pageOf = {for (final p in doc.pages) for (final t in p.tables) t.id: p.number};
  final chains = <List<Table>>[];
  final chainOf = <String, List<Table>>{};
  for (final t in doc.tables) {
    final chain = chainOf[t.continuesFrom] ?? (chains..add([])).last;
    chain.add(t);
    chainOf[t.id] = chain;
  }
  return {
    'pages': doc.pages.length,
    'tables': [
      for (final t in doc.tables)
        {
          'page': pageOf[t.id],
          'id': t.id,
          'continues_from': t.continuesFrom,
          'columns': t.cols,
          'header': t.headerRow == null ? null : _row(t, t.headerRow!),
          'rows': _rows(t),
        }
    ],
    'logical_tables': [
      for (final chain in chains)
        {
          'pages': [for (final t in chain) pageOf[t.id]],
          'tables': [for (final t in chain) t.id],
          'columns': chain.first.cols,
          'same_columns': chain.every((t) => t.cols == chain.first.cols),
          'header': [for (final t in chain) if (t.headerRow != null) _row(t, t.headerRow!)].firstOrNull,
          'rows': [for (final t in chain) ..._rows(t)],
        }
    ],
  };
}
