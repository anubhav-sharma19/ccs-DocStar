/// Page furniture, column-header detection, column model and word->cell assignment.
///
/// Name table (Python -> Dart): detect_headers -> detectHeaders, detect_furniture -> detectFurniture,
/// join_numeric_fragments -> joinNumericFragments, assign_cells -> assignCells, compute_cuts -> computeCuts,
/// refine_numeric_anchors -> refineNumericAnchors.
library;

import 'dart:math' as math;

import 'extract.dart';
import 'lexicon.dart' as lx;
import 'numbers.dart';
import 'py.dart';

// ===================================================================== header detection

class Column {
  String role;
  final double x0, x1;
  final String text;
  double? anchor; // data-derived right edge for numeric columns
  Column(this.role, this.x0, this.x1, [this.text = '', this.anchor]);

  double get center => (x0 + x1) / 2;
  bool get numeric => lx.numericRoles.contains(role);
  double get right => anchor ?? x1;
}

class ColumnModel {
  final List<Column> cols;
  final List<int> headerLines; // line idx
  final int page;
  List<double>? cuts; // data-driven boundaries (len = n-1)
  ColumnModel(this.cols, [this.headerLines = const [], this.page = 0]);

  List<String> roles() => [for (final c in cols) c.role];
  String signature() => roles().join('|');

  Column? get(String role) {
    for (final c in cols) {
      if (c.role == role) return c;
    }
    return null;
  }

  double cut(int i) {
    if (cuts != null) return cuts![i];
    final a = cols[i], b = cols[i + 1];
    // text after a column starts at (or slightly before) its header's left edge
    return b.x0 > a.x1 ? math.max(a.x0 + 4, math.min((a.x1 + b.x0) / 2, b.x0 - 2)) : (a.x1 + b.x0) / 2;
  }

  /// Left/right band for each column.
  List<(double, double)> bounds() {
    final n = cols.length;
    return [
      for (var i = 0; i < n; i++) (i == 0 ? -1e9 : cut(i - 1), i == n - 1 ? 1e9 : cut(i)),
    ];
  }
}

/// 'DEPOSITSWITHDRAWALS' / 'DateParticulars' -> words for each known header phrase.
List<Word>? _splitGlued(Word w) {
  final sq = lx.squash(w.text);
  if (sq.length < 7 || lx.phrases.any((p) => p.$1 == sq)) return null;
  final n = sq.length;
  final best = List<List<String>?>.filled(n + 1, null);
  best[0] = [];
  final known = {for (final (p, _) in lx.phrases) if (p.length >= 2) p};
  for (var i = 0; i < n; i++) {
    if (best[i] == null) continue;
    for (var j = i + 2; j <= n; j++) {
      if (known.contains(sq.substring(i, j)) && (best[j] == null || best[j]!.length > best[i]!.length + 1)) {
        best[j] = [...best[i]!, sq.substring(i, j)];
      }
    }
  }
  final parts = best[n];
  if (parts == null || parts.length < 2) return null;
  final roles = [for (final prt in parts) lx.phrases.firstWhere((e) => e.$1 == prt).$2];
  if (roles.toSet().length < 2) return null; // 'Paid In' style phrase, not two glued columns
  final out = <Word>[];
  var x = w.x0;
  final per = (w.x1 - w.x0) / n;
  for (final prt in parts) {
    final x1 = x + per * prt.length;
    out.add(Word(prt, x, x1, w.top, w.bottom, w.size, w.bold));
    x = x1;
  }
  return out;
}

