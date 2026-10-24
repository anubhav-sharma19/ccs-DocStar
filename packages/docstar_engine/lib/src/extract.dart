/// Positioned words -> visual lines. Pure: the PDF adapter (outside this package) fills [Page]s.
/// Reads only the PDF's own text layer (no OCR, by policy).
///
/// Name table (Python -> Dart): build_lines -> buildLines, load_words -> loadWords, dump_words -> dumpWords.
library;

import 'py.dart';

class Word {
  final String text;
  final double x0, x1, top, bottom, size;
  final bool bold;
  const Word(this.text, this.x0, this.x1, this.top, this.bottom, [this.size = 9.0, this.bold = false]);

  double get xc => (x0 + x1) / 2;
  double get yc => (top + bottom) / 2;
}

class Line {
  final List<Word> words;
  final int page;
  int idx; // index in the document line stream
  String kind = ''; // header|furniture|table|...
  dynamic cells; // layout.Cells, set by the engine

  Line(this.words, this.page, [this.idx = 0]);

  // words never change once a line exists, so the derived values are computed once
  late final double top = words.map((w) => w.top).reduce((a, b) => a < b ? a : b);
  late final double bottom = words.map((w) => w.bottom).reduce((a, b) => a > b ? a : b);
  late final double x0 = words.map((w) => w.x0).reduce((a, b) => a < b ? a : b);
  late final double x1 = words.map((w) => w.x1).reduce((a, b) => a > b ? a : b);
  late final String text = words.map((w) => w.text).join(' ');
  late final double height = median([for (final w in words) w.bottom - w.top]);
  late final double size = median([for (final w in words) w.size]);
}

/// Horizontal ruling line: y, x0, x1.
typedef HRule = (double, double, double);

class Page {
  final int number;
  final double width, height;
  final List<Word> words;
  final List<HRule> hrules;
  List<Line> lines = [];
  Page(this.number, this.width, this.height, this.words, this.hrules);
}

class Document {
  final List<Page> pages;
  final String path;
  final List<String> warnings;
  Document(this.pages, [this.path = '', List<String>? warnings]) : warnings = warnings ?? [];
}

/// What Python `extract.load` does once the PDF adapter has read the pages: flag unreadable pages, build lines.
Document makeDocument(List<Page> pages, {String path = ''}) {
  final doc = Document(pages, path, [for (final p in pages) if (unreadable(p)) 'page ${p.number}: no readable text layer']);
  buildLines(doc);
  return doc;
}

const noOcrNotice = "No OCR: DocStar reads only the PDF's own text layer. Scanned or image-only statements "
    "are not supported, by design, under CalmCraft's privacy commitment. "
    'Download the original e-statement PDF from your bank instead.';

final _garbage = RegExp(r'[-�]|\(cid:\d+\)');

double _garbageRatio(List<Word> words) {
  if (words.isEmpty) return 1.0;
  final txt = words.map((w) => w.text).join();
  final bad = _garbage.allMatches(txt).length;
  final letters = txt.runes.where((r) => isAlnum(String.fromCharCode(r))).length;
  return bad / (bad + letters > 1 ? bad + letters : 1);
}

/// No usable text layer: fewer than 8 words, or more than 30% replacement chars / (cid:N) glyphs.
bool unreadable(Page page) => page.words.length < 8 || _garbageRatio(page.words) > 0.3;

/// Group words into visual lines (same baseline band), left-to-right.
void buildLines(Document doc) {
  var idx = 0;
  for (final pg in doc.pages) {
    final ws = [...pg.words];
    stableSort(ws, (a, b) => a.yc != b.yc ? a.yc.compareTo(b.yc) : a.x0.compareTo(b.x0));
    final lines = <List<Word>>[];
    for (final w in ws) {
      var placed = false;
      for (var k = lines.length - 1; k >= 0 && k >= lines.length - 4; k--) {
        final ln = lines[k];
        final ref = median([for (final x in ln) x.yc]);
        final h = median([for (final x in ln) x.bottom - x.top]);
        final wh = w.bottom - w.top;
        final tol = 0.45 * (h < wh ? h : wh);
        if ((w.yc - ref).abs() <= (tol > 1.6 ? tol : 1.6)) {
          // don't merge if this x-range is already occupied (overlapping text = different line)
          if (ln.any((x) => !(w.x1 <= x.x0 - 0.5 || w.x0 >= x.x1 + 0.5))) continue;
          ln.add(w);
          placed = true;
          break;
        }
      }
      if (!placed) lines.add([w]);
    }
    final out = <Line>[];
    for (final ln in lines) {
      stableSort(ln, (a, b) => a.x0.compareTo(b.x0));
      out.add(Line(ln, pg.number));
    }
    stableSort(out, (a, b) {
      final ta = pyRound(a.top, 1), tb = pyRound(b.top, 1);
      return ta != tb ? ta.compareTo(tb) : a.x0.compareTo(b.x0);
    });
    for (final l in out) {
      l.idx = idx++;
    }
    pg.lines = out;
  }
}

// ---------------------------------------------------------------- words.json (golden harness)

double _d(Object? v) => (v as num).toDouble();

/// Builds a [Document] (with lines) from the words.json written by Python `extract.dump_words`.
Document loadWords(Map<String, dynamic> data) {
  final pages = [
    for (final p in data['pages'] as List)
      Page(
        p['number'] as int,
        _d(p['width']),
        _d(p['height']),
        [
          for (final w in p['words'] as List)
            Word(w[0] as String, _d(w[1]), _d(w[2]), _d(w[3]), _d(w[4]), _d(w[5]), w[6] as bool),
        ],
        [for (final r in p['hrules'] as List) (_d(r[0]), _d(r[1]), _d(r[2]))],
      ),
  ];
  final doc = Document(pages, (data['path'] ?? '') as String, [for (final w in (data['warnings'] ?? []) as List) w as String]);
  buildLines(doc);
  return doc;
}

/// What the engine saw: page sizes, words, ruling lines (Python `dump_words` format).
Map<String, dynamic> dumpWords(Document doc) => {
      'path': doc.path,
      'warnings': doc.warnings,
      'pages': [
        for (final p in doc.pages)
          {
            'number': p.number,
            'width': p.width,
            'height': p.height,
            'hrules': [for (final r in p.hrules) [r.$1, r.$2, r.$3]],
            'words': [for (final w in p.words) [w.text, w.x0, w.x1, w.top, w.bottom, w.size, w.bold]],
          },
      ],
    };
