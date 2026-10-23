# Spike report: does pdfrx (PDFium) work on Android for our engine?

Throwaway spike, not the engine. Date 2026-10-23. **Everything below was measured on an Android 16 arm64 emulator (6 GB RAM, 4 cores, Apple-silicon host). No physical phone was attached.** Items that need your phone are marked **PENDING DEVICE RUN**, with exact steps in section 4.

## 1. Recommendation

**GO (conditional).** `pdfrx_engine` 0.8.0 + `pdfium_flutter` 0.4.0 (PDFium `chromium/7811`) gives per-character boxes, a working password callback, deterministic output, and fast extraction on Android arm64, with no `INTERNET` permission in the release build. Conditions before we build on it:

| # | Condition | Why |
|---|---|---|
| C1 | The reader adapter converts boxes from the **unrotated page frame** to our top-left displayed frame (item 2) | Library returns unrotated coordinates; page width/height are rotated |
| C2 | Vendor the PDFium `.so` and pin its SHA-256; stop downloading it at build time (item 7) | The build hook downloads from GitHub with no checksum check |
| C3 | CI check: release merged manifest must not contain `INTERNET` (item 7) | Debug/profile manifests do |
| C4 | Run the device steps in section 4 on your phone, especially real-statement codepoints (item 3) and performance (item 5) | Emulator numbers are not phone numbers |

## 2. Results at a glance

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | Character boxes + overlay | **PASS** (emulator, fakes). Real-file visual check **PENDING DEVICE RUN** | 3,096 chars/page; rects = text length; 0 empty boxes on non-space chars; overlay screenshot |
| 2 | Rotation | **PASS, with a finding**: boxes are in the **unrotated** frame | err <= 0.64 pt in unrotated frame for 0/90/180/270 and crop box |
| 3 | Rupee / codepoints | **PASS (mechanics)**. Real-statement codepoints **PENDING DEVICE RUN** | U+20B9, U+0060, `C` detected on fake; PUA flagging implemented |
| 4 | Password flow | **PASS** (emulator, real SAF picker + dialog) | wrong -> retry -> OK; cancel -> clean exit; no crash |
| 5 | Performance, 10 pages | **PASS on emulator**; phone numbers **PENDING DEVICE RUN** | extract 51-82 ms; peak RSS 213 MB |
| 6 | APK size | **PASS**: **+8.31 MB** (arm64 release) | 15,879,622 -> 24,188,469 bytes |
| 7 | Zero-network audit | **PASS (runtime)**; build-time notes below | release APK has no `INTERNET`; `http` code not linked |
| 8 | Determinism | **PASS in-process**; cross-device **PENDING DEVICE RUN** | identical digest on every run |

## 3. Details

### Setup (what was actually used)

| Item | Value |
|---|---|
| Flutter / Dart | 3.47.1 / 3.13.1 |
| Packages | `pdfrx_engine` 0.8.0, `pdfium_flutter` 0.4.0, `file_picker` 13.1.0, `path_provider` 2.1.6 (the full `pdfrx` plugin was **not** used) |
| PDFium | `chromium/7811`, `libpdfium.so` arm64, 6,386,696 bytes (`pdfium_dart-0.4.0/hook/build.dart:10`) |
| Build gotchas | JDK 17 required (system has Java 8). `file_picker` 8.3.7 failed (compileSdk 34 vs required 36); 11.0.3 failed (plugin class not generated under built-in Kotlin); **13.1.0 works**. Gradle auto-installed Android SDK Platform 34 into the shared SDK at `finora/.tools/android-sdk` (additive) |
| Fixtures | Generated fakes only (`tool/make_fixtures.py`): plain, rot 90/180/270, crop box, locked (AES-256, fake password), 10 pages, rupee test |

### Item 1: character boxes and overlay

- Source: `PdfPage.loadText()` returns text plus one rectangle per character (`FPDFText_GetCharBox`, `pdfrx_engine/lib/src/native/pdfrx_pdfium.dart:1954-1986`).
- Fake page: **3,096 characters**; `charRects.length == fullText.length` on every fixture. 237 boxes are empty, **all on whitespace** (`empty_rects_non_space = 0` everywhere).
- Overlay: red per-character boxes drawn over the rendered page. Zoomed screenshot of the 90-degree page shows each rotated glyph inside its box.
- Not yet checked: a real statement's overlay (**PENDING DEVICE RUN**).

### Item 2: rotation

| Fixture | Reported rotation | Reported size (pt) | Probe error, unrotated frame | Probe error, displayed frame |
|---|---|---|---|---|
| plain | 0 | 595 x 842 | 0.45-0.64 pt | same |
| rot 90 | 90 | 842 x 595 | 0.45-0.64 pt | 68-634 pt |
| rot 180 | 180 | 595 x 842 | 0.45-0.64 pt | 251-762 pt |
| rot 270 | 270 | 842 x 595 | 0.45-0.64 pt | 196-596 pt |
| crop box (50,60)-(545,782) | 0 | 495 x 722 | 0.45-0.64 pt, **relative to the crop-box origin** | same |

