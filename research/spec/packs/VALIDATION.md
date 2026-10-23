# Stage 2 validation — packs

## Method

1. **Citation check (automated).** Every `repo/path:line` in `bank_statement.md` and `credit_card.md` is resolved against the cloned sources. Ambiguous short names (`hdfc.rs`, `icici.rs`, `axis.rs`) resolve by context: bank file → `bank_accounts/`, card file → `credit_cards/`.
2. **Meaning check (manual).** The printed line was read against each claim; mismatches were fixed (see below).
3. **Evidence types** are kept apart: code (cited by line), web (URL, marked unverified), our proposals (marked "proposal" / "ours").

## Result

**139 citations: 138 resolve; 1 not indexed** (`CardQL/docs/CONFIG.md:19`, `:40`; the check only indexes `src/`; both lines were read directly in an earlier grep: they say `passwords` is a list of templates and placeholders are not supported).

## Corrections made during validation

| # | What was wrong | Fix |
|---|---|---|
| 1 | Claimed "no source handles multi-line card descriptions" | IDFC First does (description before the date line, `Convert` tag stripped, promo-line stop list): `stmt-forge/.../idfc_first_parser.py:3-6`, `:18-25`, `:70-71`. Row and shared rule rewritten |
| 2 | Called stmt-forge's extractor "pdfplumber-style" | Confirmed pdfplumber (`extractor.py:7`, `:26`, `:36`) |
| 3 | Seven `~` approximate line numbers | Replaced with exact lines |
| 4 | Column headers for HDFC/ICICI/Axis bank were written as if quoted | Only `Date`, `Narration`, `S No.`, `SRL NO` are quoted in code; the rest labelled "roles read from variable names" |
| 5 | A `config.py` citation resolved to the wrong repo | Now written as `CardQL/src/cardql/config.py` |
| 6 | Password section was missing | Added the generic candidate list from stmt-forge (`config.py:84-152`) and noted that no per-issuer rule exists in any source |

## Evidence quality: what is solid and what is not

| Area | Status |
|---|---|
| SBI bank PDF rules (xfina) | Read line by line, including checks. **Solid for code behaviour**; correctness on real PDFs is untested |
| Card PDF line layouts (stmt-forge, CardQL) | Regex and docstring examples read. Layout claims rest on parsers' own docstrings |
| Excel-export facts (xfina HDFC/ICICI/Axis/BoB, cards) | Read selectively (probes, columns, summary labels, checks). Not all code paths read |
| Password rules | **No code evidence.** Web search summaries only; ICICI card result is contradictory; marked unverified |
| EMI / add-on / reward sections | Only HDFC export section names and IDFC promo-line list |
| Thresholds I proposed (LR / TR in Stage 1; verify tolerances here) | Marked "ours"; untested |

## Not done / open gaps

| # | Gap |
|---|---|
| P1 | `CardQL/.../icici_v1.py` sample line shows a reward-points number before the amount; confirmed only from the docstring (`icici_v1.py:6-7`), not from a document |
| P2 | stmt-forge `extractor.py` card-last-4 detection and `scope_filter.py` not read |
| P3 | xfina `intl_stocks`, `mutual_funds`, `reference_rates` not read (out of scope) |
| P4 | xfina ICICI card CSV/export logic read only at labels, columns, probe, one check |
| P5 | No synthetic PDFs exist yet to test any rule |