/// Greedy longest-phrase matching over one header line: (i, jExclusive, role).
///
/// Multi-word spans must match a known phrase exactly (modifiers like 'Amt.'/'(INR)' are
/// attached afterwards); fuzzy/prefix matching is only used for single words.
List<(int, int, String?)> _phraseSpans(List<Word> words) {
  final spans = <(int, int, String?)>[];
  var i = 0;
  final n = words.length;
  while (i < n) {
    (int, int, String?)? best;
    for (var j = math.min(n, i + 5); j > i + 1; j--) {
      var maxGap = -double.infinity;
      for (var k = i; k < j - 1; k++) {
        maxGap = math.max(maxGap, words[k + 1].x0 - words[k].x1);
      }
      if (maxGap > 1.6 * math.max(5.0, words[i].size)) continue;
      final sq = lx.squash(words.sublist(i, j).map((w) => w.text).join(' '));
      for (final (p, rr) in lx.phrases) {
        if (p == sq) {
          best = (i, j, rr);
          break;
        }
      }
      if (best != null) break;
    }
    best ??= (i, i + 1, lx.headerRole(words[i].text));
    spans.add(best);
    i = best.$2;
  }
  final out = <(int, int, String?)>[];
  for (final sp in spans) {
    if (sp.$3 == null &&
        out.isNotEmpty &&
        out.last.$3 != null &&
        lx.headerModifiers.hasMatch(words[sp.$1].text) &&
        words[sp.$1].x0 - words[out.last.$2 - 1].x1 < 1.6 * math.max(5.0, words[sp.$1].size)) {
      out[out.length - 1] = (out.last.$1, sp.$2, out.last.$3);
    } else {
      out.add(sp);
    }
  }
  return out;
}

bool _isDataLine(Line line) {
  for (final w in line.words) {
    if (looksLikeAmount(w.text)) return true;
  }
  return findDates(line.text).any((h) => h.y != null);
}

List<Word> _expandGlued(List<Word> words) => [
      for (final w in words) ...(_splitGlued(w) ?? [w]),
    ];

class _Unit {
  final List<Word> words;
  final String? role;
  final double top;
  _Unit(this.words, this.role, this.top);
  double get x0 => words.first.x0;
  double get x1 => words.last.x1;
  String get text => words.map((w) => w.text).join(' ');
}

List<_Unit> _units(Line line) {
  final ws = _expandGlued(line.words);
  return [for (final (i, j, r) in _phraseSpans(ws)) _Unit(ws.sublist(i, j), r, line.top)];
}

/// Stack header units of 1-3 lines into columns by horizontal overlap.
List<Column> _stack(List<Line> lines) {
  final stacks = <List<_Unit>>[];
  final sorted = [...lines];
  stableSort(sorted, (a, b) => a.top.compareTo(b.top));
  for (final ln in sorted) {
    for (final u in _units(ln)) {
      List<_Unit>? best;
      var bo = 0.0;
      for (final st in stacks) {
        final sx0 = st.map((x) => x.x0).reduce(math.min);
        final sx1 = st.map((x) => x.x1).reduce(math.max);
        if (st.any((x) => (x.top - u.top).abs() < 1)) continue; // same visual line -> different column
        final ov = math.min(u.x1, sx1) - math.max(u.x0, sx0);
        final cen = (u.x0 + u.x1) / 2;
        final scen = (sx0 + sx1) / 2;
        final minw = math.max(1.0, math.min(u.x1 - u.x0, sx1 - sx0));
        if (ov > 0.3 * minw || (sx0 - 3 <= cen && cen <= sx1 + 3) || (u.x0 - 3 <= scen && scen <= u.x1 + 3)) {
          if (ov > bo || best == null) {
            best = st;
            bo = ov;
          }
        }
      }
      if (best != null) {
        best.add(u);
      } else {
        stacks.add([u]);
      }
    }
  }
  final cols = <Column>[];
  for (final st in stacks) {
    stableSort(st, (a, b) => a.top != b.top ? a.top.compareTo(b.top) : a.x0.compareTo(b.x0));
    final text = st.map((u) => u.text).join(' ');
    var role = lx.headerRole(text);
    if (role == null) {
      final roles = [for (final u in st) if (u.role != null) u.role!];
      role = roles.isEmpty ? null : roles.last;
    }
    cols.add(Column(role ?? '?', st.map((u) => u.x0).reduce(math.min), st.map((u) => u.x1).reduce(math.max), text));
  }
  stableSort(cols, (a, b) => a.x0.compareTo(b.x0));
  return cols;
}

