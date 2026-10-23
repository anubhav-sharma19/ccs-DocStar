# DocStar core design (Stage B)

Status: approved 2026-10-23 with additions (continuation direction, headless page links, benchmark); updated after a PDFium probe (§3 steps 3, 6). Source of truth for rules: `research/ENGINE_SPEC.md` (cited as §). Values marked **guess** are the spec's starting values, to be tuned on fixtures, not facts.

## 1. Packages

| Package | Depends on | Job |
|---|---|---|
| `packages/docstar_core` | **nothing** (Dart SDK only: `dart:core`, `dart:convert`, `dart:math`; no `dart:io`, no Flutter) | Geometry only: chars → document model. No money, dates, issuers. Pack + Verify interfaces |
| `packages/docstar_pdfium` | `docstar_core`, `pdfrx_engine` | Reader adapter (§1.1 zone A): open, password, per-char boxes, rotation to display frame |

No packs in this stage. `docstar_pdfium`'s own pubspec carries the `pdfium_dart` override (it is the root when its tests run); `check_release.sh` gets its lockfile added to the guard. Dev-only deps (`test`, `crypto` for hashes in tests) are allowed; runtime deps of `docstar_core` stay empty.

## 2. Adapter (`docstar_pdfium`)

- `Future<ReadResult> readPdf(Uint8List bytes, {PasswordProvider? passwords})`. The caller runs `pdfrxInitialize()` once (pure Dart) or the Flutter equivalent. Result is `ReadOk(List<PageInput>)` or `ReadFailed(state)` with state `corrupt`, `cancelled`, `noTextLayer` (§1.2).
- `typedef PasswordProvider = Future<String?> Function(int attempt)`. Attempt 0 means `LOCKED`, attempt > 0 means the previous one was `WRONG_PASSWORD`, and `null` means cancel. The engine tries the empty password first and never stores, logs or puts the password in an exception (§1.7). This is built on pdfrx's repeating callback.
- It converts each char box from PDFium's unrotated frame (relative to the crop box) to the **display frame**: points, top-left origin, using the spike's table (`SPIKE_REPORT.md` item 2). Coordinates are rounded to 0.01 pt here so float noise across CPUs cannot change the output (ours).
- `PageInput` = number, width, height, rotation, `List<CharCell>`. `CharCell` = page-local stream index, text, box. Whitespace chars are kept, since they act as explicit word breaks.
- `noTextLayer` = no non-space char on any page. pdfrx exposes no image objects, so a blank PDF also lands here. That is acceptable: no rows either way.

## 3. Core pipeline

All steps are pure functions of `PageInput`s plus `LayoutConfig` plus optional `TableHints`.

1. **Reading frame.** Detect each page's text direction from consecutive in-word chars (vote across 0/90/180/270; ties go to 0). Rotate the page's chars so text runs left-to-right and top-to-bottom. The page records `readingRotation`, so boxes can be mapped back for overlays. This is what makes a sideways page give the same structure (ours; the spike showed rotated fixtures keep text vertical in the display frame).
2. **Lines.** Group chars into visual lines by vertical overlap, sorted by x (docling-parse "line runs"). A glyph joins a line only if its chunk's font-size estimate is within `overlaySizeRatio` of the line's. Punctuation and symbols in a chunk that has letters or digits skip this test and join the line of their nearest letter/digit in the chunk; a comma hanging below the baseline used to become a line of its own and leave its amount. A **chunk** is a stream-continuous run of glyphs; its size estimate is the median of glyph height ÷ shape factor (0.52 for x-height letters, 0.72 for caps, digits, ascenders and descenders; ours).
   **Overlay (stamp/watermark), Phase 3b.** Positive: normal text has a size near the page median and a horizontal baseline. Negative, labelled `overlay`: (1) a chunk larger than `overprintHeightFactor` × the page median size; (2) a chunk of ≥ 4 glyphs whose baseline slope exceeds `overlaySlope`; (3) a line larger than `overlaySizeRatio` × the page size whose centre lies inside a table's region. Lines in rule 3's size class never join or break a table run. Overlay text never joins normal lines, enters a cell, or forms a text block. It keeps its words and char indices, and comes last in reading order. Normal-size text that does not fit a table's grid still ends the table (not an overlay; widen when a statement needs it).
