# Rule register (seed)

**Every rule here is a HYPOTHESIS** until it reaches `held-out-validated` (see `research/ENGINE_SPEC.md` sections 0.1, 1.5.2, 5.4). Nothing in this file has been run on a real or fake document.

Columns: `evidence_level` uses the Stage 2 scale (High / Medium / Low). `validation` starts at `hypothesis`. `status`: `active`, `unresolved` (decision D3), `open` (decision D4 and similar).
Detectors and matchers always have both a **positive** rule (when it fires) and a **negative** rule (when it must not fire).

## Common rules (all packs)

| ID | Kind | Rule | Positive (fires when) | Negative (must NOT fire when) | Evidence | Level | Validation | Status |
|---|---|---|---|---|---|---|---|---|
| X-001 | matcher | Row starts at a line that begins with the variant's date pattern | Line starts with the pattern | A continuation line that quotes a date mid-text | spec: `spec/packs/credit_card.md` s1 | Low | hypothesis | active |
| X-002 | parser | Strip commas before parsing amounts (lakh grouping works by removal) | `1,23,456.78` -> 12345678 paise | A string with letters inside | code: `stmt-forge/src/stmtforge/parsers/base_parser.py:69`; `xfina/src/bank_accounts/sbi.rs:110-116` | Medium | hypothesis | active |
| X-003 | parser | Direction comes from the variant's marker or column, never from words | Known marker in known position | Marker-like letter inside description | ours (negative of `base_parser.py:85-116`) | Low | hypothesis | active |
| X-004 | policy | Keep every row; never deduplicate within a statement | Two identical rows both kept | Any dedupe | ours; negative of `base_parser.py:165` | Low | hypothesis | active |
| X-005 | policy | Keep printed order; never sort rows | Output order = page order | Sorting by date or text | negative of `CardQL/src/cardql/parsers/banks/sbi_v1.py:122` | Low | hypothesis | active |
| X-006 | policy | Year comes from the printed period; no hard-coded fallback | Period found -> year set | Period missing -> must not invent a year (REVIEW) | negative of `stmt-forge/src/stmtforge/parsers/hdfc_parser.py:183-188` | Low | hypothesis | active |
| X-007 | detector | Table region: closed ruled grid, or 3+ aligned lines with 3+ columns, or pack header | One of the three holds | A two-column label / value summary box | spec: `spec/core/layout_postprocessing.md` LR3 | Low | hypothesis | active |
| X-008 | detector | Repeated header / footer: same text (digits -> `#`) in top / bottom 8% on 2+ pages | Repeats across pages | A transaction row repeated in another statement | spec: LR4 | Low | hypothesis | active |

## SBI bank statement (PDF) — variant `sbi-bank`

