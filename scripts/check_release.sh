#!/usr/bin/env bash
# Zero-network release guard: builds the spike's release APK and fails if
#   - a root app's pubspec.lock resolves pdfium_dart to anything but our fork,
#   - a vendored PDFium binary does not match SHA256SUMS,
#   - the merged release manifest (or the APK) requests INTERNET,
#   - libpdfium.so in the APK has network symbols (socket/connect/DNS/curl).
# Fails closed: a missing tool or file is a failure, never a skip.
# Needs: ANDROID_HOME (build-tools + NDK installed), JDK 17 on JAVA_HOME, flutter, dart.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
spike=$root/spikes/pdfrx_spike
vendor=$root/third_party/pdfium/chromium-7811
apps=(spikes/pdfrx_spike spikes/pdfrx_cli packages/docstar_pdfium)
# APK ABI -> vendored dir
abis=(armeabi-v7a:android-arm arm64-v8a:android-arm64 x86_64:android-x64)
vendored=(android-arm/libpdfium.so android-arm64/libpdfium.so android-x64/libpdfium.so mac-arm64/libpdfium.dylib)
net_syms='(socket|connect|getaddrinfo|gethostbyname|curl_.*)'

fail() { echo "check_release: FAIL: $*" >&2; exit 1; }
need_tool() { command -v "$1" >/dev/null 2>&1 || fail "required tool not found on PATH: $1"; }
need_file() { [[ -f $1 ]] || fail "required file missing: $1"; }
step() { echo "check_release: $*"; }

# --- tools ---
for t in flutter dart shasum unzip awk; do need_tool "$t"; done
[[ -n ${ANDROID_HOME:-} ]] || fail "ANDROID_HOME is not set"
aapt2=$(ls "$ANDROID_HOME"/build-tools/*/aapt2 2>/dev/null | sort | tail -1 || true)
[[ -n $aapt2 && -x $aapt2 ]] || fail "aapt2 not found under $ANDROID_HOME/build-tools"
ndk=${ANDROID_NDK_HOME:-$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort | tail -1 || true)}
llvm_nm=$(ls "$ndk"/toolchains/llvm/prebuilt/*/bin/llvm-nm 2>/dev/null | head -1 || true)
[[ -n $llvm_nm && -x $llvm_nm ]] || fail "llvm-nm not found in NDK (${ndk:-none}); install the NDK or set ANDROID_NDK_HOME"

# --- 1. vendored binaries match SHA256SUMS ---
step "checking vendored PDFium hashes"
need_file "$vendor/SHA256SUMS"
for rel in "${vendored[@]}"; do
  need_file "$vendor/$rel"
  grep -q "  $rel\$" "$vendor/SHA256SUMS" || fail "$rel is not listed in SHA256SUMS"
done
(cd "$vendor" && shasum -a 256 -c SHA256SUMS) || fail "vendored PDFium hash mismatch"

# --- 2. every root app resolves pdfium_dart to the fork ---
step "checking pubspec.lock files"
(cd "$spike" && flutter pub get >/dev/null) || fail "flutter pub get failed (spike)"
(cd "$root/spikes/pdfrx_cli" && dart pub get >/dev/null) || fail "dart pub get failed (cli)"
(cd "$root/packages/docstar_pdfium" && dart pub get >/dev/null) || fail "dart pub get failed (docstar_pdfium)"
for app in "${apps[@]}"; do
  lock=$root/$app/pubspec.lock
  need_file "$lock"
  block=$(awk '/^  pdfium_dart:$/{f=1;next} f&&/^  [^ ]/{exit} f' "$lock")
  grep -q 'source: path$' <<<"$block" && grep -q 'path: "../../third_party/pdfium_dart"' <<<"$block" \
    || fail "$app/pubspec.lock does not resolve pdfium_dart to third_party/pdfium_dart (missing dependency_overrides?)"
done

# --- 3. release APK ---
step "building release APK"
(cd "$spike" && flutter build apk --release --target-platform android-arm,android-arm64,android-x64) \
  || fail "flutter build apk --release failed"
apk=$spike/build/app/outputs/flutter-apk/app-release.apk
need_file "$apk"

# --- 4. no INTERNET ---
step "checking permissions"
manifest=$(find "$spike/build/app/intermediates/merged_manifests/release" -name AndroidManifest.xml 2>/dev/null | head -1 || true)
need_file "$manifest"
if grep -q 'android.permission.INTERNET' "$manifest"; then fail "merged release manifest requests INTERNET: $manifest"; fi
perms=$("$aapt2" dump permissions "$apk") || fail "aapt2 dump permissions failed"
[[ -n $perms ]] || fail "aapt2 printed nothing for $apk"
if grep -q 'android.permission.INTERNET' <<<"$perms"; then fail "release APK requests INTERNET"; fi

# --- 5. libpdfium.so in the APK: same bytes as vendored, no network symbols ---
step "checking libpdfium.so in the APK"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -q "$apk" 'lib/*/libpdfium.so' -d "$tmp" || fail "could not extract libpdfium.so from the APK"
for pair in "${abis[@]}"; do
  abi=${pair%%:*} dir=${pair##*:}
  so=$tmp/lib/$abi/libpdfium.so
  need_file "$so"
  want=$(awk -v p="$dir/libpdfium.so" '$2==p{print $1}' "$vendor/SHA256SUMS")
  got=$(shasum -a 256 "$so" | awk '{print $1}')
  [[ $got == "$want" ]] || fail "APK lib/$abi/libpdfium.so differs from vendored $dir ($got != $want)"
  syms=$("$llvm_nm" -D "$so") || fail "llvm-nm failed on lib/$abi/libpdfium.so"
  [[ -n $syms ]] || fail "llvm-nm found no dynamic symbols in lib/$abi/libpdfium.so (broken tool?)"
  bad=$(awk '{print $NF}' <<<"$syms" | sed 's/@.*//' | grep -E -x "$net_syms" || true)
  [[ -z $bad ]] || fail "lib/$abi/libpdfium.so has network symbols: $(tr '\n' ' ' <<<"$bad")"
done

# --- 6. tampered binary fails the build ---
step "running tamper test"
"$root/scripts/test_tamper.sh" || fail "tamper test failed"

step "PASS"
