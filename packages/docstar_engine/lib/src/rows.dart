/// Group table lines into transaction rows (top/bottom anchored, amount-closing, grid).
///
/// Name table (Python -> Dart): detect_mode -> detectMode, grid_groups -> gridGroups,
/// assemble_grid -> assembleGrid. `mode` stays a `Map<String, dynamic>` for JSON parity.
library;

import 'extract.dart';
import 'layout.dart';
import 'numbers.dart';
import 'py.dart';

const txnAmountRoles = ['debit', 'credit', 'amount', 'amount2'];

/// A table line with its parsed features.
class TLine {
  final Line line;
  final Cells cells;
  final DateHit? date, vdate;
  final String? special;
  final bool hasAmt, hasBal;
  final int section;
  int? direction; // section heading direction for single-amount layouts

  TLine(this.line, this.cells, this.date, this.vdate, this.special, this.hasAmt, this.hasBal, this.section, [this.direction]);

  bool get isAnchor => date != null;

  String get kind {
    if (special != null) return 'S';
    if (date != null) return 'A';
    if (hasAmt || hasBal) return 'N';
    return 'T';
  }
}

class Row {
  List<TLine> tlines;
  String? special;
  bool dateCarried;
  String kind; // txn | special | info

  Row(this.tlines, {this.special, this.dateCarried = false, this.kind = 'txn'});

  void add(TLine t) => tlines.add(t);

  bool get hasAmt => tlines.any((t) => t.hasAmt);
  bool get hasBal => tlines.any((t) => t.hasBal);

  DateHit? get date {
    for (final t in tlines) {
      if (t.date != null) return t.date;
    }
    return null;
  }

  int get section => tlines.isNotEmpty ? tlines.first.section : 0;

  int get page {
    for (final t in tlines) {
      if (t.date != null || t.hasAmt) return t.line.page;
    }
    return tlines.first.line.page;
  }
}

// ------------------------------------------------------------------ mode detection

/// Decide anchor position (top/bottom) and whether amounts close a row.
Map<String, dynamic> detectMode(List<TLine> tls) {
  final txn = [for (final t in tls) if (t.special == null) t];
  final a = [for (final t in txn) if (t.kind == 'A') t];
  if (a.isEmpty) return {'anchor': 'top', 'amt_close': false, 'evidence': <String, dynamic>{}};
  final aWithAmt = a.where((t) => t.hasAmt || t.hasBal).length / a.length;
  final n = txn.where((t) => t.kind == 'N').length;
  var amtClose = aWithAmt < 0.5 && n >= 0.5 * a.length;

  var evTop = 0.0, evBot = 0.0;
  // 1) wrap fullness of the description cell, measured against the observed wrap edge
  final xs = [for (final t in txn) if (t.cells.descX1 > 0) t.cells.descX1]..sort();
  if (xs.length >= 4) {
    final edge = xs[(0.9 * (xs.length - 1)).truncate()];
    final left = tls.isEmpty ? 0.0 : tls.map((t) => t.line.x0).reduce((p, q) => p < q ? p : q);
    final width = edge - left > 40.0 ? edge - left : 40.0;
    bool full(TLine t) => t.cells.descX1 > 0 && t.cells.descX1 >= edge - 0.15 * width;
    for (var i = 0; i + 1 < txn.length; i++) {
      final t = txn[i], nx = txn[i + 1];
      if (t.kind == 'A' && nx.kind == 'T' && full(t) && !full(nx)) evTop += 1;
      if (t.kind == 'T' && nx.kind == 'A' && full(t) && !full(nx)) evBot += 1;
    }
  }
  // 2) gaps: a continuation sits closer to the line it belongs to
  for (var i = 1; i < txn.length - 1; i++) {
    final t = txn[i];
    if (t.kind != 'T') continue;
    final p = txn[i - 1], nx = txn[i + 1];
    if (p.line.page != t.line.page || nx.line.page != t.line.page) continue;
    final ga = t.line.top - p.line.bottom;
    final gb = nx.line.top - t.line.bottom;
    if (p.kind == 'A' && nx.kind == 'A') {
      if (ga + 0.8 < gb) {
        evTop += 0.5;
      } else if (gb + 0.8 < ga) {
        evBot += 0.5;
      }
    }
  }
  // 3) first / last line of each page stretch
  final byPage = <int, List<TLine>>{};
  for (final t in txn) {
    byPage.putIfAbsent(t.line.page, () => []).add(t);
  }
  final pages = byPage.keys.toList()..sort();
  if (pages.isNotEmpty) {
    final first = byPage[pages.first]!;
    if (first.isNotEmpty && first.first.kind == 'T') evBot += 1;
    final last = byPage[pages.last]!;
    if (last.isNotEmpty && last.last.kind == 'T') evTop += 1;
  }
  final anchor = evBot > evTop * 1.2 && evBot >= 1.5 ? 'bottom' : 'top';
  if (anchor == 'bottom') amtClose = false;
  return {
    'anchor': anchor,
    'amt_close': amtClose,
    'evidence': {'top': evTop, 'bottom': evBot, 'a_with_amt': pyRound(aWithAmt, 2)},
  };
}

