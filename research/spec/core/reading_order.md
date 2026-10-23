# Step 4 — Reading order

**Tag: [DETERMINISTIC]** — despite the class name `ReadingOrderModel`, Docling's reading order is rule-based. No ML model is called.

## Purpose (plain English)

After layout, we know the blocks on the page but not the order a human reads them in. This step puts them in order: headers first, then body, then footers. Within the body it follows columns, separators, and captions.

## Input → output

- **In:** page elements (text, table, picture, etc.) with bounding boxes and labels; optional separators (horizontal/vertical lines between regions).
- **Out:** ordered list of elements (headers, then body, then footers, page by page).

## Steps

| # | Step | Code | Tag |
|---|---|---|---|
| 1 | Wrapper creates the rule-based predictor (no model load) | `docling/models/stages/reading_order/readingorder_model.py:72-79` (`ReadingOrderPredictor()` at `:77`) | DETERMINISTIC |
| 2 | Imports show only the rule-based predictor is used | `readingorder_model.py:53-55` (import from `reading_order_rb`) | DETERMINISTIC |
| 3 | Split elements per page: headers, body (plus horizontal separators), footers | `docling/models/postprocessing/reading_order_rb.py:464-529` (`predict_reading_order`) | DETERMINISTIC |
| 4 | Build separators (long horizontal/vertical gaps and lines) | `reading_order_rb.py:318` (`build_page_separators`) | DETERMINISTIC |
| 5 | Order body elements by dilation, left-to-right and up-down maps, with heads and interruption checks | `reading_order_rb.py:652` (`_predict_page`), `:743` (`_init_h2i_map`), `:753` (`_init_l2r_map`), `:805` (`_init_ud_maps`), `:899` (`_has_sequence_interruption`), `:952` (`_do_horizontal_dilation`) | DETERMINISTIC |
| 6 | Output order: headers, then body per page, then footers, with pages in ascending order | `reading_order_rb.py:530-535` (`sorted_elements`) | DETERMINISTIC |
| 7 | Captions and footnotes are attached by rule | `reading_order_rb.py:538` (`predict_to_captions`), `:564` (`predict_to_footnotes`) | DETERMINISTIC |

Thresholds used (copy as-is or tune on synthetic data): horizontal dilation 0.15 (normalised); vertical overlap IoU 0.8; near-vertical overlap 0.0025; left-edge alignment 0.01; interruption padding 1.0 (`reading_order_rb.py:454-459`, class constants).

## ML steps

None in this step. The earlier layout model (step 2 of the pipeline) decides *what* the blocks are, not their order.

## Why this matters for bank statements

Statements have a summary box at the top, a transaction table in the middle, and footers with page numbers. Rules above keep the table body in order. Header/footer detection depends on the labels from the layout step, which for us will come from rules.

## Open questions

1. Are headers and footers detected by layout labels only? For digital statements, repeated text across pages is a stronger rule. Test in Stage 2.
