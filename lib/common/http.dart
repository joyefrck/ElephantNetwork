import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/local_control.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FlClashHttpOverrides extends HttpOverrides {
  final String Function(Uri)? findProxy;
  final (int, AuthenticationProps) Function()? proxySettings;

  FlClashHttpOverrides({this.findProxy, this.proxySettings});

  static String handleFindProxy(Uri url) {
    if (['localhost', '127.0.0.1', '::1', '[::1]'].contains(url.host)) {
      return 'DIRECT';
    }
    final ref = globalState.container;
    final isStart = ref.read(isStartProvider);
    final suspend = ref.read(suspendProvider);
    commonPrint.log('find $url proxy: $isStart');
    if (!isStart || suspend) return 'DIRECT';
    final mixedPort = ref.read(
      patchClashConfigProvider.select((state) => state.mixedPort),
    );
    return 'PROXY localhost:$mixedPort';
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = findProxy ?? handleFindProxy;
    final attemptedCredentials = <(String, int, String?, String, String)>{};
    client.authenticateProxy = (host, port, scheme, realm) async {
      if (!['localhost', '127.0.0.1', '::1', '[::1]'].contains(host) ||
          scheme.toLowerCase() != 'basic') {
        return false;
      }
      final settings =
          proxySettings?.call() ??
          (
            globalState.container.read(patchClashConfigProvider).mixedPort,
            globalState.container.read(networkSettingProvider).authentication,
          );
      final authentication = settings.$2;
      if (port != settings.$1 ||
          !authentication.enable ||
          !authentication.isValid) {
        return false;
      }
      if (!attemptedCredentials.add((
        host,
        port,
        realm,
        authentication.username,
        authentication.password,
      ))) {
        return false;
      }
      client.addProxyCredentials(
        host,
        port,
        realm ?? '',
        HttpClientBasicCredentials(
          authentication.username,
          authentication.password,
        ),
      );
      return true;
    };
    return client;
  }
}
