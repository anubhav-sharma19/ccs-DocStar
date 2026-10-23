// chars -> reading frame -> lines -> words -> page furniture -> tables (columns,
// rows, grid) -> text blocks -> reading order -> DsDocument. Deterministic: every
// sort has a full tie-break ending in a char index or a creation index.
// Rules and numbers: docs/CORE_DESIGN.md (values marked "guess" there are guesses).
import 'dart:math' as math;

import 'model.dart';

enum Continuation { after, before }

/// Optional hints from a pack. The core never needs them; they sharpen tables.
class TableHints {
  final List<String> headerWords; // column header texts, e.g. Date, Description, Amount
  final RegExp? rowStart; // a line matching this at its start begins a new row (TR2)
  final Continuation continuation; // where a line without a row start goes
  final List<String> sectionTitles; // lines with exactly this text are section headers
  const TableHints(
      {this.headerWords = const [],
      this.rowStart,
      this.continuation = Continuation.after,
      this.sectionTitles = const []});
}

class LayoutConfig {
  final double wordGapPitch, lineOverlap, blockGapFactor, blockIndentPitch;
  final int tableMinLines, tableMinCols;
  final double headerFooterBand;
  final int headerFooterMinPages;
  final double colGapPitch, colGapRowShare, cellOverlap;
  final double tableMaxGapLines, continuationGapLines, continuationGapSlack;
  final double headlessTolerancePitch, headlessTopBand;
  final double overprintHeightFactor, overlaySlope, overlaySizeRatio;
  const LayoutConfig({
    this.wordGapPitch = 1.0,
    this.lineOverlap = 0.5,
    this.blockGapFactor = 1.5,
    this.blockIndentPitch = 1.0,
    this.tableMinLines = 3,
    this.tableMinCols = 3,
    this.headerFooterBand = 0.08,
    this.headerFooterMinPages = 2,
    this.colGapPitch = 1.5,
    this.colGapRowShare = 0.8,
    this.cellOverlap = 0.3,
    this.tableMaxGapLines = 3.0,
    this.continuationGapLines = 1.0,
    this.continuationGapSlack = 1.2,
    this.headlessTolerancePitch = 1.0,
    this.headlessTopBand = 0.25,
    this.overprintHeightFactor = 2.0,
    this.overlaySlope = 0.15,
    this.overlaySizeRatio = 1.4,
  });
}

DsDocument layout(List<PageInput> pages, {LayoutConfig config = const LayoutConfig(), TableHints? hints}) {
  final input = [...pages]..sort((a, b) => a.number.compareTo(b.number));
  final prepared = [for (final p in input) _Prepared(p, config)];
  _markFurniture(prepared, config);
  final out = <DsPage>[];
  _TableInfo? prevLast;
  for (final p in prepared) {
    final built = _buildPage(p, config, hints, prevLast);
    out.add(built.page);
    prevLast = built.lastTable;
  }
  return DsDocument(out);
}

// ---------------------------------------------------------------- page prep

class _Word {
  final String text;
  final Box box;
  final List<int> chars;
  _Word(this.text, this.box, this.chars);
}

class _Line {
  final int idx; // top-to-bottom order on the page
  final List<_Word> words;
  final Box box;
  final double em; // font size estimate of the line's first chunk
  bool overlay; // stamp / watermark: never in a table, a cell or a text block
  BlockLabel? furniture;
  _Line(this.idx, this.words, this.box, this.em, this.overlay);
  String get text => words.map((w) => w.text).join(' ');
}

class _Prepared {
  final PageInput input;
  late final int readingRotation;
  late final double w, h; // reading-frame size
  late final double pitch, lineHeight, em;
  late final List<_Line> lines;

