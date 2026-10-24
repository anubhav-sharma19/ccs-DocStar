/// Small helpers that reproduce the Python behaviours the engine relies on
/// (stable sort, half-even `round`, `statistics.median`, `str.find`, `Counter`).
library;

/// Python `sorted`/`list.sort`: stable. Dart's `List.sort` is not.
void stableSort<T>(List<T> l, int Function(T a, T b) cmp) {
  final w = [for (var i = 0; i < l.length; i++) (i, l[i])];
  w.sort((a, b) {
    final r = cmp(a.$2, b.$2);
    return r != 0 ? r : a.$1 - b.$1;
  });
  for (var i = 0; i < w.length; i++) {
    l[i] = w[i].$2;
  }
}

/// Python `round(x, nd)`: correctly rounded on the exact binary value, ties to even.
/// An exact tie needs x = odd / 2^(nd+1), so it is detected exactly (multiplying by a power of two is exact).
double pyRound(double x, int nd) {
  final p2 = (1 << (nd + 1)).toDouble();
  final t = x * p2;
  if (t == t.truncateToDouble() && t.abs() < 9e15 && t.toInt().isOdd) {
    final scale = _pow10(nd);
    final k = x * scale; // exactly k.5
    final lo = k.floorToDouble();
    final even = lo.toInt().isEven ? lo : lo + 1;
    return even / scale;
  }
  return double.parse(x.toStringAsFixed(nd));
}

double _pow10(int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// Python `statistics.median`.
double median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  if (n == 0) throw StateError('median of empty list');
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Python `str.find(sub, start)`: -1 instead of an exception when start is past the end.
int pyFind(String s, String sub, [int start = 0]) => start > s.length ? -1 : s.indexOf(sub, start);

/// Python `str.rstrip(chars)`.
String rstripChars(String s, String chars) {
  var e = s.length;
  while (e > 0 && chars.contains(s[e - 1])) {
    e--;
  }
  return s.substring(0, e);
}

final _alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Python `str.isalnum` for a single character.
bool isAlnum(String c) => _alnum.hasMatch(c);

/// First element with the highest count, ties broken by first insertion (`Counter.most_common(1)`).
T? mostCommon<T>(Iterable<T> items) {
  final counts = <T, int>{};
  for (final i in items) {
    counts[i] = (counts[i] ?? 0) + 1;
  }
  T? best;
  var bc = 0;
  counts.forEach((k, c) {
    if (c > bc) {
      best = k;
      bc = c;
    }
  });
  return best;
}
