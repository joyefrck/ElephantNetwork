import 'package:fl_clash/common/local_control.dart';
import 'package:fl_clash/common/apns.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/backup.dart';
import 'package:fl_clash/common/migration.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/config_overrides.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/account/xboard_dns_policy.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

Future<T> decodeJSONTask<T>(String data) async {
  return compute<String, T>(_decodeJSON, data);
}

Future<T> _decodeJSON<T>(String content) async {
  return json.decode(content);
}

Future<String> encodeJSONTask<T>(T data) async {
  return compute<T, String>(_encodeJSON, data);
}

Future<String> _encodeJSON<T>(T content) async {
  return json.encode(content);
}

Future<String> encodeYamlTask<T>(T data) async {
  return compute<T, String>(_encodeYaml, data);
}

Future<String> _encodeYaml<T>(T content) async {
  return yaml.encode(content);
}

Future<String> encodeMD5Task(String data) async {
  return compute<String, String>(_encodeMD5, data);
}

Future<String> _encodeMD5<T>(String content) async {
  return content.toMd5();
}

Future<List<Group>> toGroupsTask(ComputeGroupsState data) async {
  return compute<ComputeGroupsState, List<Group>>(_toGroupsTask, data);
}

Future<List<Group>> _toGroupsTask(ComputeGroupsState state) async {
  final proxiesData = state.proxiesData;
  final all = proxiesData.all;
  final sortType = state.sortType;
  final delayMap = state.delayMap;
  final selectedMap = state.selectedMap;
  final defaultTestUrl = state.defaultTestUrl;
  final proxies = proxiesData.proxies;
  if (proxies.isEmpty) return [];
  final groupsRaw = all
      .where((name) {
        final proxy = proxies[name] ?? {};
        return GroupTypeExtension.valueList.contains(proxy['type']);
      })
      .map((groupName) {
        final group = proxies[groupName];
        group['all'] = ((group['all'] ?? []) as List)
            .map((name) => proxies[name])
            .where((proxy) => proxy != null)
            .toList();
        return group;
      })
      .toList();
  final groups = groupsRaw.map((e) => Group.fromJson(e)).toList();
  return computeSort(
    groups: groups,
    sortType: sortType,
    delayMap: delayMap,
    selectedMap: selectedMap,
    defaultTestUrl: defaultTestUrl,
  );
}

typedef CompiledProfile = ({
  String yaml,
  String md5,
  String structureMd5,
  Map<String, dynamic> runtimeConfig,
});

Future<VM2<String, String>> makeRealProfileTask(
  MakeRealProfileState data,
) async {
  final compiled = await compileProfileTask(data);
  return VM2(compiled.yaml, compiled.md5);
}

Future<CompiledProfile> compileProfileTask(MakeRealProfileState data) =>
    compute<MakeRealProfileState, CompiledProfile>(_compileProfileTask, data);