  _Prepared(this.input, LayoutConfig cfg) {
    final chars = [...input.chars]..sort((a, b) => a.index.compareTo(b.index));
    readingRotation = _readingRotation(chars);
    final turned = readingRotation == 90 || readingRotation == 270;
    w = turned ? input.height : input.width;
    h = turned ? input.width : input.height;
    final framed = [
      for (final c in chars) CharCell(c.index, c.text, _toReading(c.box, readingRotation, input.width, input.height))
    ];
    final byIndex = {for (final c in framed) c.index: c};
    final chunks = _chunks(framed, byIndex);
    em = _median([for (final c in framed) ?_glyphEm(c)]);
    // Overlay rules 1-2: a chunk far above the page's font size, or on a slanted baseline.
    bool overlay(_Chunk c) => c.em > cfg.overprintHeightFactor * em || c.slope.abs() > cfg.overlaySlope;
    final chunkEm = {for (final c in chunks) for (final g in c.glyphs) g.index: c.em};
    final rawLines = _groupLines([for (final c in chunks) if (!overlay(c)) ...c.glyphs], cfg.lineOverlap,
        (g) => chunkEm[g.index]!, cfg.overlaySizeRatio, {for (final c in chunks) if (!overlay(c)) ..._followers(c)});
    pitch = _pitch([for (final l in rawLines) l.$1]);
    final built = <_Line>[];
    for (final (chars, lineEm) in rawLines) {
      final words = _words(chars, byIndex, cfg.wordGapPitch * pitch);
      built.add(_Line(0, words, words.map((w) => w.box).reduce((a, b) => a.union(b)), lineEm, false));
    }
    for (final c in chunks.where(overlay)) {
      // Stream order runs left to right; the gap scales with the stamp's own font size.
      final words = _words(c.glyphs, byIndex, cfg.wordGapPitch * pitch * math.max(1, c.em / em));
      built.add(_Line(0, words, words.map((w) => w.box).reduce((a, b) => a.union(b)), c.em, true));
    }
    built.sort((a, b) => _cmpBox(a.box, b.box, a.words.first.chars.first, b.words.first.chars.first));
    lines = [for (var i = 0; i < built.length; i++) _Line(i, built[i].words, built[i].box, built[i].em, built[i].overlay)];
    final normal = [for (final l in lines) if (!l.overlay) l.box.height];
    lineHeight = normal.isEmpty ? 10 : _median(normal);
  }
}

int _cmpBox(Box a, Box b, int ia, int ib) {
  var c = a.top.compareTo(b.top);
  if (c == 0) c = a.left.compareTo(b.left);
  return c != 0 ? c : ia.compareTo(ib);
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[(s.length - 1) ~/ 2];
}

/// Votes on the direction from each in-word glyph to the next one in the stream.
/// 90 = text runs downward in the display frame (turned clockwise). Ties -> lowest angle.
int _readingRotation(List<CharCell> chars) {
  final votes = [0, 0, 0, 0];
  for (var i = 0; i + 1 < chars.length; i++) {
    final a = chars[i], b = chars[i + 1];
    if (a.isSpace || b.isSpace || b.index != a.index + 1) continue;
    final size = [a.box.width, a.box.height, b.box.width, b.box.height].reduce(math.max);
    final dx = b.box.cx - a.box.cx, dy = b.box.cy - a.box.cy;
    if (dx == 0 && dy == 0 || dx.abs() + dy.abs() > 3 * size) continue;
    if (dx.abs() >= dy.abs()) {
      votes[dx > 0 ? 0 : 2]++;
    } else {
      votes[dy > 0 ? 1 : 3]++;
    }
  }
  var best = 0;
  for (var i = 1; i < 4; i++) {
    if (votes[i] > votes[best]) best = i;
  }
  return best * 90;
}

/// Display frame (w x h) -> reading frame, so text runs left to right.
Box _toReading(Box b, int r, double w, double h) => (switch (r) {
      90 => Box(b.top, w - b.right, b.bottom, w - b.left),
      180 => Box(w - b.right, h - b.bottom, w - b.left, h - b.top),
      270 => Box(h - b.bottom, b.left, h - b.top, b.right),
      _ => b,
    })
        .quantized();

/// Font size estimate from one glyph: tight box height over the glyph's share of
/// the em (x-height letters ~0.52, caps/digits/ascenders/descenders ~0.72).
/// ponytail: Latin letters and digits only; other glyphs do not vote. Per-script tables if needed.
double? _glyphEm(CharCell c) {
  if (c.text.length != 1) return null;
  final u = c.text.codeUnitAt(0);
  if (!(u >= 0x30 && u <= 0x39 || u >= 0x41 && u <= 0x5A || u >= 0x61 && u <= 0x7A)) return null;
  return c.box.height / ('acemnorsuvwxz'.contains(c.text) ? 0.52 : 0.72);
}

/// A stream-continuous run of glyphs (one PDF text show, usually one font size).
class _Chunk {
  final List<CharCell> glyphs;
  late final double em, slope;
  _Chunk(this.glyphs) {
    final ems = [for (final g in glyphs) ?_glyphEm(g)];
    em = ems.isEmpty ? glyphs.map((g) => g.box.height).reduce(math.max) / 0.72 : _median(ems);
    if (glyphs.length < 4) {
      slope = 0;
    } else {
      // Baseline rise between the halves' medians: robust to descenders and commas.
      final half = glyphs.length ~/ 2;
      final a = glyphs.sublist(0, half), b = glyphs.sublist(glyphs.length - half);
      final dx = _median([for (final g in b) g.box.cx]) - _median([for (final g in a) g.box.cx]);
      final dy = _median([for (final g in a) g.box.bottom]) - _median([for (final g in b) g.box.bottom]);
      slope = dx <= 0 ? 0 : dy / dx;
    }
  }
}

