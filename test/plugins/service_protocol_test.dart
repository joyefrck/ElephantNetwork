import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('$packageName/core');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'Android bridge preserves object arguments and null command replies',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        final request = jsonDecode(call.arguments as String) as Map;
        expect(request['method'], 'config.update');
        expect(request['arguments'], {'mixed-port': 7890});
        return jsonEncode({'id': request['id'], 'result': null});
      });
      final response = await Service().invokeMethod(
        const CoreMethodCall(
          id: '1',
          method: CoreMethod.configUpdate,
          arguments: {'mixed-port': 7890},
        ),
      );
      expect(response!.id, '1');
      expect(response.result, isNull);
      expect(response.error, isNull);
    },
  );

  test(
    'Android bridge rejects a mismatched reply instead of applying it',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => jsonEncode({'id': 'old', 'result': null}),
      );
      await expectLater(
        Service().invokeMethod(
          const CoreMethodCall(id: 'new', method: CoreMethod.configUpdate),
        ),
        throwsA(
          isA<CoreMethodException>().having(
            (error) => error.code,
            'code',
            'protocol_error',
          ),
        ),
      );
    },
  );
}