Future<CompiledProfile> _compileProfileTask(MakeRealProfileState data) async {
  final rawConfig = Map<String, dynamic>.from(data.rawConfig);
  final inherited = captureConfigOverrides(rawConfig);
  final realPatchConfig = data.realPatchConfig;
  final profilesPath = data.profilesPath;
  final profileId = data.profileId;
  final overrideDns = data.overrideDns;
  final addedRules = data.addedRules;
  final appendSystemDns = data.appendSystemDns;
  final defaultUA = data.defaultUA;
  String getProvidersFilePathInner(String type, String url) {
    return join(
      profilesPath,
      'providers',
      profileId.toString(),
      type,
      url.toMd5(),
    );
  }

  rawConfig['external-controller'] = effectiveController(
    realPatchConfig,
    safeMode: data.safeMode,
  ).value;
  rawConfig['secret'] = realPatchConfig.secret;
  for (final endpoint in ['tls', 'unix', 'pipe']) {
    rawConfig['external-controller-$endpoint'] = '';
  }
  rawConfig['authentication'] = data.authentication;
  rawConfig['skip-auth-prefixes'] = <String>[];
  rawConfig['external-ui'] = '';
  rawConfig['interface-name'] = '';
  rawConfig['external-ui-url'] = '';
  rawConfig['tcp-concurrent'] = realPatchConfig.tcpConcurrent;
  rawConfig['unified-delay'] = realPatchConfig.unifiedDelay;
  rawConfig['ipv6'] = realPatchConfig.ipv6;
  rawConfig['log-level'] = realPatchConfig.logLevel.name;
  rawConfig['port'] = 0;
  rawConfig['socks-port'] = 0;
  rawConfig['keep-alive-interval'] = realPatchConfig.keepAliveInterval;
  rawConfig['mixed-port'] = realPatchConfig.mixedPort;
  rawConfig['port'] = realPatchConfig.port;
  rawConfig['socks-port'] = realPatchConfig.socksPort;
  rawConfig['redir-port'] = realPatchConfig.redirPort;
  rawConfig['tproxy-port'] = realPatchConfig.tproxyPort;
  rawConfig['find-process-mode'] = realPatchConfig.findProcessMode.name;
  rawConfig['allow-lan'] = realPatchConfig.allowLan;
  rawConfig['mode'] = realPatchConfig.mode.name;
  if (rawConfig['tun'] == null) {
    rawConfig['tun'] = {};
  }
  rawConfig['tun']['enable'] = realPatchConfig.tun.enable;
  rawConfig['tun']['device'] = realPatchConfig.tun.device;
  rawConfig['tun']['dns-hijack'] = realPatchConfig.tun.dnsHijack;
  rawConfig['tun']['stack'] = realPatchConfig.tun.stack.name;
  rawConfig['tun']['route-address'] = realPatchConfig.tun.routeAddress;
  rawConfig['tun']['auto-route'] = realPatchConfig.tun.autoRoute;
  for (final entry in realPatchConfig.tun.toJson().entries) {
    if (entry.value != null) rawConfig['tun'][entry.key] = entry.value;
  }
  if (system.isDesktop && realPatchConfig.tun.autoRoute) {
    rawConfig['tun']['auto-detect-interface'] ??= true;
  }
  rawConfig['geodata-loader'] = realPatchConfig.geodataLoader.name;
  if (rawConfig['sniffer']?['sniff'] != null) {
    for (final value in (rawConfig['sniffer']?['sniff'] as Map).values) {
      if (value['ports'] != null && value['ports'] is List) {
        value['ports'] =
            value['ports']?.map((item) => item.toString()).toList() ?? [];
      }
    }
  }
  if (rawConfig['profile'] == null) {
    rawConfig['profile'] = {};
  }
  if (rawConfig['proxy-providers'] != null) {
    final proxyProviders = rawConfig['proxy-providers'] as Map;
    for (final key in proxyProviders.keys) {
      final proxyProvider = proxyProviders[key];
      if (proxyProvider['type'] != 'http') {
        continue;
      }
      if (proxyProvider['url'] != null) {
        proxyProvider['path'] = getProvidersFilePathInner(
          'proxies',
          proxyProvider['url'],
        );
      }
    }
  }
  if (rawConfig['rule-providers'] != null) {
    final ruleProviders = rawConfig['rule-providers'] as Map;
    for (final key in ruleProviders.keys) {
      final ruleProvider = ruleProviders[key];
      if (ruleProvider['type'] != 'http') {
        continue;
      }
      if (ruleProvider['url'] != null) {
        ruleProvider['path'] = getProvidersFilePathInner(
          'rules',
          ruleProvider['url'],
        );
      }
    }
  }
  rawConfig['profile']['store-selected'] = false;
  rawConfig['geox-url'] = realPatchConfig.geoXUrl.raw;
  rawConfig['global-ua'] = realPatchConfig.globalUa ?? defaultUA;
  if (rawConfig['hosts'] == null) {
    rawConfig['hosts'] = {};
  }
  for (final host in realPatchConfig.hosts.entries) {
    rawConfig['hosts'][host.key] = host.value.splitByMultipleSeparators;
  }
  if (rawConfig['dns'] == null) {
    rawConfig['dns'] = {};
  }
  final isEnableDns = rawConfig['dns']['enable'] == true;
  const systemDns = 'system://';
  if (overrideDns || !isEnableDns) {
    final dns = switch (!isEnableDns) {
      true => realPatchConfig.dns.copyWith(
        nameserver: [...realPatchConfig.dns.nameserver, systemDns],
      ),
      false => realPatchConfig.dns,
    };
    rawConfig['dns'] = dns.toJson();
    rawConfig['dns']['nameserver-policy'] = {};
    for (final entry in dns.nameserverPolicy.entries) {
      rawConfig['dns']['nameserver-policy'][entry.key] =
          entry.value.splitByMultipleSeparators;
    }
  }
  if (appendSystemDns) {
    final List<String> nameserver = List<String>.from(
      rawConfig['dns']['nameserver'] ?? [],
    );
    if (!nameserver.contains(systemDns)) {
      rawConfig['dns']['nameserver'] = [...nameserver, systemDns];
    }
  }
  List<String> rules = [];
  if (data.rules.isEmpty) {
    if (rawConfig['rules'] != null) {
      rules = List<String>.from(rawConfig['rules']);
    }
    if (addedRules.isNotEmpty) {
      final hasMatchPlaceholder = addedRules.any(
        (item) => item.ruleTarget?.toUpperCase() == 'MATCH',
      );
      String? replacementTarget;

      if (hasMatchPlaceholder) {
        for (int i = rules.length - 1; i >= 0; i--) {
          final parsed = Rule.parse(rules[i]);
          if (parsed.ruleAction == RuleAction.MATCH) {
            final target = parsed.ruleTarget;
            if (target != null && target.isNotEmpty) {
              replacementTarget = target;
              break;
            }
          }
        }
      }
      final List<String> finalAddedRules;

      if (replacementTarget?.isNotEmpty == true) {
        finalAddedRules = [];
        for (int i = 0; i < addedRules.length; i++) {
          final parsed = addedRules[i];
          if (parsed.ruleTarget?.toUpperCase() == 'MATCH') {
            finalAddedRules.add(
              parsed.copyWith(ruleTarget: replacementTarget).rawValue,
            );
          } else {
            finalAddedRules.add(addedRules[i].rawValue);
          }
        }
      } else {
        finalAddedRules = addedRules.map((e) => e.rawValue).toList();
      }
      rules = [...finalAddedRules, ...rules];
    }
  } else {
    rules = data.rules.map((item) => item.rawValue).toList();
  }
  if (data.proxyGroups.isNotEmpty) {
    rawConfig['proxy-groups'] = data.proxyGroups
        .map((group) => group.toJson())
        .toList();
  }
  rawConfig['rules'] = rules;
  applyConfigOverrides(
    rawConfig,
    inherited,
    realPatchConfig,
    android: system.isAndroid,
  );
  if (data.profileSource == ProfileSource.xboard) {
    applyXboardDnsPolicy(rawConfig);
  }
  if (system.isMacOS) {
    applyApnsPolicy(rawConfig, data.networkProps);
  }
  final yaml = await _encodeYaml(Map<String, dynamic>.from(rawConfig));
  const runtimeKeys = {'dns', 'hosts', 'ntp', 'sniffer'};
  final structure = Map<String, dynamic>.from(rawConfig)
    ..removeWhere((key, _) => runtimeKeys.contains(key));
  return (
    yaml: yaml,
    md5: yaml.toMd5(),
    structureMd5: json.encode(structure).toMd5(),
    runtimeConfig: Map<String, dynamic>.from(
      json.decode(
            json.encode({for (final key in runtimeKeys) key: rawConfig[key]}),
          )
          as Map,
    ),
  );
}

