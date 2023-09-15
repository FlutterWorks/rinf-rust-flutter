import 'dart:io';
import 'package:package_config/package_config.dart';
import 'dart:convert';

Future<void> main(List<String> args) async {
  if (args.length == 0) {
    print("No operation is provided");
  } else if (args[0] == "template") {
    await _applyRustTemplate();
  } else if (args[0] == "message") {
    await _generateMessageCode();
  } else if (args[0] == "wasm") {
    if (args.contains("--release") || args.contains("-r")) {
      await _buildWebassembly(isReleaseMode: true);
    } else {
      await _buildWebassembly(isReleaseMode: false);
    }
  } else {
    print("No available operation is provided");
  }
}

/// Creates new folders and files to an existing Flutter project folder.
Future<void> _applyRustTemplate() async {
  // Get the path of the current project directory
  final flutterProjectPath = Directory.current.path;

  // Get the package directory path
  final packageConfig = await findPackageConfig(Directory.current);
  if (packageConfig == null) {
    return;
  }
  final packageName = 'rust_in_flutter';
  final package = packageConfig.packages.firstWhere(
    (p) => p.name == packageName,
  );
  final packagePath = package.root.toFilePath();

  // Check if current folder is a Flutter project.
  final mainFile = File('$flutterProjectPath/lib/main.dart');
  final isFlutterProject = await mainFile.exists();
  if (!isFlutterProject) {
    print("\nThis folder doesn't look like a Flutter project. Aborting...\n");
    return;
  }

  // Copy basic folders needed for Rust to work
  final templateSource = Directory('$packagePath/example/native');
  final templateDestination = Directory('$flutterProjectPath/native');
  await _copyDirectory(templateSource, templateDestination);
  final messagesSource = Directory('$packagePath/example/messages');
  final messagesDestination = Directory('$flutterProjectPath/messages');
  await _copyDirectory(messagesSource, messagesDestination);

  // Copy `Cargo.toml`
  final cargoSource = File('$packagePath/example/Cargo.toml');
  final cargoDestination = File('$flutterProjectPath/Cargo.toml');
  await cargoSource.copy(cargoDestination.path);

  // Create `.cargo/config.toml` file
  final cargoConfigFile = File('$flutterProjectPath/.cargo/config.toml');
  if (!(await cargoConfigFile.exists())) {
    await cargoConfigFile.create(recursive: true);
  }
  const cargoConfigContent = '''
[build]
# Uncomment the line below to switch Rust-analyzer to perform
# type checking and linting in webassembly mode, for the web target.
# You might have to restart Rust-analyzer for this change to take effect.
# target = "wasm32-unknown-unknown"
''';
  await cargoConfigFile.writeAsString(cargoConfigContent);

  // Add some lines to `.gitignore`
  final rustSectionTitle = '# Rust related';
  final messageSectionTitle = '# Generated messages';
  final gitignoreFile = File('$flutterProjectPath/.gitignore');
  if (!(await gitignoreFile.exists())) {
    await gitignoreFile.create(recursive: true);
  }
  final gitignoreContent = await gitignoreFile.readAsString();
  var gitignoreSplitted = gitignoreContent.split('\n\n');
  gitignoreSplitted = gitignoreSplitted.map((s) => s.trim()).toList();
  if (!gitignoreContent.contains(rustSectionTitle)) {
    var text = rustSectionTitle;
    text += '\n' + '.cargo/';
    text += '\n' + 'target/';
    gitignoreSplitted.add(text);
  }
  if (!gitignoreContent.contains(messageSectionTitle)) {
    var text = messageSectionTitle;
    text += '\n' + '*/**/messages/';
    gitignoreSplitted.add(text);
  }
  await gitignoreFile.writeAsString(gitignoreSplitted.join('\n\n') + '\n');

  // Add some guides to `README.md`
  final guideSectionTitle = '## Using Rust Inside Flutter';
  final readmeFile = File('$flutterProjectPath/README.md');
  if (!(await readmeFile.exists())) {
    await readmeFile.create(recursive: true);
  }
  final readmeContent = await readmeFile.readAsString();
  var readmeSplitted = readmeContent.split('\n\n');
  readmeSplitted = readmeSplitted.map((s) => s.trim()).toList();
  if (!readmeContent.contains(guideSectionTitle)) {
    final text = '''
$guideSectionTitle

This project leverages Flutter for GUI and Rust for the backend logic,
utilizing the capabilities of the
[Rust-In-Flutter](https://pub.dev/packages/rust_in_flutter) framework.

To run and build this app, you need to have
[Flutter SDK](https://docs.flutter.dev/get-started/install),
[Rust toolchain](https://www.rust-lang.org/tools/install),
and [FlatBuffers compiler](https://github.com/google/flatbuffers/releases)
installed on your system.
You can check that your system is ready with the commands below.
Note that all the Flutter subcomponents should be installed.

```bash
rustc --version
flatc --version
flutter doctor
```

Also, please install the CLI tool for Rust-In-Flutter

```bash
cargo install rifs
```

Messages sent between Dart and Rust are implemented using Protobuf.
If you have newly cloned the project repository
or made changes to the `.fbs` files in the `./messages` directory,
run the following command:

```bash
rifs message
```

For detailed instructions on writing Rust and Flutter together,
please refer to Rust-In-Flutter's [documentation](https://docs.cunarist.com/rust-in-flutter).
''';
    readmeSplitted.add(text);
  }
  await readmeFile.writeAsString(readmeSplitted.join('\n\n') + '\n');

  // Add Dart dependencies
  await Process.run('dart', ['pub', 'add', 'flat_buffers']);

  // Modify `./lib/main.dart`
  await Process.run('dart', ['format', './lib/main.dart']);
  var mainText = await mainFile.readAsString();
  if (!mainText.contains('package:rust_in_flutter/rust_in_flutter.dart')) {
    final lines = mainText.split("\n");
    final lastImportIndex = lines.lastIndexWhere(
      (line) => line.startsWith('import '),
    );
    lines.insert(
      lastImportIndex + 1,
      "import 'package:rust_in_flutter/rust_in_flutter.dart';",
    );
    mainText = lines.join("\n");
  }
  if (mainText.contains('main() {')) {
    mainText = mainText.replaceFirst(
      'main() {',
      'main() async {',
    );
  }
  if (!mainText.contains('RustInFlutter.ensureInitialized()')) {
    mainText = mainText.replaceFirst(
      'main() async {',
      'main() async { await RustInFlutter.ensureInitialized();',
    );
  }
  await mainFile.writeAsString(mainText);
  await Process.run('dart', ['format', './lib/main.dart']);

  print("🎉 Rust template is now ready! 🎉");
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  final newDirectory = Directory(destination.path);
  await newDirectory.create();
  await source.list(recursive: false).forEach(
    (entity) async {
      if (entity is Directory) {
        final newDirectory = Directory(
          '${destination.uri.path}/${Uri.file(entity.path).pathSegments.last}',
        );
        await newDirectory.create();
        _copyDirectory(entity.absolute, newDirectory);
      } else if (entity is File) {
        await entity.copy(
          '${destination.uri.path}/${Uri.file(entity.path).pathSegments.last}',
        );
      }
    },
  );
}

