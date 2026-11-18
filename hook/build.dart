import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final configuration = _tryGetConfiguration(input);
    final dylibName = _getLibName(input.config.code.targetOS);

    if (configuration != null) {
      final localBuildDir = input.packageRoot.resolve('build_$configuration/');
      var localLib = File.fromUri(localBuildDir.resolve(dylibName));
      if (!localLib.existsSync()) {
        localLib = File.fromUri(localBuildDir.resolve('Release/$dylibName'));
      }

      if (localLib.existsSync()) {
        output.dependencies.add(localLib.uri);
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: '${input.packageName}.dart',
            linkMode: DynamicLoadingBundled(),
            file: localLib.uri,
          ),
        );
        return;
      }

      // Try prebuilt download if available
      final prebuiltUri = await _tryDownloadPrebuiltBinary(
        input: input,
        output: output,
        configuration: configuration,
        dylibName: dylibName,
      );
      if (prebuiltUri != null) {
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: '${input.packageName}.dart',
            linkMode: DynamicLoadingBundled(),
            file: prebuiltUri,
          ),
        );
        return;
      }
    }

    // Fallback: compile on the fly with native_toolchain_rust
    await const RustBuilder(
      assetName: 'fsrs_dart.dart',
      cratePath: 'src',
    ).run(input: input, output: output);
  });
}

const _releaseBaseUrl = 'https://github.com/iv-re/fsrs-dart/releases/download';

Future<Uri?> _tryDownloadPrebuiltBinary({
  required BuildInput input,
  required BuildOutputBuilder output,
  required String configuration,
  required String dylibName,
}) async {
  final hashFile = File.fromUri(input.packageRoot.resolve('fsrs_hash'));
  final hashesFile = File.fromUri(
    input.packageRoot.resolve('prebuilt_hashes.json'),
  );
  if (hashFile.existsSync()) output.dependencies.add(hashFile.uri);
  if (hashesFile.existsSync()) output.dependencies.add(hashesFile.uri);
  if (!hashFile.existsSync() || !hashesFile.existsSync()) return null;

  File? tmpFile;
  IOSink? fileSink;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  try {
    final hash = hashFile.readAsStringSync().trim();
    if (hash.isEmpty) return null;

    final hashes =
        jsonDecode(hashesFile.readAsStringSync()) as Map<String, dynamic>;
    final downloadFileName = '${configuration}_$dylibName';
    final expectedSha256 = hashes[downloadFileName] as String?;
    if (expectedSha256 == null) return null;

    final cacheDir = Directory.fromUri(
      // Per configuration: the shared directory is shared across targets, and
      // a simulator build fetches arm64 and x64, which must not overwrite
      // each other before lipo joins them.
      input.outputDirectoryShared.resolve(
        'prebuilt_cache/$hash/$configuration/',
      ),
    );
    await cacheDir.create(recursive: true);

    final cachedFile = File.fromUri(cacheDir.uri.resolve(dylibName));
    if (cachedFile.existsSync()) return cachedFile.uri;

    final downloadUrl = Uri.parse(
      '$_releaseBaseUrl/fsrs_$hash/$downloadFileName',
    );
    tmpFile = File.fromUri(
      cacheDir.uri.resolve('$dylibName.$pid.tmp'),
    );

    final request = await client
        .getUrl(downloadUrl)
        .timeout(const Duration(seconds: 15));
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      stderr.writeln(
        '[fsrs_dart] Prebuilt binary not available '
        '(HTTP ${response.statusCode} for $downloadFileName), '
        'falling back to Rust build.',
      );
      return null;
    }

    final digestSink = AccumulatorSink<Digest>();
    final hashSink = sha256.startChunkedConversion(digestSink);
    fileSink = tmpFile.openWrite();

    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      hashSink.add(chunk);
      fileSink.add(chunk);
    }
    hashSink.close();
    await fileSink.flush();
    await fileSink.close();
    fileSink = null;

    final downloadedHash = digestSink.events.single.toString();
    if (downloadedHash != expectedSha256) {
      stderr.writeln(
        '[fsrs_dart] SHA-256 mismatch for $downloadFileName '
        '(expected $expectedSha256, got $downloadedHash), '
        'falling back to Rust build.',
      );
      if (tmpFile.existsSync()) await tmpFile.delete();
      return null;
    }

    try {
      await tmpFile.rename(cachedFile.path);
    } on FileSystemException {
      if (cachedFile.existsSync()) {
        if (tmpFile.existsSync()) await tmpFile.delete();
        return cachedFile.uri;
      }
      rethrow;
    }
    return cachedFile.uri;
  } catch (e) {
    stderr.writeln(
      '[fsrs_dart] Prebuilt download failed ($e), falling back to Rust build.',
    );
    try {
      await fileSink?.close();
    } catch (_) {}
    try {
      if (tmpFile != null && tmpFile.existsSync()) {
        await tmpFile.delete();
      }
    } catch (_) {}
    return null;
  } finally {
    client.close();
  }
}

String? _tryGetConfiguration(BuildInput input) {
  final code = input.config.code;
  final platform = switch (code.targetOS) {
    .macOS => 'macos',
    .windows => 'windows',
    .linux => 'linux',
    .android => 'android',
    .iOS => code.iOS.targetSdk == IOSSdk.iPhoneSimulator ? 'ios_sim' : 'ios',
    _ => null,
  };
  if (platform == null) return null;

  final arch = switch (code.targetArchitecture) {
    .x64 => 'x64',
    .arm64 => 'arm64',
    .arm => 'arm',
    .ia32 => 'x86',
    _ => null,
  };
  if (arch == null) return null;

  return '${platform}_$arch';
}

String _getLibName(OS os) => switch (os) {
  .macOS || .iOS => 'libfsrs_dart.dylib',
  .windows => 'fsrs_dart.dll',
  _ => 'libfsrs_dart.so',
};
