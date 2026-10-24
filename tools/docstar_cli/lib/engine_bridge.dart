// Bridge from the core layout to the statement engine's input (the adapter that
// packages/docstar_engine/lib/src/extract.dart leaves open). Temporary, CLI-only.
//
// What the engine needs and what the core gives us:
//   text, x0, x1, top, bottom  -> from the core word box (exact)
//   size                       -> word box height. ponytail: a proxy for font size; the
//                                 reader exposes no font size. The engine only uses it for
//                                 gap thresholds, so this moves word joins, not amounts.
//   bold                       -> false. ponytail: no font weight from the reader, so title
//                                 and bold-header rules never fire.
//   hrules                     -> none. ponytail: pdfrx exposes no path objects, so ruled
//                                 tables are read as whitespace tables.
import 'package:docstar_core/docstar_core.dart' as core;
import 'package:docstar_engine/docstar_engine.dart';

/// [path] becomes the engine's `file` field, so pass a label, never the real file name.
Document documentFromCore(core.DsDocument laid, {String path = ''}) {
  final pages = [
    for (final p in laid.pages)
      Page(p.number, p.width, p.height, [
        for (final w in p.words) Word(w.text, w.box.left, w.box.right, w.box.top, w.box.bottom, w.box.bottom - w.box.top, false),
      ], const []),
  ];
  return makeDocument(pages, path: path);
}
