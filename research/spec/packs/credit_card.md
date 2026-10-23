# Pack: credit_card (Indian credit card statements)

Status: Stage 2 draft. Every rule is read from code in `research/sources/` (cited as `repo/path:line`) or marked as web evidence. **No real statement was opened.** Confidence is "from code only" until tested on synthetic PDFs.

Confidence scale (same as `bank_statement.md`): **High** = 2+ independent sources agree on the PDF layout and the summary fields were seen (none reaches this); **Medium** = one full PDF parser with validation, or 2 independent sources agree on the line layout; **Low** = single source, generic pattern, export-only, or template-bound.

## 0. How the three sources differ

| Source | What it reads | Fingerprint method | Math check | License |
|---|---|---|---|---|
| stmt-forge | PDF text and tables via pdfplumber (`stmt-forge/.../pdf_processing/extractor.py:7`, `:26`, `:36`), generic regex per issuer | none in the parser; picks the parser from the email domain (`stmt-forge/src/stmtforge/config_template.yaml:70-77`) | none for transactions | MIT |
| CardQL | PDF text (pypdf) line by line | none; picks the parser from the sender rule (`CardQL/src/cardql/parsers/registry.py:1-7`; `CardQL/src/cardql/config.py:116-142`) | none | Apache-2.0 |
| xfina | **Excel / CSV exports** of card statements (HDFC, ICICI, Axis), not PDFs | content markers (`probe()` functions) | yes, summary checks | Apache-2.0 (medium confidence) |

Consequence: there is **no PDF-content fingerprint in any source for credit cards**. Section 2 lists the *text anchors* that the parsers rely on; these are our raw material for fingerprints, not tested fingerprints.

## 1. Rules shared by card issuers

| Topic | Rule | Evidence |
|---|---|---|
| Date formats seen | `DD/MM/YYYY`; `DD/MM/YYYY| HH:MM` (HDFC, 2025 template); `DD Mon YY` (SBI Card, IDFC First); `DD-MM-YYYY` (Scapia); `DDMMM` without year (HSBC, e.g. `13FEB`); period line `15 Aug, 2025` (HDFC) | `stmt-forge/.../hdfc_parser.py:19-45`, `.../sbi_parser.py:18-24`, `.../federal_parser.py:23-30`; `CardQL/.../hsbc_v1.py:22`; `.../hdfc_v2.py:105-112` |
| Year missing | HSBC prints no year per row; take it from the period line. stmt-forge picks "most frequent 20xx year in the text, else 2024" (`hdfc_parser.py:183-188`): **do not copy** (hard-coded fallback). Our rule: derive the year from the statement period and handle December→January wrap (proposal) | `CardQL/.../hsbc_v1.py:33-36` |
| Credit / debit marker | Suffix `Cr`/`Dr` (Axis, IDFC, Kotak, Yes), `CR`/`DR` (IndusInd, ICICI credit only), `C`/`D`/`M` (SBI Card), leading `+ C` before the amount for credits (HDFC 2025 template) | `.../hdfc_parser.py:39-45`; `CardQL/.../hdfc_v2.py:54-56`; `.../sbi_v1.py:68-70` |
| Amount format | Strip `Rs.`, `INR`, `₹`, commas; trailing `-` or parentheses = negative | `stmt-forge/.../base_parser.py:65-77` |
| Lakh grouping | Handled only by blind comma removal; no source tests it (inference) | `base_parser.py:69` |
| Wrapped description | Most card parsers read one line at a time. **IDFC First is the exception**: the description can sit on the line(s) **before** the `DD Mon YY [Convert] AMOUNT DR/CR` line. Our rule (proposal): decide per issuer whether continuation lines come before or after the date line; never assume "after". See `bank_statement.md` §2.1 for the SBI bank precedent (continuation after) | `stmt-forge/.../idfc_first_parser.py:3-6`; other card parsers: single-line regexes |
| Deduplication | stmt-forge and CardQL drop rows that look identical (`base_parser.py:165`; `CardQL/.../sbi_v1.py:111-120`). **Do not copy**: two real purchases of the same amount on the same day would be lost. Use page/row position, never text equality | negative example |
| Privacy | Do not hard-code card prefixes or names. CardQL's ICICI parser skips lines starting with `3747` (`CardQL/.../icici_v1.py:99`): looks like a masked card number from one template; **do not copy** | negative example |

### Password candidates (what the sources really contain)

None of the three repos has a per-issuer password rule. The only password logic is a **generic candidate list** in stmt-forge, tried in order until one opens the file (max 50 attempts, `stmt-forge/src/stmtforge/config_template.yaml:60-66`). The user supplies date of birth, PAN and name; the code builds these candidates (MIT, facts only):

