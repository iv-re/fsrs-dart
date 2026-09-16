import 'dart:io';

import 'package:ffigen/ffigen.dart';
import 'package:logging/logging.dart';

FfiGenerator getConfig(Uri packageRoot) {
  return FfiGenerator(
    input: Input(
      entryPoints: [packageRoot.resolve('src/include/fsrs_dart.h')],
      compilerOptions: [
        ...defaultCompilerOpts(Logger('ffigen')),
      ],
    ),
    output: Output(
      dart: DartOutput(path: packageRoot.resolve('lib/fsrs_dart.g.dart')),
      style: const NativeExternalBindings(
        assetId: 'package:fsrs_dart/fsrs_dart.dart',
      ),
    ),
    visitors: [
      Visitor(
        func: (node) {
          node.isIncluded = node.name.startsWith('fsrs_');
        },
        struct: (node) {
          node.isIncluded = node.name.startsWith('fsrs_');
        },
        union: (node) {
          node.isIncluded = node.name.startsWith('fsrs_');
        },
        enumClass: (node) {
          if (node.name.startsWith('fsrs_')) {
            node.isIncluded = true;
            node.silenceWarning = true;
          }
        },
        typealias: (node) {
          node.isIncluded = node.name.startsWith('fsrs_') ? .always : .never;
        },
        global: (node) {
          node.isIncluded = node.name.startsWith('fsrs_');
        },
        macroConstant: (node) {
          node.isIncluded = node.name.startsWith('fsrs_');
        },
        unnamedEnumConstant: (node) {
          node.isIncluded = node.name.startsWith('fsrs_');
        },
      ),
    ],
  );
}

void main() async {
  await getConfig(Platform.script.resolve('../')).generate();
}
