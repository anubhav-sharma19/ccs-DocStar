# Pack: bank_statement (Indian savings / current account statements)

Status: Stage 2 draft. Every rule below is read from code in `research/sources/` (cited as `repo/path:line`) or marked as web evidence. **No real statement was opened.** All confidence levels are "from code only" and must be confirmed on synthetic PDFs.

## 0. Read this first: what the sources can and cannot tell us

| Finding | Evidence | Consequence |
|---|---|---|
| Only **one** bank-account parser reads a **PDF**: SBI (xfina). | `xfina/src/detect/registry.rs:216` (`ba-sbi`, ext `pdf`, locked), vs HDFC/ICICI/BoB/Axis bank parsers = `xls` (`registry.rs:189`, `:202`, `:228`, `:241`) | For HDFC, ICICI, Axis, BoB we know the **content and column order of the bank's Excel export**, not the PDF. Treat them as hints. |
| stmt-forge and CardQL parse **credit cards only**. | `stmt-forge/.../parsers/base_parser.py:130` ("Parse a credit card statement PDF"); `CardQL/.../parsers/schema.py` has `card` field | No extra PDF bank-statement source exists in our clones. |
| xfina is a young repo; confidence capped at medium. | `research/LICENSES.md` (xfina re-check) | Rules from xfina are "Medium at most". |

**Confidence scale used in this file**

| Level | Meaning |
|---|---|
| High | 2 or more independent sources agree on the PDF layout **and** the summary fields were seen. No issuer reaches this yet. |
| Medium | One full PDF parser with validation, **or** 2 independent sources agree on the line layout. |
| Low | Single source, a generic pattern, an Excel export only, or tied to one template. |

## 1. Rules shared by all banks

| Topic | Rule | Source (license) |
|---|---|---|
| Thousands separators | Remove every comma before parsing, so lakh grouping `1,23,456.78` becomes `123456.78`. Sources do this with a blind comma strip; **no source tests lakh grouping explicitly** (inference). | `xfina/src/bank_accounts/sbi.rs:110-116` (Apache-2.0); `stmt-forge/.../base_parser.py:69` (MIT) |
| Empty amount cell | A dash `-` means "no amount" in the SBI table. | `sbi.rs:310-312`, `:340` |
| Credit / debit | Banks with two amount columns (Withdrawal / Deposit, Debit / Credit): the non-zero column decides the type. | `xfina/src/bank_accounts/hdfc.rs:171-185`, `axis.rs:186-188`, `icici.rs:126-127` |
| Balance sign | `DR` suffix on a balance means negative; `CR` suffix means positive. | `sbi.rs:117-129` |
| Keep the sign | Do **not** use `abs()` and then guess the type from words. stmt-forge's `parse_amount` returns `abs(...)` (`base_parser.py:80`) and then guesses debit/credit from keywords (`base_parser.py:85-116`). Fragile: do not copy. | stmt-forge (MIT), as a negative example |
| Privacy | The source repos forbid real data in public places. We follow the same rule. | `xfina/AGENTS.md:5` |

## 2. Per-bank rules

### 2.1 State Bank of India (PDF) — confidence **Medium**

Source: `xfina/src/bank_accounts/sbi.rs` (Apache-2.0, keep notice; repo verdict "medium, usable per license").

| Item | Rule | Evidence |
|---|---|---|
| **Fingerprint** | On page 1 text (uppercased): at least 2 of `ACCOUNT NUMBER`, `IFSC CODE`, `MICR CODE`, `CIF NUMBER`, `BRANCH NAME` **and** `STATE BANK OF INDIA` = strong claim; 3 or more labels without the bank name = weak claim | `sbi.rs:671-694` |
| Parse gate | Parser refuses unless at least 2 of 6 header labels (`Account Number`, `Account Name`, `IFSC Code`, `MICR Code`, `Branch Name`, `CIF Number`) appear in the first 2 pages | `sbi.rs:36-40`, `:653-668` |
| **Transaction columns (order)** | transaction date, value date, description, debit, credit, balance (roles read from variable names, header text not confirmed). The last three whitespace tokens of the row are debit, credit, balance | `sbi.rs:90` (two dates at line start), `:332-337` |
| **Date formats** | Rows: `dd/mm/yyyy`. Header dates `Date of Statement : dd-mm-yyyy`, `Statement From : dd-mm-yyyy to dd-mm-yyyy`. Account open date `dd/mm/yyyy` | `sbi.rs:90-94`, `:259`, `:378` |
| **Amount format** | Commas removed; balance and summary amounts may carry `CR` / `DR` suffix | `sbi.rs:95-98`, `:110-129` |
| **Line building** | Group characters into lines with a y tolerance of 2.0 points, a space is inserted when the gap is more than 0.25 of the character height | `sbi.rs:137`; `xfina/src/bank_accounts/layout.rs:9-80` (`:41` space rule) |
| **Row blocks** | Start a new block when the vertical gap between lines is more than 11.5 points | `sbi.rs:144-157` |
| **Multi-line description** | Extra lines in a row block whose left edge is between x=120 and x=150 are description continuation; joined in top-to-bottom order with a space | `sbi.rs:350-365`. **Template-specific numbers**: re-derive from the page's own column header positions, do not hard-code. |
| **Table start** | A short line containing `Balance` (fewer than 10 characters) is the table header | `sbi.rs:285-288` |
| **Table stop / skip** | Stop on `Statement Summary` or `Closing Balance`. Skip lines with `Account Number`, `Page no.`. Skip anything outside the table | `sbi.rs:223-232`, `:289-295`, `:298-300` |
| **Repeated header/footer** | Handled by the same skip rules above (every page repeats the header block) | `sbi.rs:136-300` |
| **Sections to skip** | Account header block (name, address, branch, IFSC, MICR, CIF, nominee), summary block, page numbers | `sbi.rs:236-264`, `:289-295` |
| **Summary fields (math check)** | One summary row: opening ("brought forward") balance, number of debits, number of credits, total debits, total credits, closing balance | `sbi.rs:95-98`, `:196-221` |
| **Math checks in source** | Row-level running balance; opening balance match; closing = opening + credits − debits; debit total; credit total; debit count; credit count (all summary checks use tolerance below 1.0, counts exact) | `sbi.rs:529-640`; `xfina/src/models/validation.rs:281-283` |
| **Statement period** | `Statement From : ... to ...` | `sbi.rs:92-94` |
| **Password** | The format is **not in any source**. xfina only marks the format as password-protected | `registry.rs:216-227` (`locked: true`) |
| **License** | Apache-2.0 | `xfina/LICENSE` |