int _scoreCols(List<Column> cols) {
  final real = cols.where((c) => c.role != '?').toList();
  if (real.length >= 2) {
    // columns of a table are spread out; a sentence/title has normal word spacing
    final gaps = [for (var i = 0; i + 1 < real.length; i++) real[i + 1].x0 - real[i].x1];
    if (real.length == 2 && gaps.reduce(math.min) < 25) return 0;
    if (real.length >= 3) {
      final s = [...gaps]..sort();
      if (s[gaps.length ~/ 2] < 7) return 0;
    }
  }
  final strong = {
    for (final c in cols)
      if (c.role != '?' && c.role != 'other' && !lx.weakTokens.contains(lx.squash(c.text))) c.role,
  };
  final weak = {
    for (final c in cols)
      if (c.role != '?' && lx.weakTokens.contains(lx.squash(c.text))) c.role,
  };
  final roles = {...strong, if (strong.length >= 2) ...weak};
  final unknown = cols.where((c) => c.role == '?').length;
  final hasNum = roles.any(lx.numericRoles.contains);
  final hasAnchor = roles.any(const {'date', 'vdate', 'desc'}.contains);
  if (!(hasNum && hasAnchor && roles.length >= 2)) return 0;
  if (unknown > math.max(2, cols.length ~/ 2)) return 0;
  return roles.length;
}

typedef _Block = (int, List<Column>?, int);

_Block _bestBlock(List<Line> lines, int k) {
  final ln = lines[k];
  if (_isDataLine(ln) || ln.words.length > 16 || !_units(ln).any((u) => u.role != null)) return (0, null, 0);
  var block = [ln];
  _Block best = (0, null, 0);
  for (var size = 1; size <= 3; size++) {
    if (size > 1) {
      if (k + size - 1 >= lines.length) break;
      final nb = lines[k + size - 1];
      final h = math.max(block.last.height, 6);
      final bold = block.expand((b) => b.words).where((w) => w.bold).length;
      final total = block.fold(0, (s, b) => s + b.words.length);
      final blkBold = bold >= 0.6 * total;
      if (nb.top - block.last.bottom > 1.3 * h ||
          _isDataLine(nb) ||
          nb.words.length > 16 ||
          findDates(nb.text).isNotEmpty ||
          lx.openRx.hasMatch(nb.text) ||
          lx.closeRx.hasMatch(nb.text) ||
          lx.totalRx.hasMatch(nb.text) ||
          (blkBold && !nb.words.every((w) => w.bold))) {
        break;
      }
      block = [...block, nb];
    }
    final cols = _stack(block);
    final sc = _scoreCols(cols);
    if (sc > best.$1) best = (sc, cols, size);
  }
  return best;
}

bool _allBold(List<Line> blk) {
  final bold = blk.expand((b) => b.words).where((w) => w.bold).length;
  return bold >= 0.6 * blk.fold(0, (s, b) => s + b.words.length);
}

bool _overHeader(Word w, List<Column> cols) => cols.any((c) => !(w.x1 < c.x0 - 4 || w.x0 > c.x1 + 4));

