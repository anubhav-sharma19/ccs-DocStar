/// DocStar reader adapter (ENGINE_SPEC zone A) over pdfrx_engine / PDFium.
/// Bytes + password callback -> per-char boxes in the display frame.
///
/// PDFium is not safe for concurrent use: run DocStar on one isolate and read
/// PDFs one at a time. As a guard, [readPdf] turns on pdfrx's native
/// process-wide PDFium gate (calls from other isolates wait instead of crashing
/// the VM) and keeps one document open at a time per isolate.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:docstar_core/docstar_core.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Asked when the PDF is locked. [attempt] 0 = first ask (LOCKED); > 0 = the
/// previous password was wrong (WRONG_PASSWORD). Return null to cancel.
typedef PasswordProvider = Future<String?> Function(int attempt);

enum ReadFailure { corrupt, cancelled, noTextLayer }

sealed class ReadResult {
  const ReadResult();
}

class ReadOk extends ReadResult {
  final List<PageInput> pages;
  const ReadOk(this.pages);
}

/// Carries only the failure kind: never the password or any file text.
class ReadFailed extends ReadResult {
  final ReadFailure reason;
  const ReadFailed(this.reason);
}

/// Initializes PDFium with the process-wide gate on. Call it instead of
/// pdfrxInitialize(), once, before anything else touches PDFium (Flutter: pass
/// [tmpPath], e.g. getTemporaryDirectory()). [readPdf] calls it too.
Future<void> initDocstarPdfium({String? tmpPath}) async {
  try {
    Pdfrx.useProcessWidePdfiumGate = true;
  } on StateError {
    throw StateError('PDFium was started without the process-wide gate. '
        'Call initDocstarPdfium() instead of pdfrxInitialize(), before any PDFium use.');
  }
  await pdfrxInitialize(tmpPath: tmpPath, processWidePdfiumGate: true);
}

Future<void> _queue = Future.value();

/// One open document at a time in this isolate: a second concurrent call waits.
Future<ReadResult> readPdf(Uint8List bytes, {PasswordProvider? passwords}) {
  final result = _queue.then((_) => _readPdf(bytes, passwords));
  _queue = result.then((_) {}, onError: (_) {});
  return result;
}

Future<ReadResult> _readPdf(Uint8List bytes, PasswordProvider? passwords) async {
  await initDocstarPdfium();
  var attempts = 0;
  var cancelled = false;
  final PdfDocument doc;
  try {
    doc = await PdfDocument.openData(bytes, passwordProvider: () async {
      final p = passwords == null ? null : await passwords(attempts++);
      if (p == null) cancelled = true;
      return p;
    });
  } catch (_) {
    // Deliberately drops the exception: it may echo input. Only the kind leaves.
    return ReadFailed(cancelled ? ReadFailure.cancelled : ReadFailure.corrupt);
  }
  try {
    final pages = await pagesOf(doc);
    if (pages == null) return const ReadFailed(ReadFailure.corrupt);
    if (pages.every((p) => p.chars.every((c) => c.isSpace))) return const ReadFailed(ReadFailure.noTextLayer);
    return ReadOk(pages);
  } catch (_) {
    return const ReadFailed(ReadFailure.corrupt);
  } finally {
    await doc.dispose();
  }
}

/// Char boxes of an already-open document (for callers that also render it,
/// such as the CLI). Null if a page's text cannot be read.
Future<List<PageInput>?> pagesOf(PdfDocument doc) async {
  final pages = <PageInput>[];
  for (final page in doc.pages) {
    final raw = await page.loadText();
    if (raw == null) return null;
    pages.add(_pageInput(page, raw.fullText, raw.charRects));
  }
  return pages;
}

PageInput _pageInput(PdfPage page, String text, List<PdfRect> rects) {
  final rot = page.rotation.index * 90;
  final turned = rot == 90 || rot == 270;
  // pdfrx reports the rotated size; char rects are in the unrotated frame (spike item 2).
  final w0 = turned ? page.height : page.width, h0 = turned ? page.width : page.height;
  // One rect per code point (pdfrx writes each char with writeCharCode), not per UTF-16 unit.
  final runes = text.runes.toList();
  final n = runes.length < rects.length ? runes.length : rects.length;
  return PageInput(
    page.pageNumber,
    page.width,
    page.height,
    [for (var i = 0; i < n; i++) CharCell(i, String.fromCharCode(runes[i]), toDisplay(rects[i], rot, w0, h0))],
    rotation: rot,
  );
}

/// PDFium's unrotated frame (origin bottom-left, relative to the crop box) ->
/// display frame (top-left, rotation applied), rounded to 0.01 pt.
/// Table from spikes/pdfrx_spike/SPIKE_REPORT.md item 2.
Box toDisplay(PdfRect r, int rot, double w0, double h0) {
  (double, double) pt(double x, double y) => switch (rot) {
        90 => (y, x),
        180 => (w0 - x, y),
        270 => (h0 - y, w0 - x),
        _ => (x, h0 - y),
      };
  final (ax, ay) = pt(r.left, r.bottom);
  final (bx, by) = pt(r.right, r.top);
  return Box(q(ax < bx ? ax : bx), q(ay < by ? ay : by), q(ax < bx ? bx : ax), q(ay < by ? by : ay));
}
