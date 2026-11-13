part of '../action.dart';

@Riverpod(keepAlive: true)
class BackupAction extends _$BackupAction {
  @override
  void build() {}

  Future<void>? _restoreOperation;
  Future<String>? _backupOperation;

  Future<String> backup() {
    return _backupOperation ??= dataMutationQueue
        .run(_backup)
        .whenComplete(() => _backupOperation = null);
  }

  Future<String> _backup() async {
    await _recoverPendingRestore();
    final configMap = ref.read(configProvider).toJson();
    configMap['version'] = await preferences.getVersion();
    final snapshot = File(await appPath.tempFilePath);
    try {
      await database.createBackup(snapshot.path);
      return await backupTask(configMap, snapshot.path);
    } finally {
      await snapshot.safeDelete();
    }
  }

  Future<void> restore(RestoreOption option) {
    return _restoreOperation ??= dataMutationQueue
        .run(() => _restore(option))
        .whenComplete(() => _restoreOperation = null);
  }

  @protected
  Future<StagedRestore> prepareRestore() => restoreTask();

  @protected
  Database get restoreDatabase => database;

  @protected
  Future<String> get restoreRoot => appPath.homeDirPath;

  @protected
  Future<bool> persistRestoredConfig(Config config) =>
      preferences.saveConfig(config);

  @protected
  Future<Map<String, Object?>?> get restoreSettingsSnapshot =>
      preferences.getConfigMap();

  Future<void> _recoverPendingRestore() async {
    await RestoreFileTransaction.recover(
      activeRoot: await restoreRoot,
      isCommitted: restoreDatabase.isRestoreCommitted,
      forgetCommit: restoreDatabase.forgetRestoreCommit,
      persistConfig: (config, previousDigest) async {
        if (!shouldRecoverConfiguration(
          await restoreSettingsSnapshot,
          config,
          previousDigest,
        )) {
          return;
        }
        if (!await persistRestoredConfig(config)) {
          throw StateError('Restored settings could not be saved');
        }
        _applyRestoredConfig(config);
      },
    );
  }

  void _applyRestoredConfig(Config config) {
    if (!ref.mounted) return;
    applyConfigSettings(ref, config);
  }

  Future<void> _restore(RestoreOption option) async {
    StagedRestore? staged;
    RestoreFileTransaction? files;
    var committed = false;
    final restoreStrategy = ref.read(
      appSettingProvider.select((state) => state.restoreStrategy),
    );
    final isOverride = restoreStrategy == RestoreStrategy.override;
    try {
      await _recoverPendingRestore();
      staged = await prepareRestore();
      final migrationData = staged.data;
      final configMap = migrationData.configMap;
      final config = configMap == null
          ? null
          : normalizeDesktopProxyConfig(
              normalizeLocalControlConfig(Config.fromJson(configMap)),
            );
      files = RestoreFileTransaction(
        stagingRoot: staged.directory,
        activeRoot: await restoreRoot,
        pendingConfig: option == RestoreOption.all ? config : null,
        previousConfigDigest: option == RestoreOption.all && config != null
            ? configurationDigest(await restoreSettingsSnapshot)
            : null,
        files: [
          for (final profile in migrationData.profiles)
            'profiles/${profile.id}.yaml',
          for (final script in migrationData.scripts) 'scripts/${script.id}.js',
        ],
      );
      await files.validate();
      await restoreDatabase.transaction(() async {
        await restoreDatabase.restore(
          migrationData.profiles,
          migrationData.scripts,
          migrationData.rules,
          migrationData.links,
          migrationData.proxyGroups,
          isOverride: isOverride,
        );
        await files!.apply();
        await restoreDatabase.markRestoreCommitted(files.id!);
      });
      committed = true;
      if (option == RestoreOption.all && config != null) {
        if (!await persistRestoredConfig(config)) {
          throw StateError('Restored settings could not be saved');
        }
      }
      final restoreId = files.id;
      await files.commit();
      if (!files.recoveryRequired && restoreId != null) {
        await restoreDatabase.forgetRestoreCommit(restoreId);
      }
      if (option == RestoreOption.onlyProfiles ||
          config == null ||
          !ref.mounted) {
        return;
      }
      _applyRestoredConfig(config);
      return;
    } on Object {
      if (!committed) {
        await files?.rollback();
        await files?.commit();
      }
      rethrow;
    } finally {
      if (staged != null) {
        await Directory(staged.directory).safeDelete(recursive: true);
      }
    }
  }
}
