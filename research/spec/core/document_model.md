# Step 6 — Document model (docling-core)

**Tag: [DETERMINISTIC]** (data structures only, no logic that uses ML.)

## Purpose (plain English)

The standard output format. Every step above ends by writing into this tree: pages, text items, tables, pictures, and where each item sits (page number plus box). The Dart engine should adopt the same shape so packs and exports work the same way.

## Core types (docling-core)

| Concept | Type | Code | Plain English |
|---|---|---|---|
| Coordinate origin | `CoordOrigin` | `docling-core/docling_core/types/doc/base.py:24` | Whether y=0 is at the top or the bottom |
| Box | `BoundingBox` | `docling-core/docling_core/types/doc/base.py:61` | Left, top, right, bottom (or quadrilateral corners) |
| Cell quadrilateral | `BoundingRectangle` | `docling-core/docling_core/types/doc/page.py:104` | 4 corners, used for rotated text |
| Text cell (word/line) | `TextCell` | `page.py:281` | Text + rectangle + index |
| PDF text cell | `PdfTextCell` | `page.py:364` | TextCell from a PDF page |
| Segmented page | `SegmentedPdfPage` | `page.py:754` | All cells, shapes and bitmaps of one page |
| Document | `DoclingDocument` | `docling-core/docling_core/types/doc/document.py:176` | Root object |
| Page entry | `PageItem` | `docling-core/docling_core/types/doc/common/reference.py:218` | Per-page size and metadata |
| Location of an item | `ProvenanceItem` | `reference.py:205` | Page number + bbox + character span |
| Layer | `ContentLayer` | `docling-core/docling_core/types/doc/common/content_layer.py:6` | Body vs furniture (headers/footers) |

## Pipeline → model mapping

| Pipeline step | What it writes |
|---|---|
| 1 PDF cells | `TextCell` list on the page (`SegmentedPdfPage`) |
| 2 Layout postprocess | Clusters → typed items with `ProvenanceItem` |
| 3 Table | `TableItem` with grid cells |
| 4 Reading order | Ordered children of the document body |
| 5 Page assembly | Text items with cleaned text |

## ML steps

None.

## Spec note for the Dart engine

Keep boxes in top-left origin after the cell step (the Python code converts with `to_top_left_origin`, e.g. `docling_parse_backend.py:158-171`). One origin everywhere avoids bugs.

## Open questions

1. Do we copy the whole `DoclingDocument` JSON shape, or a smaller one? Decide in Stage 3 (keep it small, bank statements need few types).
