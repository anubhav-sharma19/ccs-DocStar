// DocStar CLI (macOS): batch metrics for local PDFs; --visual draws layout overlays
// (words, lines, blocks, table grids; see lib/overlay.dart for the colours).
//   dart run bin/docstar_cli.dart --in <folder-or-file> --out <folder outside any git repo> [--visual]
// Passwords: hidden TTY prompt only. Never args, never stored, never written.
// metrics.json: labels + numbers + codepoint counts only. No names, paths, text or hashes.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:docstar_cli/overlay.dart';
import 'package:docstar_core/docstar_core.dart';
import 'package:docstar_pdfium/docstar_pdfium.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

Never _die(String msg) {
  stderr.writeln(msg);
  exit(2);
}

Future<void> main(List<String> args) async {
  String? inArg, outArg;
  var visual = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--in':
        inArg = i + 1 < args.length ? args[++i] : null;
      case '--out':
        outArg = i + 1 < args.length ? args[++i] : null;
      case '--visual':
        visual = true;
      // Deliberately not echoed: an unknown arg could be a password.
      default:
        _die('Unknown argument. Usage: --in <folder-or-file> --out <folder> [--visual]\n'
            'Passwords are never accepted as arguments; you are prompted when needed.');
    }
  }
  if (inArg == null || outArg == null) _die('Usage: dart run bin/docstar_cli.dart --in <folder-or-file> --out <folder> [--visual]');
  _refuseInsideGit(outArg);

  final files = FileSystemEntity.isDirectorySync(inArg)
      ? (Directory(inArg).listSync(recursive: true, followLinks: false).whereType<File>().map((f) => f.path).where((p) => p.toLowerCase().endsWith('.pdf')).toList()..sort())
      : File(inArg).existsSync()
          ? [inArg]
          : _die('--in not found');
  if (files.isEmpty) _die('No PDFs found.');
  Directory(outArg).createSync(recursive: true);

  // Ctrl-C during the hidden prompt would leave the terminal with echo off.
  final sigint = ProcessSignal.sigint.watch().listen((_) {
    try {
      stdin.echoMode = true;
    } on StdinException {}
    exit(130);
  });
  await pdfrxInitialize();

  final results = <Map<String, Object?>>[];
  final names = <String>[]; // real names: terminal only
  for (var i = 0; i < files.length; i++) {
    final label = 'file_${(i + 1).toString().padLeft(2, '0')}';
    names.add(files[i].split(Platform.pathSeparator).last);
    stdout.writeln('[$label] ${names.last}');
    results.add(await _measure(files[i], names.last, label, visual ? '$outArg/visual/$label' : null));
  }

  File('$outArg/metrics.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'engine': 'pdfrx_engine 0.8.0, pdfium chromium/7811',
    'dart': Platform.version.split(' (').first,
    'os': Platform.operatingSystem,
    'process_max_rss_mb': _mb(ProcessInfo.maxRss),
    'files': results,
  }));
  _table(results, names);
  stdout.writeln('\nWrote $outArg/metrics.json (no filenames inside). MB = sampled in-process RSS: earlier files inflate the baseline.');
  await sigint.cancel(); // an active signal listener would keep the process alive
  if (visual) stdout.writeln('Visual overlays in $outArg/visual/ contain your document content. Keep them local.');
}

/// Fails closed: if git can't confirm "not a repo", we refuse.
void _refuseInsideGit(String out) {
  var d = Directory(out).absolute;
  while (!d.existsSync()) {
    d = d.parent;
  }
  final ProcessResult r;
  try {
    r = Process.runSync('git', ['-C', d.resolveSymbolicLinksSync(), 'rev-parse', '--git-dir']);
  } on ProcessException {
    _die('Cannot run git to verify --out is outside a repo. Refusing.');
  }
  if (r.exitCode == 0) {
    _die('Refusing: --out is inside a git repo. Use a folder on your external SSD instead.');
  }
  if (!'${r.stderr}'.contains('not a git repository')) _die('Could not verify --out is outside a git repo. Refusing.');
}

