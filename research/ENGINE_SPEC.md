# DocStar — Engine Specification (Stage 3)

Name: `DocStar` (Dart package `docstar`; renamed from `ccs-docengine` on 2026-10-23). Universal CalmCraft document engine; Finora and Pocket Proof will consume it. Output of the research phase. **No code in this document.**
Written for a reader new to document AI: every term is explained where it first appears.

---

## 0. Read this first

### 0.1 Status of everything below

> **All pack rules are HYPOTHESES until they are validated on real statements** (Phase 0, build / held-out split, section 5.4). They were read from open-source parsers and from Docling's code. Nobody has run them on a real statement. The core rules are better grounded (they come from Docling's code), but they are also untested on Indian statements.

Every rule carries a **confidence record** (section 1.5). Nothing may be called "validated" until it passes the held-out set.

### 0.2 Decisions already made by you (binding)

| # | Decision | Where it lands |
|---|---|---|
| D1 | The **user enters the PDF password**. Optional save per account in secure storage. Per-issuer password hints are a later nice-to-have. No password research pass. | 1.7 |
| D2 | **No synthetic statements in this phase** (spec only). Instead: requirements for a Phase 2 layout-preserving fake generator (real layout, fake values). | 5.5 |
| D3 | **ICICI card: keep both layouts as variants, marked unresolved.** | 1.6, rule register |
| D4 | **SBI Card `M` suffix: open.** To be resolved from a real statement's legend. Until then a row with `M` makes the statement REVIEW. | 1.6, 3.4 |
| D5 | **Sections.** NEVER import: account summary, reward points tables, EMI schedule / amortization tables, offers / ads / messages. ALWAYS import: EMI installment lines, interest / fees / GST charges, payments (as credits), add-on card spends (tagged by card member), international transactions (INR amount). | 1.4 |
| D6 | **xfina**: medium confidence accepted. No stricter rule. | `research/LICENSES.md` |
| D7 | The "do-not-copy" list becomes explicit **negative rules**. Every detector and matcher has **both a positive and a negative rule**. | 3.5, 3.6 |
| D8 | Use the `ponytail:ponytail` skill for every implementation. | memory rule |

### 0.3 Evidence types used in this document

| Tag | Meaning |
|---|---|
| `code:` | Read in a cloned repo, cited `repo/path:line` |
| `web:` | From a web search or page; **unverified** against a real file |
| `ours:` | Our proposal; no source supports it |
| `spec:` | Defined in an earlier research file in this workspace |

### 0.4 Vocabulary

| Term | Plain meaning |
|---|---|
| Word cell | One piece of text with its position (box) on the page |
| Bounding box (bbox) | The rectangle around a piece of text |
| Line / block / table / cell | Words grouped by position into lines; lines into blocks; blocks that are grids into tables |
| Document model | The standard shape every step reads and writes |
| Pack | A plug-in with the rules for one kind of statement (bank statement, credit card) |
| Variant | One layout of one issuer's statement (for example "HDFC card, 2025 layout") |
| Fingerprint | Text and layout clues that tell which pack and variant a document is |
| Profile | A pack's settings for one variant: column names, date format, section titles |
| Verify | Arithmetic and sanity checks run after extraction |
| Paise | Money stored as whole paise (integers), never decimals |

---

## 1. Core architecture

### 1.1 Three zones

```
  PDF bytes + password (from user)
        |
  [ A. READER ADAPTER ]  native PDF library (not pure Dart)      -> word cells with boxes
        |
  [ B. CORE ]            pure Dart, no money, no issuers        -> lines, blocks, tables, document model
        |
  [ C. PACKS ]           pure Dart, knows money and issuers     -> statement rows + summary
        |
  [ D. VERIFY ]          pure Dart, generic arithmetic          -> VERIFIED / REVIEW / BLOCKED
        |
  App decides: import (only VERIFIED, or REVIEW after the user confirms)
```

| Zone | Knows about | Must not know about | Replaces (Docling) |
|---|---|---|---|
| A Reader adapter | PDF file format, password, pages, characters, rotation | layout, money | PDF backend (`pdf_text_cells.md`) |
| B Core | Geometry: words, lines, blocks, tables, reading order | money, dates-as-money, issuers | layout postprocess, table matching, reading order, assembly (`spec/core/*`) |
| C Packs | Issuers, columns, dates, amounts, sections | PDF internals | none (Docling has no pack idea) |
| D Verify | Totals, balances, sanity limits | PDF, layout | none |

**Why the reader is separate.** The best candidate library (section 5.1) calls native PDFium code through Dart's foreign-function interface, so it is **not pure Dart**. The pure-Dart promise is kept by making the core accept plain word cells: `code: pdfrx_engine/lib/src/native/pdfrx_pdfium.dart:1954-1986` returns text plus one rectangle per character; the adapter turns that into the core's input. Replacing the library later changes only zone A.

### 1.2 Pipeline states (one document, one run)

| State | Meaning | Next states |
|---|---|---|
| `OPENED` | File bytes read | `LOCKED`, `UNLOCKED`, `CORRUPT` |
| `LOCKED` | PDF needs a password | `UNLOCKED`, `WRONG_PASSWORD`, `CANCELLED` |
| `WRONG_PASSWORD` | Provided password failed (retryable) | `LOCKED` |
| `UNLOCKED` | Readable | `READ`, `NO_TEXT_LAYER` |
| `NO_TEXT_LAYER` | Pages have no text (scanned image). **Unsupported in v1** (no OCR, no ML) | terminal |
| `READ` | Word cells with boxes for every page | `LAID_OUT` |
| `LAID_OUT` | Lines, blocks, tables, document model built | `DETECTED`, `UNKNOWN_FORMAT` |
| `UNKNOWN_FORMAT` | No pack matched | terminal |
| `DETECTED` | One pack + variant chosen (1.5.3) | `EXTRACTED` |
| `EXTRACTED` | Statement rows and summary produced | `VERIFIED`, `REVIEW`, `BLOCKED` |
| `VERIFIED` / `REVIEW` / `BLOCKED` | Verify outcome (section 3) | `IMPORTED` (by the user), terminal |

Rules: no backwards moves except `WRONG_PASSWORD -> LOCKED`. `CORRUPT`, `NO_TEXT_LAYER`, `UNKNOWN_FORMAT`, `BLOCKED` are terminal. Re-running the same bytes gives the same final state (section 4, determinism).

### 1.3 Standard document model (what zone B outputs)