**Finding:** `charRects` are in the **unrotated PDF frame** (origin bottom-left, points, relative to the crop box). `page.width/height` are the **rotated** size. The adapter must map points with the page rotation:

| Rotation | displayed x | displayed y (top-left origin) |
|---|---|---|
| 0 | x | H0 - y |
| 90 | y | x |
| 180 | W0 - x | y |
| 270 | H0 - y | W0 - x |

(W0, H0 = unrotated width and height.) This is `toDisplay` in `lib/spike.dart`. The 90-degree overlay with this mapping was confirmed visually; 180 and 270 only numerically. The behaviour matches why Docling converts explicitly for PDFium (`docling/backend/pypdfium2_backend.py:168-265`).

### Item 3: rupee and codepoints

- The app reports, as `U+XXXX`, the codepoint directly **before and after each amount-like token** (digits merged into one `DIGIT` bucket), flags U+20B9, backtick U+0060, letter `C`, and lists any private-use codepoints.
- Fake rupee page (STIX Two Text, SIL OFL): before-amount codepoints include **U+20B9 (1), U+0060 (1), U+0043 `C` (1)**; PUA: none. So PDFium returns U+20B9 correctly **when the font maps the glyph to Unicode**.
- First attempt used Arial Unicode and returned `U+0000`: that font has no U+20B9 glyph (checked with a font scan and poppler). A fixture bug, not a PDFium result.
- **Open (PENDING DEVICE RUN):** what PDFium returns for the currency symbol in your real statements. Sources suggest some print it as backtick or `C` (`CardQL .../icici_v1.py:5`, `stmt-forge/.../hdfc_parser.py:36-43`).

### Item 4: password flow

| Scenario (callback level, fake locked file) | Outcome | Provider calls |
|---|---|---|
| right password first | opened | 1 |
| wrong, then right | opened | 2 |
| wrong, then cancel | `password_failed_or_cancelled` | 2 |
| cancel immediately | `password_failed_or_cancelled` | 1 |
| unlocked file | opened | 0 |

The empty password is tried first by the library, so it is not counted as a provider call.

End-to-end on the emulator with the real Android system picker (DocumentsUI, SAF): pick the file -> password dialog -> wrong password -> dialog again (empty) -> correct password -> 3,096 chars extracted. Cancel in the dialog -> status "not opened", app stays alive, no `FATAL EXCEPTION` in logcat.
Not tested: AES-128 and RC4 encryption (only AES-256), which real statements may use. **PENDING DEVICE RUN** for your real locked file.

### Item 5: performance (10 pages, about 31,000 characters, release build)

| Metric | Emulator, release | Emulator, debug (JIT, for reference) |
|---|---|---|
| Open | 7-18 ms | 10-118 ms |
| Extract all 10 pages | **51-82 ms** (1-18 ms per page) | 32-1,181 ms (first run slow) |
| Render 10 pages at 1x | 10-54 ms | 12-323 ms |
| Process RSS at start / peak | 189 MB / **213 MB** | 408 MB / 437 MB |
| PSS after run (`dumpsys meminfo`) | 109-112 MB | not measured |

RSS is the whole app (Flutter engine included); extraction itself added about 24 MB. Target from the spec (<= 5 s, <= 200 MB extra) is met by a wide margin **on the emulator**; a mid-range phone will be slower. **PENDING DEVICE RUN.** Note: `open_ms` in picked-file metrics includes the time you spend typing the password.

### Item 6: APK size (release, arm64 only, same assets in both)

| Build | Bytes |
|---|---|
| Baseline (file_picker + path_provider, no pdfrx) | 15,879,622 |
| With `pdfrx_engine` + `pdfium_flutter` | 24,188,469 |
| **Delta** | **8,308,847 (+8.3 MB)** |

`libpdfium.so` 6.39 MB (stored uncompressed), `libapp.so` 4.98 MB, `libpdfrx_pdfium_gate.so` 5 KB. The Flutter-created APK is debug-signed and not shrunk; a Play bundle will deliver less. Reproduce: `tool/measure_size.sh`.

### Item 7: zero-network audit

