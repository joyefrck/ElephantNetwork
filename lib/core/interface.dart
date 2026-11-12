import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';

import 'desktop/model.dart';
import 'method.dart';

mixin CoreInterface {
  Future<CoreLifecycleResult> start();

  Future<CoreLifecycleResult> restart();

  Future<CoreLifecycleResult> stop();

  Future<CoreLifecycleResult> close();

  Future<bool> init(InitParams params);

  Future<bool> get isInit;

  Future<bool> forceGc();

  Future<String> validateConfig(String path, {bool runtime = false});

  Future<Map<String, dynamic>> getConfig(String path);

  Future<Delay> asyncTestDelay(
    String url,
    String proxyName, [
    Duration? timeout,
  ]);

  Future<String> updateConfig(UpdateParams updateParams);

  Future<String> setupConfig(SetupParams setupParams);

  Future<ProxiesData> getProxies();

  Future<String> changeProxy(ChangeProxyParams changeProxyParams);

  Future<bool> startListener();

  Future<bool> stopListener();

  Future<List<ExternalProvider>> getExternalProviders();

  Future<ExternalProvider?> getExternalProvider(String externalProviderName);

  Future<String> updateGeoData(String type);

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  });

  Future<String> updateExternalProvider(String providerName);

  FutureOr<Traffic> getTraffic(bool onlyStatisticsProxy);

  FutureOr<Traffic> getTotalTraffic(bool onlyStatisticsProxy);

  FutureOr<String> getCountryCode(String ip);

  FutureOr<int> getMemory();

  FutureOr<void> resetTraffic();

  FutureOr<void> startLog();

  FutureOr<void> stopLog();

  Future<bool> crash();

  FutureOr<List<TrackerInfo>> getConnections();

  FutureOr<bool> closeConnection(String id);

  FutureOr<String> clearEffect(int profileId);

  FutureOr<bool> closeConnections();

  FutureOr<bool> resetConnections();

  Future<bool> clearDnsCache();

  Future<bool> resetNetwork();

  Future<String> updateRuntimeConfig(Map<String, dynamic> config);
}

abstract class CoreHandlerInterface with CoreInterface {
  Future<T?> _invokeMethod<T>({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  }) async {
    return await utils.handleWatch(
      onStart: () {
        commonPrint.log('Invoke method ${method.name} ${DateTime.now()}');
      },
      function: () async {
        return invokeMethod<T>(
          method: method,
          arguments: arguments,
          timeout: timeout,
        );
      },
      onEnd: (result, elapsedMilliseconds) {
        commonPrint.log(
          'Invoke method ${method.name} completed in ${elapsedMilliseconds}ms',
        );
      },
    );
  }

  Future<void> _invokeCommand({
    required CoreMethod method,
    Object? arguments,
  }) async {
    final result = await _invokeMethod<Object?>(
      method: method,
      arguments: arguments,
    );
    if (result != null) {
      throw CoreMethodException(
        code: 'protocol_error',
        message: 'Command ${method.wireName} returned a non-null result',
      );
    }
  }

  Future<T?> invokeMethod<T>({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  });

  @override
  Future<bool> clearDnsCache() async {
    await _invokeCommand(method: CoreMethod.dnsClearCache);
    return true;
  }

  @override
  Future<bool> resetNetwork() async {
    await _invokeCommand(method: CoreMethod.networkChanged);
    return true;
  }

  @override
  Future<String> updateRuntimeConfig(Map<String, dynamic> config) async {
    await _invokeCommand(
      method: CoreMethod.configUpdateRuntime,
      arguments: config,
    );
    return '';
  }

  @override
  Future<bool> init(InitParams params) async {
    await _invokeCommand(
      method: CoreMethod.coreInit,
      arguments: params.toJson(),
    );
    return true;
  }

  @override
  Future<bool> get isInit async {
    return await _invokeMethod<bool>(method: CoreMethod.coreInitialized) ??
        false;
  }

  @override
  Future<bool> forceGc() async {
    await _invokeCommand(method: CoreMethod.coreGc);
    return true;
  }

  @override
  Future<String> validateConfig(String path, {bool runtime = false}) async {
    await _invokeCommand(
      method: CoreMethod.configValidate,
      arguments: {'path': path, if (runtime) 'runtime': true},
    );
    return '';
  }

  @override
  Future<String> updateConfig(UpdateParams updateParams) async {
    await _invokeCommand(
      method: CoreMethod.configUpdate,
      arguments: updateParams.toJson(),
    );
    return '';
  }

  @override
  Future<Map<String, dynamic>> getConfig(String path) async {
    final result = await _invokeMethod<Map<String, dynamic>>(
      method: CoreMethod.configRead,
      arguments: {'path': path},
    );
    if (result == null) {
      throw const CoreMethodException(
        code: 'empty_result',
        message: 'Core returned an empty config result',
      );
    }
    return result;
  }

  @override
  Future<String> setupConfig(SetupParams setupParams) async {
    await _invokeCommand(
      method: CoreMethod.configSetup,
      arguments: setupParams.toJson(),
    );
    return '';
  }

  @override
  Future<bool> crash() async {
    return await _invokeMethod<bool>(method: CoreMethod.coreCrash) ?? false;
  }