All coordinates: **points (1/72 inch), origin top-left, y grows downward, page rotation already applied.** (One origin everywhere; `spec: spec/core/document_model.md`. The reader library reports PDF coordinates with origin bottom-left, `code: pdfrx_engine/lib/src/pdf_rect.dart:4-9`; the adapter converts.)

| Item | Fields |
|---|---|
| Document | page list, source file hash, page count |
| Page | number (1-based), width, height, rotation, word cells, lines, blocks |
| WordCell | text, bbox, page number, index in reading order |
| Line | word cells, bbox, text (words joined by one space) |
| Block | label (`text`, `section_header`, `table`, `picture`, `page_header`, `page_footer`), lines, bbox, confidence (rule-made = 1.0) |
| Table | rows x columns of cells, header row index, bbox, how it was found (`ruled`, `header_anchored`, `whitespace`) |
| Cell | row, column, text, bbox, word cells |

Every item that later becomes a transaction keeps a **provenance link** (page + bbox + line ids) so the app can show "this row came from here". No other metadata is required in v1.

### 1.4 Statement model (what zone C outputs) and the section policy

| Item | Fields |
|---|---|
| Statement | kind (`bank` / `card`), issuer id, variant id, period start / end, account label (**masked, last 4 only**), currency (`INR`), rows, summary components, source hash, ids of rules used |
| Row | date, description (raw text, unchanged), amount in paise (positive), direction (`debit` / `credit`), running balance in paise (bank only, optional), card member (card only, optional), flags (list), provenance link |

Money is **never** a floating-point number (`code:` stmt-forge parses to `float`, `stmt-forge/src/stmtforge/parsers/base_parser.py:58`; xfina uses exact decimals, `xfina/src/bank_accounts/sbi.rs:12`).

**Section policy (decision D5).**

| Content | Policy | Positive rule (how to recognise it) | Negative rule (what must NOT be mistaken for it) | Confidence |
|---|---|---|---|---|
| Account summary box (opening, totals, limits, due dates) | NEVER import as rows. Read it as **summary components** for verify | Lines matching the pack's summary labels, outside the transaction table | A transaction row whose description contains words like "payment" or "total" | Low |
| Reward points tables | NEVER import | Section titled with the pack's reward title (HDFC export: `Reward Points Summary`, `code: xfina/src/credit_cards/hdfc.rs:111-135`) | A transaction row with a reward-points column (points stay out of the description) | Low |
| EMI schedule / amortization tables | NEVER import | Table outside the transaction table whose header has schedule words (tenure, instalment number, principal, interest, outstanding) | An **EMI installment line** inside the transaction table (see below) | Low (`ours:`, no source describes it) |
| Offers, ads, messages | NEVER import | Lines under the pack's noise list (`code: stmt-forge/src/stmtforge/parsers/idfc_first_parser.py:18-25` lists promo prefixes) or outside any table | A transaction row with merchant text that looks promotional | Low |
| EMI installment lines | ALWAYS import | A row **inside the transaction table** with a date and an amount whose description has the EMI tag (IDFC First tags with `Convert`, `code: idfc_first_parser.py:3-6`) | A schedule line (above) | Low |
| Interest, fees, GST charges | ALWAYS import (flag `charge`) | Transaction-table rows whose description matches the pack's charge words | none; they are normal rows | Low |
| Payments | ALWAYS import, direction `credit` | Credit marker (`Cr`, `CR`, `C`, or `+ C` per variant) or the pack's credit column | A purchase of a merchant named "PAYMENT ..." | Medium |
| Add-on card spends | ALWAYS import, tagged with **card member** | Card-member name column or sub-heading (HDFC export has a per-row owner, `xfina/src/credit_cards/hdfc.rs:230-233`) | Treating an add-on spend as a separate statement | Low |
| International transactions | ALWAYS import, amount = **INR amount** | Section or rows after an "International Transactions" title; INR amount column | Stopping at that title (negative rule N2); using the foreign-currency amount | Low |

If a row cannot be classified into either list, it is **imported but flagged**, never silently dropped (section 3.4, rule S-DROP).

### 1.5 Pack interface and the rule record

#### 1.5.1 What a pack must provide

| # | Part | Contents |
|---|---|---|
| 1 | Identity | pack id, issuer id, kind, list of variants |
| 2 | **Fingerprint** (per variant) | Positive anchors (text + where on the page + minimum hits), **negative anchors** (text that must NOT be present), result strength (`strong` / `weak`) |
| 3 | **Profile** (per variant) | Table header texts, date patterns, amount patterns, credit / debit marker meaning, section start / stop titles, noise list, continuation direction (`after` or `before` the date line) |
| 4 | **Extraction rules** | Row-start rule, continuation rule, column assignment, direction rule, card-member rule, international rule, the section policy mapping (1.4) |
| 5 | **Summary map** | Which printed labels become which components (opening, payments, purchases, finance charges, total due, ...) |
| 6 | **Verify checks** | Check ids with formulas (section 3.2), severity |
| 7 | Password hints | Optional, later (D1) |
| 8 | Test vectors | For every rule: one positive and one negative sample reference (produced later by the fake generator, section 5.5) |

The core never imports a pack. A pack receives the document model and returns a statement.

#### 1.5.2 Rule record (the confidence field)

Every rule in every pack is one record. No rule exists without all of these fields.

| Field | Meaning |
|---|---|
| `id` | Stable id, e.g. `K-HDFC-03` |
| `kind` | `detector`, `matcher`, `parser`, `verify`, `policy` |
| `statement` | One sentence, plain language |
| `positive_rule` | When it must fire (detectors / matchers only) |
| `negative_rule` | When it must NOT fire (detectors / matchers only) |
| `evidence` | List of `code:` / `web:` / `ours:` entries |
| `evidence_level` | `High` / `Medium` / `Low`, using the Stage 2 scale |
| `validation` | `hypothesis` (default) -> `build-validated` -> `held-out-validated` |
| `variant` | Which variant it belongs to, or `all` |
| `status` | `active`, `unresolved`, `open-question` |

**Rule of promotion:** a rule moves from `hypothesis` to `build-validated` only when it works on the build set, and to `held-out-validated` only when it works on the held-out set **without having been edited after seeing it**. Seeded records for the current rules are in `research/spec/packs/rule_register.md`.

#### 1.5.3 Detection and variant choice (decision table)

| Strong hits (packs) | Variants of that pack matching | Negative anchor fired | Outcome |
|---|---|---|---|
| exactly 1 | exactly 1 | no | `DETECTED(pack, variant)` |
| exactly 1 | 2 or more | no | Extract with **each** matching variant; pick the one that reaches `VERIFIED`. If none or more than one verifies -> `REVIEW` ("layout ambiguous") |
| exactly 1 | any | yes | `REVIEW` ("conflicting signals") |
| 2 or more | any | any | `REVIEW` ("two issuers match") |
| 0 | any | any | `UNKNOWN_FORMAT` (weak hits are only shown as a hint) |