/// Splits the glyph stream into chunks: the next glyph continues a chunk when only
/// whitespace lies between them in the stream and it sits just ahead on (about) the same path.
List<_Chunk> _chunks(List<CharCell> chars, Map<int, CharCell> byIndex) {
  final out = <List<CharCell>>[];
  CharCell? prev;
  for (final g in chars) {
    if (g.isSpace) continue;
    final p = prev;
    var joins = false;
    if (p != null && (g.index == p.index + 1 || _explicitSpace(p, g, byIndex))) {
      final size = math.max(p.box.height, g.box.height);
      final dx = g.box.cx - p.box.cx;
      joins = dx > 0 &&
          g.box.left - p.box.right <= 2 * size &&
          (g.box.bottom - p.box.bottom).abs() <= math.max(0.5 * size, 1.5 * dx);
    }
    if (joins) {
      out.last.add(g);
    } else {
      out.add([g]);
    }
    prev = g;
  }
  return [for (final c in out) _Chunk(c)];
}

/// Punctuation and symbols in a chunk that also has letters or digits -> the
/// nearest letter/digit of that chunk (previous one on ties). They join its line:
/// a comma hanging below the baseline must not become a line of its own.
Map<CharCell, CharCell> _followers(_Chunk c) {
  final anchors = [for (final g in c.glyphs) if (_glyphEm(g) != null) g];
  if (anchors.isEmpty) return const {};
  return {
    for (final g in c.glyphs)
      if (_glyphEm(g) == null)
        g: anchors.reduce((a, b) => (b.index - g.index).abs() < (a.index - g.index).abs() ? b : a)
  };
}

/// Visual lines: a glyph joins the open line it overlaps most vertically, when the
/// overlap is at least [overlap] of the smaller height and its chunk's font size is
/// within [sizeRatio] of the line's (an overprinted stamp does not join a row).
/// Glyphs go in by (top, left, index). Each line comes with its size estimate.
List<(List<CharCell>, double)> _groupLines(List<CharCell> glyphs, double overlap, double Function(CharCell) emOf,
    double sizeRatio, Map<CharCell, CharCell> follows) {
  glyphs = glyphs.where((g) => !follows.containsKey(g)).toList()
    ..sort((a, b) => _cmpBox(a.box, b.box, a.index, b.index));
  final lines = <List<CharCell>>[];
  final bands = <Box>[];
  final ems = <double>[];
  final open = <int>[];
  for (final g in glyphs) {
    open.removeWhere((i) => bands[i].bottom < g.box.top);
    var best = -1;
    var bestOv = 0.0;
    for (final i in open) {
      final ov = g.box.vOverlap(bands[i]);
      final need = overlap * math.max(0.01, math.min(g.box.height, bands[i].height));
      final e = emOf(g);
      final sameSize = math.max(e, ems[i]) <= sizeRatio * math.min(e, ems[i]);
      if (ov >= need && ov > bestOv && sameSize) {
        best = i;
        bestOv = ov;
      }
    }
    if (best < 0) {
      lines.add([g]);
      bands.add(g.box);
      ems.add(emOf(g));
      open.add(lines.length - 1);
    } else {
      lines[best].add(g);
      bands[best] = bands[best].union(g.box);
    }
  }
  final lineOf = {for (var i = 0; i < lines.length; i++) for (final g in lines[i]) g.index: i};
  for (final e in follows.entries) {
    lines[lineOf[e.value.index]!].add(e.key);
  }
  for (final l in lines) {
    l.sort((a, b) {
      final c = a.box.left.compareTo(b.box.left);
      return c != 0 ? c : a.index.compareTo(b.index);
    });
  }
  return [for (var i = 0; i < lines.length; i++) (lines[i], ems[i])];
}

/// About one character advance: median left-to-left step of stream-adjacent glyphs.
double _pitch(List<List<CharCell>> lines) {
  final steps = <double>[];
  for (final l in lines) {
    for (var i = 0; i + 1 < l.length; i++) {
      if (l[i + 1].index == l[i].index + 1 && l[i + 1].box.left > l[i].box.left) {
        steps.add(l[i + 1].box.left - l[i].box.left);
      }
    }
  }
  if (steps.isNotEmpty) return _median(steps);
  final widths = [for (final l in lines) for (final c in l) c.box.width];
  final m = _median(widths);
  return m > 0 ? m : 5;
}

/// Only whitespace between two glyphs in the stream = an explicit word break.
/// ponytail: streams more than 64 chars apart fall back to geometry; scan if it matters.
bool _explicitSpace(CharCell a, CharCell b, Map<int, CharCell> byIndex) {
  final lo = math.min(a.index, b.index), hi = math.max(a.index, b.index);
  if (hi - lo < 2 || hi - lo > 64) return false;
  for (var i = lo + 1; i < hi; i++) {
    final c = byIndex[i];
    if (c != null && !c.isSpace) return false;
  }
  return true;
}