/// Find column-header blocks (1-3 stacked lines). Returns {firstLineIdx: ColumnModel}.
Map<int, ColumnModel> detectHeaders(Document doc) {
  final found = <int, ColumnModel>{};
  for (final pg in doc.pages) {
    final lines = pg.lines;
    var k = 0;
    while (k < lines.length) {
      var (sc, cols, size) = _bestBlock(lines, k);
      if (sc >= 2 && k + 1 < lines.length) {
        // the first line must add something: if the block starting one line lower is as good, skip it
        final sc2 = _bestBlock(lines, k + 1).$1;
        var heading = lx.sectionCreditRx.hasMatch(lines[k].text) || lx.sectionDebitRx.hasMatch(lines[k].text);
        if (heading && cols != null) {
          // a section heading starts at the table's left edge; a wrapped label sits over its column
          final left = cols.map((c) => c.x0).reduce(math.min);
          heading = lines[k].x0 <= left + 15;
        }
        if (sc2 >= sc || heading) {
          k++;
          continue;
        }
      }
      if (sc >= 2) {
        var blk = lines.sublist(k, math.min(k + size, lines.length));
        var cs = cols!;
        // absorb a label-only line just above (wrapped header text like 'Init.' / 'Transaction')
        if (k > 0) {
          final up = lines[k - 1];
          final h = math.max(blk[0].height, 6);
          final hb = _allBold(blk);
          if (blk[0].top - up.bottom < 1.0 * h &&
              up.kind != 'header' &&
              !_isDataLine(up) &&
              up.words.length <= 6 &&
              !lx.sectionCreditRx.hasMatch(up.text) &&
              !lx.sectionDebitRx.hasMatch(up.text) &&
              findDates(up.text).isEmpty &&
              (up.words.every((w) => _overHeader(w, cs)) || (hb && up.words.every((w) => w.bold) && up.words.length <= 4))) {
            blk = [up, ...blk];
            cs = _stack(blk);
          }
        }
        // ... and label-only lines just below ('(INR)', 'Amt.', 'Date')
        while (true) {
          final nxtI = lines.indexOf(blk.last) + 1;
          if (nxtI >= lines.length) break;
          final dn = lines[nxtI];
          final h = math.max(blk.last.height, 6);
          final hdrBold = _allBold(blk);
          if (dn.top - blk.last.bottom < 1.0 * h &&
              !_isDataLine(dn) &&
              findDates(dn.text).isEmpty &&
              dn.words.length <= 8 &&
              ((dn.words.every((w) => lx.headerModifiers.hasMatch(w.text) || lx.headerRole(w.text) != null) &&
                      dn.words.every((w) => _overHeader(w, cs))) ||
                  (hdrBold && dn.words.every((w) => w.bold) && dn.words.length <= 6))) {
            blk = [...blk, dn];
            cs = _stack(blk);
          } else {
            break;
          }
        }
        cs = cs.where((c) => c.role != '?').toList();
        final seen = <String, int>{};
        for (final c in cs) {
          seen[c.role] = (seen[c.role] ?? 0) + 1;
          if (seen[c.role]! > 1) {
            c.role = const {'date': 'vdate', 'desc': 'desc2', 'amount': 'amount2'}[c.role] ?? '${c.role}${seen[c.role]}';
          }
        }
        if (!cs.any((c) => c.role == 'date')) {
          for (final c in cs) {
            if (c.role == 'vdate') {
              c.role = 'date';
              break;
            }
          }
        }
        if (cs.length >= 2) {
          found[blk[0].idx] = ColumnModel(cs, [for (final b in blk) b.idx], pg.number);
          for (final b in blk) {
            b.kind = 'header';
          }
          k = lines.indexOf(blk.last) + 1;
          continue;
        }
      }
      k++;
    }
  }
  return found;
}

// ===================================================================== furniture

final _digits = RegExp(r'\d');
final _hashes = RegExp(r'#+');

String _mask(String text) => lx.norm(text).replaceAll(_digits, '#').replaceAll(_hashes, '#');

bool _txnLike(Line ln) {
  final head = ln.words.take(3).map((w) => w.text).join(' ');
  if (findDates(head).isEmpty) return false;
  return ln.words.skip(1).any((w) => looksLikeAmount(w.text));
}

void detectFurniture(Document doc) {
  final n = doc.pages.length;
  final sigPages = <String, Set<int>>{};
  final sigs = <int, List<String>>{};
  for (final pg in doc.pages) {
    for (final ln in pg.lines) {
      if (ln.kind == 'header') continue;
      final m = _mask(ln.text);
      // y bucket relative to page height; repeated blocks drift only a little
      final keys = [
        '$m@${(ln.top / 4).floor()}',
        '$m@${((ln.top + 2) / 4).floor()}',
        '$m@B${((pg.height - ln.bottom) / 4).floor()}',
        '$m@B${((pg.height - ln.bottom + 2) / 4).floor()}',
      ];
      sigs[ln.idx] = keys;
      for (final k in keys) {
        sigPages.putIfAbsent(k, () => {}).add(pg.number);
      }
    }
  }
  final need = math.max(2, (0.5 * n).ceil());
  // where each page's column header ends; text above a header is the page's letterhead
  final hdrBottom = <int, double?>{};
  for (final pg in doc.pages) {
    final hs = [for (final l in pg.lines) if (l.kind == 'header') l.bottom];
    hdrBottom[pg.number] = hs.isEmpty ? null : hs.reduce(math.max);
  }
  final preHeader = <String>{};
  for (final pg in doc.pages) {
    final hb = hdrBottom[pg.number];
    if (hb != null) {
      for (final ln in pg.lines) {
        if (ln.bottom < hb && ln.kind != 'header') preHeader.add(_mask(ln.text));
      }
    }
  }
  for (final pg in doc.pages) {
    final hb = hdrBottom[pg.number];
    for (final ln in pg.lines) {
      if (ln.kind == 'header') continue;
      final t = ln.text;
      if (lx.pageMarkerRx.hasMatch(t) || lx.continuedRx.hasMatch(t) || lx.synthWatermarkRx.hasMatch(t)) {
        ln.kind = 'furniture';
        continue;
      }
      final bool topOk;
      if (hb != null) {
        topOk = ln.bottom <= hb + 1;
      } else {
        topOk = ln.top < 0.35 * pg.height && preHeader.contains(_mask(ln.text));
      }
      var bottomOk = false;
      if (ln.bottom > 0.85 * pg.height) {
        // a footer sits below every transaction on the page and is set apart from the line above it
        final belowTxn = !pg.lines.any((o) => o.top > ln.bottom && _txnLike(o));
        final above = [for (final o in pg.lines) if (o.bottom <= ln.top + 0.5 && !identical(o, ln)) o.bottom];
        final gap = above.isNotEmpty ? ln.top - above.reduce(math.max) : 99.0;
        bottomOk = belowTxn && (gap > 1.3 * math.max(6.0, ln.height) || ln.bottom > 0.93 * pg.height);
      }
      final inBand = topOk || bottomOk;
      final reps = sigs[ln.idx]!.map((k) => sigPages[k]!.length).reduce(math.max);
      final dated = findDates(ln.words.take(3).map((w) => w.text).join(' ')).isNotEmpty;
      if (n >= 2 && reps >= need && inBand && !dated) {
        if (lx.openRx.hasMatch(t) || lx.closeRx.hasMatch(t)) continue; // B/F and C/F rows repeat every page but carry balances
        if (_txnLike(ln)) continue; // a dated line with money is a transaction, however often it repeats
        if (_mask(t).length <= 2) continue;
        ln.kind = 'furniture';
      }
    }
  }
}

