# Step 2 — Layout postprocessing (clusters, merging, overlaps, cell assignment)

**Tag: [ML] for the layout model that proposes boxes; [DETERMINISTIC] for everything in this step.**

## Purpose (plain English)

The layout model draws boxes around things on the page (paragraph, table, picture, header). Several boxes often overlap. This step decides which box wins, merges the leftovers, and gives each text cell to exactly one box.

## Input → output

- **In:** layout clusters from the model (`id`, `label`, `bbox`, `confidence`, `cells`); the page's text cells (step 1).
- **Out:** final list of clusters (regular, picture, table/wrapper), each holding its text cells in reading-ready order.

## Steps

| # | Step | Code | Tag |
|---|---|---|---|
| 1 | Layout model proposes clusters (object-detection model; architecture not checked in Stage 1) | `docling/models/stages/layout/layout_object_detection_model.py` (model); `models/factories/layout_factory.py` | **[ML]** |
| 2 | Entry: process regular clusters, then special clusters (tables, pictures, wrappers) | `utils/layout_postprocessor.py:181-219` (`postprocess`), `:220` (`_process_regular_clusters`), `:278` (`_process_special_clusters`) | DETERMINISTIC |
| 3 | Two boxes are "overlapping" when IoU > 0.8 **or** either contains the other by > 0.8 | `layout_postprocessor.py:84-107` (`check_overlap`), defaults `:551-556` | DETERMINISTIC |
| 4 | Overlapping boxes form groups (union-find) | `layout_postprocessor.py:22-54` (`UnionFind`), `:551-606` (`_remove_overlapping_clusters`) | DETERMINISTIC |
| 5 | Per type, thresholds: regular area 1.3 / conf 0.05; picture 2.0 / 0.3; wrapper 2.0 / 0.2 | `layout_postprocessor.py:112-116` (`OVERLAP_PARAMS`) | DETERMINISTIC |
| 6 | Pick the winner in a group: label rules first (LIST_ITEM vs TEXT if area within 20%; CODE wins if it contains > 80% of another) | `layout_postprocessor.py:482-516` (`_should_prefer_cluster`) | DETERMINISTIC |
| 7 | Otherwise: reject a candidate if its area ≤ `area_threshold` and it has lower confidence by more than `conf_threshold` | `layout_postprocessor.py:508-515` | DETERMINISTIC |
| 8 | Among survivors, prefer the larger box unless confidence differs by more than the threshold | `layout_postprocessor.py:518-549` (`_select_best_cluster_from_group`) | DETERMINISTIC |
| 9 | Losers' cells are moved to the winner; cells are de-duplicated and re-sorted | `layout_postprocessor.py:598-604`, `:638-647` (`_deduplicate_cells`) | DETERMINISTIC |
| 10 | Each text cell goes to the cluster that covers it most. Needs ≥ 0.2 overlap and skips blank or zero-area cells | `layout_postprocessor.py:648-690` (`_assign_cells_to_clusters`, `min_overlap=0.2`) | DETERMINISTIC |
| 11 | Cells not assigned to any box are returned as unassigned | `layout_postprocessor.py:691-698` (`_find_unassigned_cells`) | DETERMINISTIC |
| 12 | Final cluster order is by id; cells sorted within each cluster | `layout_postprocessor.py:181-219` | DETERMINISTIC |

## ML steps and candidate deterministic rules

**The one [ML] step:** the layout model (step 1) draws boxes and gives each a label and a confidence. Steps 2-12 then use `label`, `bbox`, `confidence` and `cells` of each box (`layout_postprocessor.py:482-516`, `:648-690`). A rule-based replacement must output boxes with those same four fields, so the rest of this step can be copied unchanged.

**What we get for free on a digital PDF:** exact word boxes (step 1), ruling lines and shapes (`get_shape_lines` `pdf_backend.py:66`, `get_connected_shape_bounding_boxes` `:81`, `get_thin_shape_boxes` `:91`), and image rectangles (`get_bitmap_rects` `:48`).

> The thresholds below are **our proposals**, not Docling values. They are starting guesses to be tuned on synthetic PDFs.

| Rule | What it does | Needs | Starting value |
|---|---|---|---|
| LR1 Lines | Group word cells into text lines by baseline (reuse `word_line_merge.md`) | word cells | n/a |
| LR2 Text blocks | Start a new block when the gap to the previous line is larger than 1.5 x the median line height, or the left edge moves by more than one average character width | lines | 1.5 x, 1 char |
| LR3 Table regions | A region is a **table** when any one holds: (a) ruling lines form a closed grid, (b) 3 or more consecutive lines have 3 or more words aligned to the same x-columns, (c) a pack column-header fingerprint (for example Date / Narration / Debit / Credit / Balance) matches | lines, shapes, pack | 3 lines, 3 columns |
| LR4 Page header / footer | A line in the top or bottom 8% of the page whose text repeats on 2 or more pages (digits replaced by `#`) gets label PAGE_HEADER / PAGE_FOOTER. Reading order already treats those two labels separately (`reading_order_rb.py:464-529`) | 2+ pages | 8% |
| LR5 Pictures | Each bitmap rectangle becomes a PICTURE box (logos); ignored later | bitmaps | n/a |
| LR6 Section headings | A line is a heading if it is larger or bolder than the body median, or its text matches a pack section title (for example "Domestic Transactions") | font size (**not checked** whether the cell exposes it), pack | pack list |
| LR7 Label and confidence | Use only the labels TEXT, SECTION_HEADER, TABLE, PICTURE, PAGE_HEADER, PAGE_FOOTER. Set confidence 1.0 for rule-made boxes. For overlaps keep the table: add a label rule "TABLE beats TEXT", like the existing CODE rule at `layout_postprocessor.py:499-504` | none | n/a |

Failure behaviour: if no table region is found on a page that the pack expects to have one, do not guess. Flag the page "needs review" (Stage 3 verify layer).

## Evidence checked

- `OVERLAP_PARAMS` values and the overlap helpers are the thresholds we copy (rule-based, no ML).
- The algorithm needs only geometry, so it ports to pure Dart.

## Open questions

1. Does the layout model's output ever produce boxes that overlap by less than 0.8 but still look duplicated? Test on synthetic pages.