**Do not copy**

- Opening balance is *derived* from the first row when the summary row is missing (`sbi.rs:418-435`). That makes the opening-balance check circular. Our verify layer should treat a derived opening balance as "unverified".
- Unmatched dates become `1970-01-01` silently (`sbi.rs:378-379`). Our rule: unparseable date = "needs review".
- Hard-coded x-range (120–150) and y-gap (11.5) come from one template.

### 2.2 HDFC Bank — confidence **Low** (Excel export, not PDF)

Source: `xfina/src/bank_accounts/hdfc.rs` (Apache-2.0).

| Item | Rule | Evidence |
|---|---|---|
| Fingerprint (export) | `HDFC BANK LTD` or `CHQ./REF.NO.` in the first 40 rows = strong; `A/C OPEN DATE` or `ACCOUNT BRANCH :` = weak | `hdfc.rs:469-473` |
| Columns (order) | date, narration, reference, value date, withdrawal, deposit, balance (7 columns, by index; only `Date` and `Narration` are quoted header texts, the rest are roles) | `hdfc.rs:157`, `:171-185` |
| Date format | `dd/mm/yy` first, then `dd/mm/yyyy` | `hdfc.rs:445-453` |
| Statement period | `Statement From : dd/mm/yyyy To : dd/mm/yyyy` | `hdfc.rs:59` |
| Repeated page markers | A row containing `**Continue**` or `HDFC BANK Ltd.` pauses transactions until the `Date` header row appears again; asterisk-only rows skipped | `hdfc.rs:111-120`, `:157` |
| Skip | `Opening Balance` row; `STATEMENT SUMMARY` block starts the summary | `hdfc.rs:122-130`, `:163` |
| Summary fields | Opening balance, total debits, total credits, closing balance (one row under `STATEMENT SUMMARY`) | `hdfc.rs:125-138` |
| Math checks | `total_debits_match`, `total_credits_match`, `opening_balance_match`, `closing_balance_match` | `hdfc.rs:308-380` |
| Password | Web: HDFC's support pages say the account statement PDF password is the numeric Customer ID (not read from a real file) | https://www.hdfc.bank.in/blogs/digital-banking-1/download-account-statement-via-netbanking (web search summary; **unverified**) |

### 2.3 ICICI Bank — confidence **Low** (Excel export)

Source: `xfina/src/bank_accounts/icici.rs` (Apache-2.0).

| Item | Rule | Evidence |
|---|---|---|
| Fingerprint (export) | `DETAILED STATEMENT` or `LEGENDS USED IN ACCOUNT STATEMENT` = strong; `DEPOSIT AMOUNT` + `WITHDRAWAL AMOUNT` + `S NO.` = weak | `icici.rs:316-329` |
| Columns (order) | S No. (quoted), value date, transaction date, reference, description, withdrawal, deposit, balance (by index; all but `S No.` are roles) | `icici.rs:90`, `:118-128` |
| Multi-line description | A row with an empty S No. continues the previous narration | `icici.rs:100-109` |
| Skip | Stop at `Legends Used in Account Statement` | `icici.rs:96` |
| Password | Web: ICICI help pages describe an 8-character scheme for bank accounts; **details not read** | https://help.icicibank.com/Phone-Bank-FAQ/909216713/What-is-the-password-to-open-my-e-statement.htm (**unverified**) |

### 2.4 Axis Bank — confidence **Low** (Excel export)