// ===================================================================== cell assignment

final _suffixWord = RegExp(r'^(\(?(dr|cr)\)?\.?|d|[+-]|\([+-]\))$', caseSensitive: false);
final _fragLeft = RegExp(r'^[-(]?[₹$£€R]?\d{1,3}([.,\s]\d{3})*[.,]?$');
final _fragRight = RegExp(r'^(\d{3}([.,\s]\d{3})*([.,]\d{1,3})?|\d{1,2})\)?(\s?(dr|cr|-|\+))?$', caseSensitive: false);
final _loneSign = RegExp(r'^[+\-−]$');
final _signPrefix = RegExp(r'^[+\-−]\s?[$£€₹R]?$');
final _endsSuffix = RegExp(r'(dr|cr|[-+)])$', caseSensitive: false);

/// Re-join '1 234.56', '10,885. 53', '2 00.00' and detached 'Cr'/'Dr'/'-' suffixes.
List<Word> joinNumericFragments(List<Word> words, bool spaceGrouped) {
  final out = <Word>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final nxt = i + 1 < words.length ? words[i + 1] : null;
    // a lone sign that sits closer to the NEXT number is that number's prefix ('+ 400.00')
    if (_loneSign.hasMatch(w.text) && nxt != null && parseAmount(nxt.text) != null) {
      final gapNext = nxt.x0 - w.x1;
      final gapPrev = out.isNotEmpty ? w.x0 - out.last.x1 : 1e9;
      if (gapNext < 1.2 * math.max(6.0, w.size) && gapNext <= gapPrev) {
        out.add(Word(w.text, w.x0, w.x1, w.top, w.bottom, w.size, w.bold));
        continue;
      }
    }
    if (out.isNotEmpty) {
      final p = out.last;
      final gap = w.x0 - p.x1;
      final sz = math.max(6.0, math.min(p.size, w.size));
      if (_signPrefix.hasMatch(p.text) && gap < 1.2 * sz && parseAmount(w.text) != null) {
        out[out.length - 1] = Word(p.text.trim() + w.text, p.x0, w.x1, p.top, p.bottom, p.size, p.bold);
        continue;
      }
      final numericPrev = _digits.hasMatch(p.text) && parseAmount(p.text) != null;
      if (numericPrev && _suffixWord.hasMatch(w.text) && gap < 1.6 * sz && !_endsSuffix.hasMatch(p.text)) {
        out[out.length - 1] = Word(w.text.length > 1 ? '${p.text} ${w.text}' : p.text + w.text, p.x0, w.x1, p.top, p.bottom, p.size, p.bold);
        continue;
      }
      if (gap < 0.8 * sz && _fragLeft.hasMatch(p.text) && _fragRight.hasMatch(w.text)) {
        final decimalSplit = '.,'.contains(p.text[p.text.length - 1]) && RegExp(r'^\d{1,2}$').hasMatch(w.text);
        final thousandSplit = spaceGrouped && RegExp(r'^\d{3}').hasMatch(w.text) && !RegExp(r'[.,]\d{1,2}$').hasMatch(p.text);
        if (decimalSplit || thousandSplit) {
          out[out.length - 1] = Word('${p.text} ${w.text}', p.x0, w.x1, p.top, p.bottom, p.size, p.bold);
          continue;
        }
      }
    }
    out.add(w);
  }
  return out;
}

