// --visual: one PNG per page, the rendered page with DocStar's layout drawn on top.
// Output contains document content: keep it local (the CLI refuses --out inside git).
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
};

/// Writes `page_<n>.png` for every page into [dir]; returns the paths.
Future<List<String>> drawOverlays(PdfDocument pdf, DsDocument doc, String dir) async {
  Directory(dir).createSync(recursive: true);
  final out = <String>[];
  for (final page in doc.pages) {
    final pdfPage = pdf.pages[page.number - 1];
    final w = (pdfPage.width * scale).round(), h = (pdfPage.height * scale).round();
    final im = await pdfPage.render(
        width: w, height: h, fullWidth: w.toDouble(), fullHeight: h.toDouble(), backgroundColor: 0xffffffff);
    if (im == null) continue;
    try {
      final canvas = im.createImageNF();
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

      for (final w in page.words) {
        box(w.box, 'words');
      }
      for (final l in page.lines) {
        box(l.box, 'lines', pad: 1);
      }
      for (final b in page.blocks) {
        final furniture = b.label == BlockLabel.pageHeader || b.label == BlockLabel.pageFooter;
        box(b.box, furniture ? 'header/footer' : 'blocks', pad: 3, px: 2);
        if (b.table != null) _grid(b.table!, (r) => box(r, 'table grid', pad: 2, px: 2));
      }
      _legend(canvas);
      final path = '$dir/page_${page.number}.png';
      File(path).writeAsBytesSync(img.encodePng(canvas));
      out.add(path);
    } finally {
      im.dispose();
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

void _legend(img.Image canvas) {
  final width = colors.keys.fold<int>(8, (w, k) => w + 28 + 8 * k.length);
  img.fillRect(canvas, x1: 4, y1: 4, x2: width, y2: 26, color: img.ColorRgba8(255, 255, 255, 230));
  var x = 8;
  for (final e in colors.entries) {
    img.fillRect(canvas, x1: x, y1: 9, x2: x + 12, y2: 21, color: e.value);
    img.drawString(canvas, e.key, font: img.arial14, x: x + 16, y: 8, color: img.ColorRgba8(0, 0, 0, 255));
    x += 28 + 8 * e.key.length;
  }
}
