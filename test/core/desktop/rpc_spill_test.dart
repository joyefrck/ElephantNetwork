import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/core/desktop/rpc_client.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/core/spill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

class _ObservedStore extends CoreSpillStore {
  final resolved = Completer<void>();
  _ObservedStore(super.directory);

  @override
  Future<CoreMethodResponse> resolve(CoreMethodResponse response) async {
    final result = await super.resolve(response);
    if (!resolved.isCompleted) resolved.complete();
    return result;
  }
}

void main() {
  test(
    'RPC resolves file responses and cleans late responses after timeout',
    () async {
      final directory = await Directory.systemTemp.createTemp('rpc-spill-');
      final gate = Completer<String>();
      final store = _ObservedStore(() => gate.future);
      final transport = FakeDesktopCoreTransport.connected();
      final client = CoreRpcClient(
        transport,
        spillStore: store,
        extensionGrace: Duration.zero,
      );
      addTearDown(() async {
        await client.close();
        await transport.close();
        await directory.delete(recursive: true);
      });
      final invocation = client.invoke<Map>(
        method: CoreMethod.getConfig,
        timeout: const Duration(milliseconds: 50),
      );
      await pumpEventQueue();
      final request = jsonDecode(transport.sentMessages.single) as Map;
      final file = await File('${directory.path}/response.json').writeAsString(
        jsonEncode({
          'id': request['id'],
          'result': {'mode': 'rule'},
        }),
      );
      transport.addJson({'id': request['id'], 'file': file.path});
      expect(await invocation, isNull);
      gate.complete(directory.path);
      await store.resolved.future;
      expect(await file.exists(), false);
      expect(client.pendingCount, 0);

      final next = client.invoke<Map>(method: CoreMethod.getConfig);
      await pumpEventQueue();
      final nextRequest = jsonDecode(transport.sentMessages.last) as Map;
      await file.writeAsString(
        jsonEncode({
          'id': nextRequest['id'],
          'result': {'mode': 'global'},
        }),
      );
      transport.addJson({'id': nextRequest['id'], 'file': file.path});
      expect(await next, {'mode': 'global'});
      expect(await file.exists(), false);
    },
  );
}
