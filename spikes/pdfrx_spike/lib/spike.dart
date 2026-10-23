// THROWAWAY spike logic. PRIVACY: nothing here may emit, log, store or return
// text content, amounts, names or numbers from a document. Output = counts,
// timings, codepoints (as U+XXXX), booleans. Fixture mode may compare probe
// strings because fixtures are generated fakes.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';

typedef PwProvider = Future<String?> Function();

class OpenResult {
  OpenResult(this.doc, this.outcome, this.providerCalls, this.openMs);
  final PdfDocument? doc;
  final String outcome; // opened | password_failed_or_cancelled | error:<Type>
  final int providerCalls;
  final int openMs;
}

Future<OpenResult> openPdf(Uint8List bytes, PwProvider provider) async {
  var calls = 0;
  final sw = Stopwatch()..start();
  try {
    final doc = await PdfDocument.openData(bytes, passwordProvider: () async {
      calls++;
      return provider();
    });
    return OpenResult(doc, 'opened', calls, sw.elapsedMilliseconds);
  } on PdfPasswordException {
    return OpenResult(null, 'password_failed_or_cancelled', calls, sw.elapsedMilliseconds);
  } catch (e) {
    return OpenResult(null, 'error:${e.runtimeType}', calls, sw.elapsedMilliseconds);
  }
}

String cp(int c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}';

bool isPua(int c) => (c >= 0xE000 && c <= 0xF8FF) || (c >= 0xF0000 && c <= 0x10FFFF);

/// FNV-1a over text + rect doubles. Used only for equal/not-equal between two runs.
class Digest {
  int h = 0xcbf29ce484222325;
  static const _p = 0x100000001b3;
  void addInt(int v) {
    for (var i = 0; i < 8; i++) {
      h = ((h ^ ((v >> (i * 8)) & 0xff)) * _p) & 0xFFFFFFFFFFFFFFFF;
    }
  }

  void addDouble(double d) {
    final b = ByteData(8)..setFloat64(0, d);
    addInt(b.getInt64(0));
  }
}

class PageData {
  PageData(this.page, this.raw, this.extractMs);
  final PdfPage page;
  final PdfPageRawText raw;
  final int extractMs;
}

/// Aggregated, content-free statistics for one document run.
class DocStats {
  final pages = <Map<String, Object?>>[];
  final before = <int, int>{}; // codepoint directly before an amount-like token
  final after = <int, int>{}; // codepoint directly after
  final puaCodepoints = <int>{};
  int totalChars = 0;
  int digest = 0;
  int maxExtractMs = 0;
}

final _amount = RegExp(r'(?:\d{1,3}(?:,\d{2})*,\d{3}|\d+)\.\d{2}');

void _bump(Map<int, int> m, int c) => m[c] = (m[c] ?? 0) + 1;

/// Extract every page. Returns per-page raw data (kept only if [keep]) and stats.
Future<DocStats> extractAll(PdfDocument doc, {List<PageData>? keep}) async {
  final s = DocStats();
  final d = Digest();
  for (final page in doc.pages) {
    final sw = Stopwatch()..start();
    final raw = await page.loadText();
    final ms = sw.elapsedMilliseconds;
    if (raw == null) {
      s.pages.add({'page': page.pageNumber, 'loaded': false});
      continue;
    }
    keep?.add(PageData(page, raw, ms));
    final text = raw.fullText;
    var nonSpace = 0, emptyRects = 0, emptyNonSpace = 0, inside = 0;
    for (var i = 0; i < raw.charRects.length; i++) {
      final r = raw.charRects[i];
      final c = text.codeUnitAt(i);
      if (c > 32) nonSpace++;
      if (r.isEmpty) {
        emptyRects++;
        if (c > 32) emptyNonSpace++;
      }
      final cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
      // plausible if centre lies in either the page box or its swapped box (frame unknown)
      final w = page.width, h = page.height;
      if ((cx >= 0 && cx <= w && cy >= 0 && cy <= h) || (cx >= 0 && cx <= h && cy >= 0 && cy <= w)) inside++;
      d.addDouble(r.left);
      d.addDouble(r.top);
      d.addDouble(r.right);
      d.addDouble(r.bottom);
    }
    final runes = text.runes.toList();
    for (final r in runes) {
      d.addInt(r);
      if (isPua(r)) s.puaCodepoints.add(r);
    }
    for (final m in _amount.allMatches(text)) {
      var i = m.start - 1;
      var skipped = 0;
      while (i >= 0 && text.codeUnitAt(i) == 0x20 && skipped < 2) {
        i--;
        skipped++;
      }
      if (i >= 0) _bump(s.before, text.codeUnitAt(i));
      var j = m.end;
      skipped = 0;
      while (j < text.length && text.codeUnitAt(j) == 0x20 && skipped < 2) {
        j++;
        skipped++;
      }
      if (j < text.length) _bump(s.after, text.codeUnitAt(j));
    }
    s.totalChars += raw.charRects.length;
    s.maxExtractMs = math.max(s.maxExtractMs, ms);
    s.pages.add({
      'page': page.pageNumber,
      'loaded': true,
      'width_pt': page.width,
      'height_pt': page.height,
      'rotation_deg': page.rotation.index * 90,
      'chars': raw.charRects.length,
      'non_space_chars': nonSpace,
      'rects_equal_text_length': raw.charRects.length == text.length,
      'empty_rects': emptyRects,
      'empty_rects_non_space': emptyNonSpace,
      'rect_centres_plausible': inside,
      'extract_ms': ms,
      'amount_like_tokens': _amount.allMatches(text).length,
    });
  }
  s.digest = d.h;
  return s;
}

