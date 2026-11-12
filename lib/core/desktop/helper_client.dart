import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:path/path.dart' as p;

import 'core_manifest.dart';
import 'launcher.dart';
import 'model.dart';

enum HelperReadiness { ready, notReady, manifestMissing }

final class HelperStartResponse {
  final String sessionId;
  final int pid;

  const HelperStartResponse({required this.sessionId, required this.pid});
}

final class HelperStopResponse {
  final String sessionId;
  final bool stopped;
  final String? reason;

  const HelperStopResponse({
    required this.sessionId,
    required this.stopped,
    this.reason,
  });
}

final class HelperException implements Exception {
  final String code;
  final String message;
  final Object? details;

  const HelperException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'HelperException($code, $message, $details)';
}

final class HelperClient {
  final Dio _dio;
  final String Function() _expectedHelperPath;
  final Future<String> Function() _readCoreSha256;
  final String baseUrl;
  final bool useUnixSocket;
  String? _coreSha256Cache;

  HelperClient({
    Dio? dio,
    String Function()? expectedHelperPath,
    Future<String> Function()? readCoreSha256,
    this.baseUrl = 'http://$localhost:$helperPort',
    bool? useUnixSocket,
  }) : useUnixSocket = useUnixSocket ?? Platform.isLinux,
       _dio =
           dio ??
           _createLoopbackDio(useUnixSocket: useUnixSocket ?? Platform.isLinux),
       _expectedHelperPath = expectedHelperPath ?? _defaultHelperPath,
       _readCoreSha256 = readCoreSha256 ?? _readBundledCoreSha256;

  Future<String> _readCoreSha256Once() async {
    final cached = _coreSha256Cache;
    if (cached != null) {
      return cached;
    }
    String coreSha256;
    try {
      coreSha256 = await _readCoreSha256();
    } catch (_) {
      coreSha256 = '';
    }
    if (coreSha256.isNotEmpty) {
      _coreSha256Cache = coreSha256;
    }
    return coreSha256;
  }

