import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  late ProviderContainer container;

  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'Elephant Network',
      packageName: 'com.elephantroute',
      version: '2.0.7',
      buildNumber: '20007',
    );
  });

  setUp(() {
    container = ProviderContainer();
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  for (final flag in [null, 'flclash', 'flclash/2.0.7', 'meta']) {
    test(
      'managed profile download normalizes the saved $flag renderer',
      () async {
        final request = await _requestSubscription(ProfileSource.xboard, flag);

        expect(request.queryParameters['flag'], 'meta');
        expect(request.queryParameters['token'], 'fixture-token');
        expect(request.queryParameters['filter'], 'test');
      },
    );
  }

  for (final flag in [null, 'flclash', 'shadowrocket']) {
    test(
      'imported profile download preserves the saved $flag renderer',
      () async {
        final request = await _requestSubscription(ProfileSource.user, flag);

        expect(request.queryParameters['flag'], flag);
        expect(request.queryParameters['token'], 'fixture-token');
      },
    );
  }
}

Future<Uri> _requestSubscription(ProfileSource source, String? flag) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  Uri? requested;
  server.listen((request) async {
    requested = request.uri;
    request.response.statusCode = HttpStatus.serviceUnavailable;
    await request.response.close();
  });
  final uri = Uri(
    scheme: 'http',
    host: server.address.address,
    port: server.port,
    path: '/subscribe',
    queryParameters: {
      'token': 'fixture-token',
      'filter': 'test',
      'flag': ?flag,
    },
  );
  final profile = Profile(
    id: 28,
    url: uri.toString(),
    source: source,
    autoUpdateDuration: const Duration(days: 1),
  );
  try {
    await expectLater(profile.update(), throwsA(anything));
    expect(requested, isNotNull);
    expect(profile.url, uri.toString());
    return requested!;
  } finally {
    await server.close(force: true);
  }
}