Future<void> _buildWebassembly({bool isReleaseMode = false}) async {
  // Verify Rust toolchain.
  print("Verifying Rust toolchain for the web." +
      " This might take a while if there are new updates to be installed.");
  await Process.run("rustup", ["toolchain", "install", "nightly"]);
  await Process.run("rustup", [
    "+nightly",
    "component",
    "add",
    "rust-src",
  ]);
  await Process.run("rustup", [
    "+nightly",
    "target",
    "add",
    "wasm32-unknown-unknown",
  ]); // For actual compilation
  await Process.run("rustup", [
    "target",
    "add",
    "wasm32-unknown-unknown",
  ]); // For Rust-analyzer
  await Process.run("cargo", ["install", "wasm-pack"]);
  await Process.run("cargo", ["install", "wasm-bindgen-cli"]);

  // Verify Flutter SDK web server's response headers.
  await _verifyServerHeaders();

  // Prepare the webassembly output path.
  final flutterProjectPath = Directory.current;
  final wasmOutputPath = flutterProjectPath.uri.resolve('web/pkg').toFilePath();

  // Build the webassembly module.
  print("Compiling Rust...");
  await _compile(
    crateDir: './native/hub',
    wasmOutput: wasmOutputPath,
    isReleaseMode: isReleaseMode,
  );

  print("🎉 Webassembly module is now ready! 🎉");
}