String? _askPassword(String name, int attempt) {
  try {
    stdin.echoMode = false; // throws when stdin isn't a real TTY (e.g. redirected from /dev/null)
  } on StdinException {
    stderr.writeln('  locked and no terminal for a password prompt: skipping');
    return null;
  }
  stdout.write(attempt == 0 ? '  Password for $name (Enter = skip): ' : '  Wrong password. Retry (Enter = skip): ');
  try {
    final pw = stdin.readLineSync();
    return pw == null || pw.isEmpty ? null : pw;
  } finally {
    stdin.echoMode = true;
    stdout.writeln();
  }
}

// Heuristic scan of the raw /Encrypt dictionary (works even when the file is locked).
// ponytail: window = enclosing object text; exotic layouts return 'encrypted-unknown'.
String _encryption(Uint8List b) {
  final s = latin1.decode(b);
  if (!s.contains('/Encrypt')) return 'none';
  final f = s.indexOf(RegExp(r'/Filter\s*/Standard'));
  if (f < 0) return 'encrypted-unknown';
  final end = s.indexOf('endobj', f);
  final w = s.substring(max(0, s.lastIndexOf('obj', f)), min(f + 2000, end < 0 ? s.length : end));
  final r = int.tryParse(RegExp(r'/R\s+(\d)').firstMatch(w)?.group(1) ?? '');
  if (r != null && r >= 5) return 'AES-256';
  switch (RegExp(r'/CFM\s*/(\w+)').firstMatch(w)?.group(1)) {
    case 'AESV3':
      return 'AES-256';
    case 'AESV2':
      return 'AES-128';
    case 'V2':
      return 'RC4';
  }
  final v = RegExp(r'/V\s+(\d)').firstMatch(w)?.group(1);
  return v == '1' ? 'RC4-40' : (v == '2' || v == '3') ? 'RC4' : 'encrypted-unknown';
}

bool _pua(int c) => (c >= 0xE000 && c <= 0xF8FF) || (c >= 0xF0000 && c <= 0xFFFFD) || (c >= 0x100000 && c <= 0x10FFFD);
bool _digit(int c) => c >= 0x30 && c <= 0x39;
bool _space(int c) => String.fromCharCode(c).trim().isEmpty;
String _cp(int c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}';
double _mb(int bytes) => double.parse((bytes / 1048576).toStringAsFixed(1));
double _ms(Stopwatch s) => s.elapsedMicroseconds / 1000;

Future<PdfPageRawText?> _text(PdfPage p) async {
  try {
    return await p.loadText();
  } catch (_) {
    return null;
  }
}

String _hash(PdfPageRawText t) =>
    sha256.convert(utf8.encode('${t.fullText}\u0000${t.charRects.map((r) => '${r.left},${r.top},${r.right},${r.bottom}').join(';')}')).toString();

/// Looks like real content (not a blank page)? Cheap 200px render.
Future<bool> _hasInk(PdfPage p) async {
  const w = 200;
  final h = max(1, (w * p.height / p.width).round());
  final im = await p.render(width: w, height: h, fullWidth: w.toDouble(), fullHeight: h.toDouble(), backgroundColor: 0xffffffff);
  if (im == null) throw StateError('render null');
  try {
    final px = im.pixels;
    var ink = 0;
    for (var i = 0; i < px.length; i += 4) {
      if (px[i] < 0xF0 || px[i + 1] < 0xF0 || px[i + 2] < 0xF0) ink++;
    }
    return ink > px.length / 4 * 0.002;
  } finally {
    im.dispose();
  }
}

