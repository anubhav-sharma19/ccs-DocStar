/// Amount and date parsing for any statement locale.
///
/// Name table (Python -> Dart): parse_amount -> parseAmount, detect_locale -> detectLocale,
/// looks_like_amount -> looksLikeAmount, find_dates -> findDates, vote_date_order -> voteDateOrder,
/// resolve_year -> resolveYear, find_period -> findPeriod. Dates are UTC midnight `DateTime`s.
library;

import 'dec.dart';
import 'lexicon.dart' show months;
import 'py.dart';

// ============================================================ amounts

RegExp _i(String p) => RegExp(p, caseSensitive: false);

final _curPrefix = _i(r"^(rs\.?|inr|usd|gbp|eur|aud|cad|zar|ngn|php|qar|bnd|kes|lkr|pln|ron|lei|hkd|brl|chf|r(?=[\d\s-])|₹|\$|£|€|₦|¥)\s*");
final _curSuffix = _i(r'\s*(inr|usd|gbp|eur|aud|cad|zar|ngn|php|qar|bnd|kes|lkr|pln|ron|lei|hkd|brl|chf|€|\$|£)\.?$');
final _drcrSuffix = _i(r'\s*\(?\s*(dr|cr)\s*\)?\.?$');
final _pmSuffix = RegExp(r'\s*\(\s*([+-])\s*\)$');
final _numBody = RegExp(r"^(\d[\d.,\s'’]*\d|\d|[.,]\d{1,2})$");
const placeholders = {'-', '–', '—', '--', 'blank', 'blank.', 'n/a', 'na', 'nil', '*', '.', '-.-', '- -'};
final _digit = RegExp(r'\d');
final _sep = RegExp(r'[.,]');

class Amount {
  final Dec value; // always >= 0
  final int? sign; // -1 / +1 when the token itself carries direction
  final String? side; // 'dr' / 'cr' suffix
  final bool repaired;
  final String raw;
  final bool integer; // no decimal part printed
  const Amount(this.value, {this.sign, this.side, this.repaired = false, this.raw = '', this.integer = false});

  Dec get signed => sign == -1 ? -value : value;
}

/// 'en' (1,234.56) or 'eu' (1.234,56 / 1 234,56) from a sample of numeric tokens.
String detectLocale(Iterable<String> tokens) {
  var dotDec = 0, commaDec = 0;
  for (var t in tokens) {
    t = rstripChars(t.trim(), '-+').trim();
    if (RegExp(r'\d,\d{2}$').hasMatch(t) && !RegExp(r'\d\.\d{2}$').hasMatch(t)) {
      commaDec++;
    } else if (RegExp(r'\d\.\d{2}$').hasMatch(t)) {
      dotDec++;
    }
  }
  return commaDec > dotDec ? 'eu' : 'en';
}

/// Parse a money token. Returns null for non-amounts and placeholders.
Amount? parseAmount(String tok, [String locale = 'en', bool allowDSuffix = true]) {
  final raw = tok;
  var s = tok.trim().replaceAll('−', '-').replaceAll('–', '-').replaceAll('—', '-');
  s = rstripChars(s, '*#').trim();
  if (s.isEmpty || placeholders.contains(s.toLowerCase())) return null;
  int? sign;
  String? side;
  // bracketed negative (7.62) / (Dr) handled below
  if (s.startsWith('(') && s.endsWith(')') && _digit.hasMatch(s) && !RegExp(r'^\(\s*[+-]\s*\)$').hasMatch(s)) {
    final inner = s.substring(1, s.length - 1).trim();
    if (!_i(r'(dr|cr)$').hasMatch(inner)) {
      s = inner;
      sign = -1;
    }
  }
  var m = _pmSuffix.firstMatch(s);
  if (m != null) {
    sign = m[1] == '-' ? -1 : 1;
    s = s.substring(0, m.start).trim();
  }
  m = _drcrSuffix.firstMatch(s);
  if (m != null && _digit.hasMatch(s.substring(0, m.start))) {
    side = m[1]!.toLowerCase();
    s = s.substring(0, m.start).trim();
  }
  s = s.replaceAll(_curSuffix, '').trim();
  final nospace = s.replaceAll(' ', '');
  if (s.endsWith('-') && RegExp(r'\d-$').hasMatch(nospace)) {
    sign = -1;
    s = s.substring(0, s.length - 1).trim();
  } else if (s.endsWith('+') && RegExp(r'\d\+$').hasMatch(nospace)) {
    sign = 1;
    s = s.substring(0, s.length - 1).trim();
  } else if (allowDSuffix && RegExp(r'\d\s?D$').hasMatch(s)) {
    sign = -1;
    side = 'dr';
    s = s.substring(0, s.length - 1).trim();
  }
  // leading sign, possibly around a currency symbol: -R200.00, -$9.95, $ -5, + $400.00
  for (var k = 0; k < 3; k++) {
    if (s.isNotEmpty && '-+'.contains(s[0])) {
      sign = s[0] == '-' ? -1 : 1;
      s = s.substring(1).trim();
      continue;
    }
    final c = _curPrefix.firstMatch(s);
    if (c != null && c.end < s.length) {
      s = s.substring(c.end).trim();
      continue;
    }
    break;
  }
  s = s.replaceAll("'", '').replaceAll('’', '');
  if (!_numBody.hasMatch(s)) return null;
  final body = s.replaceAll(RegExp(r'\s'), '');
  if (!_digit.hasMatch(body)) return null;
  final (value, repaired, integer) = _normaliseNumber(body, locale);
  if (value == null) return null;
  return Amount(value, sign: sign, side: side, repaired: repaired, raw: raw, integer: integer);
}

