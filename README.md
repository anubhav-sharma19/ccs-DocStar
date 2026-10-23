# DocStar

Universal CalmCraft document engine (Dart package `docstar`): offline, deterministic PDF text and table extraction. Finora and Pocket Proof will consume it. Formerly `ccs-docengine`.

| Path | What |
|---|---|
| `research/` | Specs (`ENGINE_SPEC.md`), rule register, progress (`PROGRESS.md`) |
| `spikes/pdfrx_spike/` | Throwaway Android spike app (pdfrx_engine on Android) |
| `spikes/pdfrx_cli/` | Throwaway macOS CLI spike (batch metrics on local PDFs) |
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

Supported PDFium targets: Android `armeabi-v7a`, `arm64-v8a`, `x86_64`, and macOS arm64 (CLI and tests). Any other target fails the build with "PDFium not vendored for this target". Android apps should set `ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64") }`. iOS/macOS Flutter apps are **not** covered yet: `pdfium_flutter`'s podspec still downloads an xcframework (see `research/PROGRESS.md`).

## Release check

```bash
ANDROID_HOME=<sdk> JAVA_HOME=<jdk17> scripts/check_release.sh
```

It fails closed: a missing tool (flutter, dart, shasum, unzip, aapt2, NDK llvm-nm) or file is a failure. It checks the vendored hashes, that the lockfiles resolve to the fork, that the release APK and merged manifest have no `INTERNET`, that each ABI's `libpdfium.so` in the APK matches the vendored bytes and has no network symbols (socket, connect, getaddrinfo, gethostbyname, curl_*), and it runs `scripts/test_tamper.sh` (a 1-byte change to a vendored binary must fail the build).
