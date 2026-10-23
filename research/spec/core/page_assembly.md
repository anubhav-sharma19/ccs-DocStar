# Step 5 — Page assembly (layout + cells → page elements)

**Tag: [DETERMINISTIC]**

## Purpose (plain English)

Put the pieces together for each page: each layout box becomes a typed element (text, heading, table, picture) with its words, cleaned up, plus any link it sits on.

## Input → output

- **In:** page layout clusters (from step 2), their assigned text cells, page form-field predictions, page hyperlinks.
- **Out:** page elements (text items with cleaned text, hyperlinks attached) ready for the document model.

## Steps

| # | Step | Code | Tag |
|---|---|---|---|
| 1 | Loop over page layout clusters | `docling/models/stages/page_assemble/page_assemble_model.py:183-215` (`__call__`) | DETERMINISTIC |
| 2 | Text-like labels: take each cell's text, strip it, drop blank cells | `page_assemble_model.py:203-210` | DETERMINISTIC |
| 3 | Join lines with `sanitize_text` (body not read in Stage 1; see VALIDATION.md) | `page_assemble_model.py:118` (`sanitize_text`); `\x02` → `-` at `:205` | DETERMINISTIC |
| 4 | Attach a hyperlink if a link's box matches the cluster box | `page_assemble_model.py:76` (`_match_hyperlink`) | DETERMINISTIC |
| 5 | Attach inline form fields by cluster id | `page_assemble_model.py:215` (`form_fields.inline_items`) | DETERMINISTIC |

## Rule notes for bank statements

- Joining lines inside a cell: statement descriptions wrap onto a second line (for example `UPI/123/SHOP` then `NAME`). Step 3 joins them with a space. The Stage 2 pack defines when a wrapped line is a new transaction instead (by date at line start).

## ML steps

None.

## Open questions

1. `sanitize_text` joins lines — is the join always a space, or can it drop a hyphen? Read `page_assemble_model.py:118-180` in Stage 2.
