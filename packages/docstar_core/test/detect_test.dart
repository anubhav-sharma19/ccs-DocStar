import 'package:docstar_core/docstar_core.dart';
import 'package:test/test.dart';

import 'package:docstar_core/testing.dart';

/// Test-only pack: strong when every anchor text appears as a line on page 1.
class FakePack implements Pack<int> {
  @override
  final String id;
  final List<String> anchors;
  final Map<String, List<String>> variantAnchors;
  final List<String> negative;
  FakePack(this.id, this.anchors, {this.variantAnchors = const {}, this.negative = const []});

  @override
  Detection detect(DsDocument doc) {
    final lines = {for (final l in doc.pages.first.lines) l.text};
    final hits = anchors.where(lines.contains).length;
    final strength =
        hits == anchors.length ? AnchorStrength.strong : (hits > 0 ? AnchorStrength.weak : AnchorStrength.none);
    return Detection(id, strength,
        variants: [for (final e in variantAnchors.entries) if (e.value.every(lines.contains)) e.key],
        negativeAnchorFired: negative.any(lines.contains));
  }

  @override
  TableHints hintsFor(String variant) => const TableHints();
  @override
  int extract(DsDocument doc, String variant) => 0;
}

DsDocument doc(List<String> lines) =>
    layout([page(1, [for (final (i, s) in lines.indexed) T(50, 100.0 + 20 * i, s)])]);

void main() {
  final ticket = doc(['CINEMA TICKET', 'SCREEN 4  ROW F  SEAT 12', 'ADMIT ONE']);
  final bankA = FakePack('bank_a', ['BANK A STATEMENT'], variantAnchors: {
    'v2025': ['LAYOUT 2025'],
    'v2024': ['LAYOUT 2024'],
  }, negative: [
    'BANK B STATEMENT'
  ]);
  final bankB = FakePack('bank_b', ['BANK B STATEMENT'], variantAnchors: {'v1': []});

  group('A-C11 unknown document', () {
    test('no packs -> UNKNOWN_FORMAT', () {
      expect(detectFormat(ticket, []), isA<UnknownFormat>());
    });
    test('fake packs that do not match -> UNKNOWN_FORMAT', () {
      expect(detectFormat(ticket, [bankA, bankB]), isA<UnknownFormat>());
    });
    test('weak hits are only a hint', () {
      final weak = FakePack('weak', ['CINEMA TICKET', 'NOT THERE']);
      final o = detectFormat(ticket, [weak]) as UnknownFormat;
      expect(o.weakHints, ['weak']);
    });
  });

  group('decision table 1.5.3', () {
    test('one pack, one variant -> DETECTED', () {
      final o = detectFormat(doc(['BANK A STATEMENT', 'LAYOUT 2025']), [bankA, bankB]);
      expect(o, isA<Detected>().having((d) => d.variant, 'variant', 'v2025'));
    });
    test('one pack, two variants -> try both; pick by verify, never by rows (N4)', () {
      final o = detectFormat(doc(['BANK A STATEMENT', 'LAYOUT 2025', 'LAYOUT 2024']), [bankA]);
      expect(o, isA<TryVariants>().having((t) => t.variants, 'variants', ['v2024', 'v2025']));
      expect(chooseVariant('bank_a', {'v2024': VerifyOutcome.blocked, 'v2025': VerifyOutcome.verified}),
          isA<Detected>().having((d) => d.variant, 'variant', 'v2025'));
      expect(chooseVariant('bank_a', {'v2024': VerifyOutcome.verified, 'v2025': VerifyOutcome.verified}),
          isA<NeedsReview>().having((r) => r.reason, 'reason', 'layout ambiguous'));
      expect(chooseVariant('bank_a', {'v2024': VerifyOutcome.review, 'v2025': VerifyOutcome.blocked}),
          isA<NeedsReview>());
    });
    test('negative anchor -> REVIEW conflicting signals', () {
      final o = detectFormat(doc(['BANK A STATEMENT', 'LAYOUT 2025', 'BANK B STATEMENT']), [bankA]);
      expect(o, isA<NeedsReview>().having((r) => r.reason, 'reason', 'conflicting signals'));
    });
    test('two strong packs -> REVIEW two issuers match', () {
      final o = detectFormat(doc(['BANK A STATEMENT', 'LAYOUT 2025', 'BANK B STATEMENT']), [bankB, bankA]);
      expect(o, isA<NeedsReview>().having((r) => r.reason, 'reason', 'two issuers match'));
    });
  });

  group('import gate 3.1', () {
    const pass = CheckResult('V-X', CheckStatus.passed);
    test('all required passed -> VERIFIED', () => expect(gate([pass]), VerifyOutcome.verified));
    test('any failed -> BLOCKED', () {
      expect(gate([pass, const CheckResult('V-Y', CheckStatus.failed)]), VerifyOutcome.blocked);
    });
    test('required not_run -> REVIEW, never VERIFIED', () {
      expect(gate([pass, const CheckResult('V-OPEN', CheckStatus.notRun)]), VerifyOutcome.review);
    });
    test('optional not_run alone -> VERIFIED', () {
      expect(gate([pass, const CheckResult('V-Z', CheckStatus.notRun, required: false)]), VerifyOutcome.verified);
    });
    test('review trigger -> REVIEW', () {
      expect(gate([pass], reviewTriggers: ['unknown_marker']), VerifyOutcome.review);
    });
  });
}
