# docstar_engine output format

For parsers, apps and AI agents that consume `parseDocument(...)` (or `docstar_cli --engine`, which writes one `<out>/engine/file_NN.json` per PDF). Source of truth: `lib/src/engine.dart` (document level), `lib/src/reconcile.dart` (`Txn.toJson`, `checks`).

## What the engine does

PDF text layer (words with positions) -> lines -> column header found -> columns measured from the page -> rows assembled (wrapped narrations and page-break continuations joined) -> amounts and signs resolved -> balances reconciled. No OCR: a PDF with no text layer returns `quality.status = "unsupported_scanned_pdf"` and no transactions.

It is bank-agnostic. `banks.json` (optional `banks:` argument) only identifies and labels the bank and supplies hints; pass `[]` to skip it.

## Standardized names vs printed names

Every bank prints different header words. The engine maps each printed header to one standard **role** so all banks give the same field names. The original text is kept next to it.

Per section:

```
"columns":        ["date", "desc", "debit", "credit", "balance"]       // roles, left to right
"column_headers": [{"role": "date",  "header": "Txn Date"},
                   {"role": "desc",  "header": "Particulars"}, ...]   // header = text as printed, null if the page had no header
```

`columns` and `column_headers` have the same length and order. Use `column_headers` to map a role back to what the PDF says (for example when two columns could be confused, or to show the user the bank's own wording). `column_headers` is additive: it has no counterpart in the Python reference, and the golden harness (`bin/golden.dart`) ignores it.

Roles: `date`, `vdate` (value date), `desc` (narration), `ref` (cheque / reference no.), `debit`, `credit`, `balance`, `?` (unrecognised header). Transaction JSON renames some: `desc` -> `description`, `vdate` -> `value_date`, `ref` -> `reference`. The vocabulary is `headerRoles` in `lib/src/lexicon.dart`.

## Document

| Key | Meaning |
|---|---|
| `engine`, `file`, `pages` | version, file base name, page count |
| `bank` | `{id, name, confidence}` or `null` |
| `account_last4` | last 4 digits of the account number, if found |
| `period` | `{from, to}` ISO dates, from the statement text |
| `locale` | `{numbers, date_order}`: number format and `DMY` / `MDY` |
| `summary_printed` | opening / closing / credit / debit totals as printed on the statement |
| `summary_checks` | booleans: do the printed totals match the parsed rows |
| `sections` | one per table stream (see below); usually one per account |
| `transaction_count`, `warnings` | totals; per-page problems such as "no readable text layer" |
| `quality` | `{score, status}`; see below |

## Section

`columns`, `column_headers`, `mode` (`anchor`: whether a wrapped narration sits above or below its date line; `grid`: ruled table), `opening`, `closing`, `checks`, `specials` (opening/closing balance rows and other non-transaction rows), `transactions`.

`checks`: `opening`, `closing`, `credits`, `debits`, `computed_closing`, `balanced` (opening + credits - debits equals the printed closing).

## Transaction

```
date, value_date      ISO yyyy-mm-dd or null
description           full narration, wrapped lines and page-break continuations joined
reference             cheque / ref number or null
debit, credit         decimal STRING or null (never a float)
amount                signed decimal string: credits positive, debits negative
balance               running balance after this row, or null
page                  page the row starts on
confidence            0..1
flags                 [] or any of the list below
extra                 other recognised columns, only when present
```

All money values are strings so no precision is lost. Parse with a decimal type.

## Flags and quality (how much to trust a row)

Flags: `invalid_date`, `date_carried` (same-day row without its own date), `repaired_number`, `both_debit_and_credit`, `reversal`, `cancelled`, `sign_unknown`, `sign_ambiguous`, `column_sign_conflict`, `amount_from_balance`, `balance_computed`, `balance_break`.

`quality.status`: `verified` (every section balances, no breaks, no unknown signs), `review`, `low`, `no_transactions`, `unsupported_scanned_pdf`. A statement with an unreadable page is at most `review`. Only treat `verified` data as final; show `review` and `low` to a human.

## Limits

- Font size comes from word box height and bold is never set (the PDF reader exposes neither), and ruled lines are not seen, so ruled tables are read as whitespace tables.
- Layout thresholds are tuned on synthetic statements; a new layout can still fail. Check `quality` and `warnings`.
- The ML layer of the Python reference is not ported: `bank` can be `null` where Python recovered it.
