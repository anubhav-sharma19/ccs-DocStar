# DocStar — Research Progress

## Stage status

| Stage | Status |
|---|---|
| 0 — Setup | DONE |
| 1 — Core logic from Docling (PDF path) | DONE (+ pass 2) |
| 2 — Pack logic from statement parsers | DONE |
| 3 — Final engine spec | **DONE** (`research/ENGINE_SPEC.md`) |
| A — Rename to DocStar + spike conditions C2/C3 | **DONE** (2026-10-23) |
| B — Core design note | **DONE** (approved 2026-10-23 with additions) |
| C — Core + tests | **DONE** (2026-10-23) |
| D — Visual debug CLI | **DONE** (2026-10-23) |
| 3b — Overprint / watermark fix (before packs) | **DONE** (2026-10-23) |

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

## Stage C: core + adapter + tests (done 2026-10-23)

- `packages/docstar_core` (zero runtime deps): layout pipeline, model, canonical JSON, Pack/Verify interfaces, §1.5.3 decision table, import gate. `package:docstar_core/testing.dart` holds the synthetic fixture generator (tests, benchmark, later packs).
- `packages/docstar_pdfium`: `readPdf(bytes, passwords:)` over pdfrx_engine, display-frame boxes rounded to 0.01 pt, `ReadFailed{corrupt, cancelled, noTextLayer}`. Its lockfile is now in the `check_release.sh` guard. CI also runs both test suites.
- **Tests: 69, all pass.** docstar_core 52: (a) char→word on 9 fixtures; (b) determinism incl. shuffled input; (c) rotation 90/180/270; tables, continuation after/before, headless links, furniture, detection, gate, hygiene. docstar_pdfium 17: generated PDFs through real PDFium, plus the spike's locked fake.
- Mutation check: breaking rotation detection, explicit-space splitting or the `before` direction each fails tests. The explicit-space mutation first survived, so a narrow-space test was added.

| Scenario (§6.1) | Status |
|---|---|
| A-C1 open, boxes inside page | met (adapter test) |
| A-C2/A-C3/A-C4 password flow | met (locked AES-256 fake: attempt 0 → wrong → attempt 1 → open; cancel; no password in the result) |
| A-C5 remembered password | met as an app-side pattern test (saved answers attempt 0, the user answers after) |
| A-C6 scanned | met: image-only PDF → `noTextLayer`. Limit: a blank PDF gives the same result (pdfrx exposes no image info) |
| A-C7 determinism | met in-process (core + adapter). **Not met: "two devices"** for the document model. Only the spike's char digests were compared across Mac/emulator earlier |
| A-C8 rotation | met: core (synthetic) and adapter (/Rotate 90/180/270, upright and sideways). PDFium orders the char stream differently on upside-down pages, so the adapter test compares structure without stream indices |
| A-C9 no network | met by `check_release.sh` + the zero-dependency test. Airplane mode not literally run |
| A-C10 money exact | core half met (`1,23,456.78` one word/cell); paise moves to the first pack (decided) |
| A-C11 unknown document | met: decision table with zero packs and a fake pack |
| A-C12 header/footer | met |
| A-C13 log hygiene | met: no print/log in either lib (source scan); failures carry only an enum |

**Found and fixed during Stage C (design note updated):**
1. Docling's 0.35 × advance word-gap rule does not apply to PDFium's tight glyph boxes. Words break on stream whitespace first, with a 1-pitch geometric fallback.
2. Transaction rows near the bottom edge were labelled page footers (X-HDRFTR). Table rows are now never furniture, and furniture must stack from the edge.
3. Tight right-aligned columns made TR5 merge credit and balance and ended tables early. A known header row now splits columns, and straddling segments are checked word by word.

**Benchmark (non-gating)**, `layoutBench()`: 15 pages, 34,662 chars, 15 tables, 615 rows, 20 runs after 5 warm-ups.

| Where | Build | Median per document |
|---|---|---|
| Mac M2 | `dart compile exe` (AOT) | 16.4-16.7 ms (min 16.1, max 17.5) |
| Android 16 arm64 emulator | spike app, Flutter release, `--dart-define=BENCH=1` | 30.0-36.0 ms (min 22.4, max 66.0) |