List<_Word> _words(List<CharCell> line, Map<int, CharCell> byIndex, double maxGap) {
  final groups = <List<CharCell>>[[line.first]];
  for (var i = 1; i < line.length; i++) {
    final a = line[i - 1], b = line[i];
    if (_explicitSpace(a, b, byIndex) || b.box.left - a.box.right > maxGap) {
      groups.add([b]);
    } else {
      groups.last.add(b);
    }
  }
  return [
    for (final g in groups)
      _Word(g.map((c) => c.text).join(), g.map((c) => c.box).reduce((a, b) => a.union(b)),
          [for (final c in g) c.index])
  ];
}

// ---------------------------------------------------------------- furniture (LR4)

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\d'), '#').replaceAll(RegExp(r'\s+'), ' ').trim();

/// LR4 with the X-HDRFTR negative rule: a line in the top/bottom band whose text
/// (digits -> #) repeats on 2+ pages, is not a multi-column row, and sits in an
/// unbroken stack from the page edge. A table row near the edge is never furniture.
void _markFurniture(List<_Prepared> pages, LayoutConfig cfg) {
  if (pages.length < cfg.headerFooterMinPages) return;
  String? key(_Prepared p, _Line l) {
    if (l.overlay || _segments(l, cfg.colGapPitch * p.pitch).length >= cfg.tableMinCols) return null;
    if (l.box.top < cfg.headerFooterBand * p.h) return 'h|${_norm(l.text)}';
    if (l.box.bottom > (1 - cfg.headerFooterBand) * p.h) return 'f|${_norm(l.text)}';
    return null;
  }

  final seen = <String, Set<int>>{};
  for (final p in pages) {
    for (final l in p.lines) {
      final k = key(p, l);
      if (k != null) (seen[k] ??= {}).add(p.input.number);
    }
  }
  bool repeated(_Prepared p, _Line l, String zone) {
    final k = key(p, l);
    return k != null && k.startsWith(zone) && seen[k]!.length >= cfg.headerFooterMinPages;
  }

  for (final p in pages) {
    for (final l in p.lines.where((l) => !l.overlay)) {
      if (!repeated(p, l, 'h')) break;
      l.furniture = BlockLabel.pageHeader;
    }
    for (final l in p.lines.reversed.where((l) => !l.overlay)) {
      if (!repeated(p, l, 'f')) break;
      l.furniture = BlockLabel.pageFooter;
    }
  }
}

// ---------------------------------------------------------------- tables

class _Range {
  final double left, right;
  const _Range(this.left, this.right);
  double get cx => (left + right) / 2;
}

class _TableInfo {
  final Table table;
  final List<_Range> cols;
  final String? headerKey;
  _TableInfo(this.table, this.cols, this.headerKey);
}

/// Words of a line split where the gap is wider than [gap] (cells of a row).
List<_Range> _segments(_Line l, double gap) {
  final out = <_Range>[];
  var left = l.words.first.box.left, right = l.words.first.box.right;
  for (final w in l.words.skip(1)) {
    if (w.box.left - right > gap) {
      out.add(_Range(left, right));
      left = w.box.left;
    }
    right = math.max(right, w.box.right);
  }
  return out..add(_Range(left, right));
}

/// Indexes of the bands [s] overlaps.
List<int> _hits(_Range s, List<_Range> bands) =>
    [for (var i = 0; i < bands.length; i++) if (s.right > bands[i].left && s.left < bands[i].right) i];

List<_Range> _mergeBands(List<_Range> bands, List<_Range> add) {
  final all = [...bands, ...add]..sort((a, b) => a.left.compareTo(b.left));
  final out = <_Range>[];
  for (final r in all) {
    if (out.isNotEmpty && r.left < out.last.right) {
      out[out.length - 1] = _Range(out.last.left, math.max(out.last.right, r.right));
    } else {
      out.add(r);
    }
  }
  return out;
}

/// TR5: columns are x-ranges covered by more than (1 - rowShare) of the row lines.
List<_Range> _coverageColumns(List<List<_Range>> rows, double rowShare) {
  final xs = <double>{for (final r in rows) for (final s in r) ...[s.left, s.right]}.toList()..sort();
  final need = (1 - rowShare) * rows.length;
  final cols = <_Range>[];
  for (var i = 0; i + 1 < xs.length; i++) {
    final a = xs[i], b = xs[i + 1];
    final cover = _coverage(rows, a, b);
    if (cover > need) {
      if (cols.isNotEmpty && cols.last.right == a) {
        cols[cols.length - 1] = _Range(cols.last.left, b);
      } else {
        cols.add(_Range(a, b));
      }
    }
  }
  return cols;
}

