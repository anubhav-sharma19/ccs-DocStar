# DocStar

Universal CalmCraft document engine (Dart package `docstar`): offline, deterministic PDF text and table extraction. Finora and Pocket Proof will consume it. Formerly `ccs-docengine`.

| Path | What |
|---|---|
| `research/` | Specs (`ENGINE_SPEC.md`), rule register, progress (`PROGRESS.md`) |
| `docs/CORE_DESIGN.md` | Core design (approved) |
| `packages/docstar_core/` | Pure-Dart core: chars → words, lines, blocks, tables, reading order; Pack/Verify interfaces. Zero runtime deps |
| `packages/docstar_pdfium/` | Reader adapter over pdfrx_engine: per-char boxes (display frame), password callback |
| `spikes/pdfrx_spike/` | Throwaway Android spike app (pdfrx_engine on Android) |
| `tools/docstar_cli/` | macOS CLI: batch metrics on local PDFs; `--visual` draws DocStar overlays (words, lines, blocks, table grids) |
| `third_party/pdfium/` | Vendored PDFium binaries, hash-pinned (`SHA256SUMS`) |
| `third_party/pdfium_dart/` | Patched fork of `pdfium_dart` 0.4.0: uses the vendored binaries, never downloads (`NOTICE.md`) |
| `patches/` | Our change as a patch + `UPGRADING.md` |
| `scripts/check_release.sh` | Zero-network release guard (also run by `.github/workflows/check_release.yml`) |

## Using DocStar

Every **root app** that depends on DocStar (or on `pdfrx_engine` / `pdfium_flutter` directly) must add this to its own `pubspec.yaml`, with the path adjusted to where the DocStar repo sits:

```yaml
dependency_overrides:
  pdfium_dart:
    path: <path-to-docstar>/third_party/pdfium_dart
```

Why: Dart only applies `dependency_overrides` from the root package, so an override inside DocStar's own packages does nothing for Finora or Pocket Proof. Without it, pub resolves upstream `pdfium_dart`, whose build hook downloads PDFium with no checksum check. After `pub get`, check that `pubspec.lock` shows `pdfium_dart` with `source: path` pointing at the fork. `scripts/check_release.sh` enforces this for the apps in this repo; consuming apps should run the same check.

**PDFium is not safe for concurrent use.** Run DocStar on ONE isolate and process PDFs sequentially, one open document at a time. Call `initDocstarPdfium()` once at startup (Flutter: `initDocstarPdfium(tmpPath: (await getTemporaryDirectory()).path)`), **instead of** `pdfrxInitialize()`. As a guard, `docstar_pdfium` turns on pdfrx's native process-wide PDFium gate, so PDFium calls from another isolate wait instead of crashing the VM ("Cannot invoke native callback from a different isolate"). `readPdf` also queues calls so one document is open at a time per isolate. Side effect of the gate: non-embedded fonts (e.g. standard-14 Courier/Helvetica) use PDFium's built-in font mapper, not pdfrx's Dart mapper; boxes move by under 0.5 pt and the result no longer depends on the device's system fonts. If anything starts PDFium without the gate first, `readPdf` throws a `StateError` saying so.

Supported PDFium targets: Android `armeabi-v7a`, `arm64-v8a`, `x86_64`, and macOS arm64 (CLI and tests). Any other target fails the build with "PDFium not vendored for this target". Android apps should set `ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64") }`. iOS/macOS Flutter apps are **not** covered yet: `pdfium_flutter`'s podspec still downloads an xcframework (see `research/PROGRESS.md`).

## Visual debug CLI (macOS arm64)

```bash
cd tools/docstar_cli && dart run bin/docstar_cli.dart --in <pdf-or-folder> --out <folder outside any git repo> --visual
```

Writes `metrics.json` (numbers and layout counts only, no text or file names) and, with `--visual`, `visual/file_NN/transformed.json` (every table per page: `header` and `rows` of cell text, empty cells `null`, `continues_from` for page links; plus `logical_tables`, each table continuing over pages as one list of rows with the same columns, `same_columns` as a check) and `visual/file_NN/page_N.png`: the rendered page with words (blue), lines (green), blocks (orange), page header/footer (purple), table grids (red, one rectangle per cell) and overlay stamps/watermarks (grey). Add `--redact` (with or without `--visual`) for **shareable** PNGs in `<out>/redacted/file_NN/page_N.png`. They are drawn on a blank canvas: every word is a solid black bar, plus the same layout outlines. No pixel comes from the PDF, so logos, signatures, QR codes or text drawn as shapes cannot leak, and the PNG carries no metadata. What still shows: layout geometry, i.e. word positions and lengths (so the digit count of an amount), and the overall template, which may hint at the bank. Look at each PNG before sharing; never share `visual/` or `transformed.json`.

```bash
cd tools/docstar_cli && dart run bin/docstar_cli.dart --in <pdf-or-folder> --out <folder outside any git repo> --visual --redact
```

The full (unredacted) PNGs and `transformed.json` show document content, so the CLI refuses an `--out` inside a git repo. Passwords are asked at a hidden prompt, never taken as arguments.

## Release check

```bash
ANDROID_HOME=<sdk> JAVA_HOME=<jdk17> scripts/check_release.sh
```

It fails closed: a missing tool (flutter, dart, shasum, unzip, aapt2, NDK llvm-nm) or file is a failure. It checks the vendored hashes, that the lockfiles resolve to the fork, that the release APK and merged manifest have no `INTERNET`, that each ABI's `libpdfium.so` in the APK matches the vendored bytes and has no network symbols (socket, connect, getaddrinfo, gethostbyname, curl_*), and it runs `scripts/test_tamper.sh` (a 1-byte change to a vendored binary must fail the build).