/// Digits are merged into one bucket so no digit frequencies leave the device.
Map<String, int> hist(Map<int, int> m) {
  final out = <String, int>{};
  for (final e in m.entries) {
    final k = (e.key >= 0x30 && e.key <= 0x39) ? 'DIGIT' : cp(e.key);
    out[k] = (out[k] ?? 0) + e.value;
  }
  return out;
}

/// Codepoint summary: only symbol/punctuation/letter codepoints, never digits.
Map<String, Object?> codepointReport(DocStats s) {
  final b = hist(s.before), a = hist(s.after);
  bool has(Map<int, int> m, int c) => m.containsKey(c);
  return {
    'before_amount': b,
    'after_amount': a,
    'has_u20b9_before_amount': has(s.before, 0x20B9),
    'has_backtick_before_amount': has(s.before, 0x60),
    'has_letter_C_before_amount': has(s.before, 0x43),
    'has_pua_anywhere': s.puaCodepoints.isNotEmpty,
    'pua_codepoints': s.puaCodepoints.map(cp).toList()..sort(),
  };
}

// ---- rotation / frame detection (FIXTURES ONLY: compares probe strings) ----

class Probe {
  Probe(this.text, this.x, this.y, this.size, this.width);
  final String text;
  final double x, y, size, width;
  factory Probe.fromJson(Map<String, dynamic> j) =>
      Probe(j['text'], (j['x'] as num).toDouble(), (j['y'] as num).toDouble(), (j['size'] as num).toDouble(), (j['width'] as num).toDouble());
}

/// Map a point in the unrotated page frame (origin bottom-left, points) to the
/// displayed frame (origin top-left). w0/h0 = unrotated size.
(double, double) toDisplay(double x, double y, int rotDeg, double w0, double h0) {
  switch (rotDeg) {
    case 90:
      return (y, x);
    case 180:
      return (w0 - x, y);
    case 270:
      return (h0 - y, w0 - x);
    default:
      return (x, h0 - y);
  }
}

/// Returns {frame, errUnrotated, errDisplay, chars} for one probe on one page.
Map<String, Object?> checkProbe(PageData pd, Probe p, int rotDeg, List<double>? crop) {
  final text = pd.raw.fullText;
  final i = text.indexOf(p.text);
  if (i < 0) return {'found': false};
  double l = 1e9, t = -1e9, r = -1e9, b = 1e9;
  for (var k = i; k < i + p.text.length; k++) {
    final q = pd.raw.charRects[k];
    l = math.min(l, q.left);
    r = math.max(r, q.right);
    t = math.max(t, q.top);
    b = math.min(b, q.bottom);
  }
  final ox = (l + r) / 2, oy = (t + b) / 2; // observed centre as reported (bottom-left origin)
  final offX = crop?[0] ?? 0, offY = crop?[1] ?? 0;
  final cx0 = p.x + p.width / 2 - offX, cy0 = p.y + p.size * 0.35 - offY; // expected, unrotated frame
  final w0 = crop != null ? crop[2] - crop[0] : 595.0, h0 = crop != null ? crop[3] - crop[1] : 842.0;
  final (xd, ydTop) = toDisplay(cx0, cy0, rotDeg, w0, h0);
  final dispH = (rotDeg == 90 || rotDeg == 270) ? w0 : h0;
  final cxD = xd, cyD = dispH - ydTop; // expected, displayed frame, bottom-left origin
  final errU = math.sqrt(math.pow(ox - cx0, 2) + math.pow(oy - cy0, 2));
  final errD = math.sqrt(math.pow(ox - cxD, 2) + math.pow(oy - cyD, 2));
  final tol = p.size * 0.6 + 2;
  return {
    'found': true,
    'err_unrotated_pt': double.parse(errU.toStringAsFixed(2)),
    'err_display_pt': double.parse(errD.toStringAsFixed(2)),
    'tol_pt': tol,
    'matches_unrotated': errU <= tol,
    'matches_display': errD <= tol,
  };
}

String memJson() => '${ProcessInfo.currentRss}/${ProcessInfo.maxRss}';