bool _sameText(String a, String b) => a.toLowerCase().trim() == b.toLowerCase().trim();

class _Run {
  final List<_Line> lines = [];
  List<_Range> bands = [];
}

class _PageBuild {
  final DsPage page;
  final _TableInfo? lastTable;
  _PageBuild(this.page, this.lastTable);
}

_PageBuild _buildPage(_Prepared p, LayoutConfig cfg, TableHints? hints, _TableInfo? prevLast) {
  final segGap = cfg.colGapPitch * p.pitch;
  final body = p.lines.where((l) => l.furniture == null && !l.overlay).toList();
  // Overlay rule 3 candidates: lines in a clearly larger font. They never join or
  // break a table run; inside a table's region they become overlays (below).
  bool tall(_Line l) => l.em > cfg.overlaySizeRatio * p.em;
  final headerBottom = p.lines
      .where((l) => l.furniture == BlockLabel.pageHeader)
      .fold<double>(0, (m, l) => math.max(m, l.box.bottom));
  bool isSection(_Line l) => hints?.sectionTitles.any((t) => _sameText(t, l.text)) ?? false;

  // A wrapped line may sit as far below its row as the page's own line spacing
  // (some statements space wrapped lines like rows), not only one line height.
  final gaps = [for (var i = 1; i < body.length; i++) body[i].box.top - body[i - 1].box.bottom]
    ..removeWhere((g) => g <= 0);
  final contGap = math.max(cfg.continuationGapLines * p.lineHeight, cfg.continuationGapSlack * _median(gaps));

  // --- find runs of table-like lines (LR3)
  final runs = <_Run>[];
  _Run? cur;
  _Line? prev;
  for (final l in body) {
    if (tall(l)) continue;
    final segs = _segments(l, segGap);
    final rowLike = segs.length >= 2;
    var fits = cur != null && !isSection(l) && l.box.top - prev!.box.bottom <= cfg.tableMaxGapLines * p.lineHeight;
    final add = <_Range>[];
    if (fits && !rowLike) {
      fits = _hits(segs.first, cur.bands).length == 1 &&
          l.box.top - prev.box.bottom <= contGap;
      add.addAll(segs);
    } else if (fits) {
      final bands = cur.bands;
      for (final s in segs) {
        if (_hits(s, bands).length <= 1) {
          add.add(s);
          continue;
        }
        // A segment straddles two columns. Fine if each of its words sits in one
        // column (tight columns, e.g. a long credit next to the balance); else not this table.
        final words = [
          for (final w in l.words)
            if (w.box.left >= s.left && w.box.right <= s.right) _Range(w.box.left, w.box.right)
        ];
        if (words.any((w) => _hits(w, bands).length > 1)) {
          fits = false;
          break;
        }
        add.addAll(words);
      }
    }
    if (fits) {
      cur!.lines.add(l);
      cur.bands = _mergeBands(cur.bands, add);
    } else {
      cur = null;
      if (rowLike && !isSection(l)) {
        cur = _Run()
          ..lines.add(l)
          ..bands = _mergeBands([], segs);
        runs.add(cur);
      }
    }
    prev = l;
  }

  // --- accept runs as tables, build grids
  final tableLines = <_Line>{};
  final infos = <_Grid>[];
  final tableBlocks = <(_Line first, List<_Line> lines, _Grid grid)>[];
  for (final run in runs) {
    final rowLines = [for (final l in run.lines) if (_segments(l, segGap).length >= 2) l];
    final rows = [for (final l in rowLines) _segments(l, segGap)];
    var cols = _sparseColumns(_coverageColumns(rows, cfg.colGapRowShare), rows);
    final header = _findHeader(run.lines, hints);
    final wide = rows.where((r) => r.length >= cfg.tableMinCols).length;
    final regular = wide >= cfg.tableMinLines && cols.length >= cfg.tableMinCols;
    final anchored = header != null && run.lines.length >= 2;
    final tol = cfg.headlessTolerancePitch * p.pitch;
    final atTop = infos.isEmpty && prevLast != null && run.lines.first.box.top <= headerBottom + cfg.headlessTopBand * p.h;
    // Fewer columns than the previous page, each matching one of its columns in order:
    // a sparse column (e.g. credits) has no entry on this page.
    final fewer = atTop && cols.length < prevLast.cols.length && _colsSubset(cols, prevLast.cols, tol);
    final headless = atTop && (fewer || _colsMatch(cols, prevLast.cols, tol));
    if (!regular && !anchored && !headless) continue;

    final headerLine = header ??
        (run.lines.first == rowLines.first && !RegExp(r'\d').hasMatch(run.lines.first.text) ? run.lines.first : null);
    if (headerLine == null && fewer) cols = prevLast.cols; // grid on the previous page's columns
    if (headerLine != null) cols = _splitAtHeader(cols, _segments(headerLine, segGap), rows);
    if (header != null) cols = _anchorColumns(cols, header, hints!);
    final table = _grid(p, run.lines, cols, headerLine, hints, cfg, header != null);
    tableLines.addAll(run.lines);
    tableBlocks.add((run.lines.first, run.lines, table));
    infos.add(table);
  }

  // --- overlay rule 3: a larger-font line inside a table's region is a stamp, not text.
  // ponytail: normal-size text that does not fit the grid still ends the table; widen when a statement needs it.
  for (final l in body.where((l) => tall(l))) {
    for (final t in tableBlocks) {
      final box = t.$2.map((x) => x.box).reduce((a, b) => a.union(b));
      if (l.box.cy >= box.top && l.box.cy <= box.bottom && l.box.hOverlap(box.left, box.right) > 0) l.overlay = true;
    }
  }

  // --- text blocks (LR2) from the remaining body lines
  final textBlocks = <(BlockLabel, List<_Line>)>[];
  final tableTops = [for (final t in tableBlocks) t.$1.box.top];
  _Line? last;
  for (final l in body.where((l) => !tableLines.contains(l) && !l.overlay)) {
    final section = isSection(l);
    final lastBlock = textBlocks.isEmpty ? null : textBlocks.last;
    final newBlock = last == null ||
        section ||
        lastBlock!.$1 == BlockLabel.sectionHeader ||
        l.box.top - last.box.bottom > cfg.blockGapFactor * p.lineHeight ||
        (l.box.left - last.box.left).abs() > cfg.blockIndentPitch * p.pitch ||
        tableTops.any((t) => t > last!.box.top && t < l.box.top);
    if (newBlock) {
      textBlocks.add((section ? BlockLabel.sectionHeader : BlockLabel.text, [l]));
    } else {
      lastBlock.$2.add(l);
    }
    last = l;
  }
  for (final label in [BlockLabel.pageHeader, BlockLabel.pageFooter]) {
    for (final l in p.lines.where((l) => l.furniture == label)) {
      textBlocks.add((label, [l]));
    }
  }
  for (final l in p.lines.where((l) => l.overlay)) {
    textBlocks.add((BlockLabel.overlay, [l]));
  }

  // --- reading order: page headers, body by (top, left), page footers, overlays
  int rank(BlockLabel b) => switch (b) {
        BlockLabel.pageHeader => 0,
        BlockLabel.pageFooter => 2,
        BlockLabel.overlay => 3,
        _ => 1,
      };
  final ordered = <(BlockLabel, List<_Line>, _Grid?)>[
    for (final t in tableBlocks) (BlockLabel.table, t.$2, t.$3),
    for (final b in textBlocks) (b.$1, b.$2, null),
  ]..sort((a, b) {
      var c = rank(a.$1).compareTo(rank(b.$1));
      if (c == 0) c = a.$2.first.box.top.compareTo(b.$2.first.box.top);
      if (c == 0) c = a.$2.first.box.left.compareTo(b.$2.first.box.left);
      return c != 0 ? c : a.$2.first.idx.compareTo(b.$2.first.idx);
    });

  // --- ids: words in reading order, lines top to bottom, tables in reading order
  final n = p.input.number;
  final wordIds = <_Word, String>{};
  for (final b in ordered) {
    for (final l in b.$2) {
      for (final w in l.words) {
        wordIds[w] = 'p$n.w${wordIds.length}';
      }
    }
  }
  final words = <Word>[];
  final wordObj = <_Word, Word>{};
  for (final e in wordIds.entries) {
    final w = Word(e.value, e.key.text, e.key.box, e.key.chars);
    words.add(w);
    wordObj[e.key] = w;
  }
  final lineObj = {
    for (final l in p.lines) l: Line('p$n.l${l.idx}', [for (final w in l.words) wordObj[w]!], l.box)
  };

  final blocks = <Block>[];
  _TableInfo? lastInfo;
  var tableNo = 0;
  for (final b in ordered) {
    final box = b.$2.map((l) => l.box).reduce((x, y) => x.union(y));
    Table? table;
    if (b.$3 != null) {
      final info = b.$3!;
      table = _finishTable(info, 'p$n.t${tableNo++}', wordIds);
      if (lastInfo == null && prevLast != null) _link(info, table, prevLast, cfg, p);
      lastInfo = _TableInfo(table, info.cols, info.headerKey);
    }
    blocks.add(Block('p$n.b${blocks.length}', b.$1, [for (final l in b.$2) lineObj[l]!], box, table: table));
  }

  final page = DsPage(n, p.input.width, p.input.height, p.input.rotation, p.readingRotation, words,
      [for (final l in p.lines) lineObj[l]!], blocks);
  return _PageBuild(page, lastInfo);
}