(Dec?, bool, bool) _normaliseNumber(String body, String locale) {
  final seps = [for (var i = 0; i < body.length; i++) if (body[i] == '.' || body[i] == ',') i];
  var repaired = false;
  if (seps.isEmpty) return (_dec(body), false, true);
  final last = seps.last;
  final tail = body.substring(last + 1);
  final sep = body[last];
  String? decSep;
  if (tail.length <= 2) {
    decSep = sep;
  } else if (tail.length == 3) {
    // 1,234 (en thousands) vs 1.234 (eu thousands) vs 1.234 (3dp - rare)
    final thousands = locale == 'en' ? ',' : '.';
    decSep = (sep == thousands || seps.length > 1) ? null : sep;
    if (locale == 'en' && sep == '.' && seps.length == 1) decSep = '.'; // 3 decimals e.g. 115515.630
  } else {
    decSep = null;
    repaired = true;
  }
  final String num;
  final bool integer;
  if (decSep == null) {
    num = body.replaceAll(_sep, '');
    integer = true;
  } else {
    final head = body.substring(0, last);
    final intpart = head.replaceAll(_sep, '');
    num = '${intpart.isEmpty ? '0' : intpart}.${tail.isEmpty ? '0' : tail}';
    integer = false;
    // validate grouping of the integer part
    final groups = head.isEmpty ? <String>[] : head.split(_sep);
    if (groups.length > 1) {
      final other = {for (final i in seps.sublist(0, seps.length - 1)) body[i]};
      if (other.length > 1 || other.contains(decSep)) repaired = true;
      final first = groups.first, rest = groups.sublist(1);
      final okEn = rest.every((g) => g.length == 3) && first.isNotEmpty && first.length <= 3;
      final okIn = rest.isNotEmpty &&
          rest.last.length == 3 &&
          rest.sublist(0, rest.length - 1).every((g) => g.length == 2) &&
          first.isNotEmpty &&
          first.length <= 2;
      if (!(okEn || okIn)) repaired = true;
    }
  }
  return (_dec(num), repaired, integer);
}

Dec? _dec(String s) {
  try {
    return Dec.parse(s);
  } on FormatException {
    return null;
  }
}

final _amountTokenRx = _i(
    r"^[\(\-+−–]?\s*(?:rs\.?|inr|usd|gbp|eur|r|₹|\$|£|€|₦)?\s*[-+]?\s*(\d{1,3}([,.\s’']\d{2,3})*|\d+)([.,]\d{1,3})?\s*"
    r"(\(?\s*(dr|cr)\s*\)?|\(\s*[+-]\s*\)|[-+]|d|€|\$|£|inr|usd|gbp|eur|zar|aud|cad|ngn)?\)?\*?$|^[.,]\d{2}$");

bool looksLikeAmount(String tok, {bool requireDecimals = true}) {
  final t = tok.trim();
  if (t.isEmpty || !_amountTokenRx.hasMatch(t)) return false;
  if (requireDecimals) {
    return RegExp(r'\d[.,]\d{1,2}(\D*)$').hasMatch(t) || RegExp(r'^[.,]\d{2}$').hasMatch(t);
  }
  return true;
}

// ============================================================ dates

