import 'dart:async';

import 'package:fl_clash/enum/enum.dart';

enum CoreMethod {
  message('message'),
  routeWatch('route.watch'),
  routeCheck('route.check'),
  probeOutboundIp('probe.outboundIp'),
  probeServices('probe.services'),
  probeCancel('probe.cancel'),
  coreInit('core.init'),
  coreInitialized('core.initialized'),
  coreGc('core.gc'),
  coreShutdown('core.shutdown'),
  configValidate('config.validate'),
  configUpdate('config.update'),
  configRead('config.read'),
  proxyList('proxy.list'),
  proxySelect('proxy.select'),
  trafficCurrent('traffic.current'),
  trafficTotal('traffic.total'),
  trafficReset('traffic.reset'),
  proxyTestDelay('proxy.testDelay'),
  connectionList('connection.list'),
  connectionCloseAll('connection.closeAll'),
  connectionReset('connection.reset'),
  dnsClearCache('dns.clearCache'),
  networkChanged('network.changed'),
  configUpdateRuntime('config.updateRuntime'),
  connectionClose('connection.close'),
  providerList('provider.list'),
  providerGet('provider.get'),
  geoUpdate('geo.update'),
  providerUpdate('provider.update'),
  providerSideLoad('provider.sideLoad'),
  logStart('log.start'),
  logStop('log.stop'),
  listenerStart('listener.start'),
  listenerStop('listener.stop'),
  geoCountryCode('geo.countryCode'),
  coreMemory('core.memory'),
  coreCrash('core.crash'),
  configSetup('config.setup'),
  profileClearEffect('profile.clearEffect'),
  dnsUpdateSystem('dns.updateSystem');

  final String wireName;

  const CoreMethod(this.wireName);

  static CoreMethod fromWireName(String value) => values.firstWhere(
    (method) => method.wireName == value,
    orElse: () => throw FormatException('Unknown Core method: $value'),
  );
}

class CoreMethodCall {
  final String? id;
  final CoreMethod method;
  final Object? arguments;

  const CoreMethodCall({this.id, required this.method, this.arguments});

  factory CoreMethodCall.fromJson(Map<String, Object?> json) {
    return CoreMethodCall(
      id: json['id'] as String?,
      method: CoreMethod.fromWireName(json['method'] as String),
      arguments: json['arguments'],
    );
  }

  Map<String, Object?> toJson() {
    return {
      if (id != null) 'id': id,
      'method': method.wireName,
      'arguments': arguments,
    };
  }
}

class CoreMethodError {
  final String code;
  final String message;
  final Object? details;

  const CoreMethodError({
    required this.code,
    required this.message,
    this.details,
  });

  factory CoreMethodError.fromJson(Map<String, Object?> json) {
    return CoreMethodError(
      code: json['code'] as String,
      message: json['message'] as String,
      details: json['details'],
    );
  }

  Map<String, Object?> toJson() {
    return {'code': code, 'message': message, 'details': details};
  }
}

class CoreMethodResponse {
  final String? id;
  final Object? result;
  final CoreMethodError? error;
  final String? file;

  const CoreMethodResponse({this.id, this.result, this.error, this.file});

  factory CoreMethodResponse.fromJson(Map<String, Object?> json) {
    final error = json['error'];
    return CoreMethodResponse(
      id: json['id'] as String?,
      file: json['file'] as String?,
      result: json['result'],
      error: error is Map
          ? CoreMethodError.fromJson(Map<String, Object?>.from(error))
          : null,
    );
  }

  Map<String, Object?> toJson() {
    return {
      if (id != null) 'id': id,
      'result': result,
      if (file != null) 'file': file,
      if (error != null) 'error': error!.toJson(),
    };
  }

  T? unwrap<T>() {
    final error = this.error;
    if (error != null) {
      throw CoreMethodException(
        code: error.code,
        message: error.message,
        details: error.details,
      );
    }
    return result as T?;
  }
}

class CoreMethodException implements Exception {
  final String code;
  final String message;
  final Object? details;

  const CoreMethodException({
    required this.code,
    required this.message,
    this.details,
  });

  bool get isCoreUnavailable => const {
    'transport_disconnected',
    'transport_error',
    'core_unavailable',
  }.contains(code);

  @override
  String toString() => 'CoreMethodException($code, $message, $details)';
}

LogLevel coreFailureLogLevel(Object? error) {
  if (error is TimeoutException) {
    return LogLevel.debug;
  }
  if (error is! CoreMethodException) {
    return LogLevel.warning;
  }
  return error.isCoreUnavailable ? LogLevel.debug : LogLevel.warning;
}
