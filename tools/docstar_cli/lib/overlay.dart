// --visual: one PNG per page, the rendered page with DocStar's layout drawn on top.
// Output contains document content: keep it local (the CLI refuses --out inside git).
// --redact: the same overlays on a BLANK canvas, every word a solid black bar. No
// pixel comes from the PDF (logos, signatures, QR codes, text drawn as paths can't
// leak); only geometry remains (word positions and lengths, table shape).
import 'dart:io';

import 'package:docstar_core/docstar_core.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

const scale = 2.0;

/// Overlay colours, also printed as the legend on every page.
final colors = <String, img.ColorRgba8>{
  'words': img.ColorRgba8(30, 110, 255, 255), // blue, 1 px
  'lines': img.ColorRgba8(0, 170, 70, 255), // green, 1 px, 1 pt outside
  'blocks': img.ColorRgba8(255, 140, 0, 255), // orange, 2 px, 3 pt outside
  'header/footer': img.ColorRgba8(160, 60, 200, 255), // purple: page furniture blocks
  'table grid': img.ColorRgba8(230, 0, 40, 255), // red, 2 px, 2 pt outside: one rectangle per cell
  'overlay': img.ColorRgba8(128, 128, 128, 255), // grey: stamp/watermark blocks
};

final white = img.ColorRgba8(255, 255, 255, 255), black = img.ColorRgba8(0, 0, 0, 255);

/// Writes `page_<n>.png` for every page into [dir]; returns the paths.
/// [redact]: blank canvas, words as black bars (nothing rendered from [pdf]).
Future<List<String>> drawOverlays(PdfDocument pdf, DsDocument doc, String dir, {bool redact = false}) async {
  Directory(dir).createSync(recursive: true);
  final out = <String>[];
  for (final page in doc.pages) {
    final w = (page.width * scale).round(), h = (page.height * scale).round();
    final im = redact
        ? null
        : await pdf.pages[page.number - 1].render(
            width: w, height: h, fullWidth: w.toDouble(), fullHeight: h.toDouble(), backgroundColor: 0xffffffff);
    if (!redact && im == null) continue;
    try {
      final canvas = im?.createImageNF() ?? img.fill(img.Image(width: w, height: h), color: white);
      void box(Box reading, String kind, {double pad = 0, int px = 1}) {
        final b = page.toDisplay(reading);
        img.drawRect(canvas,
            x1: ((b.left - pad) * scale).round(),
            y1: ((b.top - pad) * scale).round(),
            x2: ((b.right + pad) * scale).round(),
            y2: ((b.bottom + pad) * scale).round(),
            color: colors[kind]!,
            thickness: px);
      }

      if (!redact) {
        for (final w in page.words) {
          box(w.box, 'words');
        }
      }
      for (final l in page.lines) {
        box(l.box, 'lines', pad: 1);
      }
      for (final b in page.blocks) {
        final kind = switch (b.label) {
          BlockLabel.pageHeader || BlockLabel.pageFooter => 'header/footer',
          BlockLabel.overlay => 'overlay',
          _ => 'blocks',
        };
        box(b.box, kind, pad: 3, px: 2);
        if (b.table != null) _grid(b.table!, (r) => box(r, 'table grid', pad: 2, px: 2));
      }
      if (redact) {
        // Last, so no outline is drawn over a word: every word area is solid black.
        for (final word in page.words) {
          final b = page.toDisplay(word.box);
          img.fillRect(canvas,
              x1: (b.left * scale).floor(),
              y1: (b.top * scale).floor(),
              x2: (b.right * scale).ceil(),
              y2: (b.bottom * scale).ceil(),
              color: black);
        }
      }
      _legend(canvas, redact);
      final path = '$dir/page_${page.number}.png';
      File(path).writeAsBytesSync(img.encodePng(canvas));
      out.add(path);
    } finally {
      im?.dispose();
    }
  }
  return out;
}

/// A regular grid: column x-extent and row y-extent over all of that column's / row's cells.
void _grid(Table t, void Function(Box) draw) {
  for (var r = 0; r < t.rows; r++) {
    final row = [for (var c = 0; c < t.cols; c++) t.cell(r, c).box];
    final top = row.map((b) => b.top).reduce((a, b) => a < b ? a : b);
    final bottom = row.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);
    for (var c = 0; c < t.cols; c++) {
      final col = [for (var k = 0; k < t.rows; k++) t.cell(k, c).box];
      final left = col.map((b) => b.left).reduce((a, b) => a < b ? a : b);
      final right = col.map((b) => b.right).reduce((a, b) => a > b ? a : b);
      draw(Box(left, top, right, bottom));
    }
  }
}

void _legend(img.Image canvas, bool redact) {
  final entries = {
    if (redact) 'words (redacted)': black,
    for (final e in colors.entries)
      if (!redact || e.key != 'words') e.key: e.value,
  };
  final width = entries.keys.fold<int>(8, (w, k) => w + 28 + 8 * k.length);
  img.fillRect(canvas, x1: 4, y1: 4, x2: width, y2: 26, color: img.ColorRgba8(255, 255, 255, 230));
  var x = 8;
  for (final e in entries.entries) {
    img.fillRect(canvas, x1: x, y1: 9, x2: x + 12, y2: 21, color: e.value);
    img.drawString(canvas, e.key, font: img.arial14, x: x + 16, y: 8, color: img.ColorRgba8(0, 0, 0, 255));
    x += 28 + 8 * e.key.length;
  }
}
