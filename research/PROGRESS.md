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
- ~~Known limit: headless page missing a sparse column did not link~~: fixed. When its columns match a subset of the previous table's in order (within 1 pitch), it links and uses the previous columns. Negative test: missing column and shifted 3 pitches does not link. Earlier fixture hashes unchanged. Tests: core 68, adapter 24, CLI 4.

## Stable columns across pages (2026-10-23)

- Problem you raised: when a column (credits) is unused for a while, tables on those pages had fewer columns. Values then sat at different positions in the JSON from page to page.
- Fix: (1) a headless page with more columns than the previous one (the column first used there) now links; (2) every chain of linked tables is gridded on one merged column set (second layout pass, only when counts differ). `transformed.json`: empty cells are `null`, plus `logical_tables` (each chain as one row list, `same_columns` check).
- Tests: page 1 with no header and no credits, page 2 with credits: linked, both 5 columns, credits only at index 3, balance always at index 4. Turning off the unify pass fails the test. Earlier fixture hashes unchanged. Synthetic run: `ten_pages.pdf` gives one logical table, 10 pages, 450 rows of 5. Tests: core 69, adapter 24, CLI 5.

## Narration continued over a page break (2026-10-23)

- Bug you reported: a narration continuing on the next page, at the top of the table before any dated row, was dropped from the table (it became a text block), so the next transaction appeared without it.
- Fix: such lines join the continuing page's first table (headless page: lines just above the first row, top of page, within wrap spacing, inside one column; after a repeated header they were already a row). The first row is flagged `Table.continuesRow` (JSON `continuesRow: true`, only when set). `transformed.json` `logical_tables` merges it into the previous page's last row.
- Tests: headless and repeated-header pages with a carried-over line (flag and row), negative (a note two blank lines above the table stays text), logical-table merge (24 rows, narration joined). Turning off the prepend fails the test. Earlier fixture hashes unchanged. Tests: core 72, adapter 24, CLI 6.

## CHECKPOINT 2026-10-23 (git tag `checkpoint-2026-10-23`)

Done: Stages A-D, Phase 3b (overlays), concurrency guard, continuation spacing, transformed.json (`tables` + `logical_tables`, nulls), `--redact`, comma/sparse-column fixes, headless and sparse-column linking, stable columns per chain, `continuesRow` for narration over a page break. Tests: core 72, adapter 24, CLI 6; `check_release.sh` PASS.

**Open bug (user-reported, NOT resolved):** on the user's test statement, a narration continued at the top of the next page is still dropped. Suspected cause, unconfirmed: every page repeats a page header and an account-info block (taller than the 8% furniture band, multi-column lines) plus the column header. That breaks one of: furniture detection, "first table on page", headerless/top-band conditions, or linking. Plan once confirmed: (1) furniture = lines repeated at the same position on every page, even below 8%, except the column-header row; (2) link to the page's table that MATCHES the previous one (header text/columns), not the first table; (3) attach carried lines to that table (above the first row or right after the repeated header).

**Next step:** the user generates a fully synthetic hard statement with `research/synthetic_statement_prompt.md` (external model, reportlab, ground-truth `truth.json`) and shares the PDF. Then compare DocStar's `logical_tables` to `truth.json`, reproduce the bug on it, fix it, and commit the generator as a fixture.

## Stage E: page-break narration fixed (2026-10-23)

Root cause: linking and the carried-line rule only looked at the first table on a page. An account-info block above the statement table is a table too, so the statement table was never linked to the previous page and its carried narration line was dropped. Fix: link the first table on a page that matches the previous page's columns, and treat a table near the top of a continuing page as the continuation whether or not an earlier table exists.

Tests: 2 new synthetic cases (headless and repeated header, account-info block above the table); core 74, adapter 24, CLI 6 all pass. Fixture canonical hashes (13 synthetic fixtures) unchanged. On the user's synthetic statement (`truth.json`): 193/193 narrations present (was 190/193); `check_release.sh` PASS.

## Stage F: Python engine port to Dart (2026-10-24)

`packages/docstar_engine` (pure Dart, zero runtime deps, no IO, no logging) ports `reference/docstar-py/docstar` module by module: `numbers`, `lexicon`, `extract` (pure part), `layout`, `rows`, `reconcile`, `engine`, plus `dec.dart` (BigInt decimal with Python `str`/`.2f` behaviour), `py.dart` (stable sort, half-even `round`, `median`) and a generated NFKD fold table (`tool/gen_fold.py`). `parseDocument(Document, banks:)` returns the same JSON as Python. Not ported: the ML layer (bank is null where Python's `ml` recovered it: 4 + 1 docs, ignored by key in the harness) and the PDF adapter (PORT_PLAN step 9; `makeDocument` is where it plugs in).

Harness (words.json in, no PDFs touched; corpora regenerated from `synth/generate.py`):
`dart run bin/golden.dart <ref>/eval/corpus --out <pred-dir>` (G1: writes `<name>.pred.json`, diffs against `<name>.expected.json`), then `python3 tool/eval_pred.py <ref> <ref>/eval/corpus <pred-dir>` (run_eval's table plus verified-but-wrong).

Result: G1 944/944 identical (corpus 472, holdout 472). run_eval: corpus 99.8% perfect, holdout 99.4% (same as the Python README). verified-but-wrong on money (date/amount/balance): 0 on both. Strict (narration included): 1 + 2 docs, all inherited from the reference (a trailing `CR` kept in a narration; a wrapped narration split across two rows), not port bugs. Tests: 89 (Python test cases, EDGE_CASES A*/D*/F*/R*/T*, no-OCR policy), hygiene test as in core.

Deliberate deviation: `parseAmount("$")` returns null (Python raises IndexError). Not done: G2/G3 (need the adapter), isolate wrapper, wiring into Finora / Pocket Proof.

## Engine output: page-break and header names (2026-10-24)

- Carried narration longer than the columns (runs under the amount columns) was dropped on a headless page: lead-line rule in `docstar_core` `_buildPage` required exactly one column band, now at least one. Tests added (core 78).
- Engine sections now carry `column_headers` (`{role, header}` with the header as printed) next to the standardized `columns`. Additive; the golden harness ignores it, G1 still 944/944. Output format for consumers (humans and AI): `packages/docstar_engine/OUTPUT.md`.

- Narration/Reference cut: `computeCuts` put the boundary at the widest empty x-run, so a gutter narrower than the gaps between narration words (user's statement: ~3 pt) cut mid-narration; the tail landed in `reference`. Now, when the left column is `desc` and the old run is word-gap-sized, a clean gap ending at the next text column's header edge wins. Needs a gap of at least 2 grid cells (3 pt). Golden parity 944/944 unchanged. Tests: `pageBreakRefTests`.

- Page-break link lost on a page with a single statement row (user's pages 14/15, from a masked `--mask` dump): the "top of page" test used the first table row (below a 26%-tall account block) instead of the carried narration above it, and the wrap spacing came from the account block's dense lines (6.7 pt vs the statement's 12.5 pt), so carried lines above and wrapped lines below the row were dropped and no table was linked. Now the carried lines count for "at top", and a run on the previous page's columns inherits that page's wrap spacing (`_TableInfo.contGap`). Test: 'a continuing page with one row and a tall account block' (fails without the inheritance).
- **Open, found in the same dump:** on page 14 the account block's last line (gap ~10 pt) is joined to the first statement rows, so the first two transactions of a page land in the account-info table instead of the statement table.

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
