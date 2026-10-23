# Step 1b — Character → word → text-line merging (docling-parse)

**Tag: [DETERMINISTIC]**

## Purpose (plain English)

Characters are tiny. We need words (for matching amounts and dates) and lines (for reading rows). This step decides where one word ends and the next begins, using only the position and spacing of characters.

## Input → output

- **In:** character cells (text, 4-corner box, font advance width, baseline, optional explicit PDF space markers).
- **Out:** word cells and line cells, each with a quadrilateral box and joined text.

## Algorithm (from the C++ code)

| # | Step | Code | Tag |
|---|---|---|---|
| 1 | Split characters into **line runs** (rotation-aware; each run is one visual line) | `cells.h:367` (`collect_line_runs` declaration; doc comment `:356-366`) | DETERMINISTIC |
| 2 | Word gap threshold for each run: `min(0.35, has_explicit_spaces ? 1.0 : inferred_gap)` | `cells.h:897-899` | DETERMINISTIC |
| 3 | If the run has no explicit spaces, infer the gap by 2-cluster 1-D k-means over normalised gaps (fixed iterations) | `cells.h:728-790` (`infer_word_gap`); doc `:372-378` | DETERMINISTIC |
| 4 | Gap between two characters: `forward_gap` (signed, page units) | `cells.h:471` | DETERMINISTIC |
| 5 | Start a new word when: explicit PDF space; **or** baselines incompatible; **or** normalised gap > threshold | `cells.h:913-944` | DETERMINISTIC |
| 6 | Special case: TOC dot leaders keep their first dot with the leader | `cells.h:913-925` | DETERMINISTIC |
| 7 | Each word = smallest rectangle around its characters | `cells.h:802` (`append_cell`), called at `:952` | DETERMINISTIC |
| 8 | Line cell = the whole run, words joined with one ASCII space | `cells.h:68-76` (doc), `:996-1003` | DETERMINISTIC |

**Normalised gap** = `max(0, forward_gap) / average character advance` (`cells.h:937-941`).

## Why this matters for bank statements

- Amounts like `1,23,456.78` (Indian lakh grouping) contain commas and dots. A wrong word split can split the amount. The normalised-gap rule keeps tight digits together, so the split is usually right. Verify with synthetic samples in Stage 2.
- Table columns separated by wide gaps split cleanly, which is what we want.

## ML steps

None.

## Parameters we must NOT rely on

- `word_space_width_factor_for_merge` (0.33), `line_space_width_factor_for_merge` (1.0), `line_space_width_factor_for_merge_with_space` (0.33) exist in the Python config (`pdf_parser.py:240-243`) but **are ignored**: `cells.h:991` and `:1002` pass `config` and discard it (`(void)config;`). The threshold that is actually used is the one in `cells.h:897-899`.

## Open questions

1. Are inferred word gaps stable across fonts with different spacing? Test with synthetic PDFs only.
