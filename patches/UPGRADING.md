# Upgrading pdfium_dart or PDFium

`pdfium_dart-0.4.0.patch` turns pristine upstream `pdfium_dart` 0.4.0 into `third_party/pdfium_dart` (everything except `NOTICE.md`). Apply it with `git apply -p1` from inside the package folder.

## New pdfium_dart version (say 0.5.0)

1. Get the pristine package: `dart pub cache add pdfium_dart --version 0.5.0`, then copy `~/.pub-cache/hosted/pub.dev/pdfium_dart-0.5.0` to a temp dir.
2. Apply our patch: `cd <temp copy> && git apply -p1 --3way <repo>/patches/pdfium_dart-0.4.0.patch`. If a hunk fails, redo the 3 changes listed in `third_party/pdfium_dart/NOTICE.md` by hand.
3. If upstream moved to a new PDFium release, update `_pdfiumRelease` in `hook/build.dart` and do the PDFium steps below.
4. Replace `third_party/pdfium_dart` with the patched copy. Keep upstream `LICENSE`. Update the version, tag, commit and archive hash in `NOTICE.md`.
5. Regenerate the patch from the pristine and patched trees (run in a dir holding `a/` = pristine, `b/` = patched, without `.dart_tool` and `NOTICE.md`):
   `git diff --no-index --no-prefix a b > patches/pdfium_dart-0.5.0.patch`, and delete the old patch.
6. `flutter pub get` / `dart pub get` in every root app, then run `scripts/check_release.sh`. It runs the tamper test and fails if a lockfile does not point at the fork.

## New PDFium release (say chromium/7900)

1. Download `pdfium-{android-arm,android-arm64,android-x64,mac-arm64}.tgz` from `https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F7900`.
2. For each, put `lib/libpdfium.*`, `LICENSE`, `licenses/`, `VERSION`, `args.gn` in `third_party/pdfium/chromium-7900/<platform>/`.
3. `cd third_party/pdfium/chromium-7900 && shasum -a 256 */libpdfium.* > SHA256SUMS`.
4. Record the tgz URLs and their SHA-256 in that folder's `README.md`. Delete the old release folder.
5. Update `_pdfiumRelease` in `hook/build.dart` and the `vendor` paths in `scripts/check_release.sh` and `scripts/test_tamper.sh`, then do step 5-6 above.
