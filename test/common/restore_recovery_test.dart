import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/backup.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory active;
  late Directory staged;
  late Database db;
  late RestoreFileTransaction transaction;
  Config? savedConfig;

  Future<void> recover({Future<void> Function(Config)? persist}) =>
      RestoreFileTransaction.recover(
        activeRoot: active.path,
        isCommitted: db.isRestoreCommitted,
        forgetCommit: db.forgetRestoreCommit,
        persistConfig: (config, _) async {
          if (persist != null) {
            await persist(config);
            return;
          }
          savedConfig = config;
        },
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elephant-recovery-');
    active = await Directory(
      '${root.path}/active/profiles',
    ).create(recursive: true);
    active = active.parent;
    staged = await Directory(
      '${root.path}/staged/profiles',
    ).create(recursive: true);
    staged = staged.parent;
    await File('${active.path}/profiles/1.yaml').writeAsString('original');
    await File('${active.path}/account.json').writeAsString('retained account');
    await File('${staged.path}/profiles/1.yaml').writeAsString('restored');
    await File('${staged.path}/profiles/2.yaml').writeAsString('new');
    db = Database(NativeDatabase.memory());
    transaction = RestoreFileTransaction(
      stagingRoot: staged.path,
      activeRoot: active.path,
      files: const ['profiles/1.yaml', 'profiles/2.yaml'],
      pendingConfig: const Config(
        themeProps: ThemeProps(),
        currentProfileId: 1,
      ),
    );
    savedConfig = null;
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('an older recovery journal does not overwrite newer saved settings', () {
    const previous = Config(themeProps: ThemeProps(), currentProfileId: 1);
    const pending = Config(themeProps: ThemeProps(), currentProfileId: 2);
    const newer = Config(themeProps: ThemeProps(), currentProfileId: 3);
    final prior = configurationDigest(
      Map<String, Object?>.from(previous.toJson()),
    );
    expect(
      shouldRecoverConfiguration(
        Map<String, Object?>.from(previous.toJson()),
        pending,
        prior,
      ),
      isTrue,
    );
    expect(
      shouldRecoverConfiguration(
        Map<String, Object?>.from(pending.toJson()),
        pending,
        prior,
      ),
      isTrue,
    );
    expect(
      shouldRecoverConfiguration(
        Map<String, Object?>.from(newer.toJson()),
        pending,
        prior,
      ),
      isFalse,
    );
  });

  test('restart rolls files back when SQLite never committed', () async {
    await transaction.apply();
    expect(
      await File('${active.path}/profiles/1.yaml').readAsString(),
      'restored',
    );
    await recover();
    expect(
      await File('${active.path}/profiles/1.yaml').readAsString(),
      'original',
    );
    expect(await File('${active.path}/profiles/2.yaml').exists(), isFalse);
    expect(
      await File('${active.path}/account.json').readAsString(),
      'retained account',
    );
    expect(savedConfig, isNull);
  });

  test(
    'restart finishes settings persistence when SQLite already committed',
    () async {
      await transaction.apply();
      await db.markRestoreCommitted(transaction.id!);
      await recover();
      expect(
        await File('${active.path}/profiles/1.yaml').readAsString(),
        'restored',
      );
      expect(savedConfig?.currentProfileId, 1);
      expect(await db.isRestoreCommitted(transaction.id!), isFalse);
      expect(
        await Directory('${active.path}/.restore-recovery').list().toList(),
        isEmpty,
      );
    },
  );

  test('recovery retries safely after interruption during rollback', () async {
    await transaction.apply();
    await File(
      '${active.path}/.restore-recovery/${transaction.id}/0',
    ).rename('${active.path}/profiles/1.yaml');
    await recover();
    expect(
      await File('${active.path}/profiles/1.yaml').readAsString(),
      'original',
    );
    expect(await File('${active.path}/profiles/2.yaml').exists(), isFalse);
  });

  test(
    'failed settings persistence retains the journal and commit marker',
    () async {
      await transaction.apply();
      await db.markRestoreCommitted(transaction.id!);
      await expectLater(
        recover(persist: (_) async => throw StateError('storage unavailable')),
        throwsStateError,
      );
      expect(await db.isRestoreCommitted(transaction.id!), isTrue);
      expect(
        await File(
          '${active.path}/.restore-recovery/${transaction.id}/journal.json',
        ).exists(),
        isTrue,
      );
      await recover();
      expect(savedConfig?.currentProfileId, 1);
      expect(await db.isRestoreCommitted(transaction.id!), isFalse);
    },
  );

  test('recovery rejects paths outside the configuration namespace', () async {
    await transaction.apply();
    final journal = File(
      '${active.path}/.restore-recovery/${transaction.id}/journal.json',
    );
    final data = jsonDecode(await journal.readAsString()) as Map;
    data['files'][0]['path'] = '../account.json';
    await journal.writeAsString(jsonEncode(data));
    await expectLater(recover(), throwsFormatException);
    expect(
      await File('${active.path}/account.json').readAsString(),
      'retained account',
    );
  });
}
