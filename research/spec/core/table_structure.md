# Step 3 — Table structure (how predicted cells are matched to text cells)

**Tag: [ML] for predicting the cell grid; [DETERMINISTIC] for matching text to cells.**

## Purpose (plain English)

A table model guesses the grid: rows, columns, and each cell's box. It does not read text. This step gives each grid cell the words that sit inside it.

## Input → output

- **In:** table image/layout predictions (rows, columns, cell boxes) from the model; text cells of the page (step 1).
- **Out:** table with `num_rows`, `num_cols`, and cells (`text`, row/column span, bbox).

## Two model versions in the repo

| Version | Code | Status in repo |
|---|---|---|
| v1 `TableStructureModel` (TableFormer-style ML) | `docling/models/stages/table_structure/table_structure_model.py:35` (class), `:181-320` (`predict_tables`) | ML prediction |
| v2 `TableStructureModelV2` | `docling/models/stages/table_structure/table_structure_model_v2.py:38` (class), `:400` (`predict_tables`) | ML prediction + deterministic text matching at `:126`, `:191-228`, `:489-508` |

Text matching lives in v2. v1 has no text-cell matching in `table_structure_model.py` (confirmed by search, see VALIDATION.md). Confirm the default before Stage 3.

## Steps (v2 text matching, deterministic)

| # | Step | Code | Tag |
|---|---|---|---|
| 1 | Model predicts cell boxes | `table_structure_model_v2.py:400` (`predict_tables`) | **[ML]** |
| 2 | For each predicted cell box, find text cells that overlap it | `table_structure_model_v2.py:196-228` (`_match_texts`) | DETERMINISTIC |
| 3 | A text cell counts when `tc_bbox.intersection_over_self(cell_box) > 0.3` (default `textcell_overlap`): more than 30% of the text cell's own area lies inside the predicted cell | `table_structure_model_v2.py:126`, `:224`, call sites `:165-168`, `:489-493` | DETERMINISTIC |
| 4 | Matched words are stripped and joined with one space, in text-cell order | `table_structure_model_v2.py:225-226` | DETERMINISTIC |
| 5 | Each table cell gets its text; cells are built from matched results | `table_structure_model_v2.py:173-178`, `:508` | DETERMINISTIC |

## ML steps and candidate deterministic rules

**The one [ML] step:** the table model (step 1) predicts the grid: where the rows, columns and cell boxes are. It does not read text. Once cell boxes exist, text matching (steps 2-5) is already deterministic, so a rule-based grid can feed it unchanged.

> Thresholds below are **our proposals**, starting guesses to tune on synthetic PDFs. Statements often have **no ruling lines**, so the unruled rules matter most.

| Rule | What it does | Needs | Starting value |
|---|---|---|---|
| TR1 Rows, ruled | Horizontal ruling lines inside the table region are the row borders (`pdf_backend.py:66`) | shapes | n/a |
| TR2 Rows, unruled | A line that **starts with a date** (pack date patterns) starts a new row. Lines without a leading date are continuation lines and are appended to the row above (wrapped descriptions) | pack | n/a |
| TR3 Columns, ruled | Vertical ruling lines are column borders | shapes | n/a |
| TR4 Columns, header-anchored | Find the pack's column-header words. A column runs from its header's left edge to the next header's left edge. Right-aligned amount columns use the header's right edge instead | pack | n/a |
| TR5 Columns, fallback | Project all word boxes in the table onto the x-axis. A gap wider than 1.5 x the average character width that appears on at least 80% of rows is a column separator | word cells | 1.5 x, 80% |
| TR6 Words to cells | Keep Docling's rule: a word belongs to a cell when more than 30% of the word's own area lies inside it (`table_structure_model_v2.py:126`, `:224`). A word that straddles two columns goes to the column containing its centre | word cells | 0.3 |
| TR7 Spanning cells | Not supported in v1. The description column absorbs continuation lines. Merged header cells are ignored | n/a | n/a |
| TR8 Self-check | Every row has a date and at least one amount; every row has the same column count; amounts parse. Otherwise flag "needs review" (Stage 3 verify layer) | pack | n/a |

Output must match what the matcher produces: cells with `text`, row, column and bbox (`table_structure_model_v2.py:173-178`).

## Open questions

1. (Low priority) Which table model version is Docling's default? Not needed: we replace the model with rules TR1-TR8, and the matcher is the same in both.
2. Overlap 0.3 is measured against the text cell's own area: a text cell that straddles two columns can be split. Test on synthetic statements.