| Order | Candidate | Evidence |
|---|---|---|
| 1 | empty password | `stmt-forge/src/stmtforge/utils/config.py:104-106` |
| 2 | date of birth as `DDMMYYYY`, `DDMMYY`, `DD-MM-YYYY`, `DD/MM/YYYY`, `MMDDYYYY`, `YYYYMMDD`, `YYYY-MM-DD`, `DDMM`, `YYYY` | `config.py:84-101` |
| 3 | PAN, upper and lower case | `config.py:104-152` |
| 4 | name as typed, upper and lower case | `config.py:104-152` |
| 5 | PAN + first 4 characters of the DOB variant; name + first 4 characters of the DOB variant (both cases) | `config.py:104-152` |

CardQL takes the opposite approach: the user types the **exact** password per card in a local file, and placeholders are not supported (`CardQL/docs/CONFIG.md:19`, `:40`).

For our app (offline, on a phone) the candidate approach is the more useful one, but only with an **issuer-aware shortlist**. The shortlist per issuer is not in any source; see the per-issuer rows (web evidence only, unverified).

## 2. Per-issuer rules

### 2.1 HDFC Bank — confidence **Medium**

Sources: stmt-forge (MIT), CardQL (Apache-2.0), xfina Excel (Apache-2.0).

| Item | Rule | Evidence |
|---|---|---|
| Text anchors (PDF) | Section titles `Domestic Transactions`, `International Transactions`, `Reward Points Summary`, `GST Summary`; 2025 table header `DATE & TIME TRANSACTION DESCRIPTION REWARDS AMOUNT PI`; page lines `Page x of y` | `CardQL/.../hdfc_v2.py:4-8`, `:125-135`; `.../hdfc_v1.py:84-90` |
| Fingerprint (export) | `PRIMARY / ADDON CUSTOMER NAME` = strong; `ALTERNATE ACCOUNT NUMBER:` = weak | `xfina/src/credit_cards/hdfc.rs:685-698` |
| Columns, old PDF | date, description, amount, optional `Cr` | `stmt-forge/.../hdfc_parser.py:19-25` |
| Columns, 2025 PDF | `DD/MM/YYYY| HH:MM`, description, rewards, `C` + amount (credit when `+` precedes `C`), trailing `l` flag (PI) | `hdfc_parser.py:39-45`; `CardQL/.../hdfc_v2.py:54-56` |
| Columns, export | Transaction type, Primary / Addon Customer Name, Date & Time, Description, REWARDS, AMT, Debit / Credit (older templates: `DATE`, no REWARDS) | `xfina/.../credit_cards/hdfc.rs:581-585` |
| Dates | `DD/MM/YYYY`, `DD/MM/YYYY| HH:MM`, export `DD/MM/YYYY / HH:MM`, summary `DD Mon, YYYY` | `hdfc.rs:663-676` |
| Credit rule | export: `Debit / Credit` equals `Cr` → credit; PDF 2025: `+` before `C` → credit | `hdfc.rs:242`; `CardQL/.../hdfc_v2.py:55` |
| Sections to skip | Reward Points Summary, Rewards Program Points Summary, Cashback Summary, GST Summary (export section names) | `hdfc.rs:111-135` |
| Add-on cards | Export carries the owner name per row (add-on holders carry an id after the name; strip it) | `hdfc.rs:230-233`. Never store that id. |
| Summary fields (math check) | Opening balance, payments/credits, purchases/debits, finance charges, total amount due; also minimum due, credit limit, available limit, cash limit, statement date, payment due date | `hdfc.rs:186-205`, `:213-221` |
| Math check in source | `total_due == opening + purchases − payments`; credits sum; debits sum; rewards closing | `hdfc.rs:414-436`, `:549-570`; tolerance below 1.0 (`xfina/src/models/validation.rs:281-283`) |
| **Gap in source** | The closing check leaves out `finance_charges` even though the summary has it. If finance charges are above ₹1 the check would report a mismatch. Inferred from code, **untested**. Our check should include finance charges | `hdfc.rs:213-221` vs `:414-436` |
| **Do not copy** | CardQL ends the transaction section at `International Transactions`, so international rows would be lost (`CardQL/.../hdfc_v1.py:87`, `hdfc_v2.py:131`). xfina notes that some downloads print a combined "Domestic/International Transactions" heading above one table (`hdfc.rs:107-112`). Include international rows | negative example |
| Password | Web search: no official card-statement password rule found. For accounts HDFC says Customer ID (unverified). **Unknown for cards** | https://www.hdfc.bank.in/need-help/net-banking-faqs (**unverified**) |

### 2.2 ICICI Bank — confidence **Low** (sources disagree)

