# DocStar core design (Stage B)

Status: proposal for approval. Source of truth for rules: `research/ENGINE_SPEC.md` (cited as §). Values marked **guess** are the spec's starting values, to be tuned on fixtures, not facts.

## 1. Packages

| Package | Depends on | Job |
|---|---|---|
| `packages/docstar_core` | **nothing** (Dart SDK only: `dart:core`, `dart:convert`, `dart:math`; no `dart:io`, no Flutter) | Geometry only: chars → document model. No money, dates, issuers. Pack + Verify interfaces |
| `packages/docstar_pdfium` | `docstar_core`, `pdfrx_engine` | Reader adapter (§1.1 zone A): open, password, per-char boxes, rotation to display frame |

No packs in this stage. `docstar_pdfium`'s own pubspec carries the `pdfium_dart` override (it is the root when its tests run); `check_release.sh` gets its lockfile added to the guard. Dev-only deps (`test`, `crypto` for hashes in tests) are allowed; runtime deps of `docstar_core` stay empty.

## 2. Adapter (`docstar_pdfium`)

- `Future<ReadResult> readPdf(String path, {PasswordProvider? passwords})`. Result is `ReadOk(List<PageInput>)` or `ReadFailed(state)` with state `corrupt`, `cancelled`, `noTextLayer` (§1.2).
- `typedef PasswordProvider = Future<String?> Function(int attempt)`. Attempt 0 means `LOCKED`, attempt > 0 means the previous one was `WRONG_PASSWORD`, and `null` means cancel. The engine tries the empty password first and never stores, logs or puts the password in an exception (§1.7). This is built on pdfrx's repeating callback.
- It converts each char box from PDFium's unrotated frame (relative to the crop box) to the **display frame**: points, top-left origin, using the spike's table (`SPIKE_REPORT.md` item 2). Coordinates are rounded to 0.01 pt here so float noise across CPUs cannot change the output (ours).
- `PageInput` = number, width, height, rotation, `List<CharCell>`. `CharCell` = page-local stream index, text, box. Whitespace chars are kept, since they act as explicit word breaks.
- `noTextLayer` = no non-space char on any page. pdfrx exposes no image objects, so a blank PDF also lands here. That is acceptable: no rows either way.

## 3. Core pipeline

All steps are pure functions of `PageInput`s plus `LayoutConfig` plus optional `TableHints`.

