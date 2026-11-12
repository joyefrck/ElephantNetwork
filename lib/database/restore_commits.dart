part of 'database.dart';

@DataClassName('RawRestoreCommit')
class RestoreCommits extends Table {
  TextColumn get id => text()();

  @override
  Set<Column> get primaryKey => {id};
}