| Item | Rule | Evidence |
|---|---|---|
| Layout A (CardQL, PDF) | `Date SerNo. Transaction Details ... Amount`; row = `dd/mm/yyyy` + serial number of 10+ digits + description + reward-points + amount, `CR` suffix for credits | `CardQL/.../icici_v1.py:4-7`, `:58`, `:101` |
| Layout B (stmt-forge, PDF) | two dates (transaction + posting) then description, amount, `Cr`/`Dr` | `stmt-forge/.../icici_parser.py:18-33` |
| Export (xfina CSV) | `"Date","Sr.No.","Transaction Details","Reward Point Header","Intl.Amount","Amount(in Rs)","BillingAmountSign"`, sign `""`, `CR`, `DR` | `xfina/.../credit_cards/icici.rs:589-592`, `:564` |
| Reading | Layout A matches the CSV export's columns (serial number, reward points), so A is the more likely modern PDF; B is probably an older template (**inference**) | — |
| Period | `Statement period : January 15, 2026 to February 14, 2026` | `CardQL/.../icici_v1.py:30-35` |
| Dates | `dd/mm/yyyy`, `dd-Mon-yy` | `icici.rs:564-567` |
| Skip | Header lines (`Statement period`, `Date SerNo`, `Amount (in`) and lines starting `Credit Limit` | `CardQL/.../icici_v1.py:97-99` |
| Known bug in source | CardQL puts the reward-points number into the description (`tokens[2:-1]`), see `icici_v1.py:63-66`. Fix: points column is separate | negative example |
| Fingerprint (export) | `ICICI BANK` plus any of `CARD HOLDER NAME`, `TOTAL CREDIT LIMIT`, `PAYMENT DUE DATE` | `icici.rs:839-851` |
| Summary fields | Previous Balance, Payments and Other Credits, Purchases and Other Charges, Total Amount Due, Minimum Amount Due, Available/Total Credit Limit, Available/Total Cash Limit, Statement Date, Payment Due Date, Statement Period | `icici.rs:110-145` |
| Math check | `total_due == previous + purchases − payments` (same finance-charge gap as HDFC) | `icici.rs:312-332` |
| Password | Web search shows **two conflicting rules**: last 4 digits of the card number (older page), or first 4 letters of the card name + day and month of birth `DDMM`, lowercase (help center) | https://help.icicibank.com/Cards/Credit-Cards/910106693/How-do-I-open-my-Credit-Card-e-statement.htm (**unverified**, summary from search) |

### 2.3 SBI Card — confidence **Medium** (two independent PDF-text sources agree)

| Item | Rule | Evidence |
|---|---|---|
| Layout | `Transaction Details Date Amount`; row = `DD Mon YY` + description + amount + `D` or `C` (or `M`) | `CardQL/.../sbi_v1.py:4-8`, `:65-70`; `stmt-forge/.../sbi_parser.py:18-24` |
| Period | `Statement Period : DD Mon YY to DD Mon YY`; 2-digit year `<50` = 20xx | `CardQL/.../sbi_v1.py:40-52` |
| Credit rule | `C` = credit; `D` = debit; **`M` is treated as a spend, its meaning is unknown** | `sbi_v1.py:68-70` |
| Section behaviour | PDF text order is not reliable: payment credits can appear **above** `TRANSACTIONS FOR ...`; some debits **below** `SHOP & SMILE SUMMARY`. So match rows by shape on the whole page, not by section | `sbi_v1.py:94-100` |
| Do not copy | Exact-line deduplication (`sbi_v1.py:111-120`); sort by (date, description) loses statement order (`:122`) | negative example |
| Summary fields | Not read by either source | — |
| Password | Not found in sources or web search | — |

### 2.4 Axis Bank — confidence **Medium**

| Item | Rule | Evidence |
|---|---|---|
| Layout (PDF) | `DATE TRANSACTION DETAILS MERCHANT CATEGORY AMOUNT (Rs.)`; row = `dd/mm/yyyy` + description + merchant category + amount + `Dr`/`Cr` | `CardQL/.../axis_v1.py:4-8`, `:43`, `:48` |
| Layout (export) | `Date | Transaction Details | | Amount (INR) | Debit/Credit`, ends with `** End of Statement **` | `xfina/src/credit_cards/axis.rs:16-21`, `:87` |
| Agreement | Both sources use the `End of Statement` marker and `Dr`/`Cr` | `axis_v1.py:95` |
| Period | `dd/mm/yyyy - dd/mm/yyyy` | `axis_v1.py:79` |
| Merchant category | Trailing words; two-word categories (`DEPT STORES`, `AUTO SERVICES`, `HOME FURNISHING`, `FOOD PRODUCTS`) must stay together | `axis_v1.py:18-23` |
| Summary fields | Total Payment Due, Minimum Payment Due, Credit Limit, Opening Balance, Payment Due Date. No purchases/payments split; totals summed from rows | `axis.rs:152-156`, `:23-26` |
| Math check | `total_due == opening + debits − credits` | `axis.rs:25-26`, `:262-282` |
| Fingerprint (export) | `SELECTED STATEMENT MONTH` or `CREDIT CARD NUMBER:` strong; `PAYMENT SUMMARY` + `DEBIT/CREDIT` weak | `axis.rs:404-417` |
| Password | Web: Axis says e-statements are password protected, format not given | https://www.axisbank.com/bank-smart/e-statements/downloads |