// ------------------------------------------------------------------ assembly

List<Row> assemble(List<TLine> tls, Map<String, dynamic> mode) {
  final rows = <Row>[];
  final anchor = mode['anchor'] as String, amtClose = mode['amt_close'] as bool;
  Row? cur;
  var pending = <TLine>[];

  void flush() {
    if (cur != null && cur!.tlines.isNotEmpty) rows.add(cur!);
    cur = null;
  }

  void specialRow(TLine t) => rows.add(Row([t], special: t.special, kind: 'special'));

  if (anchor == 'bottom') {
    for (final t in tls) {
      switch (t.kind) {
        case 'S':
          if (pending.isNotEmpty) {
            _attachOrphans(rows, pending);
            pending = [];
          }
          specialRow(t);
        case 'T':
          pending.add(t);
        case 'A':
          rows.add(Row([...pending, t]));
          pending = [];
        default: // N: amount without date -> same-day row
          rows.add(Row([...pending, t], dateCarried: true));
          pending = [];
      }
    }
    if (pending.isNotEmpty) _attachOrphans(rows, pending);
    return _post(rows, anchor);
  }

  for (var i = 0; i < tls.length; i++) {
    final t = tls[i];
    final k = t.kind;
    if (k == 'S') {
      flush();
      specialRow(t);
      continue;
    }
    if (k == 'A') {
      flush();
      cur = Row([t]);
      continue;
    }
    if (k == 'N') {
      if (cur != null && !cur!.hasAmt) {
        cur!.add(t);
      } else {
        flush();
        cur = Row([t], dateCarried: true);
      }
      continue;
    }
    // T line
    if (cur == null) {
      if (rows.isNotEmpty && rows.last.kind == 'txn') {
        rows.last.add(t); // tail of a row split by a page break / special row
      } else {
        cur = Row([t], dateCarried: true);
      }
      continue;
    }
    if (amtClose && cur!.hasAmt) {
      // row already closed: either a trailing reference line, or the start of a same-day row
      if (_nextKind(tls, i) == 'N') {
        flush();
        cur = Row([t], dateCarried: true);
      } else {
        cur!.add(t);
      }
      continue;
    }
    cur!.add(t);
  }
  flush();
  return _post(rows, anchor);
}

String? _nextKind(List<TLine> tls, int i) {
  for (var j = i + 1; j < tls.length; j++) {
    if (tls[j].kind != 'T') return tls[j].kind;
  }
  return null;
}

void _attachOrphans(List<Row> rows, List<TLine> orphans) {
  for (final r in rows.reversed) {
    if (r.kind == 'txn') {
      r.tlines.addAll(orphans);
      return;
    }
  }
  rows.add(Row([...orphans], dateCarried: true));
}

/// Merge text-only fragments (no amount, no balance) into their neighbour; mark info rows.
List<Row> _post(List<Row> rows, String anchor) {
  var out = <Row>[];
  for (final r in rows) {
    if (r.kind == 'txn' && !r.hasAmt && !r.hasBal) {
      if (r.date == null) {
        // pure text fragment
        final target = (anchor == 'top' && out.isNotEmpty && out.last.kind == 'txn') ? out.last : null;
        if (target != null) {
          target.tlines.addAll(r.tlines);
          continue;
        }
        out.add(r);
        continue;
      }
      r.kind = 'info'; // dated line with no money: 'Interest Rate ...', memo rows
    }
    out.add(r);
  }
  if (anchor == 'bottom') {
    // text fragments with no date that ended up first: glue to the next txn row
    final merged = <Row>[];
    var carry = <TLine>[];
    for (final r in out) {
      if (r.kind == 'txn' && !r.hasAmt && !r.hasBal && r.date == null) {
        carry.addAll(r.tlines);
        continue;
      }
      if (carry.isNotEmpty && r.kind == 'txn') {
        r.tlines = [...carry, ...r.tlines];
        carry = [];
      }
      merged.add(r);
    }
    if (carry.isNotEmpty && merged.isNotEmpty) merged.last.tlines.addAll(carry);
    out = merged;
  }
  return out;
}

