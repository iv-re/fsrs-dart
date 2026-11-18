import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  final runner = CommandRunner<void>('fsrs_build', 'fsrs_dart build tool')
    ..addCommand(BuildCommand())
    ..addCommand(HashCommand())
    ..addCommand(CollectCommand())
    ..addCommand(ListCommand())
    ..addCommand(TrimCommand());

  try {
    await runner.run(args);
  } catch (e) {
    stderr.writeln(e);
    exit(1);
  }
}

class BuildConfig {
  BuildConfig({required this.name, required this.options});

  final String name;
  final Map<String, dynamic> options;

  String get targetOs => options['target_os'] as String;
  String get targetCpu => options['target_cpu'] as String;
  String get rustTarget => options['rust_target'] as String;

  static List<BuildConfig> loadAll() {
    final configFile = File('tool/build_config.json');
    if (!configFile.existsSync()) return [];
    final json = configFile.readAsStringSync();
    final configData = jsonDecode(json) as Map<String, dynamic>;
    return configData.entries
        .map(
          (e) => BuildConfig(
            name: e.key,
            options: e.value as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  static List<BuildConfig> loadLocal() {
    return loadAll().where((config) {
      if (config.targetOs == 'android') return true;
      if (Platform.isMacOS) {
        return config.targetOs == 'macos' || config.targetOs == 'ios';
      }
      if (Platform.isWindows) return config.targetOs == 'windows';
      if (Platform.isLinux) return config.targetOs == 'linux';
      return false;
    }).toList();
  }
}

class BuildCommand extends Command<void> {
  BuildCommand() {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Config name from build_config.json',
        allowed: BuildConfig.loadAll().map((e) => e.name),
      )
      ..addOption(
        'ndk',
        help: 'Path to Android NDK',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enable verbose output',
        negatable: false,
      );
  }

  @override
  final String name = 'build';

  @override
  final String description = 'Build fsrs_dart for a specific configuration.';

  @override
  Future<void> run() async {
    final results = argResults;
    final configName = results?['config'] as String?;
    if (configName == null) {
      stdout.writeln('Available configurations:');
      for (final c in BuildConfig.loadAll()) {
        stdout.writeln(
          '  ${c.name} (${c.targetOs}/${c.targetCpu}) -> ${c.rustTarget}',
        );
      }
      return;
    }

    final config = BuildConfig.loadAll().firstWhere(
      (e) => e.name == configName,
      orElse: () => throw Exception('Unknown config: $configName'),
    );

    final buildDir = p.canonicalize('build_${config.name}');
    final buildDirObj = Directory(buildDir);
    if (!buildDirObj.existsSync()) {
      buildDirObj.createSync(recursive: true);
    }

    stdout.writeln('--- Building ${config.name} (${config.rustTarget}) ---');

    final verbose = results?['verbose'] as bool? ?? false;
    final isAndroid = config.targetOs == 'android';

    final Process process;
    if (isAndroid) {
      // For Android, prefer cargo-ndk
      final ndkPath =
          results?['ndk'] as String? ??
          Platform.environment['ANDROID_NDK_HOME'] ??
          _detectLocalNdk();
      if (ndkPath == null) {
        throw Exception(
          'Android NDK not found. Pass --ndk or set ANDROID_NDK_HOME.',
        );
      }

      final androidTargetMap = {
        'arm64': 'arm64-v8a',
        'arm': 'armeabi-v7a',
        'x64': 'x86_64',
        'x86': 'x86',
      };
      final androidArch =
          androidTargetMap[config.targetCpu] ?? config.targetCpu;

      process = await Process.start(
        'cargo',
        [
          'ndk',
          '-t',
          androidArch,
          '--platform',
          '21',
          'build',
          '--release',
          if (verbose) '-v',
        ],
        workingDirectory: 'src',
        environment: {
          ...Platform.environment,
          'ANDROID_NDK_HOME': ndkPath,
          'ANDROID_NDK_ROOT': ndkPath,
        },
      );
    } else {
      process = await Process.start(
        'cargo',
        [
          'build',
          '--release',
          '--target',
          config.rustTarget,
          '--manifest-path',
          'src/Cargo.toml',
          if (verbose) '-v',
        ],
      );
    }

    process.stdout.transform(utf8.decoder).listen(stdout.write);
    process.stderr.transform(utf8.decoder).listen(stderr.write);

    if (await process.exitCode != 0) {
      throw Exception('Cargo build failed for ${config.name}');
    }

    // Copy built artifact to build_${config.name}/
    final libName = getLibName(config.targetOs);
    final srcTargetDir = Directory('src/target/${config.rustTarget}/release');

    var builtFile = File(p.join(srcTargetDir.path, libName));
    if (!builtFile.existsSync()) {
      // Fallback check in root target dir
      builtFile = File(p.join('target', config.rustTarget, 'release', libName));
    }

    if (!builtFile.existsSync()) {
      throw Exception('Built binary not found: ${builtFile.path}');
    }

    final destFile = File(p.join(buildDir, libName));
    await builtFile.copy(destFile.path);

    stdout.writeln(
      '--- Successfully built ${config.name}: ${destFile.path} ---',
    );
  }
}

class HashCommand extends Command<void> {
  HashCommand() {
    argParser.addFlag(
      'verify',
      help: 'Check if current hash matches state',
      negatable: false,
    );
  }

  @override
  final String name = 'hash';

  @override
  final String description = 'Generate or verify the fsrs_hash.';

  @override
  void run() {
    final workspaceRoot = Directory.current.path;
    final expectedHash = _generateHash(workspaceRoot);

    if (argResults?['verify'] as bool? ?? false) {
      final hashFile = File('fsrs_hash');
      if (!hashFile.existsSync()) throw Exception('fsrs_hash file missing');
      final actualHash = hashFile.readAsStringSync().trim();
      if (expectedHash != actualHash) {
        throw Exception(
          'fsrs_hash is out of date! Expected: $expectedHash, Got: $actualHash',
        );
      }
      stdout.writeln('fsrs_hash is up to date.');
    } else {
      File('fsrs_hash').writeAsStringSync(expectedHash);
      stdout.writeln('Generated fsrs_hash: $expectedHash');
    }
  }

  String _generateHash(String root) {
    String gitHash(String obj) {
      final res = Process.runSync(
        'git',
        ['rev-parse', obj],
        workingDirectory: root,
      );
      return res.exitCode == 0 ? (res.stdout as String).trim() : 'unknown';
    }

    final headSrc = gitHash('HEAD:src');
    if (headSrc != 'unknown') {
      return sha1.convert(utf8.encode(headSrc)).toString();
    }

    // Fallback if repository has no commits yet: hash directory files
    final srcDir = Directory(p.join(root, 'src'));
    final files =
        srcDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => !f.path.contains('/target/'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final bytes = <int>[];
    for (final f in files) {
      bytes.addAll(utf8.encode(p.relative(f.path, from: root)));
      bytes.addAll(f.readAsBytesSync());
    }
    return sha1.convert(bytes).toString();
  }
}

class CollectCommand extends Command<void> {
  @override
  final String name = 'collect';

  @override
  final String description =
      'Collect all built binaries and update prebuilt_hashes.json.';

  @override
  Future<void> run() async {
    final configs = BuildConfig.loadAll();
    final hashes = <String, String>{};

    final releaseAssetsDir = Directory('release_assets');
    if (releaseAssetsDir.existsSync()) {
      releaseAssetsDir.deleteSync(recursive: true);
    }
    releaseAssetsDir.createSync();

    for (final config in configs) {
      final buildDir = Directory('build_${config.name}');
      if (!buildDir.existsSync()) continue;

      final libName = getLibName(config.targetOs);
      final libFile = File(p.join(buildDir.path, libName));

      if (libFile.existsSync()) {
        final bytes = await libFile.readAsBytes();
        final hash = sha256.convert(bytes).toString();
        final assetName = '${config.name}_$libName';
        hashes[assetName] = hash;
        await libFile.copy(p.join(releaseAssetsDir.path, assetName));
        stdout.writeln('Collected: $assetName');
      }
    }

    final hashesFile = File('prebuilt_hashes.json');
    const encoder = JsonEncoder.withIndent('  ');
    hashesFile.writeAsStringSync('${encoder.convert(hashes)}\n');

    stdout.writeln(
      'Updated prebuilt_hashes.json with ${hashes.length} entries.',
    );
  }
}

class ListCommand extends Command<void> {
  ListCommand() {
    argParser.addFlag('local', help: 'Only local platforms', negatable: false);
  }

  @override
  final String name = 'list';

  @override
  final String description = 'List configurations.';

  @override
  void run() {
    final results = argResults;
    final configs = (results?['local'] as bool? ?? false)
        ? BuildConfig.loadLocal()
        : BuildConfig.loadAll();

    for (final c in configs) {
      stdout.writeln(
        '${c.name} (${c.targetOs}/${c.targetCpu}) -> ${c.rustTarget}',
      );
    }
  }
}

class TrimCommand extends Command<void> {
  @override
  final String name = 'trim';

  @override
  final String description = 'Remove all artifacts except the final binary.';

  @override
  Future<void> run() async {
    final configs = BuildConfig.loadAll();
    for (final config in configs) {
      final buildDir = Directory('build_${config.name}');
      if (!buildDir.existsSync()) continue;
      await _trimDirectory(config, buildDir);
    }
    stdout.writeln('--- Aggressive trim complete ---');
  }

  Future<void> _trimDirectory(BuildConfig config, Directory dir) async {
    final libName = getLibName(config.targetOs);
    final libFile = File(p.join(dir.path, libName));

    if (!libFile.existsSync()) {
      stdout.writeln('Notice: Binary not found in ${dir.path}, skipping trim.');
      return;
    }

    final bytes = await libFile.readAsBytes();
    dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final finalFile = File(p.join(dir.path, libName));
    await finalFile.writeAsBytes(bytes);
    stdout.writeln('Trimmed to 1 file: ${finalFile.path}');
  }
}

String getLibName(String os) {
  return switch (os) {
    'macos' || 'ios' => 'libfsrs_dart.dylib',
    'windows' => 'fsrs_dart.dll',
    _ => 'libfsrs_dart.so',
  };
}

String? _detectLocalNdk() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null) return null;

  if (Platform.isMacOS) {
    final ndkDir = Directory(p.join(home, 'Library/Android/sdk/ndk'));
    if (ndkDir.existsSync()) {
      final versions = ndkDir.listSync().whereType<Directory>().toList();
      if (versions.isNotEmpty) {
        versions.sort(
          (a, b) => p.basename(b.path).compareTo(p.basename(a.path)),
        );
        return versions.first.path;
      }
    }
    final bundleDir = Directory(p.join(home, 'Library/Android/sdk/ndk-bundle'));
    if (bundleDir.existsSync()) return bundleDir.path;
  } else if (Platform.isLinux) {
    final ndkDir = Directory(p.join(home, 'Android/Sdk/ndk'));
    if (ndkDir.existsSync()) {
      final versions = ndkDir.listSync().whereType<Directory>().toList();
      if (versions.isNotEmpty) {
        versions.sort(
          (a, b) => p.basename(b.path).compareTo(p.basename(a.path)),
        );
        return versions.first.path;
      }
    }
    final bundleDir = Directory(p.join(home, 'Android/Sdk/ndk-bundle'));
    if (bundleDir.existsSync()) return bundleDir.path;
  }
  return null;
}
