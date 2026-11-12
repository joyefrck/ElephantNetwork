import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fl_clash/common/backup.dart';
import 'package:fl_clash/common/local_control.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory active;
  late Directory staged;
  late _FailingDatabase db;
  late ProviderContainer container;
  late _RestoreAction action;
  const first = Profile(
    id: 1,
    label: 'Original',
    autoUpdateDuration: Duration.zero,
  );
  final replacement = first.copyWith(label: 'Restored');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elephant-restore-');
    active = await Directory(
      '${root.path}/active/profiles',
    ).create(recursive: true);
    active = active.parent;
    staged = await Directory(
      '${root.path}/staged/profiles',
    ).create(recursive: true);
    staged = staged.parent;
    await File(
      '${active.path}/profiles/1.yaml',
    ).writeAsString('original payload');
    await File('${active.path}/account.json').writeAsString('retained session');
    await File(
      '${staged.path}/profiles/1.yaml',
    ).writeAsString('restored payload');
    db = _FailingDatabase(File('${active.path}/profiles/1.yaml'));
    await db.profilesDao.setAll([first]);
    action = _RestoreAction(
      db,
      active.path,
      StagedRestore(
        data: MigrationData(profiles: [replacement]),
        directory: staged.path,
      ),
    );
    container = ProviderContainer(
      overrides: [
        backupActionProvider.overrideWith(() => action),
        appSettingProvider.overrideWithBuild((_, _) => const AppSettingProps()),
      ],
    );
    container.read(backupActionProvider);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'restores files and database together while retaining account data',
    () async {
      await action.restore(RestoreOption.onlyProfiles);
      expect((await db.profilesDao.query().get()).single.label, 'Restored');
      expect(
        await File('${active.path}/profiles/1.yaml').readAsString(),
        'restored payload',
      );
      expect(
        await File('${active.path}/account.json').readAsString(),
        'retained session',
      );
      expect(await staged.exists(), isFalse);
    },
  );

  test(
    'a file failure rolls back both earlier files and database rows',
    () async {
      await File(
        '${staged.path}/profiles/2.yaml',
      ).writeAsString('second payload');
      await Directory('${active.path}/profiles/2.yaml').create();
      action.bundle = StagedRestore(
        data: MigrationData(
          profiles: [replacement, replacement.copyWith(id: 2)],
        ),
        directory: staged.path,
      );
      await expectLater(
        action.restore(RestoreOption.onlyProfiles),
        throwsFormatException,
      );
      expect((await db.profilesDao.query().get()).single.label, 'Original');
      expect(
        await File('${active.path}/profiles/1.yaml').readAsString(),
        'original payload',
      );
      expect(
        await Directory('${active.path}/profiles/2.yaml').exists(),
        isTrue,
      );
    },
  );

  test(
    'a database failure after file replacement restores original files',
    () async {
      db.failAfterFiles = true;
      await expectLater(
        action.restore(RestoreOption.onlyProfiles),
        throwsStateError,
      );
      expect((await db.profilesDao.query().get()).single.label, 'Original');
      expect(
        await File('${active.path}/profiles/1.yaml').readAsString(),
        'original payload',
      );
    },
  );

  test('invalid settings fail before any active data is modified', () async {
    action.bundle = StagedRestore(
      data: MigrationData(
        profiles: [replacement],
        configMap: {'currentProfileId': 'invalid'},
      ),
      directory: staged.path,
    );
    await expectLater(action.restore(RestoreOption.all), throwsA(anything));
    expect((await db.profilesDao.query().get()).single.label, 'Original');
    expect(
      await File('${active.path}/profiles/1.yaml').readAsString(),
      'original payload',
    );
  });

  test(
    'restoring old settings repairs enabled local credentials before persistence',
    () async {
      final subscription = container.listen(
        patchClashConfigProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      const config = Config(
        themeProps: ThemeProps(),
        patchClashConfig: PatchClashConfig(
          externalController: ExternalControllerStatus.open,
        ),
        networkProps: NetworkProps(
          authentication: AuthenticationProps(enable: true),
        ),
      );
      action.bundle = StagedRestore(
        data: MigrationData(
          profiles: [replacement],
          configMap: jsonDecode(jsonEncode(config)),
        ),
        directory: staged.path,
      );
      await action.restore(RestoreOption.all);
      expect(
        isValidControllerSecret(action.persisted!.patchClashConfig.secret),
        true,
      );
      expect(action.persisted!.networkProps.authentication.isValid, true);
      expect(
        container.read(patchClashConfigProvider).secret,
        action.persisted!.patchClashConfig.secret,
      );
    },
  );

  test(
    'failed settings persistence retains committed data and blocks another restore until recovery',
    () async {
      final config =
          jsonDecode(
                jsonEncode(
                  const Config(
                    themeProps: ThemeProps(),
                    currentProfileId: 1,
                  ).toJson(),
                ),
              )
              as Map<String, dynamic>;
      action.bundle = StagedRestore(
        data: MigrationData(profiles: [replacement], configMap: config),
        directory: staged.path,
      );
      action.canPersist = false;
      await expectLater(action.restore(RestoreOption.all), throwsStateError);
      expect((await db.profilesDao.query().get()).single.label, 'Restored');
      expect(
        await File('${active.path}/profiles/1.yaml').readAsString(),
        'restored payload',
      );
      final journals = await Directory(
        '${active.path}/.restore-recovery',
      ).list().toList();
      expect(journals.length, 1);
      final id = journals.single.path.split(Platform.pathSeparator).last;
      expect(await db.isRestoreCommitted(id), isTrue);
      await expectLater(
        action.restore(RestoreOption.onlyProfiles),
        throwsStateError,
      );
      expect(action.preparations, 1);
      expect(await db.isRestoreCommitted(id), isTrue);
    },
  );

  test('overlapping restore requests share the same operation', () async {
    action.pending = Completer<StagedRestore>();
    final first = action.restore(RestoreOption.onlyProfiles);
    final second = action.restore(RestoreOption.onlyProfiles);
    expect(identical(first, second), isTrue);
    await action.prepared.future;
    expect(action.preparations, 1);
    action.pending!.complete(action.bundle);
    await Future.wait([first, second]);
    expect((await db.profilesDao.query().get()).single.label, 'Restored');
  });
}

class _RestoreAction extends BackupAction {
  _RestoreAction(this.db, this.root, this.bundle);
  final Database db;
  final String root;
  StagedRestore bundle;
  Completer<StagedRestore>? pending;
  int preparations = 0;
  final prepared = Completer<void>();
  bool canPersist = true;
  Config? persisted;
  @override
  Future<Map<String, Object?>?> get restoreSettingsSnapshot async => null;
  @override
  Future<bool> persistRestoredConfig(Config config) async {
    persisted = config;
    return canPersist;
  }

  @override
  Future<StagedRestore> prepareRestore() async {
    preparations++;
    if (!prepared.isCompleted) prepared.complete();
    return pending?.future ?? bundle;
  }

  @override
  Database get restoreDatabase => db;
  @override
  Future<String> get restoreRoot async => root;
}

class _FailingDatabase extends Database {
  _FailingDatabase(this.file) : super(NativeDatabase.memory());
  final File file;
  bool failAfterFiles = false;
  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) {
    return super.transaction(() async {
      final result = await action();
      if (failAfterFiles && await file.readAsString() == 'restored payload') {
        throw StateError('simulated database commit failure');
      }
      return result;
    }, requireNew: requireNew);
  }
}
