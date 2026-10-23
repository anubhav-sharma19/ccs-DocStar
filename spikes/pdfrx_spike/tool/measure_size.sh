#!/usr/bin/env bash
# APK size with vs without pdfrx (release, arm64 only). Needs JAVA_HOME + ANDROID_HOME set.
# Baseline = same app, same assets, same file_picker/path_provider, minus pdfrx_engine + pdfium_flutter.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
rsync -a --exclude build --exclude .dart_tool --exclude '*.log' "$here/" "$tmp/baseline/"
cd "$tmp/baseline"
sed -i '' '/pdfrx_engine:/d;/pdfium_flutter:/d' pubspec.yaml
rm lib/spike.dart
cat > lib/main.dart <<'EOF'
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(MaterialApp(
    home: Scaffold(
        body: Center(
            child: FilledButton(
                onPressed: () async {
                  await FilePicker.pickFiles();
                  await getTemporaryDirectory();
                },
                child: const Text('baseline'))))));
EOF
flutter pub get >/dev/null
flutter build apk --release --target-platform android-arm64 >/dev/null
base_bytes=$(stat -f%z build/app/outputs/flutter-apk/app-release.apk)
cd "$here"
flutter build apk --release --target-platform android-arm64 >/dev/null
with_bytes=$(stat -f%z build/app/outputs/flutter-apk/app-release.apk)
echo "baseline_bytes=$base_bytes"
echo "with_pdfrx_bytes=$with_bytes"
echo "delta_bytes=$((with_bytes - base_bytes))"