| Check | Result |
|---|---|
| `INTERNET` in the **release** APK (`aapt2 dump permissions`, merged manifest) | **Absent.** Only the app's own `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` |
| `INTERNET` in debug / profile | **Present**, from Flutter's template (`android/app/src/{debug,profile}/AndroidManifest.xml`). Never ship those builds |
| Network packages in the dependency tree | `http 1.6.0` and `http_parser`, **only via `pdfrx_engine`** (`pdfrx_engine/pubspec.yaml`, URL-open code). No `dio`, `url_launcher`, web socket packages. (The full `pdfrx` plugin would add `url_launcher` and `web`) |
| Is `http` code in the release binary? | **No**: 0 hits for `package:http/` in `libapp.so`. Control search found `package:pdfrx_engine/` (20), `package:flutter/` (373), so the method works. `archive` and `image` are also absent. It is tree-shaken |
| Build-time network | `pdfium_dart`'s build hook **downloads PDFium from `github.com/bblanchon/pdfium-binaries` (`chromium/7811`) with no checksum check** (`pdfium_dart-0.4.0/hook/build.dart:55-80`); the hook itself depends on `http` and `archive` |

**How to exclude network code completely, if wanted:**
1. Already satisfied at runtime: no permission and the code is not linked. Make it a CI rule: fail if the release merged manifest contains `android.permission.INTERNET`.
2. Vendor the PDFium `.so` into the repo (pinned SHA-256) and replace the downloading hook, so the build needs no network and `http` leaves the build graph. This needs a fork or override of `pdfium_dart`/`pdfium_flutter`; not tried in this spike.
3. Optionally fork `pdfrx_engine` to delete the URL-open and cache files that import `http`.

### Item 8: determinism

- Each fixture is extracted twice; a 64-bit FNV digest over all text and box coordinates matched every time (3 repeated runs on the 10-page file, debug and release; also the real picker flow on the locked file).
- Cross-device comparison: the self-test now prints `digest_fixture_only` for the **fake** fixtures. Emulator values: plain `3e9521116bec318b`, rot90 `a69624659a22560`, rot180 `6b04988803fa5ceb`, rot270 `3e9521116bec318b`, crop box `-3a5d483426014528`, ten pages `-576f85aecc7f57ee`. Install the **same APK** on your phone and compare. **PENDING DEVICE RUN.**
- (plain and rot270 share a digest because the boxes are stored in the unrotated frame, which is identical.)

## 4. Steps to run on your phone

1. Enable USB debugging, connect, check `adb devices` shows the phone.
2. Install the APK built in this spike:
   `adb install -r spikes/pdfrx_spike/build/app/outputs/flutter-apk/app-release.apk`
   (or rebuild: `flutter build apk --release --target-platform android-arm64`; needs JDK 17 and the Android SDK).
3. **Fakes first.** Open the app, tap **Self-test (fakes)**. Compare with `spike_metrics_emulator.json` in this folder: `frame_verdict` should be `unrotated_frame_all_fixtures`, the `digest_fixture_only` values should match the emulator values above, and note `extract_total_ms` and `rss_current_max_after` for the 10-page file.
4. **Your own statement.** Tap **Pick PDF**, choose the file in the system picker, enter the password if asked. Then:
   - Look at the overlay: do the red boxes sit on the characters? Toggle **Overlay frame** if not (use `display` for unrotated pages).
   - Read the metrics on screen. Check `codepoints.has_u20b9_before_amount`, `has_backtick_before_amount`, `has_letter_C_before_amount`, `has_pua_anywhere`, `pua_codepoints`, and the `before_amount` / `after_amount` histograms (these are codepoints and counts only).
   - Check `per_page[*].empty_rects_non_space` is 0 and `rects_equal_text_length` is true.
   - `deterministic_identical` should be true.
5. Memory: right after the run, `adb shell dumpsys meminfo dev.calmcraft.spike.pdfrx_spike` and read `TOTAL PSS`.
6. Get the JSON: tap **Copy metrics JSON**, or `adb pull /sdcard/Android/data/dev.calmcraft.spike.pdfrx_spike/files/` (one file per run). The JSON holds counts, timings, codepoints and booleans only. The app prints no text; the metrics JSON is also printed to logcat for the same reason.
7. Clean up: `adb uninstall dev.calmcraft.spike.pdfrx_spike` removes the app and its files. The app deletes the picker's cached copy of your PDF right after reading it (the copy is in internal storage, so I could not inspect it).

## 5. What this spike does not cover

| Gap | Note |
|---|---|
| Real phone speed and memory | Section 4 |
| Real statement fonts (Type 1, CID, odd ToUnicode maps) | Fakes are reportlab TrueType subsets |
| AES-128 / RC4 locked files | Only AES-256 tested |
| Visual check of 180 and 270 degree overlays | Numerical check only |
| Multi-engine or multi-isolate use | Not used |
| PDFium's own licence | Not checked (pdfrx packages are MIT) |
| Android versions other than 16 | One emulator image |

## 6. Files

`lib/spike.dart` (extraction, metrics, probes), `lib/main.dart` (UI), `tool/make_fixtures.py` (fake PDFs and ground truth), `tool/measure_size.sh`, `assets/fixtures/` (fakes, committed), `spike_metrics_emulator.json` (emulator self-test output, fakes only).
