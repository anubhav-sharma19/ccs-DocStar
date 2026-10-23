// Input (chars with boxes) and output (document model). Geometry only: no money.
// Coordinates: points, origin top-left, y down. Output boxes are in each page's
// reading frame (text runs left-to-right); DsPage.toDisplay maps them back.
import 'dart:convert';
import 'dart:math' as math;

/// Rounds to 0.01 pt so float noise cannot change the output.
double q(double v) => (v * 100).roundToDouble() / 100;

class Box {
  final double left, top, right, bottom;
  const Box(this.left, this.top, this.right, this.bottom);

  double get width => right - left;
  double get height => bottom - top;
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;

  Box union(Box o) =>
      Box(math.min(left, o.left), math.min(top, o.top), math.max(right, o.right), math.max(bottom, o.bottom));

  /// Length of the vertical overlap with [o] (0 when apart).
  double vOverlap(Box o) => math.max(0, math.min(bottom, o.bottom) - math.max(top, o.top));

  /// Length of the horizontal overlap with [left2]..[right2] (0 when apart).
  double hOverlap(double left2, double right2) => math.max(0, math.min(right, right2) - math.max(left, left2));

  Box quantized() => Box(q(left), q(top), q(right), q(bottom));

  List<double> toJson() => [q(left), q(top), q(right), q(bottom)];

  @override
  bool operator ==(Object o) =>
      o is Box && o.left == left && o.top == top && o.right == right && o.bottom == bottom;
  @override
  int get hashCode => Object.hash(left, top, right, bottom);
  @override
  String toString() => 'Box($left, $top, $right, $bottom)';
}

/// One character from the reader, in the page's display frame.
/// [index] is its position in the page's character stream (provenance).
class CharCell {
  final int index;
  final String text;
  final Box box;
  const CharCell(this.index, this.text, this.box);

  bool get isSpace => text.trim().isEmpty;
}

/// One page from the reader. [width] x [height] is the displayed size.
class PageInput {
  final int number; // 1-based
  final double width, height;
  final int rotation; // the PDF's /Rotate, informational
  final List<CharCell> chars;
  const PageInput(this.number, this.width, this.height, this.chars, {this.rotation = 0});
}

class Word {
  final String id, text;
  final Box box;
  final List<int> charIndices; // page-local stream indices, left to right
  const Word(this.id, this.text, this.box, this.charIndices);

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'box': box.toJson(), 'chars': charIndices};
}

class Line {
  final String id;
  final List<Word> words;
  final Box box;
  const Line(this.id, this.words, this.box);

  String get text => words.map((w) => w.text).join(' ');

  Map<String, Object?> toJson() =>
      {'id': id, 'text': text, 'box': box.toJson(), 'words': [for (final w in words) w.id]};
}

/// [overlay]: stamp or watermark text (larger font, slanted, or over a table). Kept
/// with full provenance, but never part of a table, a cell or a text block.
enum BlockLabel { text, sectionHeader, table, pageHeader, pageFooter, overlay }

enum TableMethod { headerAnchored, whitespace }

class Cell {
  final int row, col;
  final String text;
  final Box box;
  final List<String> wordIds;
  const Cell(this.row, this.col, this.text, this.box, this.wordIds);

  Map<String, Object?> toJson() =>
      {'row': row, 'col': col, 'text': text, 'box': box.toJson(), 'words': wordIds};
}

class Table {
  final String id;
  final TableMethod method;
  final int rows, cols;
  final int? headerRow;
  final List<Cell> cells; // row-major, rows x cols, empty cells included
  String? continuesFrom; // id of the previous page's table
  bool repeatedHeader = false;
  /// The first data row has no row start: it is the end of the previous page's
  /// last row (a narration wrapped over the page break). Set only when linked.
  bool continuesRow = false;
  Table(this.id, this.method, this.rows, this.cols, this.headerRow, this.cells);

  Cell cell(int r, int c) => cells[r * cols + c];
  List<String> rowTexts(int r) => [for (var c = 0; c < cols; c++) cell(r, c).text];

  Map<String, Object?> toJson() => {
        'id': id,
        'method': method.name,
        'rows': rows,
        'cols': cols,
        'headerRow': headerRow,
        'continuesFrom': continuesFrom,
        'repeatedHeader': repeatedHeader,
        if (continuesRow) 'continuesRow': true,
        'cells': [for (final c in cells) c.toJson()],
      };
}

class Block {
  final String id;
  final BlockLabel label;
  final List<Line> lines;
  final Box box;
  final Table? table;
  const Block(this.id, this.label, this.lines, this.box, {this.table});

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label.name,
        'box': box.toJson(),
        'lines': [for (final l in lines) l.id],
        if (table != null) 'table': table!.toJson(),
      };
}

class DsPage {
  final int number;
  final double width, height; // displayed size
  final int rotation; // the PDF's /Rotate
  final int readingRotation; // 0/90/180/270: how far the text is turned in the display frame
  final List<Word> words; // reading order
  final List<Line> lines; // top to bottom
  final List<Block> blocks; // reading order: page headers, body, page footers
  const DsPage(this.number, this.width, this.height, this.rotation, this.readingRotation, this.words, this.lines,
      this.blocks);

  Iterable<Table> get tables => blocks.where((b) => b.table != null).map((b) => b.table!);

  /// Maps a reading-frame box back to the display frame (for overlays).
  Box toDisplay(Box b) => switch (readingRotation) {
        90 => Box(width - b.bottom, b.left, width - b.top, b.right),
        180 => Box(width - b.right, height - b.bottom, width - b.left, height - b.top),
        270 => Box(b.top, height - b.right, b.bottom, height - b.left),
        _ => b,
      };

  Map<String, Object?> toJson() => {
        'number': number,
        'width': q(width),
        'height': q(height),
        'rotation': rotation,
        'readingRotation': readingRotation,
        'words': [for (final w in words) w.toJson()],
        'lines': [for (final l in lines) l.toJson()],
        'blocks': [for (final b in blocks) b.toJson()],
      };
}

class DsDocument {
  final List<DsPage> pages;
  const DsDocument(this.pages);

  Iterable<Table> get tables => pages.expand((p) => p.tables);

  Map<String, Object?> toJson() => {'pages': [for (final p in pages) p.toJson()]};

  /// Canonical JSON: fixed key order, coordinates at 0.01 pt. Same input -> same string.
  String toCanonicalJson() => jsonEncode(toJson());
}