  static Dio _createLoopbackDio({required bool useUnixSocket}) {
    return Dio()
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (uri) => 'DIRECT';
          if (useUnixSocket) {
            client.connectionFactory = (uri, proxyHost, proxyPort) async {
              for (final path in [
                helperSocketPath,
                p.dirname(helperSocketPath),
              ]) {
                final result = await Process.run('/usr/bin/stat', [
                  '-c',
                  '%u:%a:%F',
                  path,
                ]);
                final parts = result.stdout.toString().trim().split(':');
                final mode = parts.length == 3
                    ? int.tryParse(parts[1], radix: 8)
                    : null;
                if (result.exitCode != 0 ||
                    parts.length != 3 ||
                    parts[0] != '0' ||
                    mode == null ||
                    (path == helperSocketPath
                        ? parts[2] != 'socket'
                        : parts[2] != 'directory' || (mode & 18) != 0)) {
                  throw const SocketException('Untrusted helper socket');
                }
              }
              return Socket.startConnect(
                InternetAddress(
                  helperSocketPath,
                  type: InternetAddressType.unix,
                ),
                0,
              );
            };
          }
          return client;
        },
      );
  }

  static Future<String> _readBundledCoreSha256() async {
    return (await CoreManifest.readCoreSha256()) ?? '';
  }

  static String _defaultHelperPath() {
    return p.join(
      p.dirname(Platform.resolvedExecutable),
      '$appHelperService${Platform.isWindows ? '.exe' : ''}',
    );
  }

  Future<HelperReadiness> readiness({
    Duration? timeout,
    bool logFailure = true,
  }) async {
    if (timeout != null && timeout <= Duration.zero) {
      return HelperReadiness.notReady;
    }
    final cancelToken = CancelToken();
    final timeoutTimer = timeout == null
        ? null
        : Timer(
            timeout,
            () => cancelToken.cancel('helper ping deadline exceeded'),
          );
    try {
      final coreSha256 = await _readCoreSha256Once();
      if (coreSha256.isEmpty) {
        _logPingFailure('Core manifest is missing or invalid', logFailure);
        return HelperReadiness.manifestMissing;
      }
      final response = await _dio.get<Object?>(
        '$baseUrl/ping',
        queryParameters: {'coreSha256': coreSha256},
        cancelToken: cancelToken,
        options: _options(ResponseType.plain, acceptAnyStatus: true),
      );
      return response.statusCode == HttpStatus.ok
          ? _readyFromOk(response, logFailure)
          : _notReadyFromPing(response, logFailure);
    } catch (error) {
      _logPingFailure('helper ping failed: $error', logFailure);
      return HelperReadiness.notReady;
    } finally {
      timeoutTimer?.cancel();
    }
  }

  HelperReadiness _readyFromOk(Response<Object?> response, bool logFailure) {
    final protocolVersion = response.headers.value(helperProtocolVersionHeader);
    final helperPath = response.data;
    if (helperPath is! String) {
      _logPingFailure('helper ping returned invalid response', logFailure);
      return HelperReadiness.notReady;
    }
    if (protocolVersion != helperProtocolVersion) {
      _logPingFailure('helper protocol mismatch: $protocolVersion', logFailure);
      return HelperReadiness.notReady;
    }
    final matches = p.Context(
      style: useUnixSocket ? p.Style.posix : p.Style.windows,
    ).equals(helperPath.trim(), _expectedHelperPath());
    if (!matches) {
      _logPingFailure('helper executable path mismatch', logFailure);
      return HelperReadiness.notReady;
    }
    return HelperReadiness.ready;
  }

  HelperReadiness _notReadyFromPing(
    Response<Object?> response,
    bool logFailure,
  ) {
    final statusCode = response.statusCode;
    final protocolVersion = response.headers.value(helperProtocolVersionHeader);
    if (statusCode == HttpStatus.conflict) {
      final code = _mapFrom(response.data)?['code'];
      if (code == 'coreSha256Mismatch') {
        _logPingFailure('Helper Core SHA256 mismatch', logFailure);
        return HelperReadiness.notReady;
      }
      if (protocolVersion == helperProtocolVersion) {
        _logPingFailure(
          'helper could not access the Core executable',
          logFailure,
        );
        return HelperReadiness.notReady;
      }
      _logPingFailure(
        'helper returned an unrecognized conflict '
        '(protocol $protocolVersion)',
        logFailure,
      );
      return HelperReadiness.notReady;
    }
    _logPingFailure(
      'helper ping returned HTTP $statusCode '
      '(protocol $protocolVersion)',
      logFailure,
    );
    return HelperReadiness.notReady;
  }

  void _logPingFailure(String message, bool enabled) {
    if (enabled) {
      commonPrint.log(message, logLevel: LogLevel.warning);
    }
  }

  Future<HelperStartResponse> start({
    required String address,
    required String sessionId,
  }) async {
    _validateSessionId(sessionId);
    try {
      final response = await _dio.post<Object?>(
        '$baseUrl/start',
        data: {'address': address, 'sessionId': sessionId},
        options: _options(ResponseType.json),
      );
      final data = _responseMap(response, operation: 'start');
      final returnedSession = data['sessionId'];
      final pid = data['pid'];
      if (returnedSession != sessionId || pid is! int || pid <= 0) {
        throw const HelperException(
          code: 'invalidResponse',
          message: 'Helper returned an invalid start response',
        );
      }
      return HelperStartResponse(
        sessionId: returnedSession as String,
        pid: pid,
      );
    } on HelperException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error, operation: 'start');
    } catch (error) {
      throw HelperException(
        code: 'transportError',
        message: 'Unable to start Core through Helper',
        details: error.toString(),
      );
    }
  }

  Future<HelperStopResponse> stop(String sessionId) async {
    _validateSessionId(sessionId);
    try {
      final response = await _dio.post<Object?>(
        '$baseUrl/stop',
        data: {'sessionId': sessionId},
        options: _options(ResponseType.json),
      );
      return _parseStopResponse(response, sessionId);
    } on HelperException {
      rethrow;
    } on DioException catch (error) {
      final response = error.response;
      if (response?.statusCode == HttpStatus.conflict) {
        final data = _mapFrom(response?.data);
        final reason = data?['reason'];
        if (reason is String) {
          throw HelperException(
            code: reason,
            message: 'Helper refused to stop the requested Core session',
            details: data,
          );
        }
      }
      throw _mapDioException(error, operation: 'stop');
    } catch (error) {
      throw HelperException(
        code: 'transportError',
        message: 'Unable to stop Core through Helper',
        details: error.toString(),
      );
    }
  }

  HelperStopResponse _parseStopResponse(
    Response<Object?> response,
    String sessionId,
  ) {
    final data = _responseMap(response, operation: 'stop');
    final returnedSession = data['sessionId'];
    final stopped = data['stopped'];
    final reason = data['reason'];
    if (returnedSession != sessionId ||
        stopped is! bool ||
        (stopped && reason != null) ||
        (!stopped && reason != 'notRunning')) {
      throw const HelperException(
        code: 'invalidResponse',
        message: 'Helper returned an invalid stop response',
      );
    }
    return HelperStopResponse(
      sessionId: returnedSession as String,
      stopped: stopped,
      reason: reason as String?,
    );
  }

  Map<String, Object?> _responseMap(
    Response<Object?> response, {
    required String operation,
  }) {
    if (response.statusCode != HttpStatus.ok) {
      throw HelperException(
        code: 'unexpectedStatus',
        message: 'Helper $operation returned HTTP ${response.statusCode}',
        details: response.data,
      );
    }
    final data = _mapFrom(response.data);
    if (data == null) {
      throw HelperException(
        code: 'invalidResponse',
        message: 'Helper returned an invalid $operation response',
        details: response.data,
      );
    }
    return data;
  }

  HelperException _mapDioException(
    DioException error, {
    required String operation,
  }) {
    final data = _mapFrom(error.response?.data);
    final code = data?['code'];
    final message = data?['message'];
    if (code is String && message is String) {
      return HelperException(
        code: code,
        message: message,
        details: data?['details'],
      );
    }
    return HelperException(
      code: 'transportError',
      message: 'Helper $operation request failed',
      details: error.toString(),
    );
  }

  Map<String, Object?>? _mapFrom(Object? data) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    if (data is! Map) {
      return null;
    }
    return Map<String, Object?>.from(data);
  }

  void _validateSessionId(String sessionId) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(sessionId)) {
      throw const HelperException(
        code: 'invalidSessionId',
        message: 'Core session ID must be 128-bit lowercase hexadecimal',
      );
    }
  }

  Options _options(ResponseType responseType, {bool acceptAnyStatus = false}) {
    return Options(
      responseType: responseType,
      connectTimeout: const Duration(milliseconds: 300),
      receiveTimeout: const Duration(seconds: 2),
      validateStatus: acceptAnyStatus ? (_) => true : null,
    );
  }
}