Soft budget < 300 ms on the emulator: met by about 8x. Layout only; PDF char extraction (spike: 51-82 ms per 10 pages) is separate. A phone run is still pending.

## Stage D: visual debug CLI (done 2026-10-23)

- `spikes/pdfrx_cli` moved to `tools/docstar_cli` (git history kept). Its metrics mode, hidden password prompt and refusal to write output inside a git repo are unchanged. `metrics.json` gains layout counts (words, lines, blocks by label, tables with rows/cols/method/header/linked), still with no text. The terminal table gains a `tables` column.
- `--visual` runs the real pipeline (`docstar_pdfium.pagesOf` → `layout`) and draws per page: words blue, lines green, blocks orange, page header/footer purple, table grid red (one rectangle per cell, at column and row extents). A legend is printed on each page. Boxes map back through `DsPage.toDisplay`, so rotated pages line up (checked by eye on the reportlab rot90 fixture and a generated sideways page).
- Tests: `tools/docstar_cli/test/overlay_test.dart` (2): one PNG per page, every colour present, word pixels at the word's display box, on upright and sideways pages. Total suite: 71 tests (52 core, 17 adapter, 2 CLI).
- Adapter fix found while reading the spike: chars are indexed by code point, not UTF-16 unit. pdfrx writes one rect per code point, so a character outside the BMP (for example supplementary private-use glyphs) would have shifted every later box.
- **Finding from the overlays (not fixed):** large overprinted text across a table (the spike fixtures' `PROBE-ALPHA`/`PROBE-BETA` labels; on real statements, stamps or watermarks) joins the row's line. That line then straddles columns, so the table splits in two and the stamp text lands in a cell. Seen on `plain_1p.pdf` (2 tables instead of 1) and `ten_pages.pdf` (20 instead of 10). A likely fix: glyphs far taller than the line's median don't join it, and overprint lines are skipped by table runs.

## Phase 3b: overprint / watermark fix (done 2026-10-23)

- New block label `overlay` (stamp/watermark) and three config guesses: `overprintHeightFactor` 2.0, `overlaySlope` 0.15, `overlaySizeRatio` 1.4 (`docs/CORE_DESIGN.md` §3.2).
- Size is estimated per stream chunk as glyph height ÷ shape factor. Raw height can't be used: the spike's PROBE labels are 14 pt on 9 pt body text, only 1.53×, below the 2.0× rule, and lowercase letters are about 0.7× the height of capitals. Rule 3 (larger font inside a table's region) is what catches PROBE. Rules 1 and 2 catch big stamps anywhere and slanted watermarks.
- Results: spike `plain_1p.pdf` gives **1 table** (was 2) and `ten_pages.pdf` **10** (was 20). PROBE-ALPHA/BETA are `overlay` blocks and no cell contains PROBE. PROBE-GAMMA (10 pt, outside the table) stays a text block, which is correct under the rules.
- Tests: **86, all pass** (core 62, adapter 22, CLI 2). New: generated (a) 40-44 pt DUPLICATE stamp across a table, (b) slanted light watermark, (c) control: bold 11.5 pt header (not an overlay); also a large title above a table stays text, a stamp outside tables (rule 1 alone), and a 1.5× label on a row's exact baseline. Turning off each rule fails its own test.
- Determinism: canonical-JSON hashes of all overlay-free fixtures are **byte-identical** before and after the change (13 core fixtures incl. the 15-page bench doc and hinted layouts; 4 adapter PDFs). The synthetic generator's lowercase glyphs were made realistic (x-height) first, and the "before" hashes were taken on that generator with the old layout code.
- Also fixed: PDFium tests must stay in one test file. Two files make `dart test` load PDFium in parallel isolates, which crashed the VM (noted in `pdfium_test.dart`).
- Benchmark: Mac M2 AOT 16.5 → **23.0 ms** per 15-page document (chunking). The emulator was not re-measured; the budget is 300 ms (it was 30-36 ms).
- Limits: normal-size text drawn over a table still ends it (not an overlay). A page title more than 2× the body size becomes an overlay, which may matter if a pack's fingerprint uses a large bank name; packs should also read overlay blocks for anchors.

## Concurrency guard (2026-10-23)

- Repro: two isolates reading PDFs at once abort the VM ("Cannot invoke native callback from a different isolate"). Concurrent calls within one isolate were already fine.
- Fix: `initDocstarPdfium()` (called by `readPdf`) turns on pdfrx's native process-wide PDFium gate (`pdfrx_pdfium_gate.c`, a mutex around PDFium calls), and `readPdf` queues calls per isolate. README "Using DocStar" states the rule: one isolate, one document at a time.
- Tests: two concurrent `readPdf` in one isolate, and two in two other isolates, both succeed with the sequential result. With the gate off, the two-isolate test crashes the VM.
- Side effect: with the gate, PDFium's built-in font mapper replaces pdfrx's Dart mapper for non-embedded fonts. Generated Courier PDFs: same structure, boxes move by < 0.5 pt. Spike PDFs (embedded fonts): byte-identical output. This likely helps cross-device determinism (A-C7): no device system fonts involved.

## Continuation spacing + transformed.json (2026-10-23)

- Continuation lines used to need a gap of at most 1.0 line height (X-CONT). Wrapped lines spaced like rows broke out of their cell, ended the table, and split one table into many small ones. Now the limit is max(1.0 line height, 1.2 × the page's median line gap) (`continuationGapSlack`, guess). Synthetic fixture: wraps at 20 pt pitch, after and before directions; it failed before the fix. Negative test: a note one blank line below the table stays text. All earlier fixture hashes are byte-identical.
- CLI `--visual` also writes `visual/file_NN/transformed.json`: every table per page, `header` + `rows` of cell text, `continues_from`. It contains document text (same rule as the PNGs). Synthetic run: generated 3-page statement gives 3 tables (2 linked), 20 rows each; spike `ten_pages.pdf` gives 10 tables (9 linked).
- Tests: core 64, adapter 24, CLI 3, all pass.

## Redacted overlays (2026-10-23)

- CLI `--redact`: shareable overlay PNGs in `<out>/redacted/`, drawn on a blank canvas. Words are black bars (drawn last, so always solid), plus lines, blocks, grid and overlays. Nothing is rendered from the PDF.
- Test (synthetic page with an embedded image): every pixel below the legend is a palette colour, every word area is solid black, and the PNG holds only IHDR/IDAT/IEND chunks. Mutation check: if redact mode rendered the page, the test fails.
- What still leaks: geometry (word positions and lengths, so the digit count of amounts) and the template look.

## Comma + sparse-column fixes (2026-10-23, from a synthetic crop you shared)

- A comma hanging mostly below the baseline (< 50% overlap) became its own line, so `246,348.58` came out as the word `246348.58` and a stray `,` at the end of the cell. Fix: punctuation and symbols join the line of their stream run's nearest letter or digit.
- A credit/deposit column used by under 20% of rows was dropped by TR5, and its amounts landed in the balance cell. Fix: segments wholly inside a coverage gap form a sparse column.
- Failing synthetic tests first (low comma; credits in 1 of 8 rows), then the fixes. Earlier fixture hashes are byte-identical. A synthetic CLI run gives the same table counts and links; no stray `,` among 1,380 amount cells. Tests: core 66, adapter 24, CLI 4.
- Known limit: a headless continuation page with no entry in a sparse column has one column fewer than the previous page, so it does not link (`continuesFrom` stays null). Pages with a repeated header still link.

## Open items

- **iOS/macOS Flutter apps still fetch PDFium via pdfium_flutter podspec. Must vendor + hash-pin before Finora iOS build.**
- `http` is still in the dependency graph via `pdfrx_engine` (URL-open code, not linked in release; spike item 7). Fork `pdfrx_engine` only if we want it out of the graph.
- `pub get` and Gradle still fetch packages from the network at build time; only the PDFium fetch was removed.
- Spike device run (SPIKE_REPORT section 4) still pending; also run the layout benchmark on the phone.
- Ruled tables (TR1/TR3), font-size headings (LR6), and blank vs scanned need data pdfrx does not expose (path objects, fonts, images). Add them through pdfium_dart bindings when a real statement needs them.
- ~~Overprinted large text splits tables~~: fixed in Phase 3b. Remaining: normal-size overprint, and big titles (> 2×) labelled overlay.
- All layout thresholds are guesses tuned on synthetic Courier fixtures only. Phase 0 real statements will move them.

## Next phase (not started)

Phase 0 (real-statement validation, local only) and the device run of the spike. No engine code has been written (the spike is throwaway).