class Cells {
  final Map<String, List<String>> text = {}; // role -> text pieces
  final Map<String, List<(Amount, Word)>> nums = {}; // role -> [(Amount, Word)]
  String dateText = '';
  String vdateText = '';
  double descX1 = 0.0;
}

const _blankInAmountBand = {'-', 'blank.', 'blank', 'n/a', 'nil', '–', '0'};

Cells assignCells(Line line, ColumnModel cm, String locale, bool spaceGrouped) {
  final words = joinNumericFragments(line.words, spaceGrouped);
  final bounds = cm.bounds();
  final cells = Cells();
  final numericCols = cm.cols.where((c) => c.numeric).toList();
  for (final w in words) {
    final amt = _digits.hasMatch(w.text) ? parseAmount(w.text, locale) : null;
    var placed = false;
    if (amt != null && looksLikeAmount(w.text, requireDecimals: false)) {
      Column? best;
      var bd = 1e9;
      for (final c in numericCols) {
        final tol = math.max(22.0, 0.6 * (c.x1 - c.x0));
        final d = [(w.x1 - c.right).abs(), (w.xc - c.center).abs(), (w.x1 - c.x1).abs()].reduce(math.min);
        final inside = c.x0 - 4 <= w.xc && w.xc <= c.x1 + 4;
        if ((d < tol || inside) && d < bd) {
          best = c;
          bd = d;
        }
      }
      if (best != null) {
        // integers only count in amount bands when right-aligned with the column
        if (amt.integer && amt.sign == null && (w.x1 - best.right).abs() > 6 && !(best.x0 - 2 <= w.x0 && w.x1 <= best.x1 + 2)) {
          best = null;
        }
      }
      if (best != null) {
        cells.nums.putIfAbsent(best.role, () => []).add((amt, w));
        placed = true;
      }
    }
    if (placed) continue;
    // text: band by left edge (left-aligned text), fallback centre
    String? role;
    for (var i = 0; i < cm.cols.length; i++) {
      if (bounds[i].$1 <= w.x0 && w.x0 < bounds[i].$2) {
        role = cm.cols[i].role;
        break;
      }
    }
    role ??= cm.cols.last.role;
    if (lx.numericRoles.contains(role)) {
      // text inside an amount band: placeholder ('-', 'blank.') or narration overflow
      if (_blankInAmountBand.contains(w.text.trim().toLowerCase())) continue;
      // narration that overflowed right: give it to the nearest text column on the left
      final leftText = cm.cols.where((c) => c.x1 <= w.x0 + 1 && !lx.numericRoles.contains(c.role)).toList();
      role = leftText.isNotEmpty ? leftText.last.role : 'desc';
    }
    if (role == 'date') {
      cells.dateText += (cells.dateText.isNotEmpty ? ' ' : '') + w.text;
    } else if (role == 'vdate') {
      cells.vdateText += (cells.vdateText.isNotEmpty ? ' ' : '') + w.text;
    } else {
      cells.text.putIfAbsent(role, () => []).add(w.text);
      if (role == 'desc') cells.descX1 = math.max(cells.descX1, w.x1);
    }
  }
  return cells;
}

