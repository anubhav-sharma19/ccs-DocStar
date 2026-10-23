import 'dart:io';

import 'package:docstar_cli/overlay.dart';
import 'package:docstar_core/docstar_core.dart';
import 'package:docstar_pdfium/docstar_pdfium.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

import '../../../packages/docstar_pdfium/test/pdf_writer.dart';

List<FakeText> stmt() {
  FakeText r(double right, double y, String s) => FakeText(right - s.length * 6, y, s);
  return [
    const FakeText(50, 30, 'DOCSTAR TEST BANK'),
    const FakeText(50, 120, 'Date'), const FakeText(130, 120, 'Description'), r(400, 120, 'Amount'), r(500, 120, 'Balance'),
    for (var i = 0; i < 6; i++) ...[
      FakeText(50, 134.0 + 14 * i, '0${i + 1}/06/2026'),
      FakeText(130, 134.0 + 14 * i, 'UPI/${1000 + i}/SHOP'),
      r(400, 134.0 + 14 * i, '1,23,456.78'),
      r(500, 134.0 + 14 * i, '${i + 1},000.00'),
    ],
    const FakeText(50, 300, 'Closing note for the period.'),
    const FakeText(50, 812, 'Page footer'),
  ];
}

/// Pixels of exactly this colour inside [b] (display points), at the overlay scale.
int count(img.Image im, img.ColorRgba8 c, [Box? b]) {
  var n = 0;
  final x0 = b == null ? 0 : (b.left * scale).floor() - 4, x1 = b == null ? im.width : (b.right * scale).ceil() + 4;
  final y0 = b == null ? 0 : (b.top * scale).floor() - 4, y1 = b == null ? im.height : (b.bottom * scale).ceil() + 4;
  for (var y = y0.clamp(0, im.height); y < y1.clamp(0, im.height); y++) {
    for (var x = x0.clamp(0, im.width); x < x1.clamp(0, im.width); x++) {
      final p = im.getPixel(x, y);
      if (p.r == c.r && p.g == c.g && p.b == c.b) n++;
    }
  }
  return n;
}

void main() {
  setUpAll(() async => pdfrxInitialize());

  for (final (name, page) in [
    ('upright', FakePage(stmt())),
    ('sideways /Rotate 90', FakePage(stmt(), rotate: 90, upright: false)),
  ]) {
    test('$name: one PNG per page, every overlay colour present, word boxes on the words', () async {
      final pdf = await PdfDocument.openData(buildPdf([page, page]));
      final doc = layout((await pagesOf(pdf))!);
      final dir = Directory.systemTemp.createTempSync('docstar_overlay_');
      try {
        final files = await drawOverlays(pdf, doc, dir.path);
        expect(files, hasLength(2));
        final im = img.decodePng(File(files.first).readAsBytesSync())!;
        for (final e in colors.entries) {
          expect(count(im, e.value), greaterThan(0), reason: e.key);
        }
        final p = doc.pages.first;
        final amount = p.words.firstWhere((w) => w.text == '1,23,456.78');
        expect(count(im, colors['words']!, p.toDisplay(amount.box)), greaterThan(20), reason: 'word box drawn at the word');
      } finally {
        dir.deleteSync(recursive: true);
        await pdf.dispose();
      }
    });
  }
}