**Variant choice is never by row count.** CardQL's registry keeps "the result with the most transactions" (`CardQL/src/cardql/parsers/registry.py:4-5`); that rewards over-matching. Negative rule N4.

### 1.6 Variants and open items (from your answers)

| Item | Status | Handling |
|---|---|---|
| ICICI card, variant **A** (serial-number layout: `Date SerNo ... Amount`, `CR`) | **unresolved** (D3) | Evidence: `CardQL/src/cardql/parsers/banks/icici_v1.py:4-7`, `:58`, `:101`; matches xfina's CSV columns, `xfina/src/credit_cards/icici.rs:589-592` |
| ICICI card, variant **B** (two dates: transaction + posting) | **unresolved** (D3) | Evidence: `stmt-forge/src/stmtforge/parsers/icici_parser.py:18-33` |
| SBI Card `M` suffix | **open** (D4) | `code: CardQL/src/cardql/parsers/banks/sbi_v1.py:68-70` treats `M` as a spend. We do NOT: a row ending in `M` sets flag `unknown_marker` and the statement ends in `REVIEW` until the legend is read from a real statement |
| Bank statement packs other than SBI | Low | Excel-export facts only; PDF layouts unconfirmed (`spec/packs/bank_statement.md` section 0) |

### 1.7 Password flow (decision D1)

