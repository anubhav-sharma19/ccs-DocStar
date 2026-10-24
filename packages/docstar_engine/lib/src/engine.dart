/// DocStar statement engine: positioned words -> sections of reconciled transactions.
///
/// Same JSON as the Python reference (`engine.parse_document`), minus the optional ML layer
/// (so `bank` is null where Python recovered it from `ml`). Bank fingerprints come from
/// `specs/banks.json` (`banks` = the decoded `["banks"]` list), passed in so this library stays IO-free.
///
/// Name table (Python -> Dart): parse_document -> parseDocument, detect_bank -> detectBank,
/// account_last4 -> accountLast4, extract_summary -> extractSummary, build_stream -> buildStream.
library;

import 'dec.dart';
import 'extract.dart';
import 'layout.dart';
import 'lexicon.dart' as lx;
import 'numbers.dart';
import 'py.dart';
import 'reconcile.dart';
import 'rows.dart';

typedef Banks = List<Map<String, dynamic>>;

// ================================================================== metadata

(Map<String, dynamic>?, double) detectBank(String text, Banks banks) {
  final t = text.toLowerCase();
  Map<String, dynamic>? best;
  var score = 0.0;
  for (final s in banks) {
    var sc = 0.0;
    for (final fp in (s['fp'] as List? ?? const [])) {
      final f = (fp as String).toLowerCase();
      if (f.length <= 3) {
        if (RegExp('\\b${RegExp.escape(f)}\\b').hasMatch(t)) sc += 0.5;
      } else if (t.contains(f)) {
        sc += 1.0 + f.length / 20;
      }
    }
    if (sc > score) {
      best = s;
      score = sc;
    }
  }
  return (best, score / 2.0 < 1.0 ? score / 2.0 : 1.0);
}

final _acctRx = RegExp(r'(account\s*(no|number|#)?|a/c\s*(no)?|acct\.?\s*(no)?|iban)\s*[:.]?\s*([A-Z]{0,4}[\dXx*•\s-]{6,30}\d)',
    caseSensitive: false);

String? accountLast4(String text) {
  final m = _acctRx.firstMatch(text);
  if (m == null) return null;
  final digits = m[5]!.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 4 ? digits.substring(digits.length - 4) : null;
}

Map<String, Dec> extractSummary(List<Line> lines, String locale) {
  final out = <String, Dec>{};
  for (var k = 0; k < lines.length; k++) {
    final ln = lines[k];
    final text = ln.text;
    var labels = <(int, int, String)>[];
    lx.summaryLabels.forEach((key, rx) {
      for (final m in rx.allMatches(text)) {
        labels.add((m.start, m.end, key));
      }
    });
    if (labels.isEmpty) continue;
    stableSort(labels, (a, b) {
      if (a.$1 != b.$1) return a.$1 - b.$1;
      if (a.$2 != b.$2) return a.$2 - b.$2;
      return a.$3.compareTo(b.$3);
    });
    // drop overlapping matches, keep the earliest
    final clean = <(int, int, String)>[];
    var lastEnd = -1;
    for (final l in labels) {
      if (l.$1 >= lastEnd) {
        clean.add(l);
        lastEnd = l.$2;
      }
    }
    labels = clean;
    final nums = [
      for (final w in ln.words)
        if (parseAmount(w.text, locale) case final a? when looksLikeAmount(w.text) || a.integer) (w, a),
    ];
    if (labels.length >= 3 && nums.isEmpty && k + 1 < lines.length) {
      // labels on one line, values on the next (HDFC 'STATEMENT SUMMARY')
      final vals = [
        for (final w in lines[k + 1].words)
          if (parseAmount(w.text, locale) case final a?) (w, a),
      ];
      if (vals.length >= labels.length) {
        // map each label word span to the value nearest in x
        for (final (a, b, key) in labels) {
          final x = _charX(ln, a, b);
          var best = vals.first;
          for (final v in vals) {
            if ((v.$1.xc - x).abs() < (best.$1.xc - x).abs()) best = v;
          }
          final amt = best.$2;
          out.putIfAbsent(key, () => !amt.integer || key.endsWith('count') ? amt.signed : amt.value);
        }
      }
      continue;
    }
    for (var i = 0; i < labels.length; i++) {
      final (_, b, key) = labels[i];
      final nxtLabel = i + 1 < labels.length ? labels[i + 1].$1 : text.length;
      // first number whose char position lies between this label and the next one
      var pos = 0;
      for (final (w, amt) in nums) {
        final start = pyFind(text, w.text, pos);
        if (start >= 0) pos = start + w.text.length;
        if ((b <= start && start < nxtLabel + 1) || (start >= b && i == labels.length - 1)) {
          if (!out.containsKey(key)) {
            out[key] = key.endsWith('count') ? amt.value : ((amt.sign == -1 || amt.side == 'dr') ? -amt.value : amt.value);
          }
          break;
        }
      }
    }
  }
  return out;
}