_Line? _findHeader(List<_Line> lines, TableHints? hints) {
  if (hints == null || hints.headerWords.isEmpty) return null;
  for (final l in lines) {
    final text = ' ${l.words.map((w) => w.text.toLowerCase()).join(' ')} ';
    if (hints.headerWords.every((h) => text.contains(' ${h.toLowerCase().trim()} '))) return l;
  }
  return null;
}

/// TR4 anchoring: merge coverage columns so each holds exactly one header word.
/// A column with no header joins its left neighbour (or the right one at the start).
List<_Range> _anchorColumns(List<_Range> cols, _Line header, TableHints hints) {
  // Each header word goes to a column by the word rule (TR6); that column owns it.
  final owner = List.filled(cols.length, -1);
  for (final h in hints.headerWords) {
    final words = h.toLowerCase().trim().split(RegExp(r'\s+'));
    for (var i = 0; i + words.length <= header.words.length; i++) {
      if (List.generate(words.length, (k) => header.words[i + k].text.toLowerCase()).join(' ') == words.join(' ')) {
        final c = _column(header.words[i].box.union(header.words[i + words.length - 1].box), cols, 0.3);
        if (owner[c] < 0) owner[c] = c;
        break;
      }
    }
  }
  final out = <_Range>[];
  final outOwner = <int>[];
  for (var i = 0; i < cols.length; i++) {
    if (out.isNotEmpty && owner[i] < 0) {
      out[out.length - 1] = _Range(out.last.left, cols[i].right);
    } else if (out.isNotEmpty && outOwner.last < 0) {
      out[out.length - 1] = _Range(out.last.left, cols[i].right);
      outOwner[outOwner.length - 1] = owner[i];
    } else {
      out.add(cols[i]);
      outOwner.add(owner[i]);
    }
  }
  return out;
}

