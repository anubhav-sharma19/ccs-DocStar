// Pack + Verify interfaces (implemented by packs later), the detection decision
// table (ENGINE_SPEC 1.5.3) and the import gate (3.1). Generic: no money here.
import 'layout.dart';
import 'model.dart';

enum AnchorStrength { none, weak, strong }

/// What one pack found in a document (its fingerprint result).
class Detection {
  final String packId;
  final AnchorStrength strength;
  final List<String> variants; // variants whose fingerprint matched
  final bool negativeAnchorFired;
  const Detection(this.packId, this.strength, {this.variants = const [], this.negativeAnchorFired = false});
}

abstract interface class Pack<R> {
  String get id;
  Detection detect(DsDocument doc);
  TableHints hintsFor(String variant); // layout runs again with these after detection
  R extract(DsDocument doc, String variant);
}

enum VerifyOutcome { verified, review, blocked }

enum CheckStatus { passed, failed, notRun }

class CheckResult {
  final String id;
  final CheckStatus status;
  final bool required;
  final String reason; // never holds amounts, narration text or passwords
  const CheckResult(this.id, this.status, {this.required = true, this.reason = ''});
}

abstract interface class Verifier<R> {
  List<CheckResult> verify(R result);
}

sealed class DetectionOutcome {
  const DetectionOutcome();
}

class Detected extends DetectionOutcome {
  final String packId, variant;
  const Detected(this.packId, this.variant);
}

/// One pack, several variants: extract with each, keep the one that verifies (see [chooseVariant]).
class TryVariants extends DetectionOutcome {
  final String packId;
  final List<String> variants;
  const TryVariants(this.packId, this.variants);
}

class NeedsReview extends DetectionOutcome {
  final String reason;
  const NeedsReview(this.reason);
}

class UnknownFormat extends DetectionOutcome {
  final List<String> weakHints; // pack ids with weak hits, shown as a hint only
  const UnknownFormat([this.weakHints = const []]);
}

/// ENGINE_SPEC 1.5.3. Never picks by row count (N4).
DetectionOutcome decide(List<Detection> detections) {
  final strong = detections.where((d) => d.strength == AnchorStrength.strong).toList();
  if (strong.isEmpty) {
    return UnknownFormat([
      for (final d in detections) if (d.strength == AnchorStrength.weak) d.packId,
    ]..sort());
  }
  if (strong.length > 1) return const NeedsReview('two issuers match');
  final d = strong.single;
  if (d.negativeAnchorFired) return const NeedsReview('conflicting signals');
  final variants = [...d.variants]..sort();
  if (variants.isEmpty) return const NeedsReview('no variant matched'); // ours: the table has no row for this
  if (variants.length == 1) return Detected(d.packId, variants.single);
  return TryVariants(d.packId, variants);
}

/// Runs every pack's fingerprint and applies the decision table.
DetectionOutcome detectFormat(DsDocument doc, List<Pack> packs) => decide([for (final p in packs) p.detect(doc)]);

/// After [TryVariants]: exactly one variant verified -> it; else REVIEW "layout ambiguous".
DetectionOutcome chooseVariant(String packId, Map<String, VerifyOutcome> outcomes) {
  final ok = [for (final e in outcomes.entries) if (e.value == VerifyOutcome.verified) e.key]..sort();
  return ok.length == 1 ? Detected(packId, ok.single) : const NeedsReview('layout ambiguous');
}

/// Import gate (3.1): any failed -> blocked; a required check not run or any review
/// trigger -> review; else verified. not_run never counts as passed.
VerifyOutcome gate(List<CheckResult> checks, {List<String> reviewTriggers = const []}) {
  if (checks.any((c) => c.status == CheckStatus.failed)) return VerifyOutcome.blocked;
  if (reviewTriggers.isNotEmpty || checks.any((c) => c.required && c.status == CheckStatus.notRun)) {
    return VerifyOutcome.review;
  }
  return VerifyOutcome.verified;
}