3. **Words.** Within a line, start a new word when the stream holds only whitespace between two neighbouring glyphs (PDFium inserts spaces and `\r\n` between separately placed runs; real spaces have width), or when the gap > 1.0 × **pitch**. Pitch is the page's median left-to-left distance of stream-adjacent glyphs, which is about one character advance. It is the length unit for every rule below. This replaces docling's `min(0.35, inferred)` × advance rule (`cells.h:897-944`): PDFium gives tight glyph boxes, not advances, so gaps inside amounts (`1,23,456.78`) are about 0.5 of a glyph width (probe, 2026-10-23). Each word keeps its **char indices**.
4. **Blocks.** LR2: start a new block when the line gap > 1.5 × median line height or the left edge jumps > 1 char width. LR4: lines in the top or bottom 8% whose text (digits → `#`) repeats on ≥ 2 pages become `pageHeader` / `pageFooter`. Two guards (X-HDRFTR negative rule): a line with ≥ 3 segments (a table row) is never furniture, and furniture must be an unbroken stack from the page edge. Without them, transaction rows near the bottom were labelled footers (found by the benchmark fixture).
5. **Table regions.** LR3(b): ≥ 3 consecutive lines sharing ≥ 3 x-columns, or a match of the hint header words (LR3(c)). Lines whose words sit inside existing columns (wrapped text) do not break the region.
6. **Columns.** A line splits into segments at gaps > 1.5 pitch. TR5: columns are the x-ranges covered by more than 20% of the table's multi-segment lines (a separator is a gap present in ≥ 80% of them). This handles right-aligned and ragged columns without knowing alignment. Segments lying wholly inside such a gap, touching no column, form a **sparse column** (e.g. a credit column only a few rows use); before this they were pulled into the nearest column's cell. With hints (TR4 header-anchored), the header line's segments must match `headerWords`, and coverage columns are merged so each holds exactly one header word. Without hints, the table's first line is its header row if it has no digit (**guess**). When a header row is known, a coverage column holding two header segments is split at its least-covered x between them. Tight amount columns (a long credit 8 pt from the balance) merge under TR5 alone. Inside a table run, a segment that straddles two columns is accepted when each of its words sits in one column.
7. **Rows + grid.** TR2: a new row starts at a line matching `hints.rowStart` (a pack's date pattern). Without hints, a line with an empty first column is a continuation line. It may sit up to max(1.0 line height, 1.2 × the page's median line gap) below the line above, so wrapped lines spaced like rows still join (`continuationGapSlack`, **guess**). `hints.continuation` decides where it goes: `after` (default) joins the row above; `before` (IDFC First: description lines sit above the date line) joins the next row, and leftovers at the table's end join the last row. Lines in a cell join top to bottom with one space. Words go to cells by > 30% own-area overlap; a straddling word goes to the column holding its centre (TR6). Empty cells are emitted with text `""`. No spanning cells (TR7).
8. **Multi-page tables.** A page's first table links to the previous page's last table (`continuesFrom`) when (a) its header row text equals that table's header (the row is marked `repeatedHeader`), or (b) it is **headless**: no header row, the same column count, every column's left or right edge within 1 pitch of the previous one's (**guess**), and its top in the page's top 25% after page headers (**guess**). A headless run at the top of a page is accepted as a table even with fewer than `tableMinLines` lines when it matches like this. If it has **fewer** columns than the previous table and each matches one of those in order (a sparse column has no entry on this page), it links and is gridded on the previous table's columns, so both pages have the same column count.
9. **Reading order.** Page headers, then body blocks by (top, left), then footers; pages ascending. Docling's dilation and column ordering (`reading_order_rb.py`) is not ported. Statements are single-flow; port it when multi-column prose appears.

**Determinism.** Dart's `List.sort` is not stable, so every sort has a full tie-break ending in char index. There are no clocks, randomness, hashes of identity, or `Map` iteration over unsorted keys. Output is canonical JSON (fixed key order, coordinates at 0.01 pt).

## 4. Document model (§1.3, trimmed)

`DsDocument{pages}` → `DsPage{number, width, height, rotation, readingRotation, words, lines, blocks}`. `Word{id, text, box, charIndices}`, `Line{id, wordIds, box, text}`, `Block{id, label: text|sectionHeader|table|pageHeader|pageFooter|overlay, lineIds, box, table?}`, `Table{method: headerAnchored|whitespace, rows, cols, headerRow?, continuesFrom?, cells}`, `Cell{row, col, text, box, wordIds}`. Ids are page-scoped (`p1.w12`). **Provenance:** every cell → word ids → char indices + page. Boxes are in the reading frame; `DsPage.toDisplay(box)` maps them back. `sectionHeader` comes only from hint titles (no font size is available, LR6). No `picture` label (no image info).

