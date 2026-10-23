#!/usr/bin/env bash
# A 1-byte change to a vendored PDFium binary must fail the build.
# Copies third_party/ and a tiny pure-Dart consumer to a temp dir, builds it clean
# (must load PDFium), flips one byte in the mac-arm64 dylib, builds again (must fail
# with "SHA-256 mismatch"). The second build reuses the first one's cache, so this
# also checks the hook re-runs when the binary changes.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "test_tamper: FAIL: $*" >&2; exit 1; }
for t in dart python3 rsync; do command -v "$t" >/dev/null 2>&1 || fail "required tool not found on PATH: $t"; done
[[ "$(uname -s)-$(uname -m)" == Darwin-arm64 ]] || fail "needs macOS arm64 (it tampers the mac-arm64 dylib)"
dylib_rel=pdfium/chromium-7811/mac-arm64/libpdfium.dylib
[[ -f $root/third_party/$dylib_rel ]] || fail "missing third_party/$dylib_rel"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/third_party" "$tmp/apps/probe/bin"
rsync -a --exclude .dart_tool "$root/third_party/pdfium" "$root/third_party/pdfium_dart" "$tmp/third_party/"
cat >"$tmp/apps/probe/pubspec.yaml" <<'EOF'
name: probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  pdfium_dart:
    path: ../../third_party/pdfium_dart
EOF
cat >"$tmp/apps/probe/bin/probe.dart" <<'EOF'
import 'package:pdfium_dart/pdfium_dart.dart';

void main() {
  final pdfium = getPdfium();
  pdfium.FPDF_InitLibrary();
  pdfium.FPDF_DestroyLibrary();
  print('pdfium ok');
}
EOF

cd "$tmp/apps/probe"
dart pub get --offline >/dev/null || fail "dart pub get --offline failed"

out=$(dart run bin/probe.dart 2>&1) || fail "clean build did not run:\n$out"
grep -q 'pdfium ok' <<<"$out" || fail "clean build did not load PDFium:\n$out"
echo "test_tamper: clean build loads vendored PDFium"

python3 - "$tmp/third_party/$dylib_rel" <<'EOF'
import sys
with open(sys.argv[1], 'r+b') as f:
    f.seek(4096); b = f.read(1); f.seek(4096); f.write(bytes([b[0] ^ 0xFF]))
EOF

if out=$(dart run bin/probe.dart 2>&1); then fail "tampered binary still built and ran"; fi
grep -q 'SHA-256 mismatch' <<<"$out" || fail "tampered build failed, but not on the hash check:\n$out"
echo "test_tamper: tampered build fails with SHA-256 mismatch"
echo "test_tamper: PASS"
