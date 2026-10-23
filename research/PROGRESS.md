# ccs-docengine — Research Progress

## Stage status

| Stage | Status |
|---|---|
| 0 — Setup | DONE |
| 1 — Core logic from Docling (PDF path) | DONE (+ pass 2) |
| 2 — Pack logic from statement parsers | DONE |
| 3 — Final engine spec | **DONE** (`research/ENGINE_SPEC.md`) |

Research phase complete. **All pack rules are hypotheses** until validated on real statements (Phase 0).

## Decisions applied (from user)

D1 user enters the password, optional save, hints later. D2 no synthetic statements now; Phase 2 fake-generator requirements written. D3 ICICI card: both layouts as variants, unresolved. D4 SBI Card `M`: open, forces REVIEW. D5 section policy (never / always import lists). D6 xfina medium confidence. D7 do-not-copy list = negative rules; every detector has positive and negative rules. D8 use `ponytail:ponytail` for every implementation.

## Stage 3 outputs

- `research/ENGINE_SPEC.md`: architecture (reader adapter / core / packs / verify), document and statement models, pack interface, rule record with confidence field, detection decision table, password flow, Docling -> rule mapping, verify layer (V-/S- checks, REVIEW triggers, 13 negative rules, 15 detectors with positive and negative rules), constraints checklist, risks and spikes, Phase 0 and Phase 2 plans, Given/When/Then criteria (13 core, 12 bank, 21 card), gap analysis, open questions Q1-Q10.
- `research/spec/packs/rule_register.md`: seeded rule records (common, SBI bank, HDFC, ICICI A/B, SBI Card, Axis, IDFC, HSBC), all `hypothesis`.
- `research/LICENSES.md`: pdfrx_engine / pdfrx (MIT) added; Syncfusion noted (commercial, not used).

**Spike S1 result (recommendation):** use `pdfrx_engine` (PDFium) as the reader adapter. It gives per-character boxes (`pdfrx_engine/lib/src/native/pdfrx_pdfium.dart:1954-1986`), a repeating password callback (`pdf_document.dart:360-366`), MIT licence. Not yet tested on a device: rotation behaviour (S1-4), the rupee glyph (S1-5), Android build and performance (S1-9, S3). Syncfusion is commercial; `pdf`, `pdfx`, `pdf_text`, `pdf_render` do not give text boxes.

## Verification

Citations: ENGINE_SPEC + rule register 107 checked, 0 wrong; spec/core 89 checked, 0 wrong; spec/packs 139 checked, 1 not indexed (docs file read directly). Web-sourced facts are marked `web:` and unverified.

## Open questions (for you; defaults in ENGINE_SPEC section 8)

Q1 held-out split 2:1 and owner of real statements. Q2 which issuers you hold. Q3 remember-password default off. Q4 verify tolerance 0. Q5 REVIEW UX per statement. Q6 "ready" pass rate. Q7 scanned PDFs unsupported in v1. Q8 Android only. Q9 who runs the Phase 2 generator spike. Q10 collecting rupee glyph and EMI wording in Phase 0 notes (structure only).

Still-open technical gaps: Stage 1 G3 (`sanitize_text`), G4 (`_sort_cells`), G6 (rotation inside docling-parse), G7 (qpdf), G8 (font info in cells); Stage 2 P1-P5 (see `spec/packs/VALIDATION.md`).

## Next phase (not started)

Phase 0 (real-statement validation, local only) and the S1 spike on a device. No code has been written.