int _monthLen(int y, int m) => DateTime.utc(y, m + 1, 0).day;

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class DateHit {
  final int? y;
  final int m, d, start, end;
  final String kind;
  final bool invalid;
  const DateHit(this.y, this.m, this.d, this.start, this.end, this.kind, [this.invalid = false]);

  DateTime? toDate([int? year]) {
    final yy = y ?? year;
    if (yy == null) return null;
    return DateTime.utc(yy, m, d < _monthLen(yy, m) ? d : _monthLen(yy, m));
  }
}

final _monAlt = () {
  final l = months.keys.toList();
  stableSort(l, (a, b) => b.length - a.length);
  return l.map(RegExp.escape).join('|');
}();
final _rxIso = RegExp(r'(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)');
final _rxNum3 = RegExp(r'(?<!\d)(\d{1,2})\s?[-/.]\s?(\d{1,2})\s?[-/.]\s?(\d{4}|\d{2})(?![\d])');
final _rxDmon = _i(r'(?<![\d\w])(\d{1,2})(?:st|nd|rd|th)?(?:[-/.]|\s{1,3})?(' +
    _monAlt +
    r")\.?(?![a-z])(?:[\s\-/.,']*(\d{4}|\d{2})(?![\d.,]\d))?");
final _rxMond = _i(r'(?<![\w])(' + _monAlt + r')\.?[\s\-/.]*(\d{1,2})(?:st|nd|rd|th)?(?![\d.,:]\d|\d)(?:,?\s*(\d{4})(?!\d))?');
final _rxNum2 = RegExp(r'(?<![\d.,/-])(\d{1,2})\s?([/-])\s?(\d{1,2})(?![\d/.,-])');
final _rxNum2dot = RegExp(r'(?<![\d.,])(\d{1,2})\.(\d{1,2})\.?(?![\d,])');

class DateConfig {
  String order; // "DMY" or "MDY"
  bool allowDotShort; // DD.MM without year (FR/DE)
  DateTime? periodStart, periodEnd;
  int? defaultYear;
  DateConfig({this.order = 'DMY', this.allowDotShort = false, this.periodStart, this.periodEnd, this.defaultYear});
}

int _yy(String y) {
  final v = int.parse(y);
  return y.length == 2 ? v + (v < 70 ? 2000 : 1900) : v;
}

bool _valid(int? y, int m, int d) {
  if (!(m >= 1 && m <= 12 && d >= 1 && d <= 31)) return false;
  final yy = (y == null || y == 0) ? 2000 : y;
  return d <= _monthLen(yy, m);
}

List<DateHit> findDates(String text, [DateConfig? cfg]) {
  cfg ??= DateConfig();
  final hits = <DateHit>[];
  final taken = <(int, int)>[];

  void add(DateHit h) {
    for (final (a, b) in taken) {
      if (!(h.end <= a || h.start >= b)) return;
    }
    taken.add((h.start, h.end));
    hits.add(h);
  }

  for (final m in _rxIso.allMatches(text)) {
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31 && y > 1900 && y < 2100) {
      add(DateHit(y, mo, d, m.start, m.end, 'iso', !_valid(y, mo, d)));
    }
  }
  for (final m in _rxNum3.allMatches(text)) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!), y = _yy(m[3]!);
    if (!(y > 1900 && y < 2100)) continue;
    var (dd, mm) = cfg.order == 'DMY' ? (a, b) : (b, a);
    if (mm > 12 && dd <= 12) (dd, mm) = (mm, dd);
    if (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) add(DateHit(y, mm, dd, m.start, m.end, 'num3', !_valid(y, mm, dd)));
  }
  for (final m in _rxDmon.allMatches(text)) {
    final mon = months[_stripDot(m[2]!.toLowerCase())];
    final d = int.parse(m[1]!);
    if (mon != null && d >= 1 && d <= 31) {
      final y = m[3] != null ? _yy(m[3]!) : null;
      add(DateHit(y, mon, d, m.start, m.end, 'dmon', !_valid(y, mon, d)));
    }
  }
  for (final m in _rxMond.allMatches(text)) {
    final mon = months[_stripDot(m[1]!.toLowerCase())];
    final d = int.parse(m[2]!);
    if (mon != null && d >= 1 && d <= 31) {
      final y = m[3] != null ? int.parse(m[3]!) : null;
      add(DateHit(y, mon, d, m.start, m.end, 'mond', !_valid(y, mon, d)));
    }
  }
  for (final m in _rxNum2.allMatches(text)) {
    final a = int.parse(m[1]!), b = int.parse(m[3]!);
    var (dd, mm) = cfg.order == 'DMY' ? (a, b) : (b, a);
    if (mm > 12 && dd <= 12) (dd, mm) = (mm, dd);
    if (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) add(DateHit(null, mm, dd, m.start, m.end, 'num2', !_valid(null, mm, dd)));
  }
  if (cfg.allowDotShort) {
    for (final m in _rxNum2dot.allMatches(text)) {
      final a = int.parse(m[1]!), b = int.parse(m[2]!);
      final (dd, mm) = cfg.order == 'DMY' ? (a, b) : (b, a);
      if (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) add(DateHit(null, mm, dd, m.start, m.end, 'num2dot', !_valid(null, mm, dd)));
    }
  }
  stableSort(hits, (a, b) => a.start - b.start);
  return hits;
}

