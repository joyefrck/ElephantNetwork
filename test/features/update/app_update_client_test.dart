import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/account/xboard_config.dart';
import 'package:fl_clash/features/update/app_update_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in ['android', 'windows', 'macos', 'linux']) {
    test(
      '$platform sends both version and build and preserves update details',
      () async {
        RequestOptions? request;
        final dio = Dio()
          ..httpClientAdapter = _ResponseAdapter((options) {
            request = options;
            return _release();
          });
        addTearDown(dio.close);
        final client = AppUpdateClient(
          dio: dio,
          resolveBaseUrl: () async => 'https://updates.example',
          platform: platform,
          arch: 'arm64',
        );

        final result = await client.check(version: '2.1.0', build: '21000');

        expect(
          request?.path,
          'https://updates.example${XboardConfig.updatePath}',
        );
        expect(request?.queryParameters, {
          'app_key': platform == 'android'
              ? XboardConfig.androidDistributionAppKey
              : XboardConfig.desktopDistributionAppKey,
          'platform': platform,
          'channel': 'stable',
          'version': '2.1.0',
          'build': 21000,
          'arch': 'arm64',
        });
        expect(result?['tag_name'], 'v2.1.0');
        expect(result?['build_number'], 21001);
        expect(result?['body'], _notes);
        expect(
          result?['download_url'],
          'https://updates.example/download/client.pkg',
        );
      },
    );
  }

  test('no update returns no prompt payload', () async {
    final dio = Dio()
      ..httpClientAdapter = _ResponseAdapter(
        (_) => {
          'data': {'has_update': false, 'latest': _latest()},
        },
      );
    addTearDown(dio.close);
    final client = AppUpdateClient(
      dio: dio,
      resolveBaseUrl: () async => 'https://updates.example',
    );

    expect(await client.check(version: '2.1.0', build: '21001'), isNull);
  });

  for (final fields in [
    {'build_number': null},
    {'build_number': 'invalid'},
    {'build_number': 0},
    {'version': ''},
    {'download_url': 'http://insecure.example/client.pkg'},
    {'download_url': 'javascript:alert(1)'},
  ]) {
    test('rejects invalid release metadata: $fields', () async {
      final dio = Dio()
        ..httpClientAdapter = _ResponseAdapter((_) => _release(fields));
      addTearDown(dio.close);
      final client = AppUpdateClient(
        dio: dio,
        resolveBaseUrl: () async => 'https://updates.example',
      );

      expect(await client.check(version: '2.1.0', build: '21000'), isNull);
    });
  }
}

const _notes =
    'Improved login\n\nPasswords no longer clear the email.\n1. Updated icons';

Map<String, Object?> _latest([Map<String, Object?> fields = const {}]) {
  return {
    'version': '2.1.0',
    'build_number': 21001,
    'release_notes': _notes,
    'download_url': '/download/client.pkg',
    ...fields,
  };
}

Map<String, Object?> _release([Map<String, Object?> fields = const {}]) {
  return {
    'data': {'has_update': true, 'latest': _latest(fields)},
  };
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.response);

  final Object? Function(RequestOptions) response;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(response(options)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
