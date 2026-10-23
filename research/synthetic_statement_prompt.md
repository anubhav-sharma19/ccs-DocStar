# Prompt: realistic synthetic statement generator (for an external model)

Given to Haiku on 2026-10-23 to produce a hard, fully synthetic multi-page statement PDF plus ground truth (`truth.json`), so DocStar's `logical_tables` can be compared row by row. If the generated script is good, commit it as a fixture generator (e.g. `tools/synthetic/make_statement.py`) and run it in tests.

```text
Write ONE self-contained Python 3 script (reportlab only; no network) that generates a synthetic,
realistic Indian bank SAVINGS ACCOUNT STATEMENT PDF plus a ground-truth JSON. All data must be
FAKE: fictional bank "Northwind Bank Ltd", fictional customer, fictional addresses, account no.
"XXXXXXXX4321", fake IFSC "NWBK0001234". No real bank names, logos or people.

Determinism: random.seed(42); fixed creation date in PDF metadata; same output every run.
CLI: python make_statement.py --out statement.pdf --truth truth.json [--pages 8] [--password Test1234]
If --password is given, also write an AES-encrypted copy statement_locked.pdf.

PAGE (A4 portrait, 595x842 pt), repeated on EVERY page:
1. Top page header: fictional bank name (bold 14pt), branch address (2 lines, 8pt), a plain drawn
   rectangle as "logo" (no image file needed).
2. Account-info block (~110 pt tall, larger than 8% of the page), 2 columns of label : value pairs,
   e.g. "Account Holder : ...", "Account No : XXXXXXXX4321", "IFSC : ...", "Branch : ...",
   "Currency : INR", "Statement Period : 01/06/2026 To 31/08/2026", "Page 2 of 8".
3. Title line "Statement of account" (12pt), then the transaction table.
4. Footer (bottom 50 pt): 3 lines of small disclaimer text + "Page N of M" (identical text on every
   page except the page number).

TRANSACTION TABLE (ruled grid: thin vertical lines between columns, light blue column shading,
horizontal line under the header only):
Columns: Date | Narration | Chq./Ref.No. | Value Dt | Withdrawal Amt. | Deposit Amt. | Closing Balance
- Column header row repeated at the top of the table on EVERY page.
- Dates dd/mm/yy. Amounts right-aligned with Indian grouping (1,23,456.78). Empty cell when no amount.
- About 25 rows per page, 8 pages, ~200 transactions; the balance must be arithmetically correct
  (opening balance + deposits - withdrawals, row by row).
- Deposits are RARE: none at all on pages 1-2, then about 1 in 10 rows (sparse column).
- Narrations realistic but fake: UPI/<12 digits>/<NAME>/<bank>/<note>, NEFT-..., IMPS-..., ACH D- ...,
  POS ..., ATW-..., "INTEREST PAID", "GST ON CHARGES", "EMI 3/12 LOAN ...".
- Narration WRAPS onto 1-3 extra lines for ~30% of rows (wrap at the Narration column width).
  The wrapped lines are spaced the same as rows (like a real statement), not tighter.
- At least TWO page breaks where a narration's wrapped lines CONTINUE at the top of the next page's
  table (after the repeated header), before the next dated row.
- At least one row where the Narration text runs very close to (within 3 pt of) the Ref No. column.
- At least one Withdrawal/Deposit amount within 6 pt of the Closing Balance text (tight columns).
- A narration line that contains a date-like token in the middle (e.g. "REF 12/06/26 REVERSAL") on a
  wrapped (non-first) line.
- Two identical transactions on the same day (same narration, same amount): both must be present.
- One very large amount (e.g. 6,00,000.00) and one tiny (1.00).
Fonts: embed a TrueType font for the table (DejaVuSans or similar, pass the path as --font, fall back
to Helvetica if missing); use Helvetica-Bold (standard 14, not embedded) for the column header row.

EXTRA NOISE (must NOT be imported as transactions):
- A large, light-grey diagonal watermark "SAMPLE - NOT A VALID STATEMENT" across every page (rotated
  35 degrees, 40pt, 85% grey), drawn ABOVE the table text.
- On page 3, a rubber-stamp style "DUPLICATE" (bold 36pt, red, rotated 10 degrees) over the table.
- After the last transaction (last page): a "Statement Summary" box (2 columns: label | amount:
  Opening Balance, Total Withdrawals, Total Deposits, Closing Balance, Dr Count, Cr Count), then a
  short "Reward points" table (3 columns) that is NOT a transaction table, then 2 lines of promo text.
- One page (page 6) rendered as LANDSCAPE content on a page with /Rotate 90 (same table layout).

GROUND TRUTH (truth.json):
{
 "pages": M,
 "columns": ["Date","Narration","Chq./Ref.No.","Value Dt","Withdrawal Amt.","Deposit Amt.","Closing Balance"],
 "transactions": [ {"page_start": p, "page_end": q, "date": "...", "narration": "<all wrapped lines joined
    with one space, in reading order>", "ref": "...", "value_date": "...", "withdrawal": "1,234.00" or null,
    "deposit": null or "...", "balance": "..."} , ... ],   // in printed order
 "summary": {"opening": "...", "total_withdrawals": "...", "total_deposits": "...", "closing": "...",
             "dr_count": n, "cr_count": n},
 "noise": ["watermark text", "DUPLICATE", "Reward points table", "promo lines", "page header", "account info", "footer"]
}
page_start != page_end marks the transactions whose narration continues over a page break.

Also print a short self-check: number of transactions, pages with a carried-over narration, and that
the summary totals match the rows.
```

Run through DocStar:

```bash
cd ~/calmcraft/docstar/tools/docstar_cli && dart run bin/docstar_cli.dart --in /path/to/statement.pdf --out /Users/anubhavsharma/Downloads/bank_statements_test/SYNTH_01 --visual --redact
```