String _stripDot(String s) => rstripChars(s, '.');

final _voteRx = RegExp(
    r'(?<![\d.,])(\d{1,2})([-/.])(\d{1,2})\2(\d{2,4})(?![\d.,]\d)|(?<![\d.,])(\d{1,2})/(\d{1,2})(?![\d/.,])');

/// 'DMY' / 'MDY' from unambiguous numeric dates, or null if no evidence.
String? voteDateOrder(Iterable<String> texts) {
  var dmy = 0, mdy = 0;
  for (final t in texts) {
    // 3-part dates with any separator; 2-part dates only with '/' (a '.' pair is usually money)
    for (final m in _voteRx.allMatches(t)) {
      final (a, b) = m[1] != null ? (int.parse(m[1]!), int.parse(m[3]!)) : (int.parse(m[5]!), int.parse(m[6]!));
      if (a > 12 && b <= 12) {
        dmy++;
      } else if (b > 12 && a <= 12) {
        mdy++;
      }
    }
  }
  if (dmy == mdy) return null;
  return dmy > mdy ? 'DMY' : 'MDY';
}

int _days(DateTime a, DateTime b) => a.difference(b).inDays;

/// A concrete date for a hit, inferring the year; second value = year inferred.
(DateTime?, bool) resolveYear(DateHit hit, DateConfig cfg) {
  if (hit.y != null) return (hit.toDate(), false);
  final ps = cfg.periodStart, pe = cfg.periodEnd;
  if (ps != null && pe != null) {
    final years = {ps.year, pe.year, pe.year - 1}.toList()..sort();
    final cands = [for (final y in years) hit.toDate(y)!];
    final lo = ps.subtract(const Duration(days: 10)), hi = pe.add(const Duration(days: 10));
    for (final c in cands) {
      if (!c.isBefore(lo) && !c.isAfter(hi)) return (c, true);
    }
    int dist(DateTime c) => _days(c, ps).abs() < _days(c, pe).abs() ? _days(c, ps).abs() : _days(c, pe).abs();
    var best = cands.first;
    for (final c in cands) {
      if (dist(c) < dist(best)) best = c;
    }
    return (best, true);
  }
  final y = cfg.defaultYear ?? pe?.year;
  if (y == null) return (null, true);
  return (hit.toDate(y), true);
}

final _connect = _i(r'^[\s:,(]*(to|-|–|through|thru|till|until|and|au|la|a|bis|al)[\s:,]*$');
final _periodKw = _i(r'(from|period|between|statement|covered|du\b|de\s+la|perioada|reporting|beginning|cycle|for)');

/// First 'A <connector> B' date range found in the given lines (B must carry a year).
(DateTime?, DateTime?) findPeriod(List<String> lines, DateConfig cfg) {
  (int, DateTime, DateTime)? best;
  for (final line in lines) {
    final hits = findDates(line, cfg);
    for (var i = 0; i + 1 < hits.length; i++) {
      final a = hits[i], b = hits[i + 1];
      if (!_connect.hasMatch(line.substring(a.end, b.start))) continue;
      if (b.y == null) continue;
      final db = b.toDate()!;
      final ay = a.y ?? ((a.m, a.d).compareTo2(b.m, b.d) <= 0 ? db.year : db.year - 1);
      final da = a.toDate(ay);
      if (da != null && !da.isAfter(db) && _days(db, da) < 800) {
        final score = _periodKw.hasMatch(line) ? 2 : 1;
        if (best == null || score > best.$1) best = (score, da, db);
      }
    }
    if (best != null && best.$1 == 2) break;
  }
  return best == null ? (null, null) : (best.$2, best.$3);
}

extension on (int, int) {
  int compareTo2(int m, int d) => $1 != m ? $1.compareTo(m) : $2.compareTo(d);
}
