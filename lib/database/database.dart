import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

part 'converter.dart';
part 'generated/database.g.dart';
part 'groups.dart';
part 'icons.dart';
part 'ip_qualities.dart';
part 'links.dart';
part 'profiles.dart';
part 'rules.dart';
part 'scripts.dart';
part 'restore_commits.dart';

@DriftDatabase(
  tables: [
    Profiles,
    Scripts,
    Rules,
    ProfileRuleLinks,
    ProxyGroups,
    IconRecords,
    RestoreCommits,
    IpQualities,
  ],
  daos: [
    ProfilesDao,
    ScriptsDao,
    RulesDao,
    ProxyGroupsDao,
    IconRecordsDao,
    IpQualitiesDao,
  ],
)
class Database extends _$Database {
  Database([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static const currentSchemaVersion = 6;

  @override
  int get schemaVersion => currentSchemaVersion;

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final databaseFile = File(await appPath.databasePath);
      return NativeDatabase.createInBackground(databaseFile);
    });
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      beforeOpen: (_) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.createTable(proxyGroups);
          await m.createTable(iconRecords);
          await _resetOrders();
          await _migrateRules(m);
        }
        if (from < 3) {
          await m.addColumn(profiles, profiles.source);
          await m.addColumn(profiles, profiles.ownerAccountId);
        }
        if (from < 4) await m.createTable(restoreCommits);
        if (from < 5) await m.addColumn(profiles, profiles.profileType);
        if (from < 6) await m.createTable(ipQualities);
      },
    );
  }

  Future<void> _migrateRules(Migrator m) async {
    final tableInfo = await customSelect('PRAGMA table_info(rules)').get();
    final columnNames = tableInfo
        .map((row) => row.read<String>('name'))
        .toList();
    if (columnNames.isEmpty) {
      await m.createTable(rules);
      return;
    } else if (columnNames.contains('rule_action')) {
      return;
    }
    await customStatement(
      'ALTER TABLE rules ADD COLUMN rule_action TEXT NOT NULL DEFAULT ""',
    );
    await customStatement('ALTER TABLE rules ADD COLUMN content TEXT');
    await customStatement('ALTER TABLE rules ADD COLUMN rule_target TEXT');
    await customStatement('ALTER TABLE rules ADD COLUMN rule_provider TEXT');
    await customStatement('ALTER TABLE rules ADD COLUMN sub_rule TEXT');
    await customStatement(
      'ALTER TABLE rules ADD COLUMN no_resolve INTEGER NOT NULL DEFAULT 0',
    );
    await customStatement(
      'ALTER TABLE rules ADD COLUMN src INTEGER NOT NULL DEFAULT 0',
    );
    final oldRows = await customSelect('SELECT id, value FROM rules').get();
    for (final row in oldRows) {
      final id = row.read<int>('id');
      final value = row.read<String>('value');
      final parsed = Rule.parse(value, id: id);
      await customStatement(
        'UPDATE rules SET rule_action = ?, content = ?, rule_target = ?, rule_provider = ?, sub_rule = ?, no_resolve = ?, src = ? WHERE id = ?',
        [
          parsed.ruleAction.name,
          parsed.content,
          parsed.ruleTarget,
          parsed.ruleProvider,
          parsed.subRule,
          parsed.noResolve ? 1 : 0,
          parsed.src ? 1 : 0,
          id,
        ],
      );
    }
    await customStatement('ALTER TABLE rules DROP COLUMN value');
    await m.createIndex(idxRuleTarget);
  }

  Future<void> _resetOrders() async {
    await rulesDao.resetOrders();
  }

  Future<void> restore(
    List<Profile> profiles,
    List<Script> scripts,
    List<Rule> rules,
    List<ProfileRuleLink> links,
    List<ProxyGroup> proxyGroups, {
    bool isOverride = false,
  }) async {
    if (!isOverride &&
        profiles.isEmpty &&
        scripts.isEmpty &&
        rules.isEmpty &&
        links.isEmpty &&
        proxyGroups.isEmpty) {
      return;
    }
    await transaction(() async {
      await customStatement('PRAGMA defer_foreign_keys = ON');
      await batch((b) {
        if (isOverride) {
          profilesDao.setAllWithBatch(b, profiles);
          scriptsDao.setAllWithBatch(b, scripts);
          rulesDao.restoreWithBatch(b, rules, links);
          proxyGroupsDao.setAllWithBatch(null, b, proxyGroups);
        } else {
          profilesDao.putAllWithBatch(
            b,
            profiles.map((item) => item.toCompanion()),
          );
          b.insertAllOnConflictUpdate(
            this.scripts,
            scripts.map((item) => item.toCompanion()),
          );
          b.insertAllOnConflictUpdate(
            this.rules,
            rules.map((item) => item.toCompanion()),
          );
          b.insertAllOnConflictUpdate(
            profileRuleLinks,
            links.map((item) => item.toCompanion()),
          );
          b.insertAllOnConflictUpdate(
            this.proxyGroups,
            proxyGroups.map((item) => item.toCompanion()),
          );
        }
      });
      await _purgeOrphans();
    });
  }

  Future<void> _purgeOrphans() async {
    await customStatement(
      'DELETE FROM profile_rule_mapping WHERE rule_id NOT IN (SELECT id FROM rules) OR (profile_id IS NOT NULL AND profile_id NOT IN (SELECT id FROM profiles))',
    );
    await customStatement(
      'DELETE FROM proxy_groups WHERE profile_id IS NOT NULL AND profile_id NOT IN (SELECT id FROM profiles)',
    );
    await customStatement(
      'UPDATE profiles SET script_id = NULL WHERE script_id IS NOT NULL AND script_id NOT IN (SELECT id FROM scripts)',
    );
  }

  Future<void> markRestoreCommitted(String id) async {
    await into(
      restoreCommits,
    ).insertOnConflictUpdate(RestoreCommitsCompanion.insert(id: id));
  }

  Future<bool> isRestoreCommitted(String id) async {
    return await (select(
          restoreCommits,
        )..where((row) => row.id.equals(id))).getSingleOrNull() !=
        null;
  }

  Future<void> forgetRestoreCommit(String id) async {
    await (delete(restoreCommits)..where((row) => row.id.equals(id))).go();
  }

  Future<void> createBackup(String path) async {
    await customStatement('VACUUM INTO ?', [path]);
  }

  Future<void> setProfileCustomData(
    int profileId,
    List<ProxyGroup> groups,
    List<Rule> rules,
  ) async {
    await batch((b) {
      proxyGroupsDao.setAllWithBatch(profileId, b, groups);
      rulesDao.setCustomRulesWithBatch(profileId, b, rules);
    });
  }
}