/// TR5 drops x-ranges used by <= 20% of rows. Segments lying wholly inside such a
/// gap (touching no column) form a sparse column of their own, e.g. a credit
/// column only a few rows use, instead of being pulled into a neighbour's cell.
List<_Range> _sparseColumns(List<_Range> cols, List<List<_Range>> rows) =>
    _mergeBands(cols, [for (final r in rows) for (final s in r) if (_hits(s, cols).isEmpty) s]);

int _coverage(List<List<_Range>> rows, double a, double b) =>
    rows.where((r) => r.any((s) => s.left <= a && s.right >= b)).length;

/// A known header row names one column per header segment: a column holding two
/// header segments (tight columns merged by TR5) is split at its least-covered
/// x-interval between them. Leftmost on ties.
List<_Range> _splitAtHeader(List<_Range> cols, List<_Range> headerSegs, List<List<_Range>> rows) {
  final out = <_Range>[];
  for (final c in cols) {
    final inside = [for (final h in headerSegs) if (h.cx >= c.left && h.cx <= c.right) h];
    var left = c.left;
    for (var i = 0; i + 1 < inside.length; i++) {
      final xs = <double>{
        inside[i].right,
        inside[i + 1].left,
        for (final r in rows)
          for (final s in r) ...[s.left, s.right].where((x) => x > inside[i].right && x < inside[i + 1].left)
      }.toList()
        ..sort();
      var best = (xs.first, xs.last);
      var bestCover = 1 << 30;
      for (var k = 0; k + 1 < xs.length; k++) {
        final cover = _coverage(rows, xs[k], xs[k + 1]);
        if (cover < bestCover) {
          best = (xs[k], xs[k + 1]);
          bestCover = cover;
        }
      }
      out.add(_Range(left, best.$1));
      left = best.$2;
    }
    out.add(_Range(left, c.right));
  }
  return out;
}

/// Every column of [a] matches a column of [b], in order (greedy).
bool _colsSubset(List<_Range> a, List<_Range> b, double tol) {
  var j = 0;
  for (final c in a) {
    while (j < b.length && math.min((c.left - b[j].left).abs(), (c.right - b[j].right).abs()) > tol) {
      j++;
    }
    if (j++ >= b.length) return false;
  }
  return a.isNotEmpty;
}

bool _colsMatch(List<_Range> a, List<_Range> b, double tol) {
  if (a.length != b.length || a.isEmpty) return false;
  for (var i = 0; i < a.length; i++) {
    if (math.min((a[i].left - b[i].left).abs(), (a[i].right - b[i].right).abs()) > tol) return false;
  }
  return true;
}

