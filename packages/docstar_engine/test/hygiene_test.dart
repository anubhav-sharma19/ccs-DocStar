// Same privacy/purity rules as docstar_core: no runtime deps, no IO, no logging anywhere in lib.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final sources = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('docstar_engine has zero runtime dependencies', () {
    expect(RegExp(r'^dependencies:', multiLine: true).hasMatch(File('pubspec.yaml').readAsStringSync()), isFalse);
  });

  test('imports only dart:core/math and its own files (no dart:io)', () {
    for (final f in sources) {
      for (final m in RegExp(r'''^(?:import|export) '([^']+)';''', multiLine: true).allMatches(f.readAsStringSync())) {
        final uri = m.group(1)!;
        expect(uri.startsWith('dart:') ? ['dart:math', 'dart:core'].contains(uri) : !uri.contains(':'), isTrue, reason: '${f.path} imports $uri');
      }
    }
  });

  test('no logging or printing anywhere in lib (no text or amounts can leak)', () {
    for (final f in sources) {
      expect(f.readAsStringSync(), isNot(matches(RegExp(r'\b(print|debugPrint|log)\s*\(|stdout|stderr'))), reason: f.path);
    }
  });
}