extension TableInfoExt<Tbl extends Table, Row> on TableInfo<Tbl, Row> {
  void setAll(
    Batch batch,
    Iterable<Insertable<Row>> items, {
    required Expression<bool> Function(Tbl tbl) deleteFilter,
    bool preDelete = false,
  }) async {
    if (preDelete) {
      batch.deleteWhere(this, deleteFilter);
    }
    batch.insertAllOnConflictUpdate(this, items);
    if (!preDelete) {
      batch.deleteWhere(this, deleteFilter);
    }
  }

  Selectable<int?> get count {
    final countExp = countAll();
    final query = select().addColumns([countExp]);
    return query.map((row) => row.read(countExp));
  }

  Future<int> remove(Expression<bool> Function(Tbl tbl) filter) async {
    return (delete()..where(filter)).go();
  }

  Future<int> put(Insertable<Row> item) async {
    return insertOnConflictUpdate(item);
  }
}

extension SimpleSelectStatementExt<T extends HasResultSet, D>
    on SimpleSelectStatement<T, D> {
  Selectable<int> get count {
    final countExp = countAll();
    final query = addColumns([countExp]);
    return query.map((row) => row.read(countExp)!);
  }
}

extension JoinedSelectStatementExt<T extends HasResultSet, D>
    on JoinedSelectStatement<T, D> {
  Selectable<int> get count {
    final countExp = countAll();
    addColumns([countExp]);
    return map((row) => row.read(countExp)!);
  }
}

final database = Database();
