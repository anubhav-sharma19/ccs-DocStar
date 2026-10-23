# Licenses — sources used by ccs-docengine

Verdict rule (from the brief):
- **MIT / Apache-2.0 / BSD** → ideas and rules may be reused (keep the license notice in any reused text).
- **Anything else / no license** → extract only high-level format facts; never copy code.

| Source | Repo (commit cloned) | License | Verdict |
|---|---|---|---|
| Docling | https://github.com/docling-project/docling (1ee1db0) | MIT (`LICENSE`) | Ideas + rules reusable. Official Docling project. |
| docling-core | https://github.com/docling-project/docling-core (b501ec8) | MIT (`LICENSE`) | Ideas + rules reusable. Official Docling project. |
| docling-parse | https://github.com/docling-project/docling-parse (1a1c06c) | MIT (`LICENSE`) | Ideas + rules reusable. Official Docling project. Note: the LICENSE copyright line is still the template placeholder `Copyright (c) [year] [fullname]`. License text is MIT; flag for the user, not a blocker. |
| reverse-engineering-skill | https://github.com/meirm/reverse-engineering-skill (69a3f16) | MIT (Copyright 2026 Meir Michanie) | Method reused for this workspace. |
| stmt-forge (PyPI `stmtforge` 1.0.1) | https://github.com/madhav921/stmt-forge (57d409f) | MIT (Copyright 2025 Madhav) | Rules reusable. Credit-card PDF parser, HDFC/ICICI/SBI/Axis/Kotak + 4 more. |
| xfina (PyPI `xfina` 0.9.0) | https://github.com/xfina-dev/xfina (2561737) | Apache-2.0 (`LICENSE`) | **Medium confidence, usable per Apache-2.0** (upgraded after provenance re-check; keep the license notice and any NOTICE file). Caveat: owner-vs-maintainer match could not be checked. See below. |
| CardQL (PyPI `cardql` 0.1.1) | https://github.com/ananyaem/CardQL (d54d6f8) | Apache-2.0 (`LICENSE`) | Rules reusable; keep NOTICE. Issuers: Axis, HDFC, HSBC, ICICI, IndusInd, SBI. PyPI metadata has no license field; the repo LICENSE is the source of truth. |
| pdfrx_engine 0.8.0 / pdfrx 2.10.0 (pub.dev) | https://github.com/espresso3389/pdfrx (pub.dev archives, read-only copies in `research/sources/`) | MIT (`LICENSE` in each package) | Rules and API facts reusable. Chosen as the recommended PDF reader adapter (spike S1). PDFium's own licence is **not checked** here |

## Removed

- **bout** (codito/bout, MIT): dropped on user decision. ICICI CSV→QIF tool, not a PDF parser. Clone deleted.

## xfina verification (user decision 4)

| Check | Result |
|---|---|
| Version: Cargo.toml `[workspace.package] version` vs PyPI latest | **Match**: 0.9.0 = 0.9.0 (PyPI latest is 0.9.0; versions list ends 0.8.0, 0.8.1, 0.9.0) |
| PyPI source / attestation link points to this repo | **Not verifiable**: PyPI `project_urls` and `home_page` are null for 0.9.0. The attestation URL `pypi.org/integrity/xfina/0.9.0/` returns 404. Only the PyPI description text links to github.com/xfina-dev/xfina. |
| Parser names from the brief | **Partial**: `parse_sbi_ba` and `parse_hdfc_cc` do NOT exist. Real names: `parse_sbi_bank_statement` (src/bank_accounts/sbi.rs:17), `parse_hdfc_bank_statement` (src/bank_accounts/hdfc.rs:455), `parse_hdfc_statement` (src/credit_cards/hdfc.rs:18). Also `parse_icici_statement` (src/credit_cards/icici.rs:18), `parse_axis_statement` (src/credit_cards/axis.rs:27). |
| **Verdict (first pass)** | Facts only, low confidence. Superseded by the re-check below. |

### Re-check (user note: parser names came from release 0.3.0, so the rename is not a red flag)

| Check | Result |
|---|---|
| Does README/examples match? | **Yes.** PyPI description is identical to repo `python/README.md` (similarity 1.0). It links to `github.com/xfina-dev/xfina` |
| Does the repo build the PyPI package? | **Yes.** `python/pyproject.toml:6` `name = "xfina"`; `.github/workflows/publish.yml` builds the wheels with maturin; homepage `xfina.dev` returns 200 and matches `Cargo.toml` and the GitHub repo homepage |
| Release timing | PyPI 0.9.0 uploaded 2026-10-11; repo HEAD pushed 2026-10-11 |
| Does the repo owner match the PyPI maintainer? | **Not checkable.** PyPI `author` / `maintainer` fields are empty. The owner is the GitHub organisation `xfina-dev` (created 2026-06-20, 4 stars). This is the one part of your test I could not confirm |
| **Verdict** | **Medium confidence, usable per license.** Based on identical README, repo-built package, and matching homepage and dates. Flag if you want the stricter rule (a named maintainer match) applied. The repo is young (created 2026-06) and small, so treat its rules as facts to cross-check against stmt-forge and CardQL, not as ground truth |

## Not cloned, licence noted

- **syncfusion_flutter_pdf** (pub.dev): commercial; Community License only if revenue is under US$1M **and** fewer than 5 developers (source: https://raw.githubusercontent.com/syncfusion/flutter-widgets/master/packages/syncfusion_flutter_pdf/LICENSE). Not used.

## Notes

- Clones live in `research/sources/` (git-ignored via `.gitignore`). They are read-only references, never committed.
- No real bank or card statements were downloaded or stored. Code analysis only.
- Git over HTTPS only. `gh` is not installed and was not needed.
