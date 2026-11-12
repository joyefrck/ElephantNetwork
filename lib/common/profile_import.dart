import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/backup.dart';
import 'package:fl_clash/common/data_mutation.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:path/path.dart' as p;

const defaultCustomProfile =
    'proxies: []\nproxy-groups: []\nrules:\n  - MATCH,DIRECT\n';

Future<Profile> commitProfileData({
  required Database database,
  required String activeRoot,
  required Profile profile,
  required Uint8List bytes,
  required Future<void> Function() recoverPending,
  required Future<void> Function(String path) validate,
  void Function(Object error)? onCleanupFailure,
}) => dataMutationQueue.run(() async {
  if (profile.id <= 0) throw const FormatException('Invalid profile identity');
  await recoverPending();
  final staging = await Directory.systemTemp.createTemp('elephant-profile-');
  RestoreFileTransaction? files;
  var committed = false;
  try {
    final path = p.join(staging.path, 'profiles', profile.fileName);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    await validate(path);
    final now = DateTime.now();
    final next = profile.copyWith(
      lastUpdateDate: DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch ~/ 1000 * 1000,
      ),
    );
    files = RestoreFileTransaction(
      stagingRoot: staging.path,
      activeRoot: activeRoot,
      files: ['profiles/${profile.fileName}'],
    );
    await files.validate();
    await database.transaction(() async {
      await files!.apply();
      await database.profilesDao.putAll([next.toCompanion()]);
      await database.markRestoreCommitted(files.id!);
    });
    committed = true;
    try {
      final id = files.id!;
      await files.commit();
      if (!files.recoveryRequired) await database.forgetRestoreCommit(id);
    } catch (error) {
      onCleanupFailure?.call(error);
    }
    return next;
  } catch (_) {
    if (!committed) {
      await files?.rollback();
      await files?.commit();
    }
    rethrow;
  } finally {
    try {
      await staging.delete(recursive: true);
    } on FileSystemException catch (error) {
      onCleanupFailure?.call(error);
    }
  }
});