double _charX(Line line, int a, int b) {
  var pos = 0;
  final xs = <double>[];
  for (final w in line.words) {
    final s = pyFind(line.text, w.text, pos);
    final e = s + w.text.length;
    pos = e;
    if (!(e <= a || s >= b)) xs.add(w.xc);
  }
  return xs.isEmpty ? 0.0 : xs.reduce((p, q) => p + q) / xs.length;
}

// ================================================================== stream building

class Section {
  final int sid;
  ColumnModel cm;
  List<TLine> tlines = [];
  int? direction;
  Section(this.sid, this.cm, {this.direction});
}

bool _isParagraph(Line line, ColumnModel cm) {
  final nums = cm.cols.where((c) => c.numeric).toList();
  if (nums.isEmpty) return false;
  final firstNumX = nums.map((c) => c.x0).reduce((a, b) => a < b ? a : b);
  final long = line.words.length >= 7 && line.x1 > firstNumX + 20;
  return long && !line.words.any((w) => looksLikeAmount(w.text));
}

/// No column header anywhere: infer bands from lines that start with a date and carry amounts.
ColumnModel? _headerlessModel(Document doc, DateConfig dcfg) {
  final data = <(Line, DateHit, List<Word>)>[];
  for (final pg in doc.pages) {
    for (final ln in pg.lines) {
      if (ln.kind == 'furniture') continue;
      final head = ln.words.take(3).map((w) => w.text).join(' ');
      final hits = findDates(head, dcfg);
      if (hits.isEmpty || hits.first.start > 2) continue;
      final amts = [for (final w in ln.words) if (looksLikeAmount(w.text)) w];
      if (amts.isNotEmpty) data.add((ln, hits.first, amts));
    }
  }
  if (data.length < 2) return null;
  // date band: words covering the date text at line start
  final dateX1 = median([for (final (ln, h, _) in data) _dateX1(ln, h)]);
  final dateX0 = median([for (final (ln, _, _) in data) ln.x0]);
  final xs = [for (final (_, _, amts) in data) for (final w in amts) w.x1]..sort();
  var clusters = <List<double>>[];
  for (final x in xs) {
    if (clusters.isNotEmpty && x - clusters.last.last < 10) {
      clusters.last.add(x);
    } else {
      clusters.add([x]);
    }
  }
  final need = 0.2 * data.length > 2 ? 0.2 * data.length : 2;
  clusters = clusters.where((c) => c.length >= need).toList();
  if (clusters.isEmpty) return null;
  final cols = [Column('date', dateX0, dateX1)];
  final firstNumLeft = clusters
      .map((c) => [
            for (final (_, _, amts) in data)
              for (final w in amts)
                if ((w.x1 - median(c)).abs() < 10) w.x0,
          ].reduce((a, b) => a < b ? a : b))
      .reduce((a, b) => a < b ? a : b);
  cols.add(Column('desc', dateX1 + 2, firstNumLeft - 4));
  var names = List.filled(clusters.length, 'amount');
  if (clusters.length >= 2) names[names.length - 1] = 'balance';
  if (clusters.length >= 3) names = ['amount', 'amount2', ...List.filled(clusters.length - 3, 'amount'), 'balance'];
  for (var i = 0; i < clusters.length; i++) {
    final x1 = median(clusters[i]);
    cols.add(Column(names[i], x1 - 45, x1, '', x1));
  }
  return ColumnModel(cols, [], 0);
}