final class HelperLauncher implements CoreProcessLauncher {
  final HelperClient client;

  const HelperLauncher(this.client);

  @override
  Future<CoreProcessLease> start({
    required String sessionId,
    required String address,
  }) async {
    try {
      final response = await client.start(
        address: address,
        sessionId: sessionId,
      );
      return HelperCoreLease(
        sessionId: response.sessionId,
        pid: response.pid,
        client: client,
      );
    } catch (error, stackTrace) {
      try {
        await client.stop(sessionId);
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

const _preSpawnHelperErrors = {'coreVerificationFailed', 'processLaunchFailed'};

final class FallbackCoreLauncher implements CoreProcessLauncher {
  final CoreProcessLauncher primary;
  final CoreProcessLauncher fallback;

  const FallbackCoreLauncher({required this.primary, required this.fallback});

  @override
  Future<CoreProcessLease> start({
    required String sessionId,
    required String address,
  }) async {
    try {
      return await primary.start(sessionId: sessionId, address: address);
    } on HelperException catch (error) {
      if (!_preSpawnHelperErrors.contains(error.code)) rethrow;
      commonPrint.log(
        'Helper could not start the Core ($error); '
        'falling back to direct Core',
        logLevel: LogLevel.warning,
      );
      return fallback.start(sessionId: sessionId, address: address);
    }
  }
}

typedef HelperReadinessProbe = Future<HelperReadiness> Function();

final class HelperLauncherResolver implements DesktopCoreLauncherResolver {
  final bool supportsHelper;
  final CoreProcessLauncher directLauncher;
  final CoreProcessLauncher helperLauncher;
  final HelperReadinessProbe helperReady;

  const HelperLauncherResolver({
    required this.supportsHelper,
    required this.directLauncher,
    required this.helperLauncher,
    required this.helperReady,
  });

  @override
  Future<CoreProcessLauncher> resolve() async {
    if (!supportsHelper) return directLauncher;
    final readiness = await helperReady();
    if (readiness == HelperReadiness.ready) {
      return FallbackCoreLauncher(
        primary: helperLauncher,
        fallback: directLauncher,
      );
    }
    return directLauncher;
  }
}

final class HelperCoreLease implements CoreProcessLease {
  @override
  final String sessionId;

  @override
  final int pid;

  final HelperClient _client;
  Future<CoreProcessStopResult>? _stopOperation;

  HelperCoreLease({
    required this.sessionId,
    required this.pid,
    required HelperClient client,
  }) : _client = client;

  @override
  CoreProcessOwner get owner => CoreProcessOwner.helper;

  @override
  Future<CoreProcessStopResult> stop(Duration timeout) {
    final stopOperation = _stopOperation;
    if (stopOperation != null) {
      return stopOperation;
    }
    final nextOperation = _stop().onError((
      Object error,
      StackTrace stackTrace,
    ) {
      _stopOperation = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _stopOperation = nextOperation;
    return nextOperation;
  }

  Future<CoreProcessStopResult> _stop() async {
    final response = await _client.stop(sessionId);
    return CoreProcessStopResult(
      stopped: response.stopped,
      exitConfirmed: true,
    );
  }
}

final desktopHelperClient = HelperClient();
