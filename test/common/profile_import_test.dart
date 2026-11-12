import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:fl_clash/common/profile_import.dart';
import 'package:fl_clash/common/task.dart';
import 'package:yaml/yaml.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingDatabase extends Database {
  _FailingDatabase() : super(NativeDatabase.memory());
  bool failCommit = false;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) => super.transaction(() async {
    final result = await action();
    if (failCommit) throw StateError('database write failed');
    return result;
  }, requireNew: requireNew);
}

void main() {
  late Directory root;
  late _FailingDatabase db;
  const original = Profile(
    id: 1,
    label: 'Valid',
    url: 'https://valid.test/profile',
    autoUpdateDuration: Duration.zero,
    source: ProfileSource.xboard,
    ownerAccountId: 'account',
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('elephant-profile-test-');
    await Directory('${root.path}/profiles').create();
    await File('${root.path}/profiles/1.yaml').writeAsString('old valid bytes');
    await File('${root.path}/account.json').writeAsString('session retained');
    db = _FailingDatabase();
    await db.profilesDao.putAll([original.toCompanion()]);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<Profile> import({
    Future<void> Function(String)? validate,
    Profile? profile,
  }) => commitProfileData(
    database: db,
    activeRoot: root.path,
    profile: profile ?? original.copyWith(label: 'Updated'),
    bytes: Uint8List.fromList('new validated bytes'.codeUnits),
    recoverPending: () async {},
    validate: validate ?? (_) async {},
  );

  test(
    'custom profile compilation retains unknown future configuration fields',
    () async {
      final compiled = await compileProfileTask(
        const MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 4,
          rawConfig: {
            'future-feature': {
              'enabled': true,
              'levels': [1, 2],
            },
            'proxy-groups': [],
            'rules': ['MATCH,DIRECT'],
          },
          realPatchConfig: PatchClashConfig(),
          overrideDns: false,
          appendSystemDns: false,
          proxyGroups: [],
          rules: [],
          addedRules: [],
          defaultUA: 'test',
        ),
      );
      final yaml = loadYaml(compiled.yaml);
      expect(yaml['future-feature']['enabled'], true);
      expect(yaml['future-feature']['levels'], [1, 2]);
      expect(yaml['rules'], ['MATCH,DIRECT']);
    },
  );

  test(
    'profile bytes and metadata commit together without changing ownership or session',
    () async {
      final imported = await import(
        validate: (path) async {
          expect(await File(path).readAsString(), 'new validated bytes');
          expect(
            await File('${root.path}/profiles/1.yaml').readAsString(),
            'old valid bytes',
          );
        },
      );
      expect(
        await File('${root.path}/profiles/1.yaml').readAsString(),
        'new validated bytes',
      );
      final persisted = await db.profilesDao.query().getSingle();
      expect(persisted, imported);
      expect(persisted.source, ProfileSource.xboard);
      expect(persisted.ownerAccountId, 'account');
      expect(
        await File('${root.path}/account.json').readAsString(),
        'session retained',
      );
      expect(await db.restoreCommits.select().get(), isEmpty);
    },
  );

  test('invalid data never replaces a valid file or its metadata', () async {
    await expectLater(
      import(
        validate: (_) async {
          throw const FormatException('invalid profile');
        },
      ),
      throwsFormatException,
    );
    expect(
      await File('${root.path}/profiles/1.yaml').readAsString(),
      'old valid bytes',
    );
    expect(await db.profilesDao.query().getSingle(), original);
  });

  test('database failure restores the previous file and metadata', () async {
    db.failCommit = true;
    await expectLater(import(), throwsStateError);
    expect(
      await File('${root.path}/profiles/1.yaml').readAsString(),
      'old valid bytes',
    );
    expect(await db.profilesDao.query().getSingle(), original);
    expect(await db.restoreCommits.select().get(), isEmpty);
  });

  test('a failed new custom import leaves no file or database row', () async {
    db.failCommit = true;
    await expectLater(
      import(
        profile: original.copyWith(
          id: 2,
          url: '',
          profileType: ProfileType.custom,
          source: ProfileSource.user,
          ownerAccountId: null,
        ),
      ),
      throwsStateError,
    );
    expect(await File('${root.path}/profiles/2.yaml').exists(), false);
    expect((await db.profilesDao.query().get()).map((value) => value.id), [1]);
  });
}