// ------------------------------------------------------------------ grid mode

/// If the table is ruled row-by-row, group lines by the rule band they fall in.
List<List<TLine>>? gridGroups(Document doc, List<TLine> tls) {
  final byPage = <int, List<TLine>>{};
  for (final t in tls) {
    byPage.putIfAbsent(t.line.page, () => []).add(t);
  }
  final groups = <List<TLine>>[];
  var ruledPages = 0;
  for (final pno in (byPage.keys.toList()..sort())) {
    final pts = byPage[pno]!;
    final page = doc.pages[pno - 1];
    final x0 = pts.map((t) => t.line.x0).reduce((a, b) => a < b ? a : b);
    final x1 = pts.map((t) => t.line.x1).reduce((a, b) => a > b ? a : b);
    final width = x1 - x0;
    final ys = {
      for (final (y, a, b) in page.hrules)
        if ((b < x1 ? b : x1) - (a > x0 ? a : x0) > 0.12 * width) pyRound(y, 1),
    }.toList()
      ..sort();
    // cluster near-identical ys
    final cl = <double>[];
    for (final y in ys) {
      if (cl.isEmpty || y - cl.last > 2.0) cl.add(y);
    }
    final top = pts.map((t) => t.line.top).reduce((a, b) => a < b ? a : b);
    final bot = pts.map((t) => t.line.bottom).reduce((a, b) => a > b ? a : b);
    final inner = cl.where((y) => top - 2 <= y && y <= bot + 2).length;
    final need = pts.length ~/ 4 > 3 ? pts.length ~/ 4 : 3;
    if (inner < need) {
      // not ruled per row on this page
      for (final t in pts) {
        groups.add([t]);
      }
      continue;
    }
    ruledPages++;
    final bands = <int, List<TLine>>{};
    for (final t in pts) {
      final yc = (t.line.top + t.line.bottom) / 2;
      final band = cl.where((y) => y < yc).length;
      bands.putIfAbsent(band, () => []).add(t);
    }
    for (final b in (bands.keys.toList()..sort())) {
      groups.add(bands[b]!);
    }
  }
  return ruledPages == 0 ? null : groups;
}

List<Row> assembleGrid(List<List<TLine>> groups, String anchor) {
  final rows = <Row>[];
  for (final g in groups) {
    final specials = g.where((t) => t.special != null);
    if (specials.isNotEmpty) {
      for (final t in specials) {
        rows.add(Row([t], special: t.special, kind: 'special'));
      }
      continue;
    }
    final nAnchor = g.where((t) => t.kind == 'A').length;
    final nAmt = g.where((t) => t.hasAmt).length;
    if (nAnchor > 1 || nAmt > 1) {
      // band holds several rows: fall back to anchor logic inside it
      rows.addAll(assemble(g, {'anchor': anchor, 'amt_close': false}));
      continue;
    }
    rows.add(Row([...g]));
  }
  // a row cut by a page break: fragment without date/amount joins its neighbour
  final out = <Row>[];
  var carry = <TLine>[];
  for (final r in rows) {
    if (r.kind == 'txn' && r.date == null && !r.hasAmt && !r.hasBal) {
      if (anchor == 'top' && out.isNotEmpty && out.last.kind == 'txn') {
        out.last.tlines.addAll(r.tlines);
      } else {
        carry.addAll(r.tlines);
      }
      continue;
    }
    if (carry.isNotEmpty && r.kind == 'txn') {
      r.tlines = [...carry, ...r.tlines];
      carry = [];
    }
    out.add(r);
  }
  if (carry.isNotEmpty && out.isNotEmpty) out.last.tlines.addAll(carry);
  return out;
}