| Step | Behaviour |
|---|---|
| 1 | Try an empty password first (`code:` the library's default, `pdfrx_engine/lib/src/pdfrx_entry_functions.dart:70`) |
| 2 | If locked: engine calls the app's **password provider** (a callback). The library calls it repeatedly until it returns nothing or a valid password (`pdfrx_engine/lib/src/pdf_document.dart:360-366`) |
| 3 | The **app** shows a password field. The user types the password. The engine does not store, log, or guess it |
| 4 | Wrong password -> state `WRONG_PASSWORD` -> prompt again; the user may cancel (`CANCELLED`) |
| 5 | Optional "remember for this account": stored by the **app** in platform secure storage, keyed by issuer + masked account label. Default **off** (`ours:`) |
| 6 | Per-issuer hints (for example "usually your DOB") are a later nice-to-have; not specified here |

Positive rule: a locked file always reaches the user prompt. Negative rule: the password never appears in a log, an error message, the document model, or a crash report.

---

## 2. Mapping table: Docling concept -> our deterministic rule -> rationale

| Docling concept | Our rule | Rationale |
|---|---|---|
| PDF backend: text cells with boxes (`spec/core/pdf_text_cells.md`) | Zone A returns **characters with boxes**; core groups them. Default Docling backend is docling-parse (`docling/docling/document_converter.py:303`), which also works from characters | Per-character boxes are what the best Dart library exposes (`pdfrx_pdfium.dart:1969`) |
| Char -> word -> line merge, gap rule capped at 0.35 (`spec/core/word_line_merge.md`) | Same rule on the Dart side: word breaks at an explicit space, an incompatible baseline, or a normalised gap above the cap | Deterministic, geometry only |
| pypdfium2 rect merge (rows within 0.5 x height, gap <= 1.0 x height) | **Fallback only**, if the library gives words not characters | Weaker heuristic |
| Layout model (ML) | Rules LR1-LR7 (`spec/core/layout_postprocessing.md`) | Digital PDFs have exact words and ruling lines |
| Layout overlap resolution (IoU / containment 0.8, label rules, `layout_postprocessor.py:84-107`, `:551-606`) | Copy unchanged, with "TABLE beats TEXT" | Pure geometry; ports directly |
| Cell -> box assignment (>= 0.2 overlap, `layout_postprocessor.py:648-690`) | Copy unchanged | Same |
| Table structure model (ML) | Rules TR1-TR8 (`spec/core/table_structure.md`) | Statements are often ruled-less; header-anchored columns |
| Table text matching (> 30% of word inside cell, `table_structure_model_v2.py:224`) | Copy unchanged; straddling words go to the column holding their centre | Pure geometry |
| Reading order (rule-based already, `reading_order_rb.py:464-529`) | Copy; headers first, then body, then footers | No ML in it |
| Page assembly (strip, join lines, `page_assemble_model.py:183-215`) | Copy; the pack decides how wrapped lines join (before / after) | Wrapping direction differs per issuer (IDFC First: before) |
| Document model (`docling_core`) | Smaller model (1.3) | Statements need few types |
| Confidence scores from the layout model | Replaced by rule priority; rule-made boxes get 1.0 | No model, so no probability |
| (none) Packs, fingerprints, verify | New | Docling is domain-free |

---

## 3. Verify layer

**Governing rule: never import silently wrong data.** Unverifiable is not the same as verified.

### 3.1 Outcomes and the import gate

| Outcome | Meaning | Gate |
|---|---|---|
| `VERIFIED` | All **required** checks for the variant ran and passed; no REVIEW trigger fired | App may import |
| `REVIEW` | Something could not be proven (a check could not run, a trigger fired, a rule is unresolved) | App shows the difference; the user must confirm; the confirmation is recorded with the statement |
| `BLOCKED` | A check ran and failed beyond tolerance, or the structure is wrong | Cannot import; user may retry with another password or report the file |

A check that cannot run because its input is missing is **`not_run`**, and `not_run` for a required check forces `REVIEW`. It never counts as passed.

### 3.2 Math checks

All amounts in integer paise. Default tolerance is **0** (exact) for every check until Phase 0 shows a need. The source repos used `< 1.0` on summary totals (`xfina/src/models/validation.rs:281-283`); we record that value but do not adopt it without data (open question Q4).

| ID | Applies to | Formula | Severity if it fails |
|---|---|---|---|
| V-ROW | bank | For each row: previous balance +/- amount = printed balance. On a miss: report the row, resync to the printed balance, continue (`xfina/src/models/validation.rs:338-371`) | BLOCKED if more than 0 rows fail |
| V-OPEN | bank | Declared opening balance = (first row balance -/+ first row amount). Runs only if the opening balance is **printed**; if derived from the row it is `not_run` (negative rule N8) | BLOCKED on mismatch; REVIEW if `not_run` |
| V-CLOSE | bank | Opening + sum(credits) - sum(debits) = declared closing | BLOCKED |
| V-TOT | bank | Sum(debits) = declared total debits; same for credits | BLOCKED |
| V-CNT | bank | Counted debit / credit rows = declared counts (when printed, SBI) | BLOCKED |
| V-CARD | card | **Total due = opening (previous) balance - payments/credits + purchases/debits + finance charges**, using whatever components the variant prints. Finance charges (interest, fees, GST) **must be included**; the source omitted them (`xfina/src/credit_cards/hdfc.rs:414-436` vs `:213-221`) | BLOCKED |
| V-CARD-SUM | card | Sum of imported credit rows = declared payments/credits; sum of imported debit rows (purchases) = declared purchases; charge rows (flag `charge`) = declared finance charges, **when the variant prints them separately** | BLOCKED; REVIEW if the summary does not split them |
| V-MEMBER | card | When the statement lists per-member totals: per-member sums match | BLOCKED |
| V-PERIOD | all | Every row date lies in [period start - 1 month, period end + 1 day], where the bounds come from the printed period | REVIEW |
| V-REWARD | card | Not used for import (reward tables are NEVER imported) | n/a |

The exact set of components differs by issuer (HDFC prints opening, payments, purchases, finance charges, total, `xfina/src/credit_cards/hdfc.rs:213-221`; Axis prints no purchases/payments split, `xfina/src/credit_cards/axis.rs:23-26`). Each variant therefore declares **which of V-CARD / V-CARD-SUM are `required`**; all are hypotheses (`ours:` formula).

### 3.3 Sanity checks

| ID | Check | Result |
|---|---|---|
| S-DATE | Date parses with the variant's pattern; **never defaults** (negative rule N9) | unparsable -> BLOCKED |
| S-YEAR | Year comes from the printed period; rows with no year (HSBC `13FEB`) use it and handle December -> January wrap | no printed period -> REVIEW |
| S-AMT | Amount parses; sign comes from the marker / column, never from words (N9) | else BLOCKED |
| S-DIR | Direction marker is one the variant knows. Unknown marker (SBI Card `M`) | REVIEW (flag `unknown_marker`) |
| S-EMPTY | Description non-empty | empty -> flag only |
| S-DUP | Identical rows (same date, text, amount) inside one statement | **kept**; info flag only (N1) |
| S-LIMIT | Row amount above the printed credit limit (cards) | REVIEW. **No fixed amount cap** (N5) |
| S-SIGN | For banks: direction agrees with the balance movement | BLOCKED (this is V-ROW) |
| S-MASK | Account label is last 4 digits only | else strip before storing |
| S-DROP | Any line inside the transaction table that matched neither a row nor a noise rule | REVIEW (listed to the user), never dropped silently |
| S-ORDER | Rows keep the statement's printed order; no sorting by text | else BLOCKED |
| S-PAGES | Same table header on every page; running balance continues across the page break | break -> REVIEW |
| S-DUPFILE | Same file hash or same issuer + masked account + period already imported | App warns; not a row-level rule |

### 3.4 "Needs review" triggers (complete list)

`REVIEW` is set when any of: a required check is `not_run`; V-PERIOD or S-LIMIT fires; S-DROP lists lines; S-PAGES breaks; an unresolved rule was used (ICICI variant A / B, SBI `M`); variant choice was ambiguous (1.5.3); fingerprint had a conflicting signal; the statement kind and the fingerprint disagree.

### 3.5 Negative rules from the "do-not-copy" list

Each negative rule has a paired positive rule. These are acceptance tests (section 6).

| ID | Negative rule (never) | Positive rule (always) | Evidence |
|---|---|---|---|
| N1 | Never deduplicate identical rows within one statement | Keep every row; flag identical ones as info | `code: stmt-forge/src/stmtforge/parsers/base_parser.py:165`; `CardQL/src/cardql/parsers/banks/sbi_v1.py:111-120` |
| N2 | Never cut off an international section | Import international rows with the INR amount | `code: CardQL/src/cardql/parsers/banks/hdfc_v1.py:87`; `.../hdfc_v2.py:131` |
| N3 | Never run the card math check without finance charges | V-CARD includes finance charges | `code: xfina/src/credit_cards/hdfc.rs:414-436` |
| N4 | Never pick a variant by row count | Pick by verify outcome (1.5.3) | `code: CardQL/src/cardql/parsers/registry.py:4-5` |
| N5 | Never cap amounts at a fixed value; never "pick the smallest amount" | Parse the column the variant names | `code: CardQL/src/cardql/parsers/banks/hsbc_v1.py:99-102` |
| N6 | Never hard-code a card-number prefix or holder name | Fingerprint on labels, not on personal data | `code: CardQL/src/cardql/parsers/banks/icici_v1.py:99` |
| N7 | Never put reward points in the description | Reward column is parsed and dropped | `code: CardQL/src/cardql/parsers/banks/icici_v1.py:63-66` |
| N8 | Never derive the opening balance from the first row and call the opening check passed | Mark V-OPEN `not_run` when derived | `code: xfina/src/bank_accounts/sbi.rs:418-435` |
| N9 | Never default a bad date to a fake date; never drop the sign with `abs()` and guess from words | Fail the row (BLOCKED); sign from marker or column only | `code: xfina/src/bank_accounts/sbi.rs:378-379`; `stmt-forge/.../base_parser.py:80`, `:85-116` |
| N10 | Never fall back to a hard-coded year | Use the printed period, else REVIEW | `code: stmt-forge/src/stmtforge/parsers/hdfc_parser.py:183-188` |
| N11 | Never hard-code coordinates from one template | Derive column x-positions from the page's own header cells | `code: xfina/src/bank_accounts/sbi.rs:350` |
| N12 | Never use ML, an LLM, or the network as a fallback | Failure ends in REVIEW / BLOCKED with a clear reason | `code: stmt-forge/src/stmtforge/hybrid_pipeline.py`, `llm/client.py` exist as the pattern we reject |
| N13 | Never sort rows by description or date to "clean up" | Keep printed order | `code: CardQL/.../sbi_v1.py:122` |

### 3.6 Detectors and matchers: positive AND negative rule

| ID | Detector / matcher | Positive rule (fires when) | Negative rule (must NOT fire when) |
|---|---|---|---|
| X-FP | Pack fingerprint | At least the variant's minimum positive anchors appear in the expected zone (for example SBI bank: >= 2 header labels **and** the bank name on page 1, `xfina/src/bank_accounts/sbi.rs:671-694`) | A negative anchor is present, or the anchors appear only in a body line (an ad naming another bank) |
| X-VAR | Variant selection | Exactly one variant verifies | Row count is used to choose |
| X-SEC-START | Section start | The variant's section title appears at line start inside a block labelled `section_header` or `text` | The same words inside a transaction description |
| X-SEC-STOP | Section stop | The stop title appears and the next lines are not rows | The title `International Transactions` or similar being used to **end** the import (N2) |
| X-TABLE | Table region | Closed ruled grid, or 3+ consecutive aligned lines with 3+ columns, or the pack's column header | A summary box with two columns (label / value) |
| X-HDRFTR | Repeated header / footer | Same normalised text (digits -> `#`) in the top / bottom 8% on 2+ pages | A transaction row that repeats across statements |
| X-ROW | Row start | Line begins with the variant's date pattern | A line that merely contains a date (a continuation line quoting a date) |
| X-CONT | Continuation line | Line is in the table, has no date at start, and lies on the variant's side (`after` / `before`) of a date line, within one line height of the previous line | A noise line (promo prefix) or a new section title |
| X-DIR | Credit / debit marker | Marker is one the variant lists, in the position the variant lists | A marker-like letter inside the description (`C` in "CAFE") |
| X-SUM | Summary field | Label from the variant's summary map and a parsable amount beside / below it | The same label in a transaction description |
| X-MEMBER | Card member | Member name appears in the member column or sub-heading | A merchant name that looks like a person |
| X-INTL | International row | Row is in the transaction table and the variant says INR amount column | Foreign-currency amount used as the amount |
| X-NOTEXT | No text layer | Page has no word cells but has image content | A page that is simply blank |
| X-LOCK | Password needed | Library reports locked | A corrupt file (reported as `CORRUPT`) |
| X-DUPFILE | Same file seen | Same source hash | Same period with a different file (could be a re-issued statement) |

---

## 4. Constraints checklist

| # | Constraint | How it is met | Checkable by |
|---|---|---|---|
| C1 | **Pure-Dart core** (zones B, C, D) | These packages import no Flutter, no `dart:ui`, no `dart:io`, no native code; only zone A may. Input = word cells | Dependency lint: forbidden imports fail the build |
| C2 | **Zero network** | The engine package declares no HTTP, socket, or analytics dependency. Android manifest of the app does not need `INTERNET` for the engine; no remote fonts, no model downloads | Build check on the dependency tree; manifest check |
| C3 | **Deterministic** | Same bytes + same password -> byte-identical statement JSON. No random, no clock reads (use statement dates, never "now"), stable sorts only, fixed-iteration clustering (like the C++ k-means, `docling-parse/src/parse/page_item_sanitators/cells.h:766`), integer paise, library option `Pdfrx.normalizeHebrewText` stays `false` (default, `pdfrx_engine/lib/src/pdfrx.dart:42`) | Run twice, compare output hash; run on two devices |
| C4 | **Mobile budget** (6 GB RAM Android) | Targets (`ours:`, to be measured in spike S3): 10-page statement to a verified result in <= 5 s on a mid-range phone; peak extra memory <= 200 MB; one page's characters in memory at a time; all PDF work off the UI thread (the library already uses a background worker, `pdfrx_pdfium.dart:61`) | Spike S3 |
| C5 | **No real data in any repo** | Real statements live only in the owner's local Phase 0 folder, outside git. Repos hold only synthetic fixtures; a pre-commit scan rejects 10+ digit numbers, names from a local deny-list, and `UPI/...` style narrations. Logs never contain narration text or amounts | Pre-commit hook; log review |
| C6 | **Licenses** | Reuse only MIT / Apache-2.0 content; keep notices; `research/LICENSES.md` is authoritative. The Syncfusion PDF package is commercial (Community License needs revenue < US$1M **and** fewer than 5 developers, `web:` https://raw.githubusercontent.com/syncfusion/flutter-widgets/master/packages/syncfusion_flutter_pdf/LICENSE) | License review before adding any dependency |
| C7 | **Money exactness** | Integer paise end to end | Property test |
| C8 | **Privacy of results** | Account label masked to last 4; password never persisted by the engine | Unit tests; log review |
| C9 | **No ML, no LLM** | Rules only | Dependency lint |
| C10 | **Offline unlock** | Password handling uses the PDF library only | C2 |

---

## 5. Risks and spikes

### 5.1 FIRST SPIKE (S1): which Dart / Flutter PDF library gives reliable per-word boxes on Android?

**Question.** Which library can give, for each page of a password-protected digital PDF, the text with a bounding box per word (or per character), on Android, offline, with a licence we can use?

| Candidate | What it is | Per-word / char boxes? | Password | Android | Licence | Verdict |
|---|---|---|---|---|---|---|
| **pdfrx** (+ `pdfrx_engine`) | PDFium wrapper, 2.10.0 (published 2026-10-22) | **Yes, per character**: `PdfPageRawText.charRects` filled from `FPDFText_GetCharBox` (`pdfrx_engine/lib/src/native/pdfrx_pdfium.dart:1954-1986`, `pdf_text.dart:10`). Page-level `PdfPageText` also gives fragments | Callback `PdfPasswordProvider`, repeated until valid or null (`pdf_document.dart:360-366`); empty password tried first (`pdfrx_entry_functions.dart:70`) | Yes (pub.dev platform tag `android`); PDFium bundled via Dart native assets (`web:` pub.dev page) | MIT (`pdfrx_engine/LICENSE`) | **Recommended** |
| `pdfium_dart` | Low-level FFI bindings to PDFium (same author) | Possible by calling PDFium directly; no convenience layer | by PDFium call | Yes | MIT (pub tag) | Fallback if pdfrx's wrapper blocks us |
| `syncfusion_flutter_pdf` | Commercial library written in Dart; `PdfTextExtractor` has `extractTextLines` and `findText` (`web:` pub.dev API) | `findText` returns `bounds`; what `extractTextLines` returns (bounds per word) is **not confirmed** | Not confirmed from the pages read | Yes | **Commercial / Community licence** with revenue and developer limits (see C6) | Not recommended now; revisit only if licence fits and pdfrx fails |
| `pdf` (dart_pdf) | Producer: creates PDFs (`web:` pub.dev: "A pdf producer for Dart") | No (does not read) | No | Yes | Apache-2.0 | Not a reader. Useful for the Phase 2 fake generator only |
| `pdfx` | Renders pages to images | No text boxes | Not checked | Yes | MIT | Reject for this purpose |
| `pdf_text` | Reads text content (iOS and Android) | Text only; last update 2021 (`web:` pub.dev) | Not checked | Yes | MIT | Reject (stale, no boxes) |
| `pdf_render` | Rendering API | No text boxes; last update 2024-08 | Not checked | n/a | MIT | Reject |

**Recommendation: pdfrx_engine (PDFium) as zone A.** It is the only candidate with confirmed per-character boxes, a password callback, an MIT licence, and an off-UI-thread worker.

**What the spike must prove (pass / fail).** Using fake PDFs made by hand (no real data):

| # | Test | Pass condition |
|---|---|---|
| S1-1 | Open an encrypted PDF with the right and wrong password | Right opens; wrong -> `PdfPasswordException` (`pdf_exception.dart:16-18`); no crash |
| S1-2 | Character boxes on a simple table | Every character has a non-empty box; boxes of one line share a baseline within 2 points |
| S1-3 | **Coordinate frame** | Box origin bottom-left in points (`pdf_rect.dart:4-9`); verify the crop-box offset the library subtracts (`bbLeft`, `bbBottom`, `pdfrx_pdfium.dart:1969-1980`) |
| S1-4 | **Rotated pages (90 / 180 / 270)** | **Unknown**: the library reads the rotation (`pdfrx_pdfium.dart:1317`), but whether `charRects` are in rotated or unrotated space is not stated. Docling had to convert explicitly (`pypdfium2_backend.py:168-265`). Measure and document |
| S1-5 | Rupee glyph | HDFC's 2025 layout prints the currency symbol as the letter `C` in extracted text (`stmt-forge/src/stmtforge/parsers/hdfc_parser.py:36-43` comment). Confirm what PDFium returns for the symbol, so the pack matches the right character |
| S1-6 | Reading order of characters | Characters come in content order; the core must not depend on it (it sorts by position) |
| S1-7 | Determinism | Two runs on the same file give identical characters and boxes |
| S1-8 | Hebrew normalisation off | Output text identical with `normalizeHebrewText` false (default, `pdfrx_engine/lib/src/pdfrx.dart:42`) |
| S1-9 | Android build | Release build for arm64 works with no network access at runtime; record APK size delta (not measured here) |

If S1-3 or S1-4 fail: fall back to `pdfium_dart` for direct PDFium calls; if PDFium itself is wrong, re-evaluate.

**Spike result (2026-10-23, Android 16 arm64 emulator, fakes only; full report `spikes/pdfrx_spike/SPIKE_REPORT.md`):** S1-1 pass (wrong password -> `PdfPasswordException`, retry works, cancel is clean); S1-2 pass; S1-3 pass (boxes are PDF points, origin bottom-left, **relative to the crop box**); **S1-4 answered: boxes are in the UNROTATED page frame while `page.width/height` are rotated, so the adapter must convert**; S1-7 pass (identical output on repeated runs); S1-8 pass (`normalizeHebrewText` defaults to false); S1-9 pass (release arm64 APK +8.3 MB, no `INTERNET` in the release manifest). **S1-5 (rupee glyph on real statements) and phone performance are still pending a device run.** Condition found: the PDFium binary is downloaded at build time without a checksum, so vendor and pin it.

### 5.2 Other spikes

| ID | Spike | Question | Done when |
|---|---|---|---|
| S2 | Word grouping from characters | Does the docling-parse gap rule (`word_line_merge.md`) keep Indian amounts such as `1,23,456.78` in one word and split table columns cleanly? | 100% of amount tokens in the fake test set stay whole |
| S3 | Android performance | Meets C4 on a 6 GB phone? | Numbers recorded |
| S4 | Table without ruling lines | TR4 / TR5 columns reliable? | Fake set passes |
| S5 | Continuation direction | `after` vs `before` handled by profile alone? | IDFC-style `before` fake passes |
| S6 | Header / footer repetition across pages | LR4 rule works with digits normalised? | Fake set passes |
| S7 | Fingerprint false positives | Do negative anchors stop wrong-pack matches? | Zero wrong-pack `DETECTED` on the fake set |

### 5.3 Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Pack rules are hypotheses; real statements differ | High | High | Phase 0; confidence field; REVIEW default |
| R2 | PDF library returns unrotated or odd boxes | Medium | High | S1-3, S1-4; adapter owns conversion |
| R3 | Issuers change layouts (HDFC changed in 2025: `stmt-forge/.../hdfc_parser.py:36-45`) | High | Medium | Variants; fingerprint negative rules; REVIEW on unknown |
| R4 | Rupee glyph or ligatures change text | Medium | Medium | S1-5; pack matches on character class, not on glyph name |
| R5 | Text order in PDF is scrambled (SBI Card: payments appear above a heading, `sbi_v1.py:94-100`) | Medium | Medium | Match rows by shape page-wide; sort by position in the core |
| R6 | Dedup or sort habits sneak back in | Medium | High | Negative rules N1, N13 as tests |
| R7 | Syncfusion or other licence trap | Low | High | C6 gate |
| R8 | Memory on long statements | Low | Medium | One page at a time (C4) |
| R9 | Scanned PDFs | Medium | Medium | `NO_TEXT_LAYER` with a clear message; OCR is out of scope for v1 |
| R10 | Real data leaks into repo or logs | Low | Very high | C5 hook; log policy |
| R11 | Verify tolerance wrong (too strict or too loose) | Medium | Medium | Start at 0; adjust only from build-set evidence |
| R12 | xfina rules were derived from Excel exports, not PDFs | High | Medium | Low confidence for those; PDF layout tests first |

### 5.4 Phase 0: validation on real statements

Real statements are the **owner's local files only**; they never enter a repo, a ticket, or a chat.

| Step | Detail |
|---|---|
| 1 | Collect real statements per issuer + variant the owner has. Record only the count and the issuer / variant (not the content) |
| 2 | **Split once, randomly by statement:** build set and held-out set (suggested 2:1 per variant; `ours:`). The held-out set is not opened during rule writing |
| 3 | Tune rules only on the build set. A rule becomes `build-validated` when it works there |
| 4 | Run the held-out set **once per rule-set version**, without edits afterwards. Rules that pass become `held-out-validated` |
| 5 | A variant is "ready" when every held-out statement ends `VERIFIED` or `REVIEW` with a correct reason, and **none** ends `VERIFIED` with wrong data. Percentage goals are open question Q6 |
| 6 | Any held-out failure that causes a rule edit moves that statement into the build set; the next release needs a new held-out statement |

### 5.5 Phase 2: layout-preserving fake generator (requirements)

Goal: produce many PDFs that **look like** real statements (same layout) with **fake values**, plus the correct answer for each, so tests need no real data.

| # | Requirement |
|---|---|
| G1 | **Input = a layout template** extracted from a real statement: page size, fonts, text positions, ruling lines, static labels, section titles, header / footer, column positions, rupee glyph handling |
| G2 | **Template extraction keeps structure only.** Every variable string (names, numbers, addresses, narrations, dates, amounts) is dropped at extraction time. The template file is safe to commit |
| G3 | **Leak check:** after generation, scan every output for any character sequence (6+ characters) that also appears in the source statement's variable text; any hit fails the build. The check runs locally where the source lives |
| G4 | **Values from a seeded generator:** same seed, same PDF. Names, merchant strings, references, amounts are invented |
| G5 | **Arithmetic is consistent:** running balances, totals, opening / closing, payments / purchases / finance charges, and per-member totals are computed so V-* checks pass on the good set |
| G6 | **Edge-case switches** (each can be turned on): wrapped descriptions (`after` and `before`), international rows, identical rows on the same day, add-on members, EMI installment lines, EMI schedule table, reward table, promo lines, multi-page tables, repeated headers / footers, rotated page, password-protected output, unknown marker, missing summary, wrong total (to test BLOCKED) |
| G7 | **Ground truth:** for every PDF a JSON file with the expected statement (rows, summary, outcome, flags) |
| G8 | **Positive and negative samples** for every detector in 3.6 |
| G9 | **Variants:** one template per variant, including both ICICI layouts and the HDFC old / 2025 layouts |
| G10 | **Deterministic output** (byte-identical for a seed) and **offline** |
| G11 | The fake generator is itself covered by C5: its templates and outputs may be committed; its inputs may not |
| G12 | Candidate tool: the `pdf` package can produce PDFs (`web:` pub.dev: "A pdf producer for Dart"); whether it can place text at exact positions with the embedded fonts needed is **unchecked** and is the first Phase 2 spike |

---

## 6. Acceptance criteria (Given / When / Then)

Values are invented. "Fake statement" means a statement made by the Phase 2 generator.

### 6.1 Core

| ID | Scenario | Given | When | Then |
|---|---|---|---|---|
| A-C1 | Open unlocked PDF | A fake PDF with no password | The engine reads it | State reaches `READ`; every page has word cells with boxes inside the page |
| A-C2 | Password required | A fake PDF locked with password `Test1234` | The engine opens it with an empty password | State `LOCKED`; the password provider is called once |
| A-C3 | Wrong password | Same file | The user types `wrong` | State `WRONG_PASSWORD`; user is asked again; nothing is logged with the password |
| A-C4 | Right password | Same file | The user types `Test1234` | State `UNLOCKED`, then `READ` |
| A-C5 | Remembered password | A saved password exists for issuer X and masked account `1234` | A new file for the same account is opened | The app supplies it without prompting; if it fails, the user is prompted |
| A-C6 | Scanned PDF | A PDF whose pages are images | The engine reads it | State `NO_TEXT_LAYER`; a plain message; no rows |
| A-C7 | Determinism | One fake PDF, one password | Run twice, on two devices | Output JSON byte-identical |
| A-C8 | Rotation | A fake page rotated 90 degrees | Words are laid out | Lines read left-to-right in the page's display orientation; same statement result as the unrotated copy |
| A-C9 | No network | The device is in airplane mode | A statement is processed | Result identical; no network permission is used by the engine |
| A-C10 | Money exact | A row with amount `1,23,456.78` | It is parsed | Stored as `12345678` paise |
| A-C11 | Unknown document | A fake PDF of a cinema ticket | The engine runs | `UNKNOWN_FORMAT`; no rows |
| A-C12 | Header / footer | A 3-page fake with the same footer on every page | Layout runs | Footer lines are labelled `page_footer` and produce no rows |
| A-C13 | Log hygiene | Any run | Logs are inspected | No narration text, amounts, or password present |

### 6.2 Bank statement pack (all hypotheses)

| ID | Scenario | Given | When | Then |
|---|---|---|---|---|
| A-B1 | Detect SBI bank | A fake SBI-layout statement with 3 of the header labels and the bank name | Detection runs | `DETECTED(bank_statement, sbi)` |
| A-B2 | Do not detect on ad text | A fake HDFC statement whose footer ad says "State Bank of India" | Detection runs | Not detected as SBI (negative anchor / zone rule) |
| A-B3 | Row split | A fake row `05/06/2026 05/06/2026 UPI/1234/SHOP - 450.00 9,550.00` style with debit, credit, balance columns | Extraction runs | One debit of `45000` paise, balance `955000` |
| A-B4 | Wrapped description | Description continues on the next line, x-position taken from the page's own header | Extraction runs | Description is joined in top-to-bottom order; no hard-coded x-range (N11) |
| A-B5 | Running balance | Rows whose balances are consistent | Verify runs | V-ROW pass |
| A-B6 | Wrong balance | One row balance is off by `10.00` | Verify runs | V-ROW fails; outcome `BLOCKED`; the row is named |
| A-B7 | Opening balance printed | Summary row with opening, counts, totals, closing | Verify runs | V-OPEN, V-CLOSE, V-TOT, V-CNT all run and pass -> `VERIFIED` |
| A-B8 | Opening balance missing | Summary row absent | Verify runs | V-OPEN `not_run` -> `REVIEW`, never `VERIFIED` (N8) |
| A-B9 | Identical rows | Two identical rows on the same day | Extraction runs | Both kept (N1) |
| A-B10 | Bad date | A row date `32/13/2026` | Extraction runs | `BLOCKED`; no `1970-01-01` (N9) |
| A-B11 | Repeated page header | Header repeated on 3 pages | Extraction runs | No header text appears in any row |
| A-B12 | Dr/Cr suffix on balance | Balance printed `1,200.00DR` | Parsing runs | Balance is negative |

### 6.3 Credit card pack (all hypotheses)

| ID | Scenario | Given | When | Then |
|---|---|---|---|---|
| A-K1 | Detect by anchors | A fake HDFC 2025-layout statement (`DATE & TIME TRANSACTION DESCRIPTION REWARDS AMOUNT PI` header) | Detection runs | `DETECTED(credit_card, hdfc, 2025)` |
| A-K2 | Two ICICI variants | A fake statement in layout A (serial number) | Detection runs | Variant A verifies, B does not -> `DETECTED(...A)`; the result carries flag `variant_unresolved` and is at most `REVIEW` while D3 is open |
| A-K3 | Both variants verify | A fake statement both layouts accept | Detection runs | `REVIEW` ("layout ambiguous") |
| A-K4 | Payment as credit | Row `... PAYMENT RECEIVED ... 5,000.00 Cr` | Extraction runs | Direction `credit`, amount `500000` |
| A-K5 | HDFC credit marker | Row `+ C 16,099.00` | Extraction runs | Direction `credit` |
| A-K6 | Rupee glyph | Amount preceded by the symbol glyph | Extraction runs | Amount parsed; symbol not left in description |
| A-K7 | International included | A statement with a section "International Transactions" holding 2 rows | Extraction runs | Both rows imported with INR amounts (N2) |
| A-K8 | Domestic + international math | Declared purchases include both sections | Verify runs | V-CARD-SUM passes only when international rows are included |
| A-K9 | Finance charges in math | Opening `10,000.00`, payments `4,000.00`, purchases `2,000.00`, finance charges `300.00`, total due `8,300.00` | Verify runs | V-CARD passes. The same statement with total `8,000.00` -> `BLOCKED` (N3) |
| A-K10 | Fees and GST rows | Rows `LATE FEE` and `IGST` | Extraction runs | Imported, flagged `charge` |
| A-K11 | EMI installment line | A row in the transaction table tagged as an EMI installment | Extraction runs | Imported |
| A-K12 | EMI schedule table | A separate table with tenure / principal / interest columns | Extraction runs | Not imported; no rows from it |
| A-K13 | Reward table | A reward summary table | Extraction runs | Not imported; reward points are not in any description (N7) |
| A-K14 | Offers | Promo lines after the table | Extraction runs | Not imported; the table ends; nothing inside the table is dropped silently |
| A-K15 | Add-on spends | Two members, 3 rows each | Extraction runs | 6 rows, each tagged with the card member; per-member sums match when declared |
| A-K16 | Identical rows | Two identical purchase rows the same day | Extraction runs | Both kept (N1) |
| A-K17 | SBI Card `M` | A row ending in `M` | Extraction runs | Flag `unknown_marker`; outcome `REVIEW` (D4) |
| A-K18 | Order | SBI Card payment credits appear above the transactions heading | Extraction runs | All rows found; printed order kept (N13) |
| A-K19 | Summary missing | No printed summary | Verify runs | Required checks `not_run` -> `REVIEW` |
| A-K20 | Year missing | HSBC-style `13FEB` rows and a printed period `15 Jan 2026 - 14 Feb 2026` | Extraction runs | Year taken from the period; December -> January wrap handled; no hard-coded year (N10) |
| A-K21 | Unknown amount scale | A purchase of `6,00,000.00` | Extraction runs | Imported (no fixed cap, N5); `S-LIMIT` fires only if above the printed credit limit |

### 6.4 Non-functional requirements

| Area | Requirement |
|---|---|
| Performance | C4 targets; measured in S3 |
| Security | C5, C8; password never persisted by the engine |
| Reliability | Deterministic output; every failure ends in a named state, never a crash |
| Portability | Core packages compile and test on plain Dart (no Flutter) |

### 6.5 Implementation checklist (for the build phase)

- [ ] Reader adapter with a fixed interface (word cells in; no library types leak into the core)
- [ ] Core: lines, blocks, tables, reading order, document model
- [ ] Pack interface, rule record, rule register loader
- [ ] Packs: SBI bank; HDFC, ICICI (A, B), SBI Card, Axis cards first
- [ ] Verify runner with the V-/S- checks
- [ ] Tests: one positive and one negative per detector (3.6), one test per negative rule (3.5)
- [ ] Lint rules for C1, C2, C9; pre-commit scan for C5
- [ ] Logging policy (A-C13)

### 6.6 Done means

Code reviewed; every rule record has evidence, confidence and validation fields; unit tests for each rule pass on the synthetic set; Phase 0 held-out result recorded per variant; no real data in the repo; this spec and the rule register updated.

---

## 7. Gap analysis applied to the research (what is still missing)

Using the gap categories (entry / exit, states, transitions, exceptional paths, terminology, actors, timing) on the Stage 1 and 2 specs:

| # | Gap | Category | Severity | Resolution in this spec |
|---|---|---|---|---|
| 1 | Pack facts came from Excel exports and regexes, not PDFs | Entry conditions | Critical | Confidence field; Phase 0; Low default |
| 2 | No spec of states for password / unreadable files | State definitions | Critical | 1.2, 1.7 |
| 3 | Credit / debit logic by words, `abs()` | Exceptional paths | Critical | N9; marker-only rule |
| 4 | Duplicate handling | Concurrent / idempotent | Critical | N1, S-DUP, S-DUPFILE |
| 5 | Section skip lists absent | Exit conditions | Important | 1.4 policy (D5) |
| 6 | Unknown markers (`M`) | Exceptional paths | Important | S-DIR -> REVIEW |
| 7 | Rotation behaviour of the reader unknown | Exceptional paths | Important | S1-4 |
| 8 | Tolerance values taken from sources without data | Timing / limits | Important | Default 0, Q4 |
| 9 | Terminology varied (statement / document / account / card member) | Terminology | Nice | 0.4 and the model in 1.3-1.4 |
| 10 | Who decides on REVIEW | Actor responsibilities | Important | App shows and records the user's confirmation (3.1) |
| 11 | Performance budget missing | Timing | Important | C4, S3 |
| 12 | No test data policy | Entry conditions | Critical | C5, 5.4, 5.5 |

---

## 8. Open questions for you

| # | Question | Why it matters | My default if you do not answer |
|---|---|---|---|
| Q1 | May the Phase 0 held-out split be 2:1 per variant, and who owns the real statements (you only)? | Defines validation | 2:1, you only |
| Q2 | Which issuers / variants do you actually hold real statements for? | Decides pack order | SBI bank, HDFC / ICICI / SBI Card / Axis cards |
| Q3 | Should "remember password" default to off? | Privacy | Off |
| Q4 | Keep verify tolerance at exactly 0 until data says otherwise? | Strictness | Yes |
| Q5 | What should the app do on `REVIEW`: show a diff and let the user confirm per statement, or per row? | UX scope | Per statement, with the list of flagged rows |
| Q6 | What pass rate means "ready" on the held-out set? | Release gate | 100% never-wrong; pass-rate target set after the first run |
| Q7 | Is `NO_TEXT_LAYER` (scanned) acceptable as unsupported in v1? | Scope | Yes |
| Q8 | Is Android-only fine for v1, or is iOS needed (PDFium supports both)? | Spike scope | Android only |
| Q9 | Who writes the first Phase 2 fake-generator spike (check whether the `pdf` package can place text at exact positions)? | Unblocks tests | Next phase |
| Q10 | The rupee glyph and EMI wording for each issuer must come from real statements. OK to collect them in Phase 0 notes (structure only, no values)? | Rule completion | Yes |