/// TR6: a word goes to the column holding more than [overlap] of its width; when
/// it straddles, to the column holding its centre; else the nearest column.
int _column(Box w, List<_Range> cols, double overlap) {
  final width = math.max(w.width, 0.01);
  final hit = [for (var i = 0; i < cols.length; i++) if (w.hOverlap(cols[i].left, cols[i].right) / width > overlap) i];
  if (hit.length == 1) return hit.first;
  final centre = cols.indexWhere((c) => w.cx >= c.left && w.cx <= c.right);
  if (centre >= 0) return centre;
  if (hit.isNotEmpty) return hit.first;
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < cols.length; i++) {
    final d = w.cx < cols[i].left ? cols[i].left - w.cx : w.cx - cols[i].right;
    if (d < bestD) {
      best = i;
      bestD = d;
    }
  }
  return best;
}

class _Grid {
  final List<List<List<_Word>>> grid; // rows x cols x words
  final List<Box> rowBoxes;
  final TableMethod method;
  final int? headerRow;
  final List<_Range> cols;
  final String? headerKey; // normalised header row text, for repeated-header links
  _Grid(this.grid, this.rowBoxes, this.method, this.headerRow, this.cols, this.headerKey);
}

_Grid _grid(_Prepared p, List<_Line> lines, List<_Range> cols, _Line? header, TableHints? hints,
    LayoutConfig cfg, bool anchored) {
  final colOf = <_Word, int>{for (final l in lines) for (final w in l.words) w: _column(w.box, cols, cfg.cellOverlap)};
  bool starts(_Line l) {
    final re = hints?.rowStart;
    if (re != null) return re.matchAsPrefix(l.text) != null;
    return l.words.any((w) => colOf[w] == 0);
  }

  final rows = <List<_Line>>[];
  int? headerRow;
  final pending = <_Line>[];
  final before = hints?.continuation == Continuation.before;
  for (final l in lines) {
    if (l == header) {
      headerRow = rows.length;
      rows.add([l]);
    } else if (starts(l)) {
      rows.add([...pending, l]);
      pending.clear();
    } else if (before) {
      pending.add(l);
    } else if (rows.isEmpty || rows.length - 1 == headerRow) {
      rows.add([l]);
    } else {
      rows.last.add(l);
    }
  }
  if (pending.isNotEmpty) {
    if (rows.isNotEmpty && rows.length - 1 != headerRow) {
      rows.last.addAll(pending);
    } else {
      rows.add([...pending]);
    }
  }

  final grid = [
    for (final r in rows)
      [
        for (var c = 0; c < cols.length; c++) [for (final l in r) for (final w in l.words) if (colOf[w] == c) w]
      ]
  ];
  final rowBoxes = [for (final r in rows) r.map((l) => l.box).reduce((a, b) => a.union(b))];
  final headerKey = headerRow == null
      ? null
      : [for (final cell in grid[headerRow]) _norm(cell.map((w) => w.text).join(' '))].join('|');
  return _Grid(grid, rowBoxes, anchored ? TableMethod.headerAnchored : TableMethod.whitespace, headerRow, cols,
      headerKey);
}

Table _finishTable(_Grid g, String id, Map<_Word, String> wordIds) {
  final cells = <Cell>[];
  for (var r = 0; r < g.grid.length; r++) {
    for (var c = 0; c < g.cols.length; c++) {
      final ws = g.grid[r][c];
      final box = ws.isEmpty
          ? Box(g.cols[c].left, g.rowBoxes[r].top, g.cols[c].right, g.rowBoxes[r].bottom)
          : ws.map((w) => w.box).reduce((a, b) => a.union(b));
      cells.add(Cell(r, c, ws.map((w) => w.text).join(' '), box, [for (final w in ws) wordIds[w]!]));
    }
  }
  return Table(id, g.method, g.grid.length, g.cols.length, g.headerRow, cells);
}

/// Links a page's first table to the previous page's last table (repeated header, or headless).
void _link(_Grid info, Table t, _TableInfo prev, LayoutConfig cfg, _Prepared p) {
  if (info.headerKey != null) {
    if (info.headerKey == prev.headerKey) {
      t.continuesFrom = prev.table.id;
      t.repeatedHeader = true;
    }
    return;
  }
  final top = t.cells.isEmpty ? 0.0 : t.cells.first.box.top;
  final bodyTop = p.lines.where((l) => l.furniture == BlockLabel.pageHeader).fold<double>(0, (m, l) => math.max(m, l.box.bottom));
  if (top <= bodyTop + cfg.headlessTopBand * p.h && _colsMatch(info.cols, prev.cols, cfg.headlessTolerancePitch * p.pitch)) {
    t.continuesFrom = prev.table.id;
  }
}
