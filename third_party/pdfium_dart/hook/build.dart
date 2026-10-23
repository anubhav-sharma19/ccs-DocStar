import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

// DocStar fork: PDFium is vendored in the repo and hash-pinned. No download.
const _pdfiumRelease = 'chromium-7811';
const _assetName = 'libpdfium';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    // Process-wide PDFium gate: a tiny dylib whose statics are shared across
    // Flutter engines in one OS process. Built on every platform, including iOS
    // (where libpdfium itself comes from pdfium_flutter's XCFramework).
    await CBuilder.library(
      name: 'pdfrx_pdfium_gate',
      packageName: input.packageName,
      assetName: 'src/pdfrx_pdfium_gate.dart',
      sources: ['src/pdfrx_pdfium_gate.c'],
    ).run(input: input, output: output);

    if (input.config.code.targetOS == OS.iOS) return;

    final target = _PdfiumTarget.fromCodeConfig(input.config.code);
    final vendorDir = input.packageRoot.resolve('../pdfium/$_pdfiumRelease/');
    final relPath =
        '${target.archivePlatform}-${target.archiveArch}/${target.libraryFileName}';
    final source = File.fromUri(vendorDir.resolve(relPath));
    final sums = File.fromUri(vendorDir.resolve('SHA256SUMS'));
    output.dependencies
      ..add(source.uri)
      ..add(sums.uri);

    final outputFile = input.outputDirectory.resolve(target.libraryFileName);
    await File.fromUri(outputFile).writeAsBytes(_verifiedPdfium(source, sums, relPath));

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: outputFile,
      ),
    );
  });
}

/// Returns the vendored binary's bytes, or throws (failing the build) if it is
/// missing, not listed in SHA256SUMS, or its SHA-256 does not match.
List<int> _verifiedPdfium(File source, File sums, String relPath) {
  if (!sums.existsSync()) throw Exception('PDFium SHA256SUMS missing: ${sums.path}');
  final expected = sums
      .readAsLinesSync()
      .map((l) => l.split(RegExp(r'\s+\*?')))
      .where((f) => f.length == 2 && f[1] == relPath)
      .map((f) => f[0].toLowerCase())
      .firstOrNull;
  if (expected == null) {
    throw Exception('PDFium not vendored for this target: $relPath is not in ${sums.path}');
  }
  if (!source.existsSync()) throw Exception('PDFium binary missing: ${source.path}');
  final bytes = source.readAsBytesSync();
  final actual = sha256.convert(bytes).toString();
  if (actual != expected) {
    throw Exception('PDFium SHA-256 mismatch for $relPath: expected $expected, got $actual');
  }
  return bytes;
}

final class _PdfiumTarget {
  const _PdfiumTarget({
    required this.archivePlatform,
    required this.archiveArch,
    required this.archiveLibraryPath,
    required this.libraryFileName,
  });

  final String archivePlatform;
  final String archiveArch;
  final String archiveLibraryPath;
  final String libraryFileName;

  static _PdfiumTarget fromCodeConfig(CodeConfig config) {
    final arch = switch (config.targetArchitecture) {
      Architecture.ia32 => 'x86',
      Architecture.x64 => 'x64',
      Architecture.arm => 'arm',
      Architecture.arm64 => 'arm64',
      _ => throw UnsupportedError(
        'Unsupported PDFium architecture: ${config.targetArchitecture}',
      ),
    };

    return switch (config.targetOS) {
      OS.android => _PdfiumTarget(
        archivePlatform: 'android',
        archiveArch: arch,
        archiveLibraryPath: 'lib/libpdfium.so',
        libraryFileName: 'libpdfium.so',
      ),
      OS.windows => _PdfiumTarget(
        archivePlatform: 'win',
        archiveArch: arch,
        archiveLibraryPath: 'bin/pdfium.dll',
        libraryFileName: 'pdfium.dll',
      ),
      OS.linux => _PdfiumTarget(
        archivePlatform: 'linux',
        archiveArch: arch,
        archiveLibraryPath: 'lib/libpdfium.so',
        libraryFileName: 'libpdfium.so',
      ),
      OS.macOS => _PdfiumTarget(
        archivePlatform: 'mac',
        archiveArch: arch,
        archiveLibraryPath: 'lib/libpdfium.dylib',
        libraryFileName: 'libpdfium.dylib',
      ),
      _ => throw UnsupportedError(
        'Unsupported PDFium platform: ${config.targetOS}',
      ),
    };
  }
}
