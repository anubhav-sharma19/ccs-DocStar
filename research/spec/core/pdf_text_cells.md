# Step 1 — PDF text cells (backend)

**Tag: [DETERMINISTIC]** (no ML anywhere in this step.)

## Purpose (plain English)

Before any layout analysis, the engine needs the text on the page *and* where each piece sits. The PDF backend reads the PDF and returns small text pieces, each with a rectangle (its bounding box). Everything later works from these pieces.

Docling has two backends that do this. We compare them because the Dart reader will need one of these approaches.

| | A. pypdfium2 backend (PDFium) | B. docling-parse backend (its own C++ decoder) |
|---|---|---|
| Who reads the PDF | Google's PDFium engine (via `pypdfium2`) | Docling's own C++ decoder (`docling-parse`) |
| Smallest unit it gets | PDFium "rect" = a run of characters PDFium groups | single characters (char cells) |
| Where word/line grouping happens | Our Python merge code | C++ `contract()` |
| Is it Docling's default? | **No.** Opt-in `PdfBackend.PYPDFIUM2` (`docling/datamodel/pipeline_options.py:1309`) | **Yes.** `PdfFormatOption.backend = ThreadedDoclingParseDocumentBackend` (`docling/document_converter.py:303`; `NativePdfFormatOption` same at `:340`); enum doc says "default and recommended" (`pipeline_options.py:1301-1303`); older names all map to it (`pipeline_options.py:1319-1340`) |

## Input → output

- **In:** PDF page (bytes), page index.
- **Out:** list of `TextCell` — `index`, `text`, `orig`, `from_ocr=False`, `rect` (4-corner quadrilateral, top-left origin).

## Steps — A. pypdfium2

| # | Step | Code | Tag |
|---|---|---|---|
| A1 | Get PDFium text page; read page rotation and origin | `backend/pypdfium2_backend.py:414-421` | DETERMINISTIC |
| A2 | Ask PDFium for each rect; take the text inside it (not the rect's own text) | `pypdfium2_backend.py:430-432` (`count_rects`, `get_rect`, `text_in_rect`) | DETERMINISTIC |
| A3 | Convert the rect from PDF frame to display frame (rotation 0/90/180/270) | `pypdfium2_backend.py:168-209` (`_rect_to_display_frame`), `:210-265` (`_rect_to_pdf_frame`) | DETERMINISTIC |
| A4 | Group rects into rows: same top and bottom within 0.5 × row height | `pypdfium2_backend.py:467-497` (`group_rows`; default `vertical_threshold_factor=0.5`, `:461`) | DETERMINISTIC |
| A5 | Within a row, merge neighbours when the horizontal gap ≤ average height × 1.0 | `pypdfium2_backend.py:498-521` (`merge_row`; default factor 1.0, `:460`) | DETERMINISTIC |
| A6 | For a merged group, re-read its text from PDFium using the merged box | `pypdfium2_backend.py:522-558` (`merge_group`) | DETERMINISTIC |
| A7 | Renumber cell indexes 1..n | `pypdfium2_backend.py:552-553` (`for i, cell in enumerate(...)`) | DETERMINISTIC |

**Key idea for us:** PDFium's rects are often split mid-word. Docling fixes this with a *heuristic* merge (A4–A5), not with ML.

## Steps — B. docling-parse

| # | Step | Code | Tag |
|---|---|---|---|
| B1 | Pick which cell levels to build (char / word / line) from a content config | `docling/backend/docling_parse_backend.py:94-124` | DETERMINISTIC |
| B2 | C++ decodes page; builds char cells | `docling-parse/src/parse/pdf_decoders/page.h` (decoder) | DETERMINISTIC |
| B3 | Word cells = `contract(cells).words` | `docling-parse/src/parse/page_item_sanitators/cells.h:987-993` | DETERMINISTIC |
| B4 | Line cells = `contract(cells).lines` | `cells.h:996-1003` | DETERMINISTIC |
| B5 | `contract()` splits each line run into words (see [word_line_merge.md](word_line_merge.md)) | `cells.h:889-960` | DETERMINISTIC |
| B6 | Python side flips y to top-left origin for text, char, word cells | `docling/backend/docling_parse_backend.py:158-171` | DETERMINISTIC |

## Rotation handling

- **A (pypdfium2):** PDFium returns rects in the *unrotated* frame. We convert with `_rect_to_display_frame` (`:168`) and back with `_rect_to_pdf_frame` (`:210`). Both take rotation 0/90/180/270.
- **B (docling-parse):** the C++ decoder rotates contents into the display frame before cell creation (`docling-parse/src/parse/pdf_decoders/page.h:910` `rotate_contents()`); the original angle is captured first (`page.h:985-986`).

## Finding that changes the Dart plan

- In docling-parse, the Python `DecodeConfig` merge knobs (`word_space_width_factor_for_merge=0.33`, `line_space_width_factor_for_merge=1.0`, `pdf_parser.py:240-243`) are **passed to C++ but never used** by `create_word_cells`/`create_line_cells` (`cells.h:991`, `:1002` both do `(void)config;`). Do not tune those knobs expecting an effect.

## ML steps

None in this step.

## Open questions

1. (Closed) Default backend is docling-parse (see table above). pypdfium2 is the opt-in alternative.
2. PDFium rect text (A) vs C++ char contraction (B): which gives fewer broken words on digital bank statements? Needs a spike with synthetic PDFs (no real statements).

## Implication for the Dart engine

- Docling's **reference behaviour is docling-parse** (B): characters first, then a gap rule for words. That is the better model to copy.
- Our likely Dart PDF engine is PDFium (A's engine). If it exposes **per-character boxes**, apply the docling-parse gap rule (`word_line_merge.md`) on top of them instead of copying the pypdfium2 rect-merge (A4–A5), which is a weaker heuristic.
- If it only exposes PDFium rects or words, copy A4–A5 as the fallback. Which one is available is the first spike in Stage 3.