### 2.5 Other issuers (all Low)

| Issuer | Layout | Notes | Evidence |
|---|---|---|---|
| IndusInd | `Date Transaction Details Merchant Category Reward Points Amount`; row ends `DR`/`CR` | Period `dd/mm/yyyy To dd/mm/yyyy`. Skip `Purchases & Cash Transactions`, `Date Transaction Details`, and `Total ...` lines | `CardQL/.../indusind_v1.py:5-6`, `:30`, `:83-91` |
| HSBC | `DDMMM` dates, no year; text can be concatenated | Start at `OPENING BALANCE` or `PURCHASES & INSTALLMENTS`; stop at `TOTAL PURCHASE OUTSTANDING`, `TOTAL CASH OUTSTANDING`, `NET OUTSTANDING BALANCE`, `Interest Rate applicable`. **Do not copy** the amount rule: it keeps values from 1 to 500,000 and picks the **smallest** | `CardQL/.../hsbc_v1.py:59-66`, `:99-102` |
| Kotak | `DD/MM/YYYY desc amount [Cr|Dr]` (generic) | no issuer-specific facts | `stmt-forge/.../kotak_parser.py:17-23` |
| Yes Bank | `DD[/-]MM[/-]YY(YY)` or `DD Mon YY` + desc + amount + `Cr`/`Dr` (generic) | no issuer-specific facts | `stmt-forge/.../yes_parser.py:17-31` |
| IDFC First | `DD Mon YY desc amount DR|CR`; bare `date amount` rows exist; description may precede the date line; EMI tag `Convert` is stripped from descriptions; card line `Card Number: XXXX nnnn` | Promotional/noise lines that end the transaction section start with: `Refer `, `Enjoy `, `EMIfy`, `Flexible tenure`, `Convert your IDFC`, `Check Eligibility`, `Apply now`, `Know More`, `friends and earn`, `reward points`, `your Bank Account`, `transactions to easy`, `Share your credit`, `your loved ones`, `Add-on Card`, `#UPI now`, `Avail Quick Cash`, `Unlimited, evergreen`. These are the only explicit EMI/add-on skip rules in any source | `stmt-forge/.../idfc_first_parser.py:3-6`, `:18-25`, `:33-52`, `:70-71` |
| Federal / Scapia | `DD-MM-YYYY desc <2-3 digit code> amount Dr|Cr`; the code is discarded | | `stmt-forge/.../federal_parser.py:23-30` |
| CSB / Jupiter / Edge | Summary fields: previous balance, spends, repayments, refunds and reversals, waivers, total amount due; newer template `Rs. AMOUNT dd Mon yyyy` (due amount and date) | Fields are extracted but no reconciliation check was found in this file. **Candidate check (ours, untested)**: previous + spends − repayments − refunds − waivers = total due | `stmt-forge/.../csb_parser.py:21-50`, `:242-247` |

## 3. Verify layer inputs from this pack

| Check | Formula | Source |
|---|---|---|
| Closing balance | total due = opening (previous) + purchases (+ finance charges) − payments | `xfina/.../credit_cards/hdfc.rs:414-436`, `icici.rs:312-332`, `axis.rs:262-282` |
| Credits total | declared payments = sum of credit rows | `hdfc.rs:438-460` |
| Debits total | declared purchases = sum of debit rows | `hdfc.rs:465-487` |
| Tolerance in source | below 1.0 on summary totals | `xfina/src/models/validation.rs:281-283` |

Proposal for Stage 3 (ours): include finance charges in the formula; keep per-row sums exact to the paisa; treat any card statement that has summary fields but a mismatch as "needs review".

## 4. Open questions (updated after your answers; decisions are in `ENGINE_SPEC.md` section 0.2)

1. ~~EMI, rewards, add-on sections~~ **Answered (D5):** never import summary, reward tables, EMI schedules, offers; always import EMI installment lines, interest / fees / GST, payments, add-on spends, international transactions. The exact on-page signs of each are still hypotheses.
2. ~~Password formats~~ **Answered (D1):** the user enters the password; optional save; per-issuer hints are later.
3. ~~ICICI layout~~ **Answered (D3):** keep both layouts as variants, marked unresolved.
4. **SBI Card `M` suffix:** still **open (D4)**; resolve from a real statement's legend. Until then `M` forces REVIEW.

## 5. License summary

stmt-forge: MIT. CardQL: Apache-2.0. xfina: Apache-2.0 (medium confidence). See `research/LICENSES.md`. Rules cited above are facts and shapes only; no code is copied.

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
