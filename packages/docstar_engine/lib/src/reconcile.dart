/// Turn rows into transactions: signs, balances, order detection, chain + summary reconciliation.
///
/// Name table (Python -> Dart): build_txns -> buildTxns, reconcile_section -> reconcileSection,
/// smart_join -> smartJoin, detect_order -> detectOrder. Specials stay `Map<String, dynamic>`.
library;

import 'dec.dart';
import 'lexicon.dart' as lx;
import 'numbers.dart';
import 'py.dart';
import 'rows.dart';

final cent = Dec.parse('0.011');
final zero = Dec.zero;

String? _s(Dec? v) => v?.toFixed2();

class Txn {
  DateTime? date, valueDate;
  String description, reference;
  Dec? debit, credit, balance;
  int page, section;
  String signSource;
  List<String> flags;
  Map<String, String> extra;
  double confidence;
  // internal
  Dec? magnitude;
  int? sign;

  Txn(this.date, this.valueDate, this.description, this.reference, this.debit, this.credit, this.balance, this.page, this.section,
      {this.signSource = '', List<String>? flags, Map<String, String>? extra, this.confidence = 1.0, this.magnitude, this.sign})
      : flags = flags ?? [],
        extra = extra ?? {};

  Dec? get amount {
    if (magnitude == null || sign == null) return null;
    return sign! > 0 ? magnitude : -magnitude!;
  }

  Map<String, dynamic> toJson() => {
        'date': date == null ? null : isoDate(date!),
        'value_date': valueDate == null ? null : isoDate(valueDate!),
        'description': description,
        'reference': reference.isEmpty ? null : reference,
        'debit': _s(debit),
        'credit': _s(credit),
        'amount': _s(amount),
        'balance': _s(balance),
        'page': page,
        'confidence': pyRound(confidence, 2),
        'flags': flags,
        if (extra.isNotEmpty) 'extra': extra,
      };
}

Dec _balanceSigned(Amount a) => (a.sign == -1 || a.side == 'dr') ? -a.value : a.value;

Amount? _firstAmt(Row row, String role) {
  for (final t in row.tlines) {
    final v = t.cells.nums[role];
    if (v != null && v.isNotEmpty) return v.first.$1;
  }
  return null;
}

Amount? _lastAmt(Row row, String role) {
  Amount? out;
  for (final t in row.tlines) {
    final v = t.cells.nums[role];
    if (v != null && v.isNotEmpty) out = v.last.$1;
  }
  return out;
}

/// If a single-amount column marks only one direction ('(x)', '-', '+'), unmarked values are the other.
int? _implicitSign(List<Row> rows) {
  var neg = 0, pos = 0, plain = 0;
  for (final r in rows) {
    if (r.kind != 'txn') continue;
    final a = _firstAmt(r, 'amount');
    if (a == null) continue;
    if (a.sign == -1 || a.side == 'dr') {
      neg++;
    } else if (a.sign == 1 || a.side == 'cr') {
      pos++;
    } else {
      plain++;
    }
  }
  if (plain == 0) return null;
  if (neg > 0 && pos == 0) return 1;
  if (pos > 0 && neg == 0) return -1;
  return null;
}

Dec _signedAmt(Amount a) => a.side != 'dr' ? a.signed : -a.value;

