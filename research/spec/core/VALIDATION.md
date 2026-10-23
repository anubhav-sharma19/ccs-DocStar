# Stage 1 validation — coverage report

## Method

1. **Citation check (automated).** Every `file:line` citation in the step specs (`spec/core/*.md` except this file) is resolved against the cloned sources (`research/sources/`). The script confirms the file exists and the line is in range, and prints the line so it can be read.
2. **Meaning check (manual).** Key lines are printed and read against the claim written next to them.
3. **Coverage gaps** are listed below, not hidden.

Results: **see "Latest run" at the bottom.**

## Coverage by step

| Spec file | Tag | Code read | Status |
|---|---|---|---|
| `pdf_text_cells.md` | DETERMINISTIC | pypdfium2 `_compute_text_cells` + merge helpers; docling-parse backend config; C++ `create_word_cells` / `create_line_cells`; backend default in options code | **Verified** |
| `word_line_merge.md` | DETERMINISTIC | `contract`, `infer_word_gap`, `forward_gap`, `append_cell` (key lines) | **Verified for the rules listed**; k-means internals not read line by line |
| `layout_postprocessing.md` | ML (model) + DETERMINISTIC | `check_overlap`, `OVERLAP_PARAMS`, `_should_prefer_cluster`, `_select_best_cluster_from_group`, `_assign_cells_to_clusters`, `postprocess` | **Verified**. `_sort_cells` / `_sort_clusters` not read |
| `table_structure.md` | ML (model) + DETERMINISTIC | v2 `_match_texts` and overlap call | **Verified** for v2 matching |
| `reading_order.md` | DETERMINISTIC (no model) | wrapper init, imports, `predict_reading_order`, constants, `sorted_elements` | **Verified** for the flow. Inner helpers cited by name, not read line by line |
| `page_assembly.md` | DETERMINISTIC | `__call__` lines, `\x02` replace, `inline_items` | **Partly verified**: `sanitize_text` body not read |
| `document_model.md` | DETERMINISTIC | class lines in docling-core | **Verified** (class names and lines only) |

## [ML] audit: does every ML step have candidate deterministic rules?

| Step | ML? | Candidate-rules section | Status |
|---|---|---|---|
| PDF text cells (A and B) | No | not needed | OK |
| Word / line merge | No | not needed | OK |
| Layout boxes | **Yes** | `layout_postprocessing.md`, rules LR1-LR7 (rewritten in this pass; before it was 2 rows) | **OK** |
| Table grid | **Yes** | `table_structure.md`, rules TR1-TR8 (rewritten in this pass; before it was 1 row) | **OK** |
| Reading order | No (rule-based) | not needed | OK |
| Page assembly | No | not needed | OK |
| Document model | No | not needed | OK |

No other step in the Stage 1 scope calls a model. The proposed rule thresholds in LR / TR are **our starting guesses**, not Docling values, and are marked as such in the specs.

## Corrections made during validation

1. `document_model.md`: one `base.py` citation was ambiguous (several `base.py` files). Changed to the full docling-core path.
2. Approximate `~` line references in all specs replaced with exact lines (13 places).
3. `table_structure.md`: overlap direction clarified. The code calls `tc_bbox.intersection_over_self(cell_box)`, so the 0.3 threshold is measured against the **text cell's own area**.
4. `reading_order.md`: the "0.15 of page width" unit was an assumption. Now written as "normalised".
5. `layout_postprocessing.md`: removed "RT-DETR" (architecture not checked).
6. `page_assembly.md`: removed the claim that `sanitize_text` fixes hyphenation (its body was not read).
7. Pass 2: the CODE-rule citation in `layout_postprocessing.md` was `497-503`; the code is at `499-504`. Fixed.

## Open gaps

| # | Gap | Status | Note |
|---|---|---|---|
| G1 | Default PDF backend | **CLOSED** | docling-parse (threaded). `document_converter.py:303`, `:340`; `pipeline_options.py:1301-1303`. pypdfium2 is opt-in (`pipeline_options.py:1309`) |
| G2 | Default table model (v1 vs v2) | **LOW PRIORITY** | We replace the model with rules TR1-TR8; the text matcher is unaffected |
| G3 | `sanitize_text` body (`page_assemble_model.py:118-180`) | open | Read in Stage 2 for wrapped-description rules |
| G4 | `_sort_cells` / `_sort_clusters` (`layout_postprocessor.py:731-761`) | open | Read in Stage 3 |
| G5 | Layout model architecture | open, not needed | Rules-only engine does not use it |
| G6 | docling-parse `rotate_contents()` body (`page.h:910` is the call site) | open | Only needed if rotated pages must be supported |
| G7 | docling-parse decoder links to qpdf (call seen, not read) | open | Check in Stage 3 library spike |
| G8 | Font information in text cells (needed by LR6 headings) | open | New in pass 2. Check `TextCell` fields in docling-core `page.py:281` during Stage 3 |

## xfina provenance (pass 2, details in `LICENSES.md`)

| Check | Result |
|---|---|
| PyPI description vs repo `python/README.md` | identical (similarity 1.0) |
| PyPI description links to the repo | yes, `github.com/xfina-dev/xfina` |
| Repo builds the PyPI package | yes: `python/pyproject.toml:6` name `xfina`; `.github/workflows/publish.yml` builds wheels with maturin |
| Repo owner vs PyPI maintainer | **not checkable**: PyPI author/maintainer fields are empty. Repo owner is the organisation `xfina-dev` |
| Release timing | PyPI 0.9.0 uploaded 2026-10-11; repo HEAD pushed 2026-10-11, workspace version 0.9.0 |
| Verdict | **Medium confidence, usable per Apache-2.0** (see caveat in LICENSES.md) |

## Verdict

Stage 1 covers the PDF text-cell path, word/line merging, layout postprocessing, table cell matching, reading order, page assembly, and the document model. Every rule written is backed by code that was read. Gaps G3-G8 are open and none blocks Stage 2.

## Latest run

**89 citations checked, 0 missing, 0 out of range** (after pass 2).
