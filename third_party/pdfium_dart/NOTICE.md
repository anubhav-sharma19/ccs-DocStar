# NOTICE: patched fork of pdfium_dart

- Upstream: `pdfium_dart` **0.4.0** from https://github.com/espresso3389/pdfrx (`packages/pdfium_dart`), tag `pdfium_dart-v0.4.0`, commit `007415ec8a4e5eb37e34a85801d17d56d56ad620`. pub.dev archive SHA-256 `e9f712166563540228e9ce7b8a515fcbd42ebd9d7c0925baa42c6b981f7e7900`.
- Licence: MIT, copyright (c) 2025 @espresso3389 (Takashi Kawasaki). See `LICENSE` (unchanged).
- Our change: `../../patches/pdfium_dart-0.4.0.patch`. Re-applying on upgrade: `../../patches/UPGRADING.md`.

## Why it is forked

Upstream's build hook (`hook/build.dart`) downloads PDFium from `github.com/bblanchon/pdfium-binaries` on every clean build and never checks a checksum. It has no setting to use a local binary. DocStar needs a build that never touches the network for PDFium and always uses pinned bytes (spike condition C2).

## What changed

1. `hook/build.dart`: no download. The hook reads `../pdfium/chromium-7811/<platform>-<arch>/<lib>` (that is, `third_party/pdfium`), checks its SHA-256 against `SHA256SUMS`, and fails the build if the binary is missing, not listed, or does not match. Both files are declared as hook dependencies, so a changed binary re-runs the check.
2. `pubspec.yaml`: `http` and `archive` removed (only the download used them), `crypto` added, `resolution: workspace` removed.
3. `lib/src/proxy_http_client.dart` and its test removed (only the download used them).

Everything else is upstream 0.4.0 byte for byte. iOS is unchanged: there, PDFium comes from `pdfium_flutter`'s podspec, which still downloads (open item in `research/PROGRESS.md`).