(List<Txn>, List<Map<String, dynamic>>) buildTxns(List<Row> rows, DateConfig dcfg) {
  final implicit = _implicitSign(rows);
  final txns = <Txn>[];
  final specials = <Map<String, dynamic>>[];
  DateTime? lastDate;
  for (final r in rows) {
    if (r.kind == 'info') continue;
    final dh = r.date;
    DateTime? d;
    final flags = <String>[];
    if (dh != null) {
      d = resolveYear(dh, dcfg).$1;
      if (dh.invalid) flags.add('invalid_date');
    }
    DateTime? vd;
    for (final t in r.tlines) {
      if (t.vdate != null) {
        vd = resolveYear(t.vdate!, dcfg).$1;
        break;
      }
    }
    if (r.kind == 'special') {
      var bal = _lastAmt(r, 'balance');
      if (bal == null) {
        // opening/closing printed in an amount column or as the only number
        for (final role in const ['amount', 'credit', 'debit', 'amount2']) {
          bal = _lastAmt(r, role);
          if (bal != null) break;
        }
      }
      if (bal == null) {
        for (final t in r.tlines) {
          for (final w in t.line.words.reversed) {
            if (looksLikeAmount(w.text)) {
              bal = parseAmount(w.text);
              break;
            }
          }
          if (bal != null) break;
        }
      }
      final amts = <String, List<String>>{};
      for (final t in r.tlines) {
        t.cells.nums.forEach((k, v) => amts[k] = [for (final (a, _) in v) _signedAmt(a).toString()]);
      }
      specials.add({
        'kind': r.special,
        'date': d == null ? null : isoDate(d),
        'balance': bal != null ? _balanceSigned(bal) : null,
        'values': amts,
        'text': r.tlines.map((t) => t.line.text).join(' '),
        'index': txns.length,
      });
      continue;
    }
    if (d == null) {
      d = lastDate;
      if (d != null) flags.add('date_carried');
    } else {
      lastDate = d;
    }
    final descParts = <String>[], refParts = <String>[];
    final extra = <String, List<String>>{};
    for (final t in r.tlines) {
      t.cells.text.forEach((role, parts) {
        if (role == 'desc' || role == 'desc2') {
          descParts.add(parts.join(' '));
        } else if (role == 'ref') {
          refParts.addAll(parts);
        } else {
          extra.putIfAbsent(role, () => []).addAll(parts);
        }
      });
    }
    var desc = smartJoin(descParts);
    if (desc.isEmpty && extra.isNotEmpty) {
      // layouts whose narration sits in a 'type' column
      desc = extra.remove(extra.keys.first)!.join(' ');
    }
    final deb = _firstAmt(r, 'debit');
    final cre = _firstAmt(r, 'credit');
    final amt = _firstAmt(r, 'amount') ?? _firstAmt(r, 'amount2');
    final bal = _lastAmt(r, 'balance');
    final fee = _firstAmt(r, 'fee');
    final x = Txn(d, vd, desc, refParts.join(' ').trim(), null, null, bal != null ? _balanceSigned(bal) : null, r.page, r.section,
        flags: flags);
    if (fee != null && !fee.value.isZero) x.extra['fee'] = fee.value.toFixed2();
    extra.forEach((k, v) => x.extra[k] = v.join(' '));
    if ([deb, cre, amt, bal].any((a) => a != null && a.repaired)) x.flags.add('repaired_number');
    // ---- magnitude + sign from columns / tokens
    var debV = deb?.value, creV = cre?.value;
    if (debV != null && creV != null) {
      if (debV.isZero && !creV.isZero) {
        debV = null;
      } else if (creV.isZero && !debV.isZero) {
        creV = null;
      } else if (!debV.isZero && !creV.isZero) {
        x.flags.add('both_debit_and_credit');
      }
    }
    if (debV != null && creV == null) {
      x.magnitude = debV;
      x.sign = -1;
      x.signSource = 'column';
    } else if (creV != null && debV == null) {
      x.magnitude = creV;
      x.sign = 1;
      x.signSource = 'column';
      if (cre!.sign == -1) x.sign = -1; // negative value printed in a credit column = reversal
    } else if (debV != null && creV != null) {
      x.magnitude = (creV - debV).abs();
      x.sign = creV >= debV ? 1 : -1;
      x.signSource = 'column';
    } else if (amt != null) {
      x.magnitude = amt.value;
      if (amt.sign != null) {
        x.sign = amt.sign;
        x.signSource = 'token';
      } else if (amt.side != null) {
        x.sign = amt.side == 'dr' ? -1 : 1;
        x.signSource = 'token';
      } else {
        int? dirn;
        for (final t in r.tlines) {
          if (t.direction != null) {
            dirn = t.direction;
            break;
          }
        }
        if (dirn != null) {
          x.sign = dirn;
          x.signSource = 'section';
        } else if (implicit != null) {
          x.sign = implicit;
          x.signSource = 'implicit';
        }
      }
    }
    if (lx.reversalRx.hasMatch(desc)) x.flags.add('reversal');
    if (lx.cancelledRx.hasMatch('${x.extra.values.join(' ')} $desc')) x.flags.add('cancelled');
    txns.add(x);
  }
  return (txns, specials);
}

