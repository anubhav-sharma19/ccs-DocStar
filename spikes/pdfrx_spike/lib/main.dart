// THROWAWAY spike UI. See spike.dart for the privacy rules (metrics only).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'spike.dart';

const _autorun = String.fromEnvironment('AUTORUN');

void main() => runApp(const MaterialApp(home: SpikePage()));

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  String status = 'idle';
  String json = '';
  bool busy = false;
  bool inited = false;
  String frame = 'display'; // how charRects are interpreted by the overlay
  PdfDocument? viewDoc;
  List<PageData> viewPages = [];
  int viewIdx = 0;
  ui.Image? img;

  @override
  void initState() {
    super.initState();
    if (_autorun == '1') WidgetsBinding.instance.addPostFrameCallback((_) => selfTest());
  }

  Future<void> init() async {
    if (inited) return;
    await pdfrxInitialize(tmpPath: (await getTemporaryDirectory()).path);
    inited = true;
  }

  Future<String?> askPassword() => showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (c) {
          final ctl = TextEditingController();
          return AlertDialog(
            title: const Text('PDF password'),
            content: TextField(controller: ctl, obscureText: true, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('OK')),
            ],
          );
        },
      );

  Future<void> save(Map<String, Object?> m) async {
    final text = const JsonEncoder.withIndent(' ').convert(m);
    final name = 'metrics_${DateTime.now().millisecondsSinceEpoch}.json';
    final dirs = <Directory?>[await getApplicationDocumentsDirectory(), await getExternalStorageDirectory()];
    for (final d in dirs) {
      if (d == null) continue;
      await File('${d.path}/$name').writeAsString(text);
    }
    debugPrint('SPIKE_METRICS_JSON_BEGIN\n$text\nSPIKE_METRICS_JSON_END'); // metrics only
    setState(() => json = text);
  }

  // ---------------- picked file (real statements): metrics only ----------------
  Future<void> pickAndRun() async {
    setState(() {
      busy = true;
      status = 'picking...';
    });
    try {
      await init();
      final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      final path = res.isEmpty ? null : res.first.path;
      if (path == null) {
        setState(() => status = 'cancelled (no file)');
        return;
      }
      final bytes = await File(path).readAsBytes();
      await File(path).delete(); // do not leave a copy of the document in the app cache
      final m = <String, Object?>{'mode': 'picked', 'time': DateTime.now().toIso8601String()};
      m['bytes'] = bytes.length;
      final memStart = memJson();
      var wrong = 0;
      final r = await openPdf(bytes, () async {
        final p = await askPassword();
        if (p == null) wrong = -1;
        return p;
      });
      m['open'] = {'outcome': r.outcome, 'provider_calls': r.providerCalls, 'open_ms': r.openMs, 'cancelled_by_user': wrong == -1};
      if (r.doc == null) {
        m['rss_current_max_start'] = memStart;
        await save(m);
        setState(() => status = 'not opened: ${r.outcome}');
        return;
      }
      setState(() => status = 'extracting (${r.doc!.pages.length} pages)...');
      final keep = <PageData>[];
      final sw = Stopwatch()..start();
      final s1 = await extractAll(r.doc!, keep: keep);
      final run1Ms = sw.elapsedMilliseconds;
      sw.reset();
      final s2 = await extractAll(r.doc!);
      m['pages'] = r.doc!.pages.length;
      m['total_chars'] = s1.totalChars;
      m['run1_total_ms'] = run1Ms;
      m['run2_total_ms'] = sw.elapsedMilliseconds;
      m['max_page_extract_ms'] = s1.maxExtractMs;
      m['per_page'] = s1.pages;
      m['codepoints'] = codepointReport(s1);
      m['deterministic_identical'] = s1.digest == s2.digest;
      m['rss_current_max_start'] = memStart;
      m['rss_current_max_end'] = memJson();
      await save(m);
      await viewDoc?.dispose();
      viewDoc = r.doc;
      viewPages = keep;
      viewIdx = 0;
      await renderView();
      setState(() => status = 'done: ${r.doc!.pages.length} pages');
    } catch (e) {
      setState(() => status = 'error: ${e.runtimeType}');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> renderView() async {
    if (viewPages.isEmpty) return;
    final page = viewPages[viewIdx].page;
    final pi = await page.render(fullWidth: page.width * 2, fullHeight: page.height * 2, backgroundColor: 0xFFFFFFFF);
    if (pi == null) return;
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(Uint8List.fromList(pi.pixels), pi.width, pi.height, ui.PixelFormat.bgra8888, c.complete);
    final out = await c.future;
    pi.dispose();
    img?.dispose();
    setState(() => img = out);
  }

  // ---------------- self-test on bundled FAKE fixtures ----------------
  Future<Uint8List> asset(String n) async => (await rootBundle.load('assets/fixtures/$n')).buffer.asUint8List();

  Future<void> selfTest() async {
    setState(() {
      busy = true;
      status = 'self-test...';
    });
    final m = <String, Object?>{'mode': 'selftest_fakes', 'time': DateTime.now().toIso8601String()};
    try {
      await init();
      m['dart'] = Platform.version.split(' ').first;
      m['os'] = Platform.operatingSystemVersion;
      m['cpus'] = Platform.numberOfProcessors;
      m['rss_start'] = memJson();
      final manifest = (jsonDecode(await rootBundle.loadString('assets/fixtures/manifest.json')) as List).cast<Map<String, dynamic>>();

      // 1+2: char boxes, rotation, crop box, frame detection
      final rot = <Map<String, Object?>>[];
      var allDisplay = true, allUnrot = true;
      for (final f in manifest.where((f) => f['password'] == null && f['pages'] == 1 && !(f['file'] as String).startsWith('rupee'))) {
        final r = await openPdf(await asset(f['file']), () async => null);
        if (r.doc == null) {
          rot.add({'file': f['file'], 'open': r.outcome});
          continue;
        }
        final keep = <PageData>[];
        final st = await extractAll(r.doc!, keep: keep);
        final crop = (f['cropbox'] as List?)?.map((e) => (e as num).toDouble()).toList();
        final probes = <Map<String, Object?>>[];
        for (final pj in f['probes']) {
          final res = checkProbe(keep.first, Probe.fromJson(pj), f['rotation'] as int, crop);
          probes.add(res);
          allDisplay &= res['matches_display'] == true;
          allUnrot &= res['matches_unrotated'] == true;
        }
        rot.add({
          'file': f['file'],
          'expected_rotation_deg': f['rotation'],
          'reported_rotation_deg': st.pages.first['rotation_deg'],
          'reported_size_pt': [st.pages.first['width_pt'], st.pages.first['height_pt']],
          'chars': st.totalChars,
          'digest_fixture_only': st.digest.toRadixString(16), // fakes only: compare across devices
          'rects_equal_text_length': st.pages.first['rects_equal_text_length'],
          'empty_rects': st.pages.first['empty_rects'],
          'empty_rects_non_space': st.pages.first['empty_rects_non_space'],
          'probes': probes,
        });
        await r.doc!.dispose();
      }
      m['rotation_and_frame'] = rot;
      m['frame_verdict'] = allDisplay ? 'display_frame_all_fixtures' : (allUnrot ? 'unrotated_frame_all_fixtures' : 'mixed_or_neither');
      frame = allUnrot && !allDisplay ? 'unrotated' : 'display';

      // 4: password flow
      Future<Map<String, Object?>> scenario(String name, List<String?> answers, {String file = 'locked_1p.pdf'}) async {
        var i = 0;
        final r = await openPdf(await asset(file), () async => i < answers.length ? answers[i++] : null);
        final out = {'scenario': name, 'outcome': r.outcome, 'provider_calls': r.providerCalls, 'open_ms': r.openMs};
        await r.doc?.dispose();
        return out;
      }

      m['password'] = [
        await scenario('right_first', ['Test1234']),
        await scenario('wrong_then_right', ['wrong', 'Test1234']),
        await scenario('wrong_then_cancel', ['wrong', null]),
        await scenario('cancel_immediately', [null]),
        await scenario('unlocked_file_never_asks', ['x'], file: 'plain_1p.pdf'),
      ];

      // 3: rupee / codepoints (fixture with ARIAL UNICODE subset may be absent)
      try {
        final r = await openPdf(await asset('rupee_1p.pdf'), () async => null);
        final st = await extractAll(r.doc!);
        m['rupee_fixture'] = codepointReport(st);
        await r.doc!.dispose();
      } catch (_) {
        m['rupee_fixture'] = 'rupee_1p.pdf missing: run tool/make_fixtures.py locally';
      }
      final rp = await openPdf(await asset('plain_1p.pdf'), () async => null);
      m['plain_fixture_codepoints'] = codepointReport(await extractAll(rp.doc!));
      await rp.doc!.dispose();

      // 5+8: performance on 10 pages, determinism
      final perf = <Map<String, Object?>>[];
      for (var run = 0; run < 3; run++) {
        final rssBefore = memJson();
        final r = await openPdf(await asset('ten_pages.pdf'), () async => null);
        final sw = Stopwatch()..start();
        final s1 = await extractAll(r.doc!);
        final extractMs = sw.elapsedMilliseconds;
        final s2 = await extractAll(r.doc!);
        sw.reset();
        var renderMs = 0;
        for (final p in r.doc!.pages) {
          final t = Stopwatch()..start();
          final pi = await p.render(fullWidth: p.width * 1.0, fullHeight: p.height * 1.0, backgroundColor: 0xFFFFFFFF);
          pi?.dispose();
          renderMs += t.elapsedMilliseconds;
        }
        perf.add({
          'run': run + 1,
          'pages': r.doc!.pages.length,
          'open_ms': r.openMs,
          'extract_total_ms': extractMs,
          'extract_ms_per_page': s1.pages.map((p) => p['extract_ms']).toList(),
          'render_total_ms_1x': renderMs,
          'chars': s1.totalChars,
          'deterministic_identical': s1.digest == s2.digest,
          'digest_fixture_only': s1.digest.toRadixString(16),
          'rss_current_max_before': rssBefore,
          'rss_current_max_after': memJson(),
        });
        await r.doc!.dispose();
      }
      m['performance_ten_pages'] = perf;
      m['rss_end'] = memJson();
      await save(m);
      // leave a page on screen for the visual overlay check
      final rv = await openPdf(await asset('rot90_1p.pdf'), () async => null);
      viewDoc = rv.doc;
      viewPages = [];
      await extractAll(rv.doc!, keep: viewPages);
      viewIdx = 0;
      await renderView();
      setState(() => status = 'self-test done');
    } catch (e, st) {
      m['error'] = e.runtimeType.toString();
      debugPrint('SPIKE_ERROR ${e.runtimeType}\n$st');
      await save(m);
      setState(() => status = 'error: ${e.runtimeType}');
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pd = viewPages.isEmpty ? null : viewPages[viewIdx];
    return Scaffold(
      appBar: AppBar(title: const Text('pdfrx spike (throwaway)')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: busy ? null : pickAndRun, child: const Text('Pick PDF')),
          OutlinedButton(onPressed: busy ? null : selfTest, child: const Text('Self-test (fakes)')),
          OutlinedButton(
              onPressed: () => setState(() => frame = frame == 'display' ? 'unrotated' : 'display'),
              child: Text('Overlay frame: $frame')),
        ]),
        Text('status: $status'),
        if (pd != null && img != null) ...[
          Row(children: [
            IconButton(
                onPressed: viewIdx > 0 ? () async { viewIdx--; await renderView(); } : null,
                icon: const Icon(Icons.chevron_left)),
            Text('page ${viewIdx + 1}/${viewPages.length}  chars=${pd.raw.charRects.length}'),
            IconButton(
                onPressed: viewIdx < viewPages.length - 1 ? () async { viewIdx++; await renderView(); } : null,
                icon: const Icon(Icons.chevron_right)),
          ]),
          AspectRatio(
            aspectRatio: pd.page.width / pd.page.height,
            child: Stack(fit: StackFit.expand, children: [
              RawImage(image: img, fit: BoxFit.fill),
              CustomPaint(painter: BoxPainter(pd, frame)),
            ]),
          ),
        ],
        if (json.isNotEmpty) ...[
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: json)), child: const Text('Copy metrics JSON')),
          SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
        ],
      ]),
    );
  }
}