Future<Map<String, Object?>> _measure(String path, String name, String label, String? visualDir) async {
  final m = <String, Object?>{'file': label, 'size_kb': File(path).lengthSync() ~/ 1024};
  m['encryption'] = _encryption(File(path).readAsBytesSync());
  final rss0 = ProcessInfo.currentRss;
  var peak = rss0;
  void sample() => peak = max(peak, ProcessInfo.currentRss);

  var promptMs = 0, attempts = 0;
  final sw = Stopwatch()..start();
  final PdfDocument doc;
  try {
    doc = await PdfDocument.openFile(path, passwordProvider: () {
      final t = Stopwatch()..start();
      final pw = _askPassword(name, attempts++);
      promptMs += t.elapsedMilliseconds;
      return pw;
    });
  } on PdfPasswordException {
    return m..['open'] = 'password-locked'..['password_attempts'] = attempts;
  } catch (e) {
    return m
      ..['open'] = 'failed'
      ..['error_type'] = e.runtimeType.toString()
      ..['error_code'] = e is PdfException ? e.errorCode : null;
  }
  m['open'] = 'ok';
  m['needed_password'] = attempts > 0;
  m['open_ms'] = sw.elapsedMilliseconds - promptMs;
  sample();

  try {
    var chars = 0, empty = 0, rotated = 0, mismatch = 0, errors = 0, text = 0, imageOnly = 0, blank = 0;
    var cRupee = 0, cTick = 0, cPua = 0, cNul = 0;
    final adj = <int, int>{};
    final rot = <int>[], pageChars = <int>[], pageMs = <double>[], h1 = <String>[];
    for (final page in doc.pages) {
      rot.add(page.rotation.index * 90);
      if (page.rotation.index != 0) rotated++;
      final t = Stopwatch()..start();
      final raw = await _text(page);
      t.stop();
      pageMs.add(_ms(t));
      sample();
      if (raw == null) {
        errors++;
        pageChars.add(-1);
        h1.add('err');
        continue;
      }
      h1.add(_hash(raw));
      final runes = raw.fullText.runes.toList(); // rune i <-> charRects[i]
      if (runes.length != raw.charRects.length) mismatch++;
      pageChars.add(raw.charRects.length);
      chars += raw.charRects.length;
      for (var i = 0; i < runes.length; i++) {
        final c = runes[i];
        if (c == 0x20B9) cRupee++;
        if (c == 0x60) cTick++;
        if (c == 0) cNul++;
        if (_pua(c)) cPua++;
        if (_space(c)) continue;
        if (i < raw.charRects.length && raw.charRects[i].isEmpty) empty++;
        if (!_digit(c) && ((i > 0 && _digit(runes[i - 1])) || (i + 1 < runes.length && _digit(runes[i + 1])))) {
          adj[c] = (adj[c] ?? 0) + 1;
        }
      }
      if (raw.charRects.length >= 5) {
        text++;
      } else {
        try {
          await _hasInk(page) ? imageOnly++ : blank++;
        } catch (_) {
          errors++;
        }
      }
    }
    // ponytail: a scan with a few stray text chars (page numbers) counts as 'text'; raise the 5-char threshold if needed.
    final h2 = <String>[];
    for (final p in doc.pages) {
      final r = await _text(p);
      h2.add(r == null ? 'err' : _hash(r));
    }

    m
      ..['pages'] = doc.pages.length
      ..['chars_total'] = chars
      ..['chars_per_page'] = pageChars
      ..['empty_boxes_nonspace'] = empty
      ..['rotation_per_page'] = rot
      ..['rotated_pages_needing_box_conversion'] = rotated
      ..['char_box_count_mismatch_pages'] = mismatch
      ..['page_errors'] = errors
      ..['text_layer'] = text > 0 && imageOnly == 0 ? 'real' : text > 0 ? 'mixed' : imageOnly > 0 ? 'scanned' : 'blank'
      ..['pages_text_image_only_blank'] = [text, imageOnly, blank]
      ..['count_u20b9'] = cRupee
      ..['count_backtick'] = cTick
      ..['count_private_use'] = cPua
      ..['count_nul'] = cNul
      ..['adjacent_to_digits'] = {for (final e in (adj.entries.toList()..sort((a, b) => b.value - a.value))) _cp(e.key): e.value}
      ..['extract_ms_total'] = double.parse(pageMs.fold(0.0, (a, b) => a + b).toStringAsFixed(1))
      ..['extract_ms_per_page'] = pageMs.map((v) => double.parse(v.toStringAsFixed(1))).toList()
      ..['deterministic'] = h1.join() == h2.join()
      ..['rss_start_mb'] = _mb(rss0)
      ..['peak_rss_mb'] = _mb(peak);
    final pages = await pagesOf(doc);
    if (pages != null) {
      final laid = layout(pages);
      m['layout'] = _layoutCounts(laid);
      if (visualDir != null) await drawOverlays(doc, laid, visualDir);
    }
  } finally {
    await doc.dispose();
  }
  return m;
}