1. **Reading frame.** Detect each page's text direction from consecutive in-word chars (vote across 0/90/180/270; ties go to 0). Rotate the page's chars so text runs left-to-right and top-to-bottom. The page records `readingRotation`, so boxes can be mapped back for overlays. This is what makes a sideways page give the same structure (ours; the spike showed rotated fixtures keep text vertical in the display frame).
2. **Lines.** Group chars into visual lines by vertical overlap, sorted by x (docling-parse "line runs").
3. **Words.** Within a line, start a new word at an explicit space, a non-overlapping baseline band, or a normalised gap > `min(0.35, inferred)` (docling `cells.h:897-944`). Normalised gap = gap / average char width. Each word keeps its **char indices**.
4. **Blocks.** LR2: start a new block when the line gap > 1.5 × median line height or the left edge jumps > 1 char width. LR4: lines in the top or bottom 8% whose text (digits → `#`) repeats on ≥ 2 pages become `pageHeader` / `pageFooter`.
5. **Table regions.** LR3(b): ≥ 3 consecutive lines sharing ≥ 3 x-columns, or a match of the hint header words (LR3(c)). Lines whose words sit inside existing columns (wrapped text) do not break the region.
6. **Columns.** TR4 header-anchored when hints are given, otherwise TR5: an x-gap > 1.5 char widths present in ≥ 80% of rows. A column whose right edges align tighter than its left edges is right-aligned (amounts) and is bounded by the header's right edge.
7. **Rows + grid.** TR2: a new row starts at a line matching `hints.rowStart` (a pack's date pattern). Without hints, a line with an empty first column continues the row above (direction `after`, the spec default). Words go to cells by > 30% own-area overlap; a straddling word goes to the column holding its centre (TR6). Empty cells are emitted with text `""`. No spanning cells (TR7).
8. **Multi-page tables.** A table whose header row text equals the previous page's table header is linked (`continuesFrom`). That header row is marked `repeatedHeader`.
9. **Reading order.** Page headers, then body blocks by (top, left), then footers; pages ascending. Docling's dilation and column ordering (`reading_order_rb.py`) is not ported. Statements are single-flow; port it when multi-column prose appears.

**Determinism.** Dart's `List.sort` is not stable, so every sort has a full tie-break ending in char index. There are no clocks, randomness, hashes of identity, or `Map` iteration over unsorted keys. Output is canonical JSON (fixed key order, coordinates at 0.01 pt).

## 4. Document model (§1.3, trimmed)

`DsDocument{pages}` → `DsPage{number, width, height, rotation, readingRotation, words, lines, blocks}`. `Word{id, text, box, charIndices}`, `Line{id, wordIds, box, text}`, `Block{id, label: text|sectionHeader|table|pageHeader|pageFooter, lineIds, box, table?}`, `Table{method: headerAnchored|whitespace, rows, cols, headerRow?, continuesFrom?, cells}`, `Cell{row, col, text, box, wordIds}`. Ids are page-scoped (`p1.w12`). **Provenance:** every cell → word ids → char indices + page. Boxes are in the reading frame; `DsPage.toDisplay(box)` maps them back. `sectionHeader` comes only from hint titles (no font size is available, LR6). No `picture` label (no image info).

## 5. Public API sketch

```dart
DsDocument layout(List<PageInput> pages, {LayoutConfig config = const LayoutConfig(), TableHints? hints});
class TableHints { List<String> headerWords; RegExp? rowStart; List<String> sectionTitles; }
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
| `wordGapCap` | 0.35 × avg char width | docling code |
| `lineOverlap` | 0.5 of the smaller height | docling pypdfium2 0.5 (adapted) |
| `blockGapFactor`, `blockIndentChars` | 1.5, 1.0 | **guess** LR2 |
| `tableMinLines`, `tableMinCols` | 3, 3 | **guess** LR3 |
| `headerFooterBand`, `headerFooterMinPages` | 0.08, 2 | **guess** LR4 |
| `colGapChars`, `colGapRowShare` | 1.5, 0.8 | **guess** TR5 |
| `cellOverlap` | 0.3 | docling code |
| `coordQuantum` | 0.01 pt | **guess** (ours) |

## 7. Open questions: ENGINE_SPEC defaults applied

Q3 remember-password off: app concern, the engine never stores. Q4 tolerance 0: for future verifiers. Q5 REVIEW per statement: the outcome is per document with a list of flagged items. Q7 scanned unsupported: `noTextLayer` is terminal. Q8 Android only: plus macOS arm64 for the CLI and tests. Core gaps: G3 `sanitize_text` joins with one space and never drops hyphens. Continuation direction is `after`. TR7 has no spanning cells. Ruled tables (TR1/TR3) are left for later because pdfrx exposes no path objects; whitespace + header-anchored rules cover the fixtures. Not applicable here: Q1, Q2, Q6, Q9, Q10.

## 8. The 13 core scenarios (§6.1) in Stage C

Met by tests: A-C1, A-C2, A-C3, A-C4 (spike's generated locked fixture), A-C6, A-C7 (in-process + macOS; the second device is the spike app run), A-C8, A-C12, A-C13 (core has no logging; a test scans the sources). A-C5: the provider is app-side; tested with a fake "remembered" provider. A-C9: `check_release.sh` + a test that `docstar_core` has no dependencies.

**Need your call:** A-C10 (`1,23,456.78` → paise) is money, which the core must not know. My default: the core test asserts the amount stays one intact word/cell, and the paise half moves to the first pack. A-C11 (`UNKNOWN_FORMAT`) needs detection. My default: implement the §1.5.3 decision table in core (generic, no money) and test it with zero packs and a test-only fake pack.