  @override
  Future<ProxiesData> getProxies() async {
    final data = await _invokeMethod<Map<String, dynamic>>(
      method: CoreMethod.proxyList,
    );
    return data != null
        ? ProxiesData.fromJson(data)
        : const ProxiesData(proxies: {}, all: []);
  }

  @override
  Future<String> changeProxy(ChangeProxyParams changeProxyParams) async {
    await _invokeCommand(
      method: CoreMethod.proxySelect,
      arguments: changeProxyParams.toJson(),
    );
    return '';
  }

  @override
  Future<List<ExternalProvider>> getExternalProviders() async {
    final data = await _invokeMethod<List<dynamic>>(
      method: CoreMethod.providerList,
    );
    return data
            ?.whereType<Map>()
            .map(
              (item) =>
                  ExternalProvider.fromJson(Map<String, Object?>.from(item)),
            )
            .toList() ??
        [];
  }

  @override
  Future<ExternalProvider?> getExternalProvider(
    String externalProviderName,
  ) async {
    final data = await _invokeMethod<Map<String, dynamic>>(
      method: CoreMethod.providerGet,
      arguments: {'name': externalProviderName},
    );
    return data == null ? null : ExternalProvider.fromJson(data);
  }

  @override
  Future<String> updateGeoData(String type) async {
    await _invokeCommand(
      method: CoreMethod.geoUpdate,
      arguments: {'type': type},
    );
    return '';
  }

  @override
  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) async {
    await _invokeCommand(
      method: CoreMethod.providerSideLoad,
      arguments: {'name': providerName, 'data': data},
    );
    return '';
  }

  @override
  Future<String> updateExternalProvider(String providerName) async {
    await _invokeCommand(
      method: CoreMethod.providerUpdate,
      arguments: {'name': providerName},
    );
    return '';
  }

  @override
  Future<List<TrackerInfo>> getConnections() async {
    final data = await _invokeMethod<Map<String, dynamic>>(
      method: CoreMethod.connectionList,
    );
    final connections = data?['connections'];
    if (connections is! List) {
      return [];
    }
    return connections
        .whereType<Map>()
        .map((item) => TrackerInfo.fromJson(Map<String, Object?>.from(item)))
        .toList();
  }

  @override
  Future<bool> closeConnections() async {
    await _invokeCommand(method: CoreMethod.connectionCloseAll);
    return true;
  }

  @override
  Future<bool> resetConnections() async {
    await _invokeCommand(method: CoreMethod.connectionReset);
    return true;
  }

  @override
  Future<bool> closeConnection(String id) async {
    await _invokeCommand(
      method: CoreMethod.connectionClose,
      arguments: {'id': id},
    );
    return true;
  }

  @override
  Future<Traffic> getTotalTraffic(bool onlyStatisticsProxy) async {
    final data = await _invokeMethod<Map<String, dynamic>>(
      method: CoreMethod.trafficTotal,
      arguments: {'only-statistics-proxy': onlyStatisticsProxy},
    );
    return data == null ? const Traffic() : Traffic.fromJson(data);
  }

  @override
  Future<Traffic> getTraffic(bool onlyStatisticsProxy) async {
    final data = await _invokeMethod<Map<String, dynamic>>(
      method: CoreMethod.trafficCurrent,
      arguments: {'only-statistics-proxy': onlyStatisticsProxy},
    );
    return data == null ? const Traffic() : Traffic.fromJson(data);
  }

  @override
  Future<String> clearEffect(int profileId) async {
    await _invokeCommand(
      method: CoreMethod.profileClearEffect,
      arguments: {'profile-id': profileId},
    );
    return '';
  }

  @override
  FutureOr<void> resetTraffic() {
    return _invokeCommand(method: CoreMethod.trafficReset);
  }

  @override
  FutureOr<void> startLog() {
    return _invokeCommand(method: CoreMethod.logStart);
  }

  @override
  FutureOr<void> stopLog() {
    return _invokeCommand(method: CoreMethod.logStop);
  }

  @override
  Future<bool> startListener() async {
    await _invokeCommand(method: CoreMethod.listenerStart);
    return true;
  }

  @override
  Future<bool> stopListener() async {
    await _invokeCommand(method: CoreMethod.listenerStop);
    return true;
  }

  @override
  Future<Delay> asyncTestDelay(
    String url,
    String proxyName, [
    Duration? timeout,
  ]) async {
    final effectiveTimeout = Duration(
      milliseconds: (timeout ?? httpTimeoutDuration).inMilliseconds.clamp(
        100,
        120000,
      ),
    );
    final delayParams = {
      'proxy-name': proxyName,
      'timeout': effectiveTimeout.inMilliseconds,
      'test-url': url,
    };
    final data = await _invokeMethod<Map<String, dynamic>>(
      method: CoreMethod.proxyTestDelay,
      arguments: delayParams,
      timeout: const Duration(minutes: 4, seconds: 2),
    );
    return data == null
        ? Delay(name: proxyName, value: -1, url: url)
        : Delay.fromJson(data);
  }

  @override
  Future<String> getCountryCode(String ip) async {
    return await _invokeMethod<String>(
          method: CoreMethod.geoCountryCode,
          arguments: {'ip': ip},
        ) ??
        '';
  }

  @override
  Future<int> getMemory() async {
    return await _invokeMethod<int>(method: CoreMethod.coreMemory) ?? 0;
  }
}
