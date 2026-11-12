import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/diagnostics/quality_repository.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const quality = IpQuality(
  ip: '8.8.8.8',
  source: IpQualitySource.ipQuery,
  type: IpType.hosting,
);

void main() {
  test(
    'persistent cache survives restart and expires after three days',
    () async {
      final dir = await Directory.systemTemp.createTemp('quality-cache-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cache.sqlite');
      var now = DateTime(2026, 11, 13, 12);
      var calls = 0;
      var db = Database(NativeDatabase(file));
      QualityRepository repo() => QualityRepository(
        dao: db.ipQualitiesDao,
        now: () => now,
        lookup: (_, _) async {
          calls++;
          return quality;
        },
      );
      await repo().get(quality.ip, CancelToken());
      await db.close();
      db = Database(NativeDatabase(file));
      addTearDown(db.close);
      now = now.add(const Duration(days: 2));
      expect(await repo().get(quality.ip, CancelToken()), quality);
      expect(calls, 1);
      now = now.add(const Duration(days: 1, seconds: 1));
      await repo().get(quality.ip, CancelToken());
      expect(calls, 2);
      now = now.subtract(const Duration(days: 10));
      await repo().get(quality.ip, CancelToken());
      expect(calls, 3);
    },
  );

  test(
    'failed lookup cools down and cancellation does not poison retries',
    () async {
      final db = Database(NativeDatabase.memory());
      addTearDown(db.close);
      var now = DateTime(2026, 11, 13);
      var calls = 0;
      final repo = QualityRepository(
        dao: db.ipQualitiesDao,
        now: () => now,
        lookup: (_, token) async {
          calls++;
          if (calls == 1) throw StateError('offline');
          if (calls == 2) {
            token.cancel();
            throw token.cancelError!;
          }
          return quality;
        },
      );
      await expectLater(repo.get(quality.ip, CancelToken()), throwsStateError);
      await expectLater(repo.get(quality.ip, CancelToken()), throwsStateError);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 5));
      await expectLater(
        repo.get(quality.ip, CancelToken()),
        throwsA(isA<DioException>()),
      );
      expect(await repo.get(quality.ip, CancelToken()), quality);
      expect(calls, 3);
    },
  );

  test('mismatching IP is never cached', () async {
    final db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = QualityRepository(
      dao: db.ipQualitiesDao,
      lookup: (_, _) async => quality,
    );
    await expectLater(
      repo.get('1.1.1.1', CancelToken()),
      throwsFormatException,
    );
    expect(await db.select(db.ipQualities).get(), isEmpty);
  });

  test('schema v5 adds quality cache while retaining profiles', () async {
    final raw = sqlite.sqlite3.openInMemory();
    final old = Database(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await old.profilesDao.putAll([
      Profile.custom(label: 'Keep').copyWith(id: 5).toCompanion(),
    ]);
    await old.close();
    raw.execute('DROP TABLE ip_qualities');
    raw.userVersion = 5;
    final db = Database(NativeDatabase.opened(raw));
    addTearDown(db.close);
    expect((await db.profilesDao.query().getSingle()).label, 'Keep');
    await db.ipQualitiesDao.put(
      quality,
      DateTime.now(),
      QualityRepository.maxAge,
    );
    expect(await db.select(db.ipQualities).get(), hasLength(1));
  });
}