/// Layout shape only (counts, sizes, booleans): no text.
Map<String, Object?> _layoutCounts(DsDocument d) => {
      'words': d.pages.fold<int>(0, (n, p) => n + p.words.length),
      'lines': d.pages.fold<int>(0, (n, p) => n + p.lines.length),
      'blocks': {
        for (final l in BlockLabel.values)
          l.name: d.pages.fold<int>(0, (n, p) => n + p.blocks.where((b) => b.label == l).length)
      },
      'reading_rotation_per_page': [for (final p in d.pages) p.readingRotation],
      'tables': [
        for (final t in d.tables)
          {
            'rows': t.rows,
            'cols': t.cols,
            'method': t.method.name,
            'header': t.headerRow != null,
            'linked_to_previous_page': t.continuesFrom != null,
          }
      ],
    };

void _table(List<Map<String, Object?>> rs, List<String> names) {
  const cols = ['file', 'name', 'open', 'pg', 'chars', 'emptyBox', 'rot', 'enc', 'open_ms', 'ms/pg', 'MB', 'det', 'layer', 'tables', 'flags'];
  String g(Map<String, Object?> m, String k) => '${m[k] ?? '-'}';
  final rows = <List<String>>[];
  for (var i = 0; i < rs.length; i++) {
    final m = rs[i];
    final pages = m['pages'] as int?;
    final flags = [
      if ((m['count_u20b9'] ?? 0) != 0) '20B9',
      if ((m['count_backtick'] ?? 0) != 0) '60',
      if ((m['count_private_use'] ?? 0) != 0) 'PUA',
      if ((m['count_nul'] ?? 0) != 0) 'NUL',
    ].join(',');
    rows.add([
      g(m, 'file'),
      names[i].length > 24 ? '${names[i].substring(0, 21)}...' : names[i],
      m['open'] == 'failed' ? 'failed:${m['error_type']}' : g(m, 'open'),
      g(m, 'pages'),
      g(m, 'chars_total'),
      g(m, 'empty_boxes_nonspace'),
      g(m, 'rotated_pages_needing_box_conversion'),
      g(m, 'encryption'),
      g(m, 'open_ms'),
      pages == null || pages == 0 ? '-' : ((m['extract_ms_total'] as double) / pages).toStringAsFixed(1),
      g(m, 'peak_rss_mb'),
      m['deterministic'] == null ? '-' : (m['deterministic'] == true ? 'yes' : 'NO'),
      g(m, 'text_layer'),
      _tablesCell(m['layout']),
      flags.isEmpty ? '-' : flags,
    ]);
  }
  final w = [for (var c = 0; c < cols.length; c++) rows.fold(cols[c].length, (a, r) => max(a, r[c].length))];
  String line(List<String> r) => [for (var c = 0; c < r.length; c++) r[c].padRight(w[c])].join('  ');
  stdout
    ..writeln('\n${line(cols)}')
    ..writeln(w.map((n) => '-' * n).join('  '));
  rows.forEach((r) => stdout.writeln(line(r)));
}

/// "3 (2 linked)": tables found and how many continue a previous page's table.
String _tablesCell(Object? layout) {
  if (layout is! Map) return '-';
  final t = layout['tables'] as List;
  final linked = t.where((e) => (e as Map)['linked_to_previous_page'] == true).length;
  return linked == 0 ? '${t.length}' : '${t.length} ($linked linked)';
}