Future<void> _verifyServerHeaders() async {
  // Get the Flutter SDK's path.
  String flutterPath;
  if (Platform.isWindows) {
    // Windows
    final whereFlutterResult = await Process.run('where', ['flutter']);
    flutterPath = (whereFlutterResult.stdout as String).split('\n').first;
  } else {
    // macOS and Linux
    final whichFlutterResult = await Process.run('which', ['flutter']);
    flutterPath = whichFlutterResult.stdout as String;
  }
  flutterPath = flutterPath.trim();
  flutterPath = await File(flutterPath).resolveSymbolicLinks();
  flutterPath = File(flutterPath).parent.parent.path;

  // Get the server module file's path.
  final serverFile = File(
      '$flutterPath/packages/flutter_tools/lib/src/isolated/devfs_web.dart');
  var serverFileContent = await serverFile.readAsString();

  // Check if the server already includes cross-origin HTTP headers.
  if (serverFileContent.contains('cross-origin-opener-policy')) {
    return;
  }

  // Add the HTTP header code to the server file.
  final lines = serverFileContent.split('\n');
  final serverDeclaredIndex = lines.lastIndexWhere(
    (line) => line.contains('httpServer = await'),
  );
  lines.insert(serverDeclaredIndex + 1, """
httpServer.defaultResponseHeaders.add(
  'cross-origin-opener-policy',
  'same-origin',
);
httpServer.defaultResponseHeaders.add(
  'cross-origin-embedder-policy',
  'credentialless',
);""");
  serverFileContent = lines.join("\n");
  await serverFile.writeAsString(serverFileContent);

  // Remove the stamp file to make it re-generated.
  final flutterToolsStampPath = '$flutterPath/bin/cache/flutter_tools.stamp';
  if (await File(flutterToolsStampPath).exists()) {
    await File(flutterToolsStampPath).delete();
  }
}

Future<void> _compile({
  required String crateDir,
  required String wasmOutput,
  required bool isReleaseMode,
}) async {
  final String crateName = 'hub';
  await _runAdvancedCommand(
    'wasm-pack',
    [
      '--quiet',
      'build', '-t', 'no-modules', '-d', wasmOutput, '--no-typescript',
      '--out-name', crateName,
      if (!isReleaseMode) '--dev', crateDir,
      '--', // cargo build args
      '-Z', 'build-std=std,panic_abort',
    ],
    env: {
      'RUSTUP_TOOLCHAIN': 'nightly',
      'RUSTFLAGS': '-C target-feature=+atomics,+bulk-memory,+mutable-globals',
      if (stdout.supportsAnsiEscapes) 'CARGO_TERM_COLOR': 'always',
    },
  );
}

Future<void> _runAdvancedCommand(
  String command,
  List<String> arguments, {
  Map<String, String>? env,
  bool silent = false,
}) async {
  final process = await Process.start(
    command,
    arguments,
    environment: env,
  );
  final processOutput = <String>[];
  process.stderr.transform(utf8.decoder).listen((line) {
    if (!silent) stderr.write(line);
    processOutput.add(line);
  });
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(
        command, arguments, processOutput.join(''), exitCode);
  }
}

