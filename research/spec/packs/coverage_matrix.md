# Coverage matrix (Stage 2)

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