class BoxPainter extends CustomPainter {
  BoxPainter(this.pd, this.frame);
  final PageData pd;
  final String frame;

  @override
  void paint(Canvas canvas, Size size) {
    final pw = pd.page.width, ph = pd.page.height; // displayed size
    final rot = pd.page.rotation.index * 90;
    final w0 = (rot == 90 || rot == 270) ? ph : pw, h0 = (rot == 90 || rot == 270) ? pw : ph;
    final sx = size.width / pw, sy = size.height / ph;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = const Color(0xCCFF0000);
    for (final r in pd.raw.charRects) {
      double l, t, rr, b;
      if (frame == 'display') {
        l = r.left;
        rr = r.right;
        t = ph - r.top;
        b = ph - r.bottom;
      } else {
        final (x1, y1) = toDisplay(r.left, r.bottom, rot, w0, h0);
        final (x2, y2) = toDisplay(r.right, r.top, rot, w0, h0);
        l = x1 < x2 ? x1 : x2;
        rr = x1 < x2 ? x2 : x1;
        t = y1 < y2 ? y1 : y2;
        b = y1 < y2 ? y2 : y1;
      }
      canvas.drawRect(Rect.fromLTRB(l * sx, t * sy, rr * sx, b * sy), paint);
    }
  }

  @override
  bool shouldRepaint(BoxPainter old) => old.pd != pd || old.frame != frame;
}
