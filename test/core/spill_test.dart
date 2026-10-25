import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/core/spill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory responses;
  late CoreSpillStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elephant-spill-');
    responses = await Directory('${root.path}/responses').create();
    store = CoreSpillStore(() async => responses.path);
  });

  tearDown(() => root.delete(recursive: true));

  test('reads a large response and deletes the file', () async {
    final result = List.generate(20000, (i) => {'name': 'proxy-$i'});
    final file = await File(
      '${responses.path}/answer.json',
    ).writeAsString(jsonEncode({'id': '1', 'result': result}));
    final response = await store.resolve(
      CoreMethodResponse(id: '1', file: file.path),
    );
    expect(response.unwrap<List>(), result);
    expect(await file.exists(), false);
  });

  test(
    'rejects foreign files and symlinks without deleting their targets',
    () async {
      final foreign = await File(
        '${root.path}/private.json',
      ).writeAsString('{}');
      final link = await Link(
        '${responses.path}/link.json',
      ).create(foreign.path);
      for (final path in [foreign.path, link.path]) {
        final response = await store.resolve(
          CoreMethodResponse(id: '1', file: path),
        );
        expect(response.error?.code, 'spill_error');
        await store.discard(CoreMethodResponse(file: path));
      }
      expect(await foreign.exists(), true);
      expect(await link.exists(), true);
    },
  );

  test('refuses a spill directory that is itself a symlink', () async {
    final outside = await Directory('${root.path}/outside').create();
    final file = await File(
      '${outside.path}/response.json',
    ).writeAsString('{}');
    final alias = await Link('${root.path}/alias').create(outside.path);
    final aliasedStore = CoreSpillStore(() async => alias.path);
    final response = CoreMethodResponse(
      id: '1',
      file: '${alias.path}/response.json',
    );
    expect((await aliasedStore.resolve(response)).error?.code, 'spill_error');
    await aliasedStore.discard(response);
    expect(await file.exists(), true);
  });

  test('rejects mismatched request IDs and cleans the file', () async {
    final file = await File(
      '${responses.path}/answer.json',
    ).writeAsString(jsonEncode({'id': 'other', 'result': true}));
    final response = await store.resolve(
      CoreMethodResponse(id: '1', file: file.path),
    );
    expect(response.error?.code, 'spill_error');
    expect(await file.exists(), false);
  });

  test('malformed and late responses do not leave files', () async {
    final file = await File('${responses.path}/answer.json').writeAsString('{');
    expect(
      (await store.resolve(CoreMethodResponse(file: file.path))).error?.code,
      'spill_error',
    );
    expect(await file.exists(), false);
    await file.writeAsString('{}');
    await store.discard(CoreMethodResponse(file: file.path));
    expect(await file.exists(), false);
    expect(
      (await store.resolve(CoreMethodResponse(file: file.path))).error?.code,
      'spill_error',
    );
  });
}
