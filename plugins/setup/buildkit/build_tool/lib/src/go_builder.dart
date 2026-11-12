import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'build_cache.dart';
import 'error.dart';
import 'fingerprint.dart';
import 'logging.dart';
import 'options.dart';
import 'target.dart';
import 'util.dart';

final _log = Logger('go_builder');

class GoBuilder {
  final String rootDir;
  final BuildConfig config;
  final BuildCache cache;
  final BuildNotice notice;

  GoBuilder({
    required this.rootDir,
    required this.config,
    required this.cache,
    required this.notice,
  });

  String get _corePath => p.join(rootDir, config.coreDir);
  String get _outputPath => p.join(rootDir, config.outputDir);

  Future<BuildExecution> build(Target target, {bool force = false}) async {
    if (target.isLib) {
      throw BuildException(
          'Android Core must be built by the gomobile Gradle task');
    }
    final outDir = p.join(_outputPath, target.platformDir);
    ensureDir(outDir);
    final fileName = '${config.coreName}${target.executableExtension}';
    final outFile = p.join(outDir, fileName);

    return cache.run(
      key: '${target.platformDir}-${target.goarch}-core',
      fingerprint: () => _calculateFingerprint(target),
      primaryOutput: outFile,
      force: force,
      notice: notice,
      build: () async {
        final env = _buildEnvironment(target);
        final args = _buildArguments(target, outFile: outFile);

        _log.info(kDoubleSeparator);
        _log.info(
          'Building Go core: $target',
        );
        _log.info(kSeparator);

        await runCommandStream(
          'go',
          args,
          workingDirectory: _corePath,
          environment: env,
        );

        final outputs = <String>[outFile];
        _log.info('Built: $outFile');
        return outputs;
      },
    );
  }

  Future<List<BuildExecution>> buildAll(
    List<Target> targets, {
    bool force = false,
  }) async {
    final results = await Future.wait(
      targets.map((target) => build(target, force: force)),
    );
    return results;
  }

  Map<String, String> _buildEnvironment(Target target) => {
        'GOOS': target.goos,
        'GOARCH': target.goarch,
        'CGO_ENABLED': '0',
      };

  List<String> _buildArguments(Target target, {String? outFile}) => [
        'build',
        '-ldflags=${config.goLdflags}',
        '-tags=${config.tags}',
        if (outFile != null) ...['-o', outFile],
        './cmd/core',
      ];

  Future<String> _calculateFingerprint(Target target) async {
    final env = _buildEnvironment(target);
    final builder = FingerprintBuilder(rootDir: rootDir)
      ..addValue('cache_schema', BuildCache.schemaVersion)
      ..addValue('kind', 'go-core')
      ..addValue('target', {
        'goos': target.goos,
        'goarch': target.goarch,
        'abi': target.abi,
        'is_lib': target.isLib,
        'flutter_platform': target.flutterPlatform,
      })
      ..addValue('config', config.toFingerprintMap())
      ..addValue('environment', env)
      ..addValue('arguments', _buildArguments(target));

    final goVersion = runCommand(
      'go',
      ['version'],
      workingDirectory: _corePath,
      environment: env,
    );
    builder.addValue('go_version', (goVersion.stdout as String).trim());

    final goEnvResult = runCommand(
      'go',
      [
        'env',
        '-json',
        'GOVERSION',
        'GOTOOLCHAIN',
        'GOFLAGS',
        'GOEXPERIMENT',
        'GOAMD64',
        'GOARM',
        'GO386',
        'GOMIPS',
        'GOMIPS64',
        'CGO_CFLAGS',
        'CGO_CPPFLAGS',
        'CGO_CXXFLAGS',
        'CGO_LDFLAGS',
        'GOWORK',
        'GOENV',
      ],
      workingDirectory: _corePath,
      environment: env,
    );
    final goEnvText = (goEnvResult.stdout as String).trim();
    builder.addValue('go_env', jsonDecode(goEnvText));

    final inputs = _resolveGoInputs(env);
    final goEnv = jsonDecode(goEnvText) as Map<String, dynamic>;
    final goWork = goEnv['GOWORK'];
    if (goWork is String && goWork.isNotEmpty && goWork != 'off') {
      inputs.add(goWork);
      final goWorkSum = p.join(p.dirname(goWork), 'go.work.sum');
      if (File(goWorkSum).existsSync()) inputs.add(goWorkSum);
    }
    inputs.addAll(collectBuildToolInputs(rootDir));

    builder.addFiles(inputs);
    return builder.finish();
  }

  Set<String> _resolveGoInputs(Map<String, String> environment) {
    const template =
        r'''{{range .GoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CgoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CXXFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .MFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .HFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .FFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SwigFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SwigCXXFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SysoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .EmbedFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{with .Module}}{{if .GoMod}}{{.GoMod}}{{"\n"}}{{end}}{{end}}''';
    final result = runCommand(
      'go',
      ['list', '-deps', '-tags=${config.tags}', '-f', template, './cmd/core'],
      workingDirectory: _corePath,
      environment: environment,
    );
    final corePath = p.normalize(p.absolute(_corePath));
    final inputs = <String>{};
    for (final line in (result.stdout as String).split('\n')) {
      final value = line.trim();
      if (value.isEmpty) continue;
      final filePath = p.normalize(
        p.absolute(p.isAbsolute(value) ? value : p.join(_corePath, value)),
      );
      if (!p.isWithin(corePath, filePath) && !p.equals(corePath, filePath)) {
        continue;
      }
      if (!File(filePath).existsSync()) continue;
      inputs.add(filePath);
      if (p.basename(filePath) == 'go.mod') {
        final goSum = p.join(p.dirname(filePath), 'go.sum');
        if (File(goSum).existsSync()) inputs.add(goSum);
      }
    }

    for (final name in const ['go.mod', 'go.sum']) {
      final filePath = p.join(_corePath, name);
      if (File(filePath).existsSync()) inputs.add(filePath);
    }
    return inputs;
  }
}