Future<void> _generateMessageCode() async {
  // Prepare paths.
  final flutterProjectPath = Directory.current;
  final messagePath = flutterProjectPath.uri.resolve('messages').toFilePath();
  final rustOutputPath =
      flutterProjectPath.uri.resolve('native/hub/src/messages').toFilePath();
  final dartOutputPath =
      flutterProjectPath.uri.resolve('lib/messages').toFilePath();
  await Directory(rustOutputPath).create(recursive: true);
  await _emptyDirectory(rustOutputPath);
  await Directory(dartOutputPath).create(recursive: true);
  await _emptyDirectory(dartOutputPath);

  // Get the list of `.fbs` files.
  final Stream<FileSystemEntity> messageEntityStream =
      Directory(messagePath).list();
  final List<String> resourceNames = [];
  await for (final entity in messageEntityStream) {
    if (entity is File) {
      final filename = entity.uri.pathSegments.last;
      final parts = filename.split('.');
      parts.removeLast(); // Remove the extension from the filename.
      final fileNameWithoutExtension = parts.join('.');
      if (filename.endsWith('.fbs')) {
        resourceNames.add(fileNameWithoutExtension);
      }
    }
  }

  // Generate Rust message files.
  final rustGenerationResult = await Process.run('flatc', [
    '--rust',
    '-o',
    rustOutputPath,
    '--filename-suffix',
    '',
    ...resourceNames.map((item) => 'messages/$item.fbs').toList(),
  ]);
  if (rustGenerationResult.exitCode != 0) {
    throw Exception('Could not compile `.fbs` files into Rust');
  }
  resourceNames.asMap().forEach((index, rustResourceName) {
    _appendLineToFile(
      'native/hub/src/messages/$rustResourceName.rs',
      'pub const ID: i32 = $index;',
    );
  });

  // Replace `unsafe fn` with `fn` in Rust code.
  final files = Directory(rustOutputPath).listSync();
  for (final file in files) {
    if (file is File) {
      final fileContent = file.readAsStringSync();
      final modifiedContent = fileContent.replaceAll('unsafe fn', 'fn');
      file.writeAsStringSync(modifiedContent);
    }
  }

  // Generate `mod.rs` for `messages` module in Rust.
  final modRsLines = resourceNames.map((resourceName) async {
    return 'pub mod $resourceName;';
  });
  final modRsContent = (await Future.wait(modRsLines)).join('\n');
  await File('$rustOutputPath/mod.rs').writeAsString(modRsContent);

  // Generate Dart message files.
  final dartGenerationResult = await Process.run('flatc', [
    '--dart',
    '-o',
    dartOutputPath,
    '--filename-suffix',
    '',
    ...resourceNames.map((item) => 'messages/$item.fbs').toList(),
  ]);
  if (dartGenerationResult.exitCode != 0) {
    throw Exception('Could not compile `.fbs` files into Rust');
  }
  resourceNames.asMap().forEach((index, rustResourceName) {
    _appendLineToFile(
      'lib/messages/$rustResourceName.dart',
      'const ID = $index;',
    );
  });

  // Notify that it's done
  print("🎉 Message code in Dart and Rust is now ready! 🎉");
}

Future<void> _emptyDirectory(String directoryPath) async {
  final directory = Directory(directoryPath);

  if (await directory.exists()) {
    await for (final entity in directory.list()) {
      if (entity is File) {
        await entity.delete();
      } else if (entity is Directory) {
        await entity.delete(recursive: true);
      }
    }
  }
}

Future<void> _appendLineToFile(String filePath, String textToAppend) async {
  // Read the existing content of the file
  final file = File(filePath);
  if (!(await file.exists())) {
    await file.create(recursive: true);
  }
  String fileContent = await file.readAsString();

  // Append the new text to the existing content
  fileContent += '\n';
  fileContent += textToAppend;

  // Write the updated content back to the file
  await file.writeAsString(fileContent);
}
