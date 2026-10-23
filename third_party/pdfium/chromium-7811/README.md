# Vendored PDFium chromium/7811

Prebuilt PDFium (VERSION 149.0.7811.0) from https://github.com/bblanchon/pdfium-binaries, release `chromium/7811`. Fetched 2026-10-23. This is the same release that `pdfium_dart` 0.4.0 downloads. The build never downloads it: `third_party/pdfium_dart/hook/build.dart` reads these files and fails if one does not match `SHA256SUMS`.

| Folder | Source archive | Archive SHA-256 | Binary bytes | Compared with an earlier cached copy |
|---|---|---|---|---|
| `android-arm/` (armeabi-v7a) | `pdfium-android-arm.tgz` | `bb9250eefb33343f56f27f7e60c81ab3236d932c40e21557bf02ca4c276eb832` | 4,209,140 | **No cached copy existed** |
| `android-arm64/` (arm64-v8a) | `pdfium-android-arm64.tgz` | `f51539cadeb5135534305b8bdf8685ce2fbe9991dbbc5b35f553108411b9ed14` | 6,386,696 | Identical (`cmp`) to the copy the pdfrx spike's build hook downloaded |
| `android-x64/` (x86_64) | `pdfium-android-x64.tgz` | `23faaf6f993a39524d9dc7fafbb760e295f8bd5e9ffa46139bad2299fb5c80f3` | 6,604,440 | **No cached copy existed** |
| `mac-arm64/` | `pdfium-mac-arm64.tgz` | `f9bbf1ebdc459e5f5ff25b2d457cc21db55ebfc0cf3d89fc1b90ce5445dac394` | 7,079,168 | Identical (`cmp`) to the copy the CLI spike's build hook downloaded |

Archive URL pattern: `https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F7811/<archive>`. Upstream publishes no checksums, so the archive hashes above are what we downloaded, not values upstream signed.

Each platform folder keeps that archive's `LICENSE` (MIT, pdfium-binaries build scripts, Benoit Blanchon) and `licenses/` (`pdfium.txt` = PDFium itself, BSD-3-Clause, plus third-party notices: FreeType, ICU, libjpeg-turbo, ...). They differ slightly per platform (the mac build bundles fewer libraries), so each is kept as shipped. `VERSION` and `args.gn` are kept for provenance.

Total size is about 24 MB, so there is no Git LFS. Upgrading: `patches/UPGRADING.md`.
