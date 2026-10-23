// Keep every PDFium test in this one file: `dart test` runs files in parallel
// isolates, and loading PDFium from two at once crashes the VM.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:docstar_core/docstar_core.dart';
import 'package:docstar_pdfium/docstar_pdfium.dart';
import 'package:test/test.dart';

import 'pdf_writer.dart';

const password = 'Test1234'; // fake, fixture only
final locked = File('test/fixtures/locked_1p.pdf').readAsBytesSync();

/// A small statement-like page in display coordinates (Courier 10, 6 pt advance).
List<FakeText> stmt({bool header = true, double headerSize = 10, bool bold = false}) {
  FakeText r(double right, double y, String s) => FakeText(right - s.length * 6, y, s);
  return [
    if (header) ...[
      FakeText(50, 120, 'Date', size: headerSize, bold: bold),
      FakeText(130, 120, 'Description', size: headerSize, bold: bold),
      FakeText(400 - 6 * 0.6 * headerSize, 120, 'Amount', size: headerSize, bold: bold),
      FakeText(500 - 7 * 0.6 * headerSize, 120, 'Balance', size: headerSize, bold: bold),
    ],
    for (var i = 0; i < 6; i++) ...[
      FakeText(50, 134.0 + 14 * i, '0${i + 1}/06/2026'),
      FakeText(130, 134.0 + 14 * i, 'UPI/${1000 + i}/SHOP ${'X' * i}'),
      r(400, 134.0 + 14 * i, i.isEven ? '1,23,456.78' : '9.50'),
      r(500, 134.0 + 14 * i, '${i + 1},000.00'),
    ],
  ];
}

Future<DsDocument> read(Uint8List bytes, {PasswordProvider? passwords, TableHints? hints}) async {
  final r = await readPdf(bytes, passwords: passwords);
  expect(r, isA<ReadOk>());
  return layout((r as ReadOk).pages, hints: hints);
}

/// Model minus frame fields. Also minus char indices: PDFium orders its char
/// stream differently on an upside-down page (probe: /Rotate 180 sideways starts
/// at the last column), so stream positions are provenance, not structure.
Object? structure(DsDocument d) {
  Object? strip(Object? v) => switch (v) {
        Map m => {
            for (final e in m.entries)
              if (!const {'width', 'height', 'readingRotation', 'rotation', 'box', 'chars'}.contains(e.key))
                e.key: strip(e.value)
          },
        List l => [for (final x in l) strip(x)],
        _ => v,
      };
  return strip(d.toJson());
}