double _dateX1(Line ln, DateHit hit) {
  var pos = 0;
  var x1 = ln.words.first.x1;
  for (final w in ln.words.take(4)) {
    final s = pyFind(ln.text, w.text, pos);
    pos = s + w.text.length;
    if (s < hit.end) x1 = w.x1;
  }
  return x1;
}

final _metaRx = RegExp(
    r'^\s*(account(\s+(no|number|name|type))?|a/c(\s+no)?|statement(\s+(period|date|no))?|period|customer(\s+id)?|'
    r'cust\s+id|branch|ifsc|micr|currency|page|address|iban|bic|sort\s+code|product|scheme|nominee|'
    r'date\s+of\s+statement|joint\s+holders?)\s*[:.]',
    caseSensitive: false);
final _carriedRx = RegExp(r'carried|c\s*/\s*f', caseSensitive: false);
final _pageTotalRx = RegExp(r'\bpage\b|sub\s*-?\s*total', caseSensitive: false);
final _sectionTotalRx = RegExp(r'total\s+(deposits?|withdrawals?|credits?|debits?|checks|fees|payments|other)', caseSensitive: false);
final _leadJunk = RegExp(r'^[\d\s/.\-]+');

(List<Section>, List<Line>) buildStream(Document doc, Map<int, ColumnModel> headers, String locale, bool spaceGrouped, DateConfig dcfg) {
  final sections = <Section>[];
  final meta = <Line>[];
  Section? cur;
  var inTable = false, stopped = true;
  int? direction;
  int? cfPage;
  var justAfterHeader = false, wasAfterHeader = false;
  if (headers.isEmpty) {
    final headerless = _headerlessModel(doc, dcfg);
    if (headerless != null) {
      cur = Section(0, headerless);
      sections.add(cur);
      inTable = true;
      stopped = false;
    }
  }
  for (final pg in doc.pages) {
    double? prevBottom;
    for (final ln in pg.lines) {
      if (headers.containsKey(ln.idx)) {
        cfPage = null;
        final cm = headers[ln.idx]!;
        if (cur == null || stopped || cm.signature() != cur.cm.signature()) {
          cur = Section(sections.length, cm, direction: direction);
          sections.add(cur);
        } else {
          cur.cm = cm; // same header on a later page: use the newer geometry
        }
        inTable = true;
        stopped = false;
        prevBottom = ln.bottom;
        justAfterHeader = true;
        continue;
      }
      if (ln.kind == 'header') {
        prevBottom = ln.bottom;
        justAfterHeader = true;
        continue;
      }
      if (ln.kind == 'furniture') continue;
      wasAfterHeader = justAfterHeader;
      justAfterHeader = false;
      final text = ln.text;
      final noMoney = !ln.words.any((w) => looksLikeAmount(w.text));
      final singleAmount = cur == null || !(cur.cm.get('debit') != null || cur.cm.get('credit') != null);
      if (noMoney && ln.words.length <= 8 && (!inTable || singleAmount) && findDates(text, dcfg).isEmpty) {
        if (lx.sectionCreditRx.hasMatch(text) && !lx.sectionDebitRx.hasMatch(text)) {
          direction = 1;
          if (cur != null && cur.cm.get('debit') == null) cur.direction = 1;
          meta.add(ln);
          continue;
        }
        if (lx.sectionDebitRx.hasMatch(text)) {
          direction = -1;
          if (cur != null && cur.cm.get('debit') == null) cur.direction = -1;
          meta.add(ln);
          continue;
        }
      }
      if (cfPage == pg.number && inTable) {
        // something printed after 'carried forward' on the same page: that was the real end
        inTable = false;
        stopped = true;
      }
      final resumeCheck = cfPage != null && cfPage != pg.number;
      if (resumeCheck) cfPage = null;
      if (!inTable || cur == null) {
        meta.add(ln);
        continue;
      }
      if (lx.stopRx.hasMatch(text) && findDates(ln.words.take(3).map((w) => w.text).join(' '), dcfg).isEmpty) {
        inTable = false;
        stopped = true;
        meta.add(ln);
        continue;
      }
      if (_metaRx.hasMatch(text)) {
        meta.add(ln); // 'Account No : ...  Period : ...' block repeated above the table
        continue;
      }
      final cells = assignCells(ln, cur.cm, locale, spaceGrouped);
      final t = _toTLine(ln, cells, cur, dcfg);
      if (resumeCheck && t.kind == 'T' && t.special == null) {
        // after 'carried forward' the next page must continue with a row or 'brought forward'
        inTable = false;
        stopped = true;
        meta.add(ln);
        continue;
      }
      // leaving the table: long paragraph, or a big vertical gap before a text-only line
      if (t.kind == 'T') {
        final h = ln.height > 6.0 ? ln.height : 6.0;
        final last12 = cur.tlines.length > 12 ? cur.tlines.sublist(cur.tlines.length - 12) : cur.tlines;
        final bodyBold = last12.where((x) => x.line.words.every((w) => w.bold)).length;
        final title = ln.words.every((w) => w.bold) &&
            bodyBold <= 2 &&
            ln.words.length <= 8 &&
            cur.tlines.isNotEmpty &&
            !wasAfterHeader;
        if (title || _isParagraph(ln, cur.cm) || (prevBottom != null && ln.top - prevBottom > 3.2 * h && cur.tlines.isNotEmpty)) {
          inTable = false;
          stopped = true;
          meta.add(ln);
          continue;
        }
      }
      ln.kind = 'table';
      ln.cells = cells;
      cur.tlines.add(t);
      prevBottom = ln.bottom;
      if (t.special == 'close' && _carriedRx.hasMatch(text)) {
        cfPage = pg.number; // per-page carried forward: table may resume on the next page
      } else if (t.special == 'close') {
        inTable = false;
        stopped = true;
      } else if (t.special == 'total' &&
          !_pageTotalRx.hasMatch(text) &&
          !lx.sectionCreditRx.hasMatch(_descText(cells, ln).replaceAll('Total', '').replaceAll('TOTAL', '').trim())) {
        // a statement-level totals row ends the table; section totals ('Total deposits') don't
        if (!_sectionTotalRx.hasMatch(text)) {
          inTable = false;
          stopped = true;
        }
      }
    }
  }
  return ([for (final s in sections) if (s.tlines.isNotEmpty) s], meta);
}