## 5. Public API sketch

```dart
DsDocument layout(List<PageInput> pages, {LayoutConfig config = const LayoutConfig(), TableHints? hints});
enum Continuation { after, before }
class TableHints { List<String> headerWords; RegExp? rowStart; Continuation continuation = after; List<String> sectionTitles; }
abstract interface class Pack<R> {           // implemented by packs later; none now
  String get id;
  Detection detect(DsDocument doc);          // strong/weak anchor hits, negative anchor fired (§1.5.3)
  TableHints hintsFor(String variant);       // layout runs again with these after detection
  R extract(DsDocument doc, String variant);
}
enum VerifyOutcome { verified, review, blocked }
enum CheckStatus { passed, failed, notRun }
abstract interface class Verifier<R> { List<CheckResult> verify(R result); }  // CheckResult{id, status, required, reason}
```
Flow later: `layout(no hints)` → `detect` → `layout(hintsFor(variant))` → `extract` → `verify`. Gate rule (§3.1): any failed → `blocked`; any required `notRun` or review trigger → `review`; else `verified`.

## 6. LayoutConfig defaults

| Field | Default | Source |
|---|---|---|
| `wordGapPitch` | 1.0 pitch (geometric fallback; explicit spaces decide first) | **guess** (replaces docling 0.35 × advance, see §3.3) |
| `lineOverlap` | 0.5 of the smaller height | docling pypdfium2 0.5 (adapted) |
| `blockGapFactor`, `blockIndentChars` | 1.5, 1.0 | **guess** LR2 |
| `tableMinLines`, `tableMinCols` | 3, 3 | **guess** LR3 |
| `headerFooterBand`, `headerFooterMinPages` | 0.08, 2 | **guess** LR4 |
| `colGapPitch`, `colGapRowShare` | 1.5, 0.8 | **guess** TR5 |
| `tableMaxGapLines`, `continuationGapLines` | 3.0, 1.0 line heights | **guess**; 1.0 from X-CONT |
| `continuationGapSlack` | 1.2 × the page's median gap between lines | **guess** (wrapped lines spaced like rows) |
| `headlessTolerancePitch`, `headlessTopBand` | 1.0, 0.25 | **guess** (your item 2) |
| `overprintHeightFactor` | 2.0 × page median font-size estimate | **guess** (overlay rule 1) |
| `overlaySlope` | 0.15 baseline rise per unit run (about 8.5°) | **guess** (overlay rule 2) |
| `overlaySizeRatio` | 1.4 | **guess**: line joining + overlay rule 3. The spike's 14/9 pt PROBE labels measure 1.53×, Courier lowercase vs caps about 1.1× |
| `cellOverlap` | 0.3 | docling code |
| `coordQuantum` | 0.01 pt | **guess** (ours) |

## 7. Open questions: ENGINE_SPEC defaults applied

Q3 remember-password off: app concern, the engine never stores. Q4 tolerance 0: for future verifiers. Q5 REVIEW per statement: the outcome is per document with a list of flagged items. Q7 scanned unsupported: `noTextLayer` is terminal. Q8 Android only: plus macOS arm64 for the CLI and tests. Core gaps: G3 `sanitize_text` joins with one space and never drops hyphens. Continuation direction is `after`. TR7 has no spanning cells. Ruled tables (TR1/TR3) are left for later because pdfrx exposes no path objects; whitespace + header-anchored rules cover the fixtures. Not applicable here: Q1, Q2, Q6, Q9, Q10.

## 8. The 13 core scenarios (§6.1) in Stage C

Met by tests: A-C1, A-C2, A-C3, A-C4 (spike's generated locked fixture), A-C6, A-C7 (in-process + macOS; the second device is the spike app run), A-C8, A-C12, A-C13 (core has no logging; a test scans the sources). A-C5: the provider is app-side; tested with a fake "remembered" provider. A-C9: `check_release.sh` + a test that `docstar_core` has no dependencies.

**Decided (2026-10-23):** A-C10 (`1,23,456.78` → paise) is money, which the core must not know. The core test asserts the amount stays one intact word/cell; the paise half moves to the first pack. A-C11 (`UNKNOWN_FORMAT`): the §1.5.3 decision table is in core, tested with zero packs and a test-only fake pack.

**Benchmark (non-gating):** `benchmark/layout_bench.dart` lays out a generated 15-page statement-like document. Timings for Mac and the emulator release build go in `research/PROGRESS.md`. Soft budget: < 300 ms on the emulator.