final _wsRun = RegExp(r'\s+');

/// Join narration fragments; no space where a wrapped line ended on '/' or '-'.
String smartJoin(List<String> parts) {
  var out = '';
  for (var p in parts) {
    p = p.trim();
    if (p.isEmpty) continue;
    if (out.isEmpty) {
      out = p;
    } else if ('/-@:'.contains(out[out.length - 1]) || '/-@'.contains(p[0])) {
      out += p;
    } else {
      out += ' $p';
    }
  }
  return out.replaceAll(_wsRun, ' ').trim();
}

// ------------------------------------------------------------------ order + chain

String detectOrder(List<Txn> txns) {
  final ds = [for (final t in txns) if (t.date != null) t.date!];
  var inc = 0, dec = 0;
  for (var i = 0; i + 1 < ds.length; i++) {
    if (ds[i + 1].isAfter(ds[i])) inc++;
    if (ds[i + 1].isBefore(ds[i])) dec++;
  }
  if (dec > inc * 2 && dec >= 2) return 'desc';
  if (inc == 0 && dec == 0 && txns.length >= 2) {
    // same-day statement: let the balance chain decide
    final fwd = _chainFit(txns);
    final bwd = _chainFit(txns.reversed.toList());
    return bwd > fwd ? 'desc' : 'asc';
  }
  return 'asc';
}

int _chainFit(List<Txn> seq) {
  var ok = 0;
  Dec? prev;
  for (final t in seq) {
    if (t.balance != null) {
      if (prev != null && t.magnitude != null && ((t.balance! - prev).abs() - t.magnitude!).abs() < cent) ok++;
      prev = t.balance;
    }
  }
  return ok;
}