| ID | Kind | Rule | Positive | Negative | Evidence | Level | Validation | Status |
|---|---|---|---|---|---|---|---|---|
| B-SBI-01 | detector | Fingerprint: page 1 has >= 2 of `ACCOUNT NUMBER`, `IFSC CODE`, `MICR CODE`, `CIF NUMBER`, `BRANCH NAME` and `STATE BANK OF INDIA` | Both conditions | Bank name only in an ad in the footer | code: `xfina/src/bank_accounts/sbi.rs:671-694` | Medium | hypothesis | active |
| B-SBI-02 | matcher | Row = `dd/mm/yyyy dd/mm/yyyy` at line start; last 3 tokens = debit, credit, balance | Pattern at line start | A header line with two dates (statement period) | code: `sbi.rs:90`, `:332-337` | Medium | hypothesis | active |
| B-SBI-03 | parser | Dash `-` in debit / credit means no amount | `-` token | `-` inside a description | code: `sbi.rs:310-312`, `:340` | Medium | hypothesis | active |
| B-SBI-04 | parser | Balance suffix `CR` positive, `DR` negative | Suffix present | Suffix on a debit/credit column | code: `sbi.rs:117-129` | Medium | hypothesis | active |
| B-SBI-05 | matcher | Continuation lines: left edge near the description column (take the column from the page's header cells, not 120-150) | Line inside the block, left edge in the description column | Header, footer, or a new dated row | code: `sbi.rs:350-365`; negative N11 | Low | hypothesis | active |
| B-SBI-06 | detector | Table starts at a short `Balance` header line; ends at `Statement Summary` or `Closing Balance` | Header seen; stop title seen | The word `Balance` inside a description | code: `sbi.rs:285-292` | Low | hypothesis | active |
| B-SBI-07 | matcher | Summary row: opening, debit count, credit count, total debits, total credits, closing | Row matches the 6-field pattern | A transaction row (it starts with two dates) | code: `sbi.rs:95-98`, `:196-221` | Medium | hypothesis | active |
| B-SBI-08 | verify | V-ROW, V-OPEN (only if printed), V-CLOSE, V-TOT, V-CNT | Checks run | Opening balance derived from the first row counted as passed (N8) | code: `sbi.rs:529-640` | Medium | hypothesis | active |

## HDFC credit card — variants `hdfc-old`, `hdfc-2025`

| ID | Kind | Rule | Positive | Negative | Evidence | Level | Validation | Status |
|---|---|---|---|---|---|---|---|---|
| K-HDFC-01 | detector | `hdfc-2025` fingerprint: header `DATE & TIME TRANSACTION DESCRIPTION REWARDS AMOUNT PI` | Header present in the table zone | Same words in a paragraph | code: `CardQL/src/cardql/parsers/banks/hdfc_v2.py:4-8` | Medium | hypothesis | active |
| K-HDFC-02 | matcher | `hdfc-2025` row = `DD/MM/YYYY| HH:MM` + description + `C` amount | Pattern at line start | A line with a time but no amount | code: `hdfc_v2.py:54-56`; `stmt-forge/src/stmtforge/parsers/hdfc_parser.py:39-45` | Medium | hypothesis | active |
| K-HDFC-03 | matcher | `hdfc-2025` credit when `+` precedes `C` | `+ C 16,099.00` | `C` as part of a word | code: `hdfc_v2.py:55` | Medium | hypothesis | active |
| K-HDFC-04 | matcher | `hdfc-old` row = `DD/MM/YYYY` + description + amount + optional `Cr` | Pattern | `DD/MM/YYYY|` with time (that is 2025) | code: `hdfc_parser.py:19-25` | Medium | hypothesis | active |
| K-HDFC-05 | policy | International rows are imported (the title does not end the section) | Rows after `International Transactions` imported | Section ended at the title (N2) | negative of `hdfc_v1.py:87`, `hdfc_v2.py:131` | Low | hypothesis | active |
| K-HDFC-06 | policy | Reward Points Summary, Rewards Program, Cashback, GST Summary tables are not imported | Section title seen | A transaction row whose description contains `GST` (a charge) | code: `xfina/src/credit_cards/hdfc.rs:111-135` | Low | hypothesis | active |
| K-HDFC-07 | matcher | Add-on spends carry a card member; strip any id printed after the name | Member column present | Treating an id as part of the name | code: `hdfc.rs:230-233` | Low | hypothesis | active |
| K-HDFC-08 | verify | V-CARD with finance charges | All components found | Check run without finance charges (N3) | code: `hdfc.rs:213-221`, `:414-436` | Medium | hypothesis | active |

## ICICI credit card — variants `icici-A`, `icici-B` (both unresolved, D3)

| ID | Kind | Rule | Positive | Negative | Evidence | Level | Validation | Status |
|---|---|---|---|---|---|---|---|---|
| K-ICICI-A01 | detector | Variant A fingerprint: header `Date SerNo` and rows with a 10+ digit serial number after the date | Header + serial rows | Variant B two-date rows | code: `CardQL/src/cardql/parsers/banks/icici_v1.py:4-7`, `:101` | Low | hypothesis | **unresolved** |
| K-ICICI-A02 | matcher | A row = date + serial + description + reward points + amount (+ `CR`); reward points are dropped, not left in the description | Points column parsed separately | Points inside description (N7) | code: `icici_v1.py:58-66`; `xfina/src/credit_cards/icici.rs:589-592` | Low | hypothesis | **unresolved** |
| K-ICICI-A03 | detector | Period line `Statement period : Month d, yyyy to Month d, yyyy` | Pattern | A transaction date line | code: `icici_v1.py:30-35` | Low | hypothesis | unresolved |
| K-ICICI-B01 | detector | Variant B fingerprint: two dates per row (transaction + posting) | Two dates at line start | One date + serial number (A) | code: `stmt-forge/src/stmtforge/parsers/icici_parser.py:18-33` | Low | hypothesis | **unresolved** |
| K-ICICI-B02 | matcher | B row = date, date, description, amount, `Cr`/`Dr` | Pattern | A summary line with two dates | code: `icici_parser.py:18-25` | Low | hypothesis | **unresolved** |
| K-ICICI-X01 | policy | Variant is chosen by verify outcome; if both verify, or neither, the statement is REVIEW | One variant verifies | Choosing by row count (N4) | ours | Low | hypothesis | active |

## SBI Card — variant `sbicard-1`

| ID | Kind | Rule | Positive | Negative | Evidence | Level | Validation | Status |
|---|---|---|---|---|---|---|---|---|
| K-SBI-01 | matcher | Row = `DD Mon YY` + description + amount + marker `D` or `C` | Pattern on any line of the page | A line without marker | code: `CardQL/.../sbi_v1.py:65-70`; `stmt-forge/.../sbi_parser.py:18-24` | Medium | hypothesis | active |
| K-SBI-02 | matcher | `C` = credit, `D` = debit | Marker `C` / `D` | Marker `M` (below) | code: `sbi_v1.py:68-70` | Medium | hypothesis | active |
| K-SBI-03 | matcher | Marker `M`: unknown; flag `unknown_marker`; statement is REVIEW | `M` marker | Treating `M` as a spend (the source does) | code: `sbi_v1.py:68-70` | Low | hypothesis | **open** (D4) |
| K-SBI-04 | detector | Do not rely on section headings for position; payments can appear above `TRANSACTIONS FOR ...` and some debits below `SHOP & SMILE SUMMARY` | Rows matched page-wide | Dropping rows outside a heading | code: `sbi_v1.py:94-100` | Medium | hypothesis | active |
| K-SBI-05 | detector | Period line `Statement Period : DD Mon YY to DD Mon YY` | Pattern | Another date range | code: `sbi_v1.py:40-46` | Medium | hypothesis | active |

## Axis credit card — variant `axis-1`

| ID | Kind | Rule | Positive | Negative | Evidence | Level | Validation | Status |
|---|---|---|---|---|---|---|---|---|
| K-AXIS-01 | detector | Header `DATE TRANSACTION DETAILS MERCHANT CATEGORY AMOUNT` | Header in table zone | Same words in a paragraph | code: `CardQL/.../axis_v1.py:4-8` | Medium | hypothesis | active |
| K-AXIS-02 | matcher | Row = `dd/mm/yyyy` + description (+ merchant category) + amount + `Dr`/`Cr` | Pattern, marker last | Period line `dd/mm/yyyy - dd/mm/yyyy` | code: `axis_v1.py:43-48`, `:79` | Medium | hypothesis | active |
| K-AXIS-03 | matcher | Keep two-word categories together: `DEPT STORES`, `AUTO SERVICES`, `HOME FURNISHING`, `FOOD PRODUCTS` | Pair seen | A merchant that happens to contain the pair | code: `axis_v1.py:18-23` | Low | hypothesis | active |
| K-AXIS-04 | detector | Table ends at `End of Statement` | Marker seen | The words in a description | code: `axis_v1.py:95`; `xfina/src/credit_cards/axis.rs:16-21` | Medium | hypothesis | active |
| K-AXIS-05 | verify | Total due = opening + debits - credits (no purchases / payments split printed) | Opening and total due printed | Check run when opening is missing (`not_run`) | code: `axis.rs:23-26`, `:262-282` | Medium | hypothesis | active |

## IDFC First credit card — variant `idfc-1` (Low)

| ID | Kind | Rule | Positive | Negative | Evidence | Level | Validation | Status |
|---|---|---|---|---|---|---|---|---|
| K-IDFC-01 | matcher | Row = `DD Mon YY [Convert] amount DR/CR`; description may be on the line(s) **before** | Date line preceded by text lines | Promo text before the date line (below) | code: `stmt-forge/.../idfc_first_parser.py:3-6`, `:33-47` | Low | hypothesis | active |
| K-IDFC-02 | policy | `Convert` EMI tag is removed from the description; the row is an EMI installment and is imported | Tag present | Schedule tables | code: `idfc_first_parser.py:70-71` | Low | hypothesis | active |
| K-IDFC-03 | detector | Promo / noise lines end the table (prefix list) | Line starts with a listed prefix | A merchant starting with the same word | code: `idfc_first_parser.py:18-25` | Low | hypothesis | active |

## HSBC credit card — variant `hsbc-1` (Low)

| ID | Kind | Rule | Positive | Negative | Evidence | Level | Validation | Status |
|---|---|---|---|---|---|---|---|---|
| K-HSBC-01 | matcher | Date `DDMMM` with no year; year from the printed period | Period found | Period missing (REVIEW) | code: `CardQL/.../hsbc_v1.py:22`, `:33-36` | Low | hypothesis | active |
| K-HSBC-02 | detector | Table between `OPENING BALANCE` / `PURCHASES & INSTALLMENTS` and the stop markers `TOTAL PURCHASE OUTSTANDING`, `TOTAL CASH OUTSTANDING`, `NET OUTSTANDING BALANCE`, `Interest Rate applicable` | Start and stop seen | A stop phrase in a description | code: `hsbc_v1.py:59-66` | Low | hypothesis | active |
| K-HSBC-03 | parser | Amount: use the amount column; no cap, no "smallest value" | Column parsed | `min` over matches (N5) | negative of `hsbc_v1.py:99-102` | Low | hypothesis | active |
