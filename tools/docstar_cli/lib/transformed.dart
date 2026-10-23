// transformed.json (written with --visual only): every table as header + rows of
// cell text, page by page, to check against the overlay PNGs. Contains document
// text, so it lives next to the PNGs, never in metrics.json.
import 'package:docstar_core/docstar_core.dart';

Map<String, Object?> transformed(DsDocument doc) => {
      'pages': doc.pages.length,
      'tables': [
        for (final p in doc.pages)
          for (final t in p.tables)
            {
              'page': p.number,
              'id': t.id,
              'continues_from': t.continuesFrom,
              'columns': t.cols,
              'header': t.headerRow == null ? null : t.rowTexts(t.headerRow!),
              'rows': [
                for (var r = 0; r < t.rows; r++)
                  if (r != t.headerRow) t.rowTexts(r)
              ],
            }
      ],
    };
