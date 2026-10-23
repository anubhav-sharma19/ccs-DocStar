// Tiny PDF writer for generated test fixtures: Courier text at exact positions,
// optional /Rotate, optional image-only page. Courier is monospaced (600/1000 em),
// so the geometry of every fixture is known.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class FakeText {
  final double x, y; // baseline start, display frame: points, origin top-left
  final String text;
  final double size;
  final double angle; // degrees, counter-clockwise (watermarks); upright unrotated pages only
  final double gray; // fill: 0 black .. 1 white
  final bool bold; // Courier-Bold
  const FakeText(this.x, this.y, this.text, {this.size = 10, this.angle = 0, this.gray = 0, this.bold = false});
}

class FakePage {
  final double width, height;
  final int rotate;
  final List<FakeText> texts;
  final bool image;

  /// true: text is drawn so it reads upright once [rotate] is applied (a landscape
  /// statement). false: text is drawn upright in the unrotated page, so it shows
  /// sideways (what the spike's rotated fixtures do).
  final bool upright;

  /// [width] x [height] is the *displayed* size when [upright], else the unrotated size.
  const FakePage(this.texts,
      {this.width = 595, this.height = 842, this.rotate = 0, this.image = false, this.upright = true});

  bool get _swap => upright && (rotate == 90 || rotate == 270);
  double get mediaW => _swap ? height : width;
  double get mediaH => _swap ? width : height;
}

Uint8List buildPdf(List<FakePage> pages) {
  final objs = <String>[]; // index i -> object i+1
  int add(String body) {
    objs.add(body);
    return objs.length;
  }

  add('<< /Type /Catalog /Pages 2 0 R >>');
  add(''); // pages, filled in below
  final font = add('<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>');
  final bold = add('<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold >>');
  final kids = <int>[];
  for (final p in pages) {
    final sb = StringBuffer();
    if (p.image) sb.write('q ${p.mediaW - 100} 0 0 ${p.mediaH - 100} 50 50 cm /Im1 Do Q\n');
    for (final t in p.texts) {
      final m = t.angle == 0
          ? _matrix(p.upright ? p.rotate : 0, t.x, t.y, p.mediaW, p.mediaH)
          : '${cos(t.angle * pi / 180)} ${sin(t.angle * pi / 180)} ${-sin(t.angle * pi / 180)} '
              '${cos(t.angle * pi / 180)} ${t.x} ${p.mediaH - t.y}';
      sb.write('BT ${t.gray} g /F${t.bold ? 2 : 1} ${t.size} Tf $m Tm (${_esc(t.text)}) Tj ET\n');
    }
    final content = sb.toString();
    final c = add('<< /Length ${latin1.encode(content).length} >>\nstream\n${content}endstream');
    var res = '/Font << /F1 $font 0 R /F2 $bold 0 R >>';
    if (p.image) {
      final im = add('<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray '
          '/BitsPerComponent 8 /Length 1 >>\nstream\n\x5a\nendstream');
      res += ' /XObject << /Im1 $im 0 R >>';
    }
    kids.add(add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${p.mediaW} ${p.mediaH}] '
        '/Rotate ${p.rotate} /Resources << $res >> /Contents $c 0 R >>'));
  }
  objs[1] = '<< /Type /Pages /Kids [${kids.map((k) => '$k 0 R').join(' ')}] /Count ${kids.length} >>';

  final out = BytesBuilder();
  void w(String s) => out.add(latin1.encode(s));
  w('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(out.length);
    w('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xref = out.length;
  w('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    w('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  w('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.toBytes();
}

String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');

/// Text matrix for a baseline start at display point (dx, dy) on a page whose
/// unrotated size is w0 x h0, shown rotated [r] degrees: reading direction and
/// "up" are mapped back into unrotated space (inverse of the spike's toDisplay).
String _matrix(int r, double dx, double dy, double w0, double h0) => switch (r) {
      0 => '1 0 0 1 $dx ${h0 - dy}',
      90 => '0 1 -1 0 $dy $dx',
      180 => '-1 0 0 -1 ${w0 - dx} $dy',
      270 => '0 -1 1 0 ${w0 - dy} ${h0 - dx}',
      _ => throw ArgumentError('rotation $r'),
    };