Future<List<String>> shakingProfileTask(
  VM2<Iterable<int>, Iterable<int>> data,
) async {
  return compute<
    VM3<Iterable<int>, Iterable<int>, RootIsolateToken>,
    List<String>
  >(_shakingProfileTask, VM3(data.a, data.b, RootIsolateToken.instance!));
}

Future<List<String>> _shakingProfileTask(
  VM3<Iterable<int>, Iterable<int>, RootIsolateToken> data,
) async {
  final profileIds = data.a;
  final scriptIds = data.b;
  final token = data.c;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final profilesDir = Directory(await appPath.profilesPath);
  final scriptsDir = Directory(await appPath.scriptsDirPath);
  final providersDir = Directory(await appPath.getProvidersRootPath());
  final List<String> targets = [];
  void scanDirectory(
    Directory dir,
    Iterable<int> baseNames, {
    bool skipProvidersFolder = false,
  }) {
    if (!dir.existsSync()) return;
    final entities = dir.listSync(recursive: false, followLinks: false);

    for (final entity in entities) {
      if (entity is File) {
        final id = basenameWithoutExtension(entity.path);
        if (!baseNames.contains(int.tryParse(id))) {
          targets.add(entity.path);
        }
      } else if (skipProvidersFolder && entity is Directory) {
        if (basename(entity.path) == 'providers') {
          continue;
        }
      }
    }
  }

  scanDirectory(profilesDir, profileIds, skipProvidersFolder: true);
  scanDirectory(providersDir, profileIds);
  scanDirectory(scriptsDir, scriptIds);
  return targets;
}