String _descText(Cells cells, Line ln) {
  final parts = cells.text['desc'];
  if (parts != null && parts.isNotEmpty) return parts.join(' ');
  // specials often print their label in the date/desc band
  return ln.text.replaceFirst(_leadJunk, '');
}

TLine _toTLine(Line ln, Cells cells, Section sec, DateConfig dcfg) {
  final cm = sec.cm;
  DateHit? date, vdate;
  if (cm.get('date') != null) {
    final hits = cells.dateText.isNotEmpty ? findDates(cells.dateText, dcfg) : <DateHit>[];
    date = hits.isNotEmpty ? hits.first : null;
  } else {
    final head = ln.words.take(3).map((w) => w.text).join(' ');
    final hits = findDates(head, dcfg);
    date = hits.isNotEmpty && hits.first.start <= 2 ? hits.first : null;
  }
  if (cells.vdateText.isNotEmpty) {
    final hits = findDates(cells.vdateText, dcfg);
    vdate = hits.isNotEmpty ? hits.first : null;
  }
  final hasAmt = txnAmountRoles.any((r) => (cells.nums[r] ?? const []).isNotEmpty);
  final hasBal = (cells.nums['balance'] ?? const []).isNotEmpty;
  final desc = lx.norm(_descText(cells, ln));
  final full = lx.norm(ln.text);
  String? special;
  int nAmt() => cells.nums.entries.where((e) => txnAmountRoles.contains(e.key)).fold(0, (s, e) => s + e.value.length);
  if (lx.totalRx.hasMatch(desc) && date == null) {
    special = 'total';
  } else if (lx.dailyRx.hasMatch(desc) && !hasAmt) {
    special = 'daily';
  } else if (lx.openRx.hasMatch(desc) || lx.openRx.hasMatch(full)) {
    if (!hasAmt || (!hasBal && nAmt() == 1)) special = 'open';
  } else if (lx.closeRx.hasMatch(desc) || lx.closeRx.hasMatch(full)) {
    if (!hasAmt || (!hasBal && nAmt() == 1)) special = 'close';
  }
  return TLine(ln, cells, date, vdate, special, hasAmt, hasBal, sec.sid, sec.direction);
}

