part of 'database.dart';

@DataClassName('IpQualityRecord')
class IpQualities extends Table {
  @override
  String get tableName => 'ip_qualities';
  TextColumn get ip => text()();
  TextColumn get quality => text().map(const IpQualityConverter())();
  DateTimeColumn get checkedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {ip};
}

@DriftAccessor(tables: [IpQualities])
class IpQualitiesDao extends DatabaseAccessor<Database>
    with _$IpQualitiesDaoMixin {
  IpQualitiesDao(super.attachedDatabase);
  Future<IpQualityRecord?> fresh(String ip, Duration maxAge, DateTime now) {
    return (select(ipQualities)..where(
          (t) =>
              t.ip.equals(ip) &
              t.checkedAt.isBetweenValues(now.subtract(maxAge), now),
        ))
        .getSingleOrNull();
  }

  Future<void> put(IpQuality quality, DateTime now, Duration maxAge) {
    return transaction(() async {
      await (delete(ipQualities)..where(
            (t) => t.checkedAt.isBetweenValues(now.subtract(maxAge), now).not(),
          ))
          .go();
      await into(ipQualities).insertOnConflictUpdate(
        IpQualitiesCompanion.insert(
          ip: quality.ip,
          quality: quality,
          checkedAt: now,
        ),
      );
    });
  }
}