void main() {
  setUpAll(() async => initDocstarPdfium());

  test('A-C1: unlocked PDF -> every page has char boxes inside the page', () async {
    final r = await readPdf(buildPdf([FakePage(stmt()), FakePage(stmt(header: false))]));
    final pages = (r as ReadOk).pages;
    expect(pages, hasLength(2));
    for (final p in pages) {
      final glyphs = p.chars.where((c) => !c.isSpace).toList();
      expect(glyphs, isNotEmpty);
      for (final c in glyphs) {
        expect(c.box.left >= 0 && c.box.right <= p.width && c.box.top >= 0 && c.box.bottom <= p.height, isTrue);
        expect(c.box.width > 0 && c.box.height > 0, isTrue);
      }
    }
  });

  test('end to end: generated PDF -> 4-column table, amounts intact, pages linked', () async {
    final doc = await read(buildPdf([FakePage(stmt()), FakePage(stmt())]));
    final t = doc.tables.toList();
    expect(t, hasLength(2));
    expect(t[0].cols, 4);
    expect(t[0].rowTexts(0), ['Date', 'Description', 'Amount', 'Balance']);
    expect(t[0].rowTexts(1), ['01/06/2026', 'UPI/1000/SHOP', '1,23,456.78', '1,000.00']);
    expect(t[0].cell(6, 1).text, 'UPI/1005/SHOP XXXXX');
    expect(t[1].continuesFrom, t[0].id);
    expect(t[1].repeatedHeader, isTrue);
  });

  group('A-C8 rotation through PDFium', () {
    late Object? upright;
    setUpAll(() async => upright = structure(await read(buildPdf([FakePage(stmt())]))));
    for (final rot in [90, 180, 270]) {
      test('/Rotate $rot, text upright when shown -> same structure', () async {
        final doc = await read(buildPdf([FakePage(stmt(), rotate: rot)]));
        expect(doc.pages.single.rotation, rot);
        expect(doc.pages.single.readingRotation, 0);
        expect(structure(doc), upright);
      });
      test('/Rotate $rot, text sideways when shown -> same structure', () async {
        final doc = await read(buildPdf([FakePage(stmt(), rotate: rot, upright: false)]));
        expect(doc.pages.single.readingRotation, isNot(0));
        expect(structure(doc), upright);
      });
    }
  });

  group('password flow', () {
    test('A-C2/A-C4: locked -> provider asked once -> right password opens', () async {
      final asked = <int>[];
      final doc = await read(locked, passwords: (a) async {
        asked.add(a);
        return password;
      });
      expect(asked, [0]);
      expect(doc.pages.single.words, isNotEmpty);
    });

    test('A-C3: wrong then right -> asked again with attempt 1', () async {
      final asked = <int>[];
      await read(locked, passwords: (a) async {
        asked.add(a);
        return a == 0 ? 'wrong' : password;
      });
      expect(asked, [0, 1]);
    });

    test('A-C3: wrong then cancel -> cancelled; result carries no password', () async {
      final r = await readPdf(locked, passwords: (a) async => a == 0 ? 'wrong-secret' : null);
      expect(r, isA<ReadFailed>().having((f) => f.reason, 'reason', ReadFailure.cancelled));
      expect('$r', isNot(contains('wrong-secret')));
    });

    test('no provider on a locked file -> cancelled, no crash', () async {
      final r = await readPdf(locked);
      expect(r, isA<ReadFailed>().having((f) => f.reason, 'reason', ReadFailure.cancelled));
    });

    test('unlocked file never asks', () async {
      var asked = 0;
      await read(buildPdf([FakePage(stmt())]), passwords: (_) async {
        asked++;
        return null;
      });
      expect(asked, 0);
    });

    test('A-C5: remembered password is tried first; on failure the user is asked', () async {
      // App-side pattern: a saved password answers attempt 0, the user answers later attempts.
      PasswordProvider remembered(String saved, PasswordProvider ask) =>
          (a) async => a == 0 ? saved : ask(a - 1);
      var prompts = 0;
      Future<String?> user(int _) async {
        prompts++;
        return password;
      }

      await read(locked, passwords: remembered(password, user));
      expect(prompts, 0, reason: 'saved password worked, no prompt');
      await read(locked, passwords: remembered('stale', user));
      expect(prompts, 1, reason: 'saved password failed, user prompted');
    });
  });

  test('A-C6: image-only (scanned) PDF -> noTextLayer', () async {
    final r = await readPdf(buildPdf([const FakePage([], image: true)]));
    expect(r, isA<ReadFailed>().having((f) => f.reason, 'reason', ReadFailure.noTextLayer));
  });

  test('not a PDF -> corrupt', () async {
    final r = await readPdf(Uint8List.fromList(utf8.encode('this is not a pdf')));
    expect(r, isA<ReadFailed>().having((f) => f.reason, 'reason', ReadFailure.corrupt));
  });

  test('A-C7: same bytes -> identical canonical JSON', () async {
    final bytes = buildPdf([FakePage(stmt()), FakePage(stmt(), rotate: 90, upright: false)]);
    final a = (await read(bytes)).toCanonicalJson();
    expect((await read(bytes)).toCanonicalJson(), a);
  });

  group('overlay (stamps, watermarks) through PDFium', () {
    List<String> overlays(DsDocument d) => [
          for (final p in d.pages)
            for (final b in p.blocks)
              if (b.label == BlockLabel.overlay) b.lines.map((l) => l.text).join(' ')
        ];
    List<String> cellTexts(DsDocument d) => [for (final t in d.tables) for (final c in t.cells) c.text];
    Future<DsDocument> spike(String name) async => read(File('test/fixtures/$name.pdf').readAsBytesSync());

    test('spike plain_1p.pdf: exactly 1 table; PROBE-ALPHA/BETA are overlays, no PROBE in any cell', () async {
      final doc = await spike('plain_1p');
      expect(doc.tables, hasLength(1));
      expect(overlays(doc), ['PROBE-ALPHA', 'PROBE-BETA']);
      expect(cellTexts(doc).where((t) => t.contains('PROBE')), isEmpty);
    });

    test('spike ten_pages.pdf: exactly 10 tables, PROBE labels never in cells', () async {
      final doc = await spike('ten_pages');
      expect(doc.tables, hasLength(10));
      expect(overlays(doc).where((t) => t.startsWith('PROBE')), hasLength(20));
      expect(cellTexts(doc).where((t) => t.contains('PROBE')), isEmpty);
    });

    late List<String> clean;
    setUpAll(() async => clean = cellTexts(await read(buildPdf([FakePage(stmt())]))));

    test('(a) large DUPLICATE stamp across the table', () async {
      final doc = await read(buildPdf([
        FakePage([...stmt(), const FakeText(150, 190, 'DUPLICATE', size: 44, gray: 0.6)])
      ]));
      expect(cellTexts(doc), clean);
      expect(overlays(doc), ['DUPLICATE']);
    });

    test('(b) diagonal light watermark across the page', () async {
      final doc = await read(buildPdf([
        FakePage([...stmt(), const FakeText(60, 400, 'SAMPLE COPY - NOT VALID', size: 12, angle: 35, gray: 0.85)])
      ]));
      expect(cellTexts(doc), clean);
      expect(overlays(doc), ['SAMPLE COPY - NOT VALID']);
    });

    test('(c) control: bold, slightly taller header is a normal header row', () async {
      final doc = await read(buildPdf([FakePage(stmt(headerSize: 11.5, bold: true))]));
      expect(overlays(doc), isEmpty);
      expect(doc.tables.single.rowTexts(0), ['Date', 'Description', 'Amount', 'Balance']);
      expect(cellTexts(doc).skip(4), clean.skip(4));
    });
  });

  group('concurrency guard', () {
    Uint8List pdf() => buildPdf([FakePage(stmt()), FakePage(stmt(header: false))]);
    String json(ReadResult r) => layout((r as ReadOk).pages).toCanonicalJson();

    test('two concurrent readPdf calls in one isolate both succeed, same result as sequential', () async {
      final expected = json(await readPdf(pdf()));
      final both = await Future.wait([readPdf(pdf()), readPdf(locked, passwords: (_) async => password)]);
      expect(json(both[0]), expected);
      expect(both[1], isA<ReadOk>());
    });

    test('two concurrent readPdf calls from two other isolates both succeed (native gate)', () async {
      final bytes = pdf();
      final expected = json(await readPdf(bytes));
      final both = await Future.wait([
        Isolate.run(() async => json(await readPdf(bytes))),
        Isolate.run(() async => json(await readPdf(bytes))),
      ]);
      expect(both, [expected, expected]);
    });
  });
}
