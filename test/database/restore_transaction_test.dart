import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Database db;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() => db = Database(NativeDatabase.memory()));
  tearDown(() => db.close());
  Profile profile(int id) => Profile(id: id, autoUpdateDuration: Duration.zero);
  Script script(int id) =>
      Script(id: id, label: 'Script $id', lastUpdateTime: DateTime(2026));

  test(
    'compatible restore preserves unrelated local scripts, rules and groups',
    () async {
      final localRule = Rule.parse('DOMAIN,local.example,DIRECT', id: 20);
      final remoteRule = Rule.parse('DOMAIN,restored.example,DIRECT', id: 21);
      await db.restore(
        [profile(1)],
        [script(10)],
        [localRule],
        [const ProfileRuleLink(profileId: 1, ruleId: 20)],
        [
          const ProxyGroup(
            id: 30,
            profileId: 1,
            name: 'Local',
            type: GroupType.Selector,
          ),
        ],
      );
      await db.restore(
        [profile(2)],
        [script(11)],
        [remoteRule],
        [const ProfileRuleLink(profileId: 2, ruleId: 21)],
        [
          const ProxyGroup(
            id: 31,
            profileId: 2,
            name: 'Restored',
            type: GroupType.Selector,
          ),
        ],
      );
      expect((await db.profilesDao.query().get()).map((p) => p.id), [1, 2]);
      expect((await db.scriptsDao.query().get()).map((p) => p.id).toSet(), {
        10,
        11,
      });
      expect((await db.rules.select().get()).map((r) => r.id).toSet(), {
        20,
        21,
      });
      expect((await db.profileRuleLinks.select().get()).length, 2);
      expect(
        (await db.proxyGroups.select().get()).map((group) => group.id).toSet(),
        {30, 31},
      );
    },
  );

  test('restore enables foreign keys and drops legacy orphan links', () async {
    final rule = Rule.parse('DOMAIN,valid.example,DIRECT', id: 20);
    final managed = profile(1).copyWith(
      source: ProfileSource.xboard,
      ownerAccountId: 'account-A',
      scriptId: 999,
    );
    await db.restore([managed], [], [rule], [
      const ProfileRuleLink(profileId: 1, ruleId: 20),
      const ProfileRuleLink(profileId: 404, ruleId: 20),
      const ProfileRuleLink(profileId: 1, ruleId: 404),
    ], []);
    expect(
      (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
        'foreign_keys',
      ),
      1,
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect((await db.profileRuleLinks.select().get()).length, 1);
    final restored = (await db.profilesDao.query().get()).single;
    expect(restored.source, ProfileSource.xboard);
    expect(restored.ownerAccountId, 'account-A');
    expect(restored.scriptId, isNull);
  });

  test('an empty override clears relational data atomically', () async {
    await db.restore(
      [profile(1)],
      [script(10)],
      [Rule.parse('MATCH,DIRECT', id: 20)],
      [const ProfileRuleLink(profileId: 1, ruleId: 20)],
      [
        const ProxyGroup(
          id: 30,
          profileId: 1,
          name: 'Local',
          type: GroupType.Selector,
        ),
      ],
    );
    await db.restore([], [], [], [], [], isOverride: true);
    expect(await db.profilesDao.query().get(), isEmpty);
    expect(await db.scriptsDao.query().get(), isEmpty);
    expect(await db.rules.select().get(), isEmpty);
    expect(await db.profileRuleLinks.select().get(), isEmpty);
  });

  test(
    'SQLite snapshot includes committed WAL data without copying a live file',
    () async {
      final root = await Directory.systemTemp.createTemp('elephant-snapshot-');
      final live = Database(NativeDatabase(File('${root.path}/live.sqlite')));
      final snapshot = File('${root.path}/snapshot.sqlite');
      try {
        await live.customStatement('PRAGMA journal_mode = WAL');
        await live.profilesDao.setAll([
          profile(42).copyWith(label: 'Committed in WAL'),
        ]);
        expect(await File('${root.path}/live.sqlite-wal').exists(), isTrue);
        await live.createBackup(snapshot.path);
        final copy = Database(NativeDatabase(snapshot));
        try {
          expect(
            (await copy.profilesDao.query().get()).single.label,
            'Committed in WAL',
          );
        } finally {
          await copy.close();
        }
      } finally {
        await live.close();
        await root.delete(recursive: true);
      }
    },
  );
}