/// Place column boundaries in the empty vertical gutters between printed values.
void computeCuts(List<Line> lines, ColumnModel cm) {
  if (cm.cols.length < 2 || lines.length < 3) return;
  final lo = lines.map((l) => l.x0).reduce(math.min).truncate() - 2;
  final hi = lines.map((l) => l.x1).reduce(math.max).truncate() + 2;
  final cov = List<int>.filled(hi - lo + 1, 0);
  for (final l in lines) {
    final seen = <int>{};
    for (final w in l.words) {
      for (var x = w.x0.truncate() - lo; x <= w.x1.truncate() - lo; x++) {
        if (x >= 0 && x < cov.length && seen.add(x)) cov[x]++;
      }
    }
  }
  final thr = math.max(0, (0.02 * lines.length).truncate());
  final cuts = <double>[];
  for (var i = 0; i < cm.cols.length - 1; i++) {
    final a = cm.cols[i], b = cm.cols[i + 1];
    final s0 = math.min(a.center, a.x0 + 6).truncate() - lo;
    final s1 = math.max(b.x0, b.numeric ? b.center : b.x0 + 4).truncate() - lo;
    final from = math.max(0, s0), to = math.min(cov.length, s1 + 1);
    // widest run of x with at most [limit] lines over it, as (start, end)
    (int, int)? widest(int limit) {
      (int, int)? out;
      int? runS;
      for (var x = from; x < to; x++) {
        if (cov[x] <= limit) {
          runS ??= x;
          if (out == null || x - runS > out.$2 - out.$1) out = (runS, x);
        } else {
          runS = null;
        }
      }
      return out;
    }

    var run = widest(thr);
    if (run == null || run.$2 - run.$1 + 1 < 6) {
      // a clean run this narrow may be a gap between words: one stray line over a wide gutter beats it
      var loose = widest(thr + 1);
      if (loose == null && from < to) {
        final least = cov.getRange(from, to).reduce(math.min);
        if (least > thr + 1) loose = widest(least);
      }
      if (loose != null && loose.$2 - loose.$1 > 2 * ((run?.$2 ?? 0) - (run?.$1 ?? 0))) {
        // centre on the emptiest part of the run, so a narration tail beside the gutter cannot drag the cut
        final m = cov.getRange(loose.$1, loose.$2 + 1).reduce(math.min);
        (int, int)? core;
        int? coreS;
        for (var x = loose.$1; x <= loose.$2; x++) {
          if (cov[x] == m) {
            coreS ??= x;
            if (core == null || x - coreS > core.$2 - core.$1) core = (coreS, x);
          } else {
            coreS = null;
          }
        }
        run = core != null && core.$2 - core.$1 >= 3 ? core : loose;
      }
    }
    final best = run == null ? null : (run.$1 + run.$2) / 2, bestW = run == null ? 0 : run.$2 - run.$1 + 1;
    if (best != null && bestW >= 2) {
      cuts.add(best! + lo);
    } else {
      cuts.add(cm.cuts == null ? cm.cut(i) : (a.x1 + b.x0) / 2);
    }
  }
  // keep monotonic
  for (var i = 1; i < cuts.length; i++) {
    if (cuts[i] <= cuts[i - 1]) cuts[i] = cuts[i - 1] + 1;
  }
  cm.cuts = cuts;
}

/// Anchor numeric columns on clusters of the right edges of printed values.
///
/// Clusters are matched to header columns in left-to-right order when the counts agree, which
/// survives approximate header geometry (glued/split headers); otherwise fall back to medians.
void refineNumericAnchors(List<Line> lines, ColumnModel cm) {
  final nums = cm.cols.where((c) => c.numeric).toList();
  final xs = <double>[];
  for (final ln in lines) {
    final cells = ln.cells as Cells?;
    if (cells != null) {
      for (final v in cells.nums.values) {
        xs.addAll([for (final (a, w) in v) if (!a.integer) w.x1]);
      }
    }
  }
  xs.sort();
  var clusters = <List<double>>[];
  for (final x in xs) {
    if (clusters.isNotEmpty && x - clusters.last.last < 6) {
      clusters.last.add(x);
    } else {
      clusters.add([x]);
    }
  }
  clusters = clusters.where((c) => c.length >= math.max(2, 0.03 * lines.length)).toList();
  if (nums.isNotEmpty && clusters.length == nums.length) {
    for (var i = 0; i < nums.length; i++) {
      nums[i].anchor = median(clusters[i]);
    }
    return;
  }
  for (final c in cm.cols) {
    if (!c.numeric) continue;
    final cx = <double>[];
    for (final ln in lines) {
      final cells = ln.cells as Cells?;
      if (cells != null && cells.nums.containsKey(c.role)) cx.addAll([for (final (_, w) in cells.nums[c.role]!) w.x1]);
    }
    if (cx.length >= 2) c.anchor = median(cx);
  }
}