Future<String> encodeLogsTask(List<Log> data) async {
  return compute<List<Log>, String>(_encodeLogsTask, data);
}

Future<String> _encodeLogsTask(List<Log> data) async {
  final logsRaw = data.map((item) => item.toString());
  final logsRawString = logsRaw.join('\n');
  return logsRawString;
}

Future<MigrationData> oldToNowTask(Map<String, Object?> data) async {
  final homeDir = await appPath.homeDirPath;
  return compute<VM3<Map<String, Object?>, String, String>, MigrationData>(
    _oldToNowTask,
    VM3(data, homeDir, homeDir),
  );
}

Future<MigrationData> _oldToNowTask(
  VM3<Map<String, Object?>, String, String> data,
) async {
  final configMap = data.a;
  final sourcePath = data.b;
  final targetPath = data.c;

  final accessControlMap = configMap['accessControl'];
  final isAccessControl = configMap['isAccessControl'];
  if (accessControlMap != null) {
    (accessControlMap as Map)['enable'] = isAccessControl;
    if (configMap['vpnProps'] != null) {
      final vpnPropsRaw = configMap['vpnProps'] as Map;
      vpnPropsRaw['accessControl'] = accessControlMap;
    }
  }
  if (configMap['vpnProps'] != null) {
    final vpnPropsRaw = configMap['vpnProps'] as Map;
    vpnPropsRaw['accessControlProps'] = vpnPropsRaw['accessControl'];
  }
  configMap['davProps'] = configMap['dav'];
  final appSettingProps =
      configMap['appSetting'] as Map<String, dynamic>? ?? {};
  appSettingProps['restoreStrategy'] = appSettingProps['recoveryStrategy'];
  configMap['appSettingProps'] = appSettingProps;
  configMap['proxiesStyleProps'] = configMap['proxiesStyle'];
  configMap['proxiesStyleProps'] = configMap['proxiesStyle'];
  List rawScripts = configMap['scripts'] as List<dynamic>? ?? [];
  if (rawScripts.isEmpty) {
    final scriptPropsJson = configMap['scriptProps'] as Map<String, dynamic>?;
    if (scriptPropsJson != null) {
      rawScripts = scriptPropsJson['scripts'] as List<dynamic>? ?? [];
    }
  }
  final Map<String, int> idMap = {};
  final List<Script> scripts = [];
  for (final rawScript in rawScripts) {
    final id = rawScript['id'] as String?;
    final content = rawScript['content'] as String?;
    final label = rawScript['label'] as String?;
    if (id == null || content == null || label == null) {
      continue;
    }
    final newId = idMap.updateCacheValue(rawScript['id'], () => snowflake.id);
    final path = _getScriptPath(targetPath, newId.toString());
    final file = File(path);
    await file.safeWriteAsString(content);
    scripts.add(
      Script(id: newId, label: label, lastUpdateTime: DateTime.now()),
    );
  }
  final List rawRules = configMap['rules'] as List<dynamic>? ?? [];
  final List<Rule> rules = [];
  final List<ProfileRuleLink> links = [];
  for (final rawRule in rawRules) {
    final id = idMap.updateCacheValue(rawRule['id'], () => snowflake.id);
    rawRule['id'] = id;
    final value = rawRule['value'] ?? '';
    rules.add(Rule.parse(value, id: id));
    links.add(ProfileRuleLink(ruleId: id));
  }
  final List rawProfiles = configMap['profiles'] as List<dynamic>? ?? [];
  final List<Profile> profiles = [];
  for (final rawProfile in rawProfiles) {
    final rawId = rawProfile['id'] as String?;
    if (rawId == null) {
      continue;
    }
    final profileId = idMap.updateCacheValue(rawId, () => snowflake.id);
    rawProfile['id'] = profileId;
    final overwrite = rawProfile['overwrite'] as Map?;
    if (overwrite != null) {
      final standardOverwrite = overwrite['standardOverwrite'] as Map?;
      if (standardOverwrite != null) {
        final addedRules = standardOverwrite['addedRules'] as List? ?? [];
        for (final addRule in addedRules) {
          final id = idMap.updateCacheValue(addRule['id'], () => snowflake.id);
          final value = addRule['value'] ?? '';
          rules.add(Rule.parse(value, id: id));
          links.add(
            ProfileRuleLink(
              profileId: profileId,
              ruleId: id,
              scene: RuleScene.added,
            ),
          );
        }
        final disabledRuleIds = standardOverwrite['disabledRuleIds'] as List?;
        if (disabledRuleIds != null) {
          for (final disabledRuleId in disabledRuleIds) {
            final newDisabledRuleId = idMap[disabledRuleId];
            if (newDisabledRuleId != null) {
              links.add(
                ProfileRuleLink(
                  profileId: profileId,
                  ruleId: newDisabledRuleId,
                  scene: RuleScene.disabled,
                ),
              );
            }
          }
        }
      }
      final scriptOverwrite = overwrite['scriptOverwrite'] as Map?;
      if (scriptOverwrite != null) {
        final scriptId = scriptOverwrite['scriptId'] as String?;
        rawProfile['scriptId'] = scriptId != null ? idMap[scriptId] : null;
      }
      rawProfile['overwriteType'] = overwrite['type'];
    }

    final sourceFile = File(_getProfilePath(sourcePath, rawId));
    final targetFilePath = _getProfilePath(targetPath, profileId.toString());
    await sourceFile.safeCopy(targetFilePath);
    profiles.add(Profile.fromJson(rawProfile));
  }
  final currentProfileId = configMap['currentProfileId'];
  configMap['currentProfileId'] = currentProfileId != null
      ? idMap[currentProfileId]
      : null;
  return MigrationData(
    configMap: configMap,
    profiles: profiles,
    rules: rules,
    scripts: scripts,
    links: links,
  );
}