// ================================================================== public API

String _basename(String p) => p.split('/').last;

final _numTokenRx = RegExp(r'\d[.,]\d{2}\b');
final _spaceGroupedRx = RegExp(r'(?<![\d.,])\d{1,3} \d{3}[.,]\d{2}(?!\d)');
final _dotShortRx = RegExp(r'^\d{2}\.\d{2}(?![.,]?\d)');

/// [banks] is `specs/banks.json["banks"]`; pass `[]` to skip bank detection.
Map<String, dynamic> parseDocument(Document doc, {Banks banks = const []}) {
  final bad = [for (final pg in doc.pages) if (unreadable(pg)) pg.number];
  if (doc.pages.isEmpty || bad.length == doc.pages.length) {
    // no OCR: refuse, don't guess
    return {
      'engine': 'docstar-0.1',
      'file': _basename(doc.path),
      'pages': doc.pages.length,
      'bank': null,
      'sections': [],
      'transaction_count': 0,
      'warnings': doc.warnings,
      'quality': {'score': 0.0, 'status': 'unsupported_scanned_pdf', 'reason': noOcrNotice},
    };
  }
  final headers = detectHeaders(doc);
  detectFurniture(doc);
  final allLines = [for (final pg in doc.pages) ...pg.lines];
  final body = [for (final ln in allLines) if (ln.kind != 'furniture') ln];
  // ---- locale & date conventions from the whole document
  final numTokens = [for (final ln in body) for (final w in ln.words) if (_numTokenRx.hasMatch(w.text)) w.text];
  final locale = detectLocale(numTokens);
  final spaceGrouped = _spaceGroupedRx.hasMatch(body.map((l) => l.text).join(' \n'));
  final firstText = doc.pages.first.lines.map((l) => l.text).join('\n');
  // bank identity comes from the letterhead (above the first column header), never from narrations
  final p0Lines = doc.pages.first.lines;
  final hdrTops = [for (final l in p0Lines) if (l.kind == 'header') l.top];
  final cut = hdrTops.isNotEmpty ? hdrTops.reduce((a, b) => a < b ? a : b) : 0.3 * doc.pages.first.height;
  final letterhead = [for (final l in p0Lines) if (l.bottom <= cut + 1) l.text].join('\n');
  final (bank, bankConf) = detectBank(letterhead.isNotEmpty ? letterhead : firstText, banks);
  final voted = voteDateOrder(body.map((l) => l.text));
  var order = voted ?? (bank != null && (bank['cc'] == 'US' || bank['cc'] == 'PH') ? 'MDY' : 'DMY');
  final dotShort = body.where((l) => _dotShortRx.hasMatch(l.text)).length >= 3;
  final dcfg = DateConfig(order: order, allowDotShort: dotShort);
  final first200 = [for (final l in allLines.take(200)) l.text];
  var (p0, p1) = findPeriod(first200, dcfg);
  // ambiguous numeric period (01/11/2024): keep the order under which month-name row dates fall inside it
  final alt = DateConfig(order: order == 'DMY' ? 'MDY' : 'DMY', allowDotShort: dotShort);
  final (q0, q1) = findPeriod(first200, alt);
  if (voted == null && q0 != null && !(q0 == p0 && q1 == p1)) {
    final named = [
      for (final l in body)
        for (final h in findDates(l.words.take(3).map((w) => w.text).join(' '), dcfg))
          if (h.kind == 'dmon' || h.kind == 'mond') h,
    ];
    final cap = named.length < 200 ? named.length : 200;
    int fit(DateTime? a, DateTime? b) {
      if (a == null) return 0;
      return named.take(200).where((h) {
        for (final y in {a.year, b!.year}) {
          final d = h.toDate(y)!;
          if (!d.isBefore(a) && !d.isAfter(b)) return true;
        }
        return false;
      }).length;
    }

    if (named.length >= 3 && fit(q0, q1) >= 0.8 * cap && fit(p0, p1) <= 0.2 * cap) {
      order = alt.order;
      p0 = q0;
      p1 = q1;
      dcfg.order = order;
    }
  }
  dcfg.periodStart = p0;
  dcfg.periodEnd = p1;
  if (p1 == null) {
    final years = [for (final l in body) for (final h in findDates(l.text, dcfg)) if (h.y != null && h.y != 0) h.y!];
    dcfg.defaultYear = mostCommon(years);
  }

  // ---- table stream: two passes so numeric anchors come from the printed values
  final (sections, meta) = buildStream(doc, headers, locale, spaceGrouped, dcfg);
  for (final s in sections) {
    _refine(s, locale, spaceGrouped, dcfg);
  }

  final summary = extractSummary(meta, locale);
  final resultSections = <Map<String, dynamic>>[];
  for (final s in sections) {
    final mode = detectMode(s.tlines);
    final groups = gridGroups(doc, s.tlines);
    final rows = groups != null ? assembleGrid(groups, mode['anchor'] as String) : assemble(s.tlines, mode);
    final (txns, specials) = buildTxns(rows, dcfg);
    if (!specials.any((sp) => sp['kind'] == 'open') && sections.length == 1 && summary.containsKey('open')) {
      specials.insert(0, {'kind': 'open', 'balance': summary['open'], 'values': <String, List<String>>{}, 'text': 'summary', 'index': 0, 'date': null});
    }
    final checks = reconcileSection(txns, specials);
    resultSections.add({
      'columns': s.cm.roles(),
      // Additive (not in the Python reference): the header text as printed, one entry per column, same order as `columns`.
      'column_headers': [for (final c in s.cm.cols) {'role': c.role, 'header': c.text.isEmpty ? null : c.text}],
      'mode': {...mode, 'grid': groups != null},
      'opening': checks['opening'],
      'closing': checks['closing'],
      'checks': checks,
      'specials': [
        for (final sp in specials)
          {
            for (final e in sp.entries)
              if (e.key != 'index') e.key: e.value is Dec ? e.value.toString() : e.value,
          },
      ],
      'transactions': [for (final t in txns) t.toJson()],
    });
  }

  final res = <String, dynamic>{
    'engine': 'docstar-0.1',
    'file': _basename(doc.path),
    'pages': doc.pages.length,
    'bank': bank != null ? {'id': bank['id'], 'name': bank['name'], 'confidence': pyRound(bankConf, 2)} : null,
    'account_last4': accountLast4(firstText),
    'period': {'from': p0 == null ? null : isoDate(p0), 'to': p1 == null ? null : isoDate(p1)},
    'locale': {'numbers': locale, 'date_order': order},
    'summary_printed': {for (final e in summary.entries) e.key: e.value.toString()},
    'summary_checks': _summaryChecks(summary, resultSections),
    'sections': resultSections,
    'transaction_count': resultSections.fold<int>(0, (n, s) => n + (s['transactions'] as List).length),
    'warnings': doc.warnings,
  };
  final q = _quality(res);
  res['quality'] = q;
  if (bad.isNotEmpty) {
    q['unreadable_pages'] = bad.length;
    if (q['status'] == 'verified') q['status'] = 'review';
  }
  return res;
}

