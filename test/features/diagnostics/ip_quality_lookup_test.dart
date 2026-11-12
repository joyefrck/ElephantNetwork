import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/ip_quality.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final Future<ResponseBody> Function(
    RequestOptions options,
    Future<void>? cancel,
  )
  handler;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Map<String, dynamic> data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  test(
    'HTTPS winner cancels other sources and keeps source metadata',
    () async {
      var canceled = 0;
      final adapter = FakeAdapter((options, cancel) async {
        if (options.uri.host == 'api.ipquery.io') {
          return jsonBody({
            'ip': '8.8.8.8',
            'risk': {'is_datacenter': true, 'is_vpn': true},
            'isp': {'org': 'Test ASN', 'asn': 'AS123'},
          });
        }
        await cancel;
        canceled++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      });
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final result = await lookupIpQuality(
        dio,
        '8.8.8.8',
        cancelToken: CancelToken(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(result.type, IpType.hosting);
      expect(result.isVpn, isTrue);
      expect(result.asn, 123);
      expect(result.source, IpQualitySource.ipQuery);
      expect(canceled, 1);
      expect(adapter.requests.every((o) => o.uri.scheme == 'https'), isTrue);
    },
  );

  test(
    'source responses for another IP never become a quality answer',
    () async {
      final adapter = FakeAdapter(
        (_, _) async => jsonBody({
          'ip': '1.1.1.1',
          'type': 'hosting',
          'risk': {'is_datacenter': true},
        }),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      await expectLater(
        lookupIpQuality(
          dio,
          '8.8.8.8',
          cancelToken: CancelToken(),
          hedge: const Duration(milliseconds: 1),
        ),
        throwsA(
          isA<IpQualityLookupException>().having(
            (e) => e.failures.every(
              (f) => f.status == IpQualitySourceStatus.ipMismatch,
            ),
            'IP matches',
            isTrue,
          ),
        ),
      );
    },
  );

  test(
    'canceling the caller stops requests and prevents later waves',
    () async {
      final adapter = FakeAdapter((options, cancel) async {
        await cancel;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      });
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final token = CancelToken();
      final task = lookupIpQuality(
        dio,
        '8.8.8.8',
        cancelToken: token,
        hedge: const Duration(milliseconds: 20),
      );
      final assertion = expectLater(task, throwsA(isA<DioException>()));
      await Future<void>.delayed(const Duration(milliseconds: 1));
      token.cancel();
      await assertion;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(adapter.requests, hasLength(2));
    },
  );
}