Future<String> backupTask(
  Map<String, dynamic> configMap,
  String snapshotPath,
) async {
  return compute<VM3<Map<String, dynamic>, String, RootIsolateToken>, String>(
    _backupTask,
    VM3(configMap, snapshotPath, RootIsolateToken.instance!),
  );
}

Future<String> _backupTask(
  VM3<Map<String, dynamic>, String, RootIsolateToken> args,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(args.c);
  return createBackupArchive(
    configMap: args.a,
    snapshotPath: args.b,
    homeRoot: await appPath.homeDirPath,
    outputPath: await appPath.tempFilePath,
    temporaryConfigPath: await appPath.tempFilePath,
  );
}

Future<String> createBackupArchive({
  required Map<String, dynamic> configMap,
  required String snapshotPath,
  required String homeRoot,
  required String outputPath,
  required String temporaryConfigPath,
}) async {
  final snapshot = File(snapshotPath);
  final sourceDatabase = Database(NativeDatabase(snapshot));
  final List<String> profileNames;
  final List<String> scriptNames;
  try {
    profileNames = await sourceDatabase.profilesDao.fileNames().get();
    scriptNames = await sourceDatabase.scriptsDao.fileNames().get();
  } finally {
    await sourceDatabase.close();
  }
  final fileNames = {...profileNames, ...scriptNames};
  final profilesDir = Directory(join(homeRoot, 'profiles'));
  final scriptsDir = Directory(join(homeRoot, 'scripts'));
  for (final paths in [
    (profilesDir, profileNames),
    (scriptsDir, scriptNames),
  ]) {
    for (final name in paths.$2) {
      if (!RegExp(r'^[0-9]+\.(yaml|js)$').hasMatch(name) ||
          await FileSystemEntity.type(
                join(paths.$1.path, name),
                followLinks: false,
              ) !=
              FileSystemEntityType.file) {
        throw const FormatException('Backup configuration file is missing');
      }
    }
  }
  final configFile = File(temporaryConfigPath);
  final encoder = ZipFileEncoder();
  var closed = false;
  var succeeded = false;
  try {
    encoder.create(outputPath);
    await configFile.writeAsString(json.encode(configMap));
    await encoder.addFile(snapshot, backupDatabaseName);
    await encoder.addFile(configFile, configJsonName);
    for (final directory in [profilesDir, scriptsDir]) {
      if (!await directory.exists()) continue;
      await encoder.addDirectory(
        directory,
        filter: (file, _) => fileNames.contains(basename(file.path))
            ? ZipFileOperation.include
            : ZipFileOperation.skip,
      );
    }
    encoder.close();
    closed = true;
    succeeded = true;
    return outputPath;
  } finally {
    if (!closed) {
      try {
        encoder.close();
      } on Object catch (error) {
        commonPrint.log(
          'Backup cleanup failed: $error',
          logLevel: LogLevel.warning,
        );
      }
    }
    await configFile.safeDelete();
    if (!succeeded) await File(outputPath).safeDelete();
  }
}