Map<String, dynamic> reconcileSection(List<Txn> txns, List<Map<String, dynamic>> specials, [String? orderHint]) {
  final order = orderHint ?? detectOrder(txns);
  final seq = order == 'desc' ? txns.reversed.toList() : [...txns];
  Dec? opening;
  for (final s in specials) {
    if (s['kind'] == 'open' && s['balance'] != null) {
      opening = s['balance'] as Dec;
      break;
    }
  }
  Dec? closingPrinted;
  for (final s in specials.reversed) {
    if (s['kind'] == 'close' && s['balance'] != null) {
      closingPrinted = s['balance'] as Dec;
      break;
    }
  }
  final stats = <String, int>{'chain_ok': 0, 'chain_break': 0, 'sign_from_balance': 0, 'conflicts': 0, 'gap_solved': 0, 'unresolved': 0};

  // pass 1: rows with their own balance
  var prev = opening;
  var gap = <Txn>[];
  for (final t in seq) {
    if (t.balance == null) {
      gap.add(t);
      continue;
    }
    if (prev == null) {
      // first balance with unknown opening: derive opening when the sign is known
      if (t.sign != null && t.magnitude != null && gap.isEmpty) {
        prev = t.balance! - t.amount!;
        opening = prev;
      }
    }
    if (prev != null) {
      final delta = t.balance! - prev;
      if (gap.isNotEmpty) {
        _solveGap(gap, t, delta, stats);
        gap = [];
      } else {
        _applyDelta(t, delta, stats);
      }
    } else {
      gap = [];
    }
    prev = t.balance;
  }
  if (gap.isNotEmpty && prev != null && closingPrinted != null) {
    // trailing rows without balance: solve against the printed closing
    final last = Txn(null, null, '', '', null, null, closingPrinted, 0, 0, magnitude: zero, sign: 1);
    _solveGap(gap, last, closingPrinted - prev, stats);
  }
  for (final t in seq) {
    if (t.sign == null) {
      stats['unresolved'] = stats['unresolved']! + 1;
      t.flags.add('sign_unknown');
    }
    if (t.sign != null) {
      if (t.sign! < 0) {
        t.debit = t.magnitude;
        t.credit = null;
      } else {
        t.debit = null;
        t.credit = t.magnitude;
      }
    }
    t.confidence = _confidence(t);
  }

  // fill running balance for rows the bank printed without one (end-of-day style), when the chain is solid
  if (opening != null) {
    var run = opening;
    for (final t in seq) {
      if (t.amount == null) break;
      if (!t.flags.contains('cancelled')) run = run + t.amount!;
      if (t.balance == null) {
        t.balance = run;
        t.flags.add('balance_computed');
      } else if ((t.balance! - run).abs() >= cent) {
        run = t.balance!; // trust the printed balance and continue from it
      }
    }
  }

  final known = [for (final t in seq) if (t.amount != null && !t.flags.contains('cancelled')) t];
  var credits = zero, debits = zero;
  for (final t in known) {
    final a = t.amount!;
    if (a > zero) credits = credits + a;
  }
  for (final t in known) {
    final a = t.amount!;
    if (a < zero) debits = debits + (-a);
  }
  Dec? lastBal;
  for (final t in seq.reversed) {
    if (t.balance != null) {
      lastBal = t.balance;
      break;
    }
  }
  if (opening == null && lastBal != null) {
    // balances everywhere but first sign unknown: back-solve from the first balance row
    final first = seq.where((t) => t.balance != null).first;
    if (first.amount != null) opening = first.balance! - first.amount!;
  }
  final computedClose = opening != null ? opening + credits - debits : null;
  final closing = closingPrinted ?? lastBal;
  final checks = <String, dynamic>{
    'order': order,
    'opening': _s(opening),
    'closing': _s(closing),
    'closing_source': closingPrinted != null ? 'printed' : (lastBal != null ? 'last_balance' : null),
    'credits': _s(credits),
    'debits': _s(debits),
    'computed_closing': _s(computedClose),
    'balanced': computedClose != null && closing != null && (computedClose - closing).abs() < cent,
    ...stats,
  };
  if (lastBal != null && closingPrinted != null && (lastBal - closingPrinted).abs() >= cent) {
    checks['closing_vs_last_balance'] = _s(closingPrinted - lastBal);
  }
  // printed totals rows
  for (final s in specials) {
    if (s['kind'] == 'total') {
      final vals = [
        for (final vs in (s['values'] as Map<String, List<String>>).values) for (final v in vs) Dec.parse(v),
      ];
      if (vals.isNotEmpty) {
        final matches = vals.any((v) => v.abs() == credits || v.abs() == debits);
        (checks.putIfAbsent('totals_rows', () => <Map<String, dynamic>>[]) as List).add({
          'text': String.fromCharCodes((s['text'] as String).runes.take(60)),
          'values': [for (final v in vals) _s(v)],
          'matches_rows': matches,
        });
      }
    }
  }
  return checks;
}

void _applyDelta(Txn t, Dec delta, Map<String, int> stats) {
  if (t.magnitude == null) {
    t.magnitude = delta.abs();
    t.sign = delta >= zero ? 1 : -1;
    t.signSource = 'balance_only';
    t.flags.add('amount_from_balance');
    stats['sign_from_balance'] = stats['sign_from_balance']! + 1;
    return;
  }
  if ((delta.abs() - t.magnitude!).abs() < cent) {
    final s = delta > zero ? 1 : (delta < zero ? -1 : (t.sign ?? 1));
    if (t.sign != null && s != t.sign && !t.magnitude!.isZero) {
      t.flags.add('column_sign_conflict');
      stats['conflicts'] = stats['conflicts']! + 1;
    }
    if (t.sign == null) {
      stats['sign_from_balance'] = stats['sign_from_balance']! + 1;
      t.signSource = 'balance';
    }
    t.sign = s;
    stats['chain_ok'] = stats['chain_ok']! + 1;
  } else {
    t.flags.add('balance_break');
    stats['chain_break'] = stats['chain_break']! + 1;
  }
}