Source: `xfina/src/bank_accounts/axis.rs` (Apache-2.0).

| Item | Rule | Evidence |
|---|---|---|
| Fingerprint (export) | `CUSTOMER ID :-`, `IFSC CODE :-` or `JOINT HOLDER :-` (note the ` :- ` separator) = strong; `SRL NO` = weak | `axis.rs:394-417` |
| Columns (order) | SRL NO (quoted), date, reference, description, debit, credit, balance, branch (by index; all but `SRL NO` are roles) | `axis.rs:144`, `:183-188`, `:198` |
| Header dates | `dd-mm-yyyy` | `axis.rs:141-142` |
| Password | Web: not stated by Axis pages found | https://www.axisbank.com/bank-smart/e-statements/downloads (**no format given**) |

### 2.5 Bank of Baroda — confidence **Low** (Excel export, single source)

Source: `xfina/src/bank_accounts/bob.rs` (Apache-2.0). Table heading `TRAN DATE` (`bob.rs:168`); fingerprint `TRAN DATE` plus `HOLDER NAME` or `ACCOUNT NO` (`bob.rs:454`); dates `dd/mm/yyyy` (`bob.rs:188`). Columns read by fixed index (`bob.rs:191-217`, template-specific).

### Passwords for bank PDFs

Same situation as cards: no per-issuer rule in any source. The generic candidate list (empty, DOB variants, PAN, name, combinations) is documented in `credit_card.md` (section 1, "Password candidates"). xfina only flags SBI's bank PDF as password-protected (`xfina/src/detect/registry.rs:216-227`).

## 3. Verify layer inputs from this pack

| Check | Formula | Tolerance in source |
|---|---|---|
| Row balance | previous balance ± amount = printed balance; on a miss, resync to the printed balance and continue | **exact** (`validation.rs:338-371`) |
| Closing balance | opening + credits − debits = declared closing | below 1.0 (`validation.rs:281-283`) |
| Debit / credit totals | sum of rows = declared totals | below 1.0 |
| Row counts | counted rows = declared counts (SBI) | exact |

Proposal for Stage 3 (ours, not from sources): keep row-balance exact to the paisa, and use a tolerance on summary totals only for printed rounding.

## 4. Open questions (updated after your answers)

1. ~~Password formats~~ **Answered (D1):** user enters the password; optional save; hints later.
2. ~~Synthetic SBI PDFs~~ **Answered (D2):** none now; the Phase 2 fake generator spec is in `ENGINE_SPEC.md` section 5.5.
3. ~~How to show "needs review"~~ **Specified:** `ENGINE_SPEC.md` sections 3.1 and 3.4 (derived opening balance = `not_run` = REVIEW).

## 5. License summary for this pack

xfina: Apache-2.0 (keep notice). stmt-forge: MIT. CardQL: Apache-2.0. See `research/LICENSES.md`.

## Coverage matrix: issuer x statement type x confidence

Scale: **High** = 2+ independent sources agree on the PDF layout and summary fields were seen. **Medium** = one full PDF parser with validation, or 2 independent sources agree on the line layout. **Low** = single source, generic pattern, export-only, or sources disagree. `n/a` = no source found in our clones. **No issuer reaches High.**

| Issuer | Bank statement | Credit card | Why (short) |
|---|---|---|---|
| SBI (State Bank of India / SBI Card) | **Medium** | **Medium** | Bank: xfina PDF parser with 7 checks (template-bound numbers). Card: stmt-forge and CardQL agree on `DD Mon YY ... amount D/C`; `M` suffix unknown |
| HDFC Bank | Low | **Medium** | Bank: Excel export only. Card: 3 sources, 3 layouts (old, 2025, export); summary fields from export only |
| ICICI Bank | Low | Low | Bank: Excel export only. Card: stmt-forge (two dates) and CardQL (serial number) disagree |
| Axis Bank | Low | **Medium** | Bank: Excel export only. Card: CardQL and xfina agree on `Dr/Cr` and `End of Statement` |
| Bank of Baroda | Low | n/a | Excel export, one source, fixed column indexes |
| IndusInd Bank | n/a | Low | CardQL only |
| HSBC | n/a | Low | CardQL only; its amount rule is unsafe |
| Kotak Mahindra | n/a | Low | stmt-forge generic regex only |
| Yes Bank | n/a | Low | stmt-forge generic regex only |
| IDFC First | n/a | Low | stmt-forge only; has multi-line and promo-line rules |
| Federal (Scapia) | n/a | Low | stmt-forge only |
| CSB (Jupiter / Edge) | n/a | Low | stmt-forge summary regexes only |

Totals: bank statements 5 issuers (1 Medium, 4 Low). Credit cards 11 issuers (3 Medium, 8 Low). All confidence is from code only; none was tested on a document.

Across all issuers, **password rules, PDF-content fingerprints, multi-line card descriptions, and EMI/add-on skip lists are mostly missing from the sources** and need synthetic-PDF testing and your input (open questions above).