Future<StagedRestore> restoreTask() async {
  return compute<RootIsolateToken, StagedRestore>(
    _restoreTask,
    RootIsolateToken.instance!,
  );
}

Future<StagedRestore> _restoreTask(RootIsolateToken token) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  return stageBackup(
    backupFilePath: await appPath.backupFilePath,
    stagingRoot: await appPath.restoreDirPath,
  );
}

Future<StagedRestore> stageBackup({
  required String backupFilePath,
  required String stagingRoot,
}) async {
  final root = await Directory(stagingRoot).create(recursive: true);
  final staging = await root.createTemp('restore-');
  try {
    final input = InputFileStream(backupFilePath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      await extractBackupArchive(archive, staging);
    } finally {
      await input.close();
    }
    final configFile = File(join(staging.path, configJsonName));
    if (!await configFile.exists()) {
      throw const FormatException('Backup configuration is missing');
    }
    if (await configFile.length() > 16 * 1024 * 1024) {
      throw const FormatException('Backup settings exceed size limit');
    }
    final raw = json.decode(await configFile.readAsString());
    if (raw is! Map) {
      throw const FormatException('Invalid backup configuration');
    }
    final configMap = Map<String, Object?>.from(raw);
    final version = int.tryParse(configMap['version']?.toString() ?? '0');
    if (version == null || version < 0 || version > Migration.currentVersion) {
      throw const FormatException('Unsupported backup version');
    }
    var data = MigrationData(configMap: configMap);
    if (version == 0) {
      for (final profile in configMap['profiles'] as List? ?? []) {
        final id = (profile as Map)['id']?.toString() ?? '';
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
            !await File(_getProfilePath(staging.path, id)).exists()) {
          throw const FormatException('Invalid legacy profile file');
        }
      }
      data = await _oldToNowTask(VM3(configMap, staging.path, staging.path));
    } else {
      final databaseFile = File(join(staging.path, backupDatabaseName));
      if (!await databaseFile.exists()) {
        throw const FormatException('Backup database is missing');
      }
      final sourceDatabase = Database(
        NativeDatabase(
          databaseFile,
          setup: (raw) {
            final version =
                raw.select('PRAGMA user_version').first['user_version'] as int;
            if (version > Database.currentSchemaVersion) {
              throw const FormatException(
                'Backup database is newer than this app',
              );
            }
          },
        ),
      );
      try {
        data = data.copyWith(
          profiles: await sourceDatabase.profilesDao.query().get(),
          scripts: await sourceDatabase.scriptsDao.query().get(),
          rules: await sourceDatabase.rules
              .all()
              .map((item) => item.toRule())
              .get(),
          links: await sourceDatabase.profileRuleLinks
              .all()
              .map((item) => item.toLink())
              .get(),
          proxyGroups: await sourceDatabase.proxyGroups
              .all()
              .map((item) => item.toProxyGroup())
              .get(),
        );
      } finally {
        await sourceDatabase.close();
      }
    }
    Config.fromJson(data.configMap!);
    final files = RestoreFileTransaction(
      stagingRoot: staging.path,
      activeRoot: staging.path,
      files: [
        for (final profile in data.profiles) 'profiles/${profile.id}.yaml',
        for (final script in data.scripts) 'scripts/${script.id}.js',
      ],
    );
    await files.validate();
    return StagedRestore(data: data, directory: staging.path);
  } on Object {
    await staging.delete(recursive: true);
    rethrow;
  }
}

String _getScriptPath(String root, String fileName) {
  return join(root, 'scripts', '$fileName.js');
}

String _getProfilePath(String root, String fileName) {
  return join(root, 'profiles', '$fileName.yaml');
}

Future<List<T>> mapListTask<T, S>(List<S> results, T Function(S) mapper) async {
  return compute<VM2<List<S>, T Function(S)>, List<T>>(
    _mapListTask,
    VM2(results, mapper),
  );
}

Future<List<T>> _mapListTask<T, S>(VM2<List<S>, T Function(S)> vm2) async {
  final results = vm2.a;
  final mapper = vm2.b;
  return results.map((item) => mapper(item)).toList();
}
