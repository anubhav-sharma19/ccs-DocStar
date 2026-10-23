// C1 pure-Dart core, C2/A-C9 no network, C9 no ML, A-C13 no logging.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final sources = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('docstar_core has zero runtime dependencies', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^dependencies:', multiLine: true).hasMatch(pubspec), isFalse);
  });

  test('imports only dart:core/convert/math and its own files', () {
    for (final f in sources) {
      for (final m in RegExp(r'''^(?:import|export) '([^']+)';''', multiLine: true).allMatches(f.readAsStringSync())) {
        final uri = m.group(1)!;
        expect(uri.startsWith('dart:') ? ['dart:convert', 'dart:math', 'dart:core'].contains(uri) : !uri.contains(':'),
            isTrue,
            reason: '${f.path} imports $uri');
      }
    }
  });

  test('A-C13: no logging or printing anywhere in lib (no text, amounts or passwords can leak)', () {
    for (final f in sources) {
      expect(f.readAsStringSync(), isNot(matches(RegExp(r'\b(print|debugPrint|log)\s*\(|stdout|stderr'))),
          reason: f.path);
    }
  });
}
