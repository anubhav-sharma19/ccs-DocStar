# DocStar — Research Progress

## Stage status

| Stage | Status |
|---|---|
| 0 — Setup | DONE |
| 1 — Core logic from Docling (PDF path) | DONE (+ pass 2) |
| 2 — Pack logic from statement parsers | DONE |
| 3 — Final engine spec | **DONE** (`research/ENGINE_SPEC.md`) |
| A — Rename to DocStar + spike conditions C2/C3 | **DONE** (2026-10-23) |
| B — Core design note | not started |
| C — Core + tests | not started |
| D — Visual debug CLI | not started |

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

## Phase 3 pre-spike (pdfrx on Android): done on emulator

`spikes/pdfrx_spike/` (throwaway Flutter app) + `SPIKE_REPORT.md`. Result: **GO (conditional)**. Items 1-8: pass on emulator (items 1, 3, 5, 8 also need a phone run; steps in the report). Findings: char boxes are in the unrotated frame; PDFium binary downloaded at build time unchecked (vendor + pin hash); `http` is in the dependency tree via `pdfrx_engine` but not linked in release; APK +8.3 MB; extraction 51-82 ms per 10 pages on the emulator. Spike code is committed (`bdbcc22`).

## Stage A: rename + spike conditions (done 2026-10-23)

- Renamed `~/calmcraft/ccs-docengine` to `~/calmcraft/docstar` (git history kept). Engine name DocStar, Dart package `docstar`; Finora and Pocket Proof will consume it. The macOS CLI spike moved into the repo (`spikes/pdfrx_cli/`).
- **C2 closed.** PDFium `chromium/7811` is vendored in `third_party/pdfium/chromium-7811/` (android-arm, android-arm64, android-x64, mac-arm64; about 24 MB, no LFS) with each archive's licences and `SHA256SUMS`. android-arm64 and mac-arm64 are byte-identical to the copies the spikes downloaded earlier; android-arm and android-x64 had no cached copy to compare against. `third_party/pdfium_dart/` is a patched fork of 0.4.0 (upstream commit `007415ec`). Its hook reads the vendored binary, checks SHA-256, fails on a mismatch, and never downloads; `http`/`archive` are dropped from the hook. The change is in `patches/pdfium_dart-0.4.0.patch` (verified to reproduce the fork from pristine 0.4.0), with steps in `patches/UPGRADING.md`. The spike and CLI use it through `dependency_overrides` (every root app needs this; README "Using DocStar").
- **C3 closed.** `scripts/check_release.sh` (fails closed) checks vendored hashes, that both lockfiles resolve `pdfium_dart` to the fork, builds the spike's release APK (armeabi-v7a, arm64-v8a, x86_64), and checks for no `INTERNET` in the merged manifest or the APK. For each ABI it checks `libpdfium.so` in the APK is byte-identical to the vendored one with no socket/connect/getaddrinfo/gethostbyname/curl symbols, then runs `scripts/test_tamper.sh` (a 1-byte change must fail the build with `SHA-256 mismatch`). `.github/workflows/check_release.yml` runs it on macOS arm64 (no remote yet, so not run in CI).
- Verified locally: check_release PASS; it fails as expected with INTERNET added, with the CLI override removed, and with no NDK or no ANDROID_HOME. Network-symbol regex confirmed on NDK libc. CLI extracts 30,864 chars from the 10-page fake. The release APK on the arm64 emulator gives all 8 self-test digests identical to `spike_metrics_emulator.json`.
- Not verified: the x86_64 and armeabi-v7a `.so` files at runtime (packaged and hash-checked only; the Apple-silicon emulator is arm64). The 3-ABI release APK is 67.4 MB (unsplit, unshrunk; a Play bundle delivers one ABI).

## Open items

- **iOS/macOS Flutter apps still fetch PDFium via pdfium_flutter podspec. Must vendor + hash-pin before Finora iOS build.**
- `http` is still in the dependency graph via `pdfrx_engine` (URL-open code, not linked in release; spike item 7). Fork `pdfrx_engine` only if we want it out of the graph.
- `pub get` and Gradle still fetch packages from the network at build time; only the PDFium fetch was removed.
- Spike device run (SPIKE_REPORT section 4) still pending.

## Next phase (not started)

Phase 0 (real-statement validation, local only) and the device run of the spike. No engine code has been written (the spike is throwaway).
