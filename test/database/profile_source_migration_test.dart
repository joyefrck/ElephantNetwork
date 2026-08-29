import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('schema v2 profiles migrate to user-owned profiles', () async {
    final rawDatabase = sqlite.sqlite3.openInMemory();
    rawDatabase.execute('''
      CREATE TABLE profiles (
        id INTEGER NOT NULL PRIMARY KEY,
        label TEXT NOT NULL,
        current_group_name TEXT NULL,
        url TEXT NOT NULL,
        last_update_date INTEGER NULL,
        overwrite_type TEXT NOT NULL,
        script_id INTEGER NULL,
        auto_update_duration_millis INTEGER NOT NULL,
        subscription_info TEXT NULL,
        auto_update INTEGER NOT NULL,
        selected_map TEXT NOT NULL,
        unfold_set TEXT NOT NULL,
        "order" INTEGER NULL
      )
    ''');
    rawDatabase.execute('''
      INSERT INTO profiles (
        id, label, url, overwrite_type, auto_update_duration_millis,
        auto_update, selected_map, unfold_set
      ) VALUES (1, 'User profile', '', 'standard', 0, 0, '{}', '[]')
    ''');
    rawDatabase.userVersion = 2;
    final database = Database(NativeDatabase.opened(rawDatabase));
    addTearDown(database.close);

    final profile = await database.profilesDao.query().getSingle();

    expect(profile.label, 'User profile');
    expect(profile.source, ProfileSource.user);
    expect(profile.ownerAccountId, isNull);
  });
}