void _refine(Section s, String locale, bool spaceGrouped, DateConfig dcfg) {
  refineNumericAnchors([for (final t in s.tlines) t.line], s.cm);
  computeCuts([for (final t in s.tlines) if (t.special == null) t.line], s.cm);
  final next = <TLine>[];
  for (final t in s.tlines) {
    final cells = assignCells(t.line, s.cm, locale, spaceGrouped);
    t.line.cells = cells;
    final nt = _toTLine(t.line, cells, s, dcfg);
    nt.direction = t.direction;
    next.add(nt);
  }
  s.tlines = next;
}

Map<String, dynamic> _summaryChecks(Map<String, Dec> summary, List<Map<String, dynamic>> sections) {
  if (summary.isEmpty || sections.isEmpty) return {};
  final out = <String, dynamic>{};
  var cr = Dec.zero, dr = Dec.zero;
  for (final s in sections) {
    cr = cr + Dec.parse(s['checks']['credits'] as String);
    dr = dr + Dec.parse(s['checks']['debits'] as String);
  }
  if (summary.containsKey('credits')) out['credits_match'] = (summary['credits']! - cr).abs() < cent;
  if (summary.containsKey('debits')) out['debits_match'] = (summary['debits']!.abs() - dr).abs() < cent;
  if (['open', 'credits', 'debits', 'close'].every(summary.containsKey)) {
    final o = summary['open']!, c = summary['credits']!, d = summary['debits']!, cl = summary['close']!;
    out['printed_summary_self_consistent'] = (o + c - d.abs() - cl).abs() < cent;
  }
  final txns = [for (final s in sections) ...(s['transactions'] as List).cast<Map<String, dynamic>>()];
  if (summary.containsKey('dr_count')) out['dr_count_match'] = summary['dr_count']!.toInt() == txns.where((t) => t['debit'] != null).length;
  if (summary.containsKey('cr_count')) out['cr_count_match'] = summary['cr_count']!.toInt() == txns.where((t) => t['credit'] != null).length;
  return out;
}

Map<String, dynamic> _quality(Map<String, dynamic> res) {
  final secs = (res['sections'] as List).cast<Map<String, dynamic>>();
  final txns = [for (final s in secs) ...(s['transactions'] as List).cast<Map<String, dynamic>>()];
  if (txns.isEmpty) return {'score': 0.0, 'status': 'no_transactions'};
  final avg = txns.fold<double>(0, (a, t) => a + (t['confidence'] as double)) / txns.length;
  final balanced = secs.where((s) => s['checks']['computed_closing'] != null).every((s) => s['checks']['balanced'] as bool);
  final unknown = txns.where((t) => (t['flags'] as List).contains('sign_unknown')).length;
  final breaks = txns.where((t) => (t['flags'] as List).contains('balance_break')).length;
  final status = balanced && breaks == 0 && unknown == 0 ? 'verified' : (avg > 0.6 ? 'review' : 'low');
  return {'score': pyRound(avg, 3), 'status': status, 'balance_breaks': breaks, 'unknown_signs': unknown};
}
