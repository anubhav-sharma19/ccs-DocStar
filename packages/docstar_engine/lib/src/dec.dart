/// Minimal decimal (BigInt unscaled value + scale) with Python `Decimal` string behaviour.
/// Only what the engine needs: parse, + - negate abs, compare, `str()` and `format(.2f)`.
library;

class Dec implements Comparable<Dec> {
  final BigInt u;
  final int scale;
  const Dec._(this.u, this.scale);

  static final zero = Dec._(BigInt.zero, 0);

  /// Digits with an optional single '.', like `Decimal("1234.50")`. Throws [FormatException] otherwise.
  factory Dec.parse(String s) {
    final m = RegExp(r'^(-?)(\d*)(?:\.(\d*))?$').firstMatch(s.trim());
    if (m == null || (m[2]!.isEmpty && (m[3] ?? '').isEmpty)) throw FormatException('bad decimal', s);
    final frac = m[3] ?? '';
    final v = BigInt.parse('${m[2]!.isEmpty ? '0' : m[2]}$frac');
    return Dec._(m[1] == '-' ? -v : v, frac.length);
  }

  Dec _aligned(int sc) => sc == scale ? this : Dec._(u * BigInt.from(10).pow(sc - scale), sc);

  Dec operator +(Dec o) {
    final sc = scale > o.scale ? scale : o.scale;
    return Dec._(_aligned(sc).u + o._aligned(sc).u, sc);
  }

  Dec operator -(Dec o) => this + (-o);

  /// Zero stays +0 (Python `-Decimal("0.00")` is `0.00`).
  Dec operator -() => Dec._(-u, scale);

  Dec abs() => Dec._(u.abs(), scale);
  bool get isZero => u == BigInt.zero;
  bool get isNegative => u < BigInt.zero;

  @override
  int compareTo(Dec o) {
    final sc = scale > o.scale ? scale : o.scale;
    return _aligned(sc).u.compareTo(o._aligned(sc).u);
  }

  bool operator <(Dec o) => compareTo(o) < 0;
  bool operator >(Dec o) => compareTo(o) > 0;
  bool operator <=(Dec o) => compareTo(o) <= 0;
  bool operator >=(Dec o) => compareTo(o) >= 0;
  @override
  bool operator ==(Object o) => o is Dec && compareTo(o) == 0;
  @override
  int get hashCode {
    var v = u, s = scale;
    final ten = BigInt.from(10);
    while (s > 0 && v.remainder(ten) == BigInt.zero) {
      v ~/= ten;
      s--;
    }
    return Object.hash(v, s);
  }

  /// Python `str(Decimal)`: keeps the printed scale (`1000.50`, `7`).
  @override
  String toString() {
    final neg = u < BigInt.zero;
    var d = u.abs().toString();
    if (scale > 0) {
      d = d.padLeft(scale + 1, '0');
      d = '${d.substring(0, d.length - scale)}.${d.substring(d.length - scale)}';
    }
    return neg ? '-$d' : d;
  }

  /// Python `f"{v:.2f}"`: round half even to 2 places; the sign survives rounding to zero.
  String toFixed2() {
    var q = u.abs();
    if (scale > 2) {
      final div = BigInt.from(10).pow(scale - 2);
      final r = q.remainder(div);
      q = q ~/ div;
      final twice = r * BigInt.two;
      if (twice > div || (twice == div && q.isOdd)) q += BigInt.one;
    } else {
      q *= BigInt.from(10).pow(2 - scale);
    }
    final d = q.toString().padLeft(3, '0');
    return '${u < BigInt.zero ? '-' : ''}${d.substring(0, d.length - 2)}.${d.substring(d.length - 2)}';
  }

  int toInt() => (u ~/ BigInt.from(10).pow(scale)).toInt();
}
