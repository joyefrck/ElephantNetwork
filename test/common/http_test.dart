import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/http.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTPS rejects untrusted certificates', () async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/tls/localhost-cert.pem')
      ..usePrivateKey('test/fixtures/tls/localhost-key.pem');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write('verified');
      await request.response.close();
    }, onError: (Object _) {});
    final overrides = FlClashHttpOverrides(findProxy: (_) => 'DIRECT');
    final client = overrides.createHttpClient(null);
    addTearDown(() => client.close(force: true));
    final uri = Uri.parse('https://localhost:${server.port}/');
    await expectLater(client.getUrl(uri), throwsA(isA<HandshakeException>()));
  });

  test(
    'own HTTP client authenticates only to its configured local proxy',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = <String?>[];
      server.listen((request) async {
        final authorization = request.headers.value(
          HttpHeaders.proxyAuthorizationHeader,
        );
        received.add(authorization);
        if (authorization ==
            'Basic ${base64Encode(utf8.encode('user:pass'))}') {
          request.response.write('authenticated');
        } else {
          request.response.statusCode = HttpStatus.proxyAuthenticationRequired;
          request.response.headers.set(
            HttpHeaders.proxyAuthenticateHeader,
            'Basic realm="local"',
          );
        }
        await request.response.close();
      });
      var port = server.port;
      final overrides = FlClashHttpOverrides(
        findProxy: (_) => 'PROXY localhost:${server.port}',
        proxySettings: () => (
          port,
          const AuthenticationProps(
            enable: true,
            username: 'user',
            password: 'pass',
          ),
        ),
      );
      final client = overrides.createHttpClient(null);
      addTearDown(() => client.close(force: true));
      var response = await (await client.getUrl(
        Uri.parse('http://example.test/'),
      )).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(await utf8.decoder.bind(response).join(), 'authenticated');
      expect(received.first, isNull);
      expect(received.last, startsWith('Basic '));
      port++;
      final wrongPort = overrides.createHttpClient(null);
      addTearDown(() => wrongPort.close(force: true));
      received.clear();
      response = await (await wrongPort.getUrl(
        Uri.parse('http://example.test/'),
      )).close();
      expect(response.statusCode, HttpStatus.proxyAuthenticationRequired);
      await response.drain<void>();
      expect(received, [null]);
    },
  );
}