/// `itertools.product((1, -1), repeat=n)` in the same order, as sums of `m * magnitude`.
Iterable<(List<int>, Dec)> _signCombos(List<Txn> ts) sync* {
  final n = ts.length;
  for (var mask = 0; mask < (1 << n); mask++) {
    final combo = [for (var i = 0; i < n; i++) ((mask >> (n - 1 - i)) & 1) == 0 ? 1 : -1];
    var s = zero;
    for (var i = 0; i < n; i++) {
      s = s + (combo[i] > 0 ? ts[i].magnitude! : -ts[i].magnitude!);
    }
    yield (combo, s);
  }
}

/// Rows between two balances: find signs for unknown rows so the sum matches the delta.
void _solveGap(List<Txn> gap, Txn anchor, Dec delta, Map<String, int> stats) {
  final rows = [...gap, anchor];
  var known = zero;
  for (final t in rows) {
    if (t.amount != null) known = known + t.amount!;
  }
  final unknown = [for (final t in rows) if (t.amount == null && t.magnitude != null) t];
  final target = delta - known;
  if (unknown.isEmpty) {
    if (target.abs() < cent) {
      stats['chain_ok'] = stats['chain_ok']! + 1;
    } else {
      // maybe the column-derived signs are wrong: try flipping (small groups only)
      final flips = [for (final t in rows) if (t.magnitude != null) t];
      if (flips.isNotEmpty && flips.length <= 12) {
        for (final (combo, s) in _signCombos(flips)) {
          if ((s - delta).abs() < cent) {
            for (var i = 0; i < flips.length; i++) {
              if (flips[i].sign != combo[i]) {
                flips[i].flags.add('column_sign_conflict');
                stats['conflicts'] = stats['conflicts']! + 1;
              }
              flips[i].sign = combo[i];
            }
            stats['gap_solved'] = stats['gap_solved']! + 1;
            return;
          }
        }
      }
      anchor.flags.add('balance_break');
      stats['chain_break'] = stats['chain_break']! + 1;
    }
    return;
  }
  if (unknown.length > 14) return;
  final sols = <List<int>>[];
  for (final (combo, s) in _signCombos(unknown)) {
    if ((s - target).abs() < cent) {
      sols.add(combo);
      if (sols.length > 1) break;
    }
  }
  if (sols.length == 1) {
    for (var i = 0; i < unknown.length; i++) {
      unknown[i].sign = sols.first[i];
      unknown[i].signSource = 'balance_gap';
    }
    stats['gap_solved'] = stats['gap_solved']! + 1;
  } else if (sols.length > 1) {
    for (final t in unknown) {
      t.flags.add('sign_ambiguous');
    }
  } else {
    anchor.flags.add('balance_break');
    stats['chain_break'] = stats['chain_break']! + 1;
  }
}

double _confidence(Txn t) {
  var c = 1.0;
  if (t.sign == null) return 0.3;
  if (t.flags.contains('balance_break')) c -= 0.35;
  if (t.flags.contains('column_sign_conflict')) c -= 0.1;
  if (t.signSource == 'section' && t.balance == null) c -= 0.15;
  if (t.signSource == 'balance_gap') c -= 0.1;
  if (t.flags.contains('date_carried') && t.date == null) c -= 0.2;
  if (t.flags.contains('invalid_date')) c -= 0.1;
  if (t.flags.contains('repaired_number')) c -= 0.1;
  if (t.date == null) c -= 0.25;
  return c > 0.05 ? c : 0.05;
}
