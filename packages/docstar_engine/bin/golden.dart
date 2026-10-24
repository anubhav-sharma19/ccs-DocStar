/// Golden harness (PORT_PLAN G1): parse every <name>.words.json in a corpus folder, write <name>.pred.json
/// (for `eval/run_eval.py --pred-dir`) and compare with <name>.expected.json.
///
///   dart run bin/golden.dart <corpus-dir> --out <pred-dir> [--banks assets/banks.json] [--show N]
import 'dart:convert';
import 'dart:io';

import 'package:docstar_engine/docstar_engine.dart';

const keep = [
  'file', 'pages', 'bank', 'account_last4', 'period', 'locale', 'summary_printed', 'summary_checks',
  'sections', 'transaction_count', 'warnings', 'quality',
];

/// First difference as a path, or null. Numbers compare exactly, except confidence/score (+-0.01).
String? diff(Object? a, Object? b, [String path = '']) {
  if (a is Map && b is Map) {
    for (final k in {...a.keys, ...b.keys}) {
      final d = diff(a[k], b[k], '$path/$k');
      if (d != null) return d;
    }
    return null;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return '$path (length ${a.length} vs ${b.length})';
    for (var i = 0; i < a.length; i++) {
      final d = diff(a[i], b[i], '$path[$i]');
      if (d != null) return d;
    }
    return null;
  }
  if (a is num && b is num) {
    final tol = path.endsWith('/confidence') || path.endsWith('/score') ? 0.0100001 : 0;
    return (a - b).abs() <= tol ? null : '$path ($a vs $b)';
  }
  return a == b ? null : '$path (${jsonEncode(a)} vs ${jsonEncode(b)})';
}

void main(List<String> args) {
  final dir = Directory(args.first);
  String opt(String n, String d) => args.contains(n) ? args[args.indexOf(n) + 1] : d;
  final out = Directory(opt('--out', 'pred'))..createSync(recursive: true);
  final show = int.parse(opt('--show', '10'));
  final banks = [for (final b in jsonDecode(File(opt('--banks', 'assets/banks.json')).readAsStringSync())['banks'] as List) b as Map<String, dynamic>];
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.words.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  var same = 0, mlGap = 0;
  final bad = <String>[];
  for (final f in files) {
    final stem = f.uri.pathSegments.last.replaceFirst('.words.json', '');
    final doc = loadWords(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
    final res = parseDocument(doc, banks: banks);
    final pred = jsonDecode(jsonEncode({for (final k in keep) if (res.containsKey(k)) k: res[k]})) as Map<String, dynamic>;
    File('${out.path}/$stem.pred.json').writeAsStringSync(jsonEncode(pred));
    final exp = jsonDecode(File('${dir.path}/$stem.expected.json').readAsStringSync()) as Map<String, dynamic>;
    if (exp['bank'] is Map && (exp['bank'] as Map)['source'] == 'ml') {
      mlGap++; // R9: bank recovered by the Python ML layer; not ported
      exp['bank'] = pred['bank'];
    }
    final d = diff(pred, exp);
    if (d == null) {
      same++;
    } else {
      bad.add('$stem  $d');
    }
  }
  print('G1 ${dir.path}: ${files.length} docs, identical=$same, different=${bad.length} (ml-bank gap, ignored: $mlGap)');
  bad.take(show).forEach(print);
  exit(bad.isEmpty ? 0 : 1);
}
