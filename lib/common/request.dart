import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/account/xboard_config.dart';
import 'package:fl_clash/features/account/xboard_domain_resolver.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/cupertino.dart';

class Request {
  late final Dio dio;
  late final Dio _clashDio;
  String? userAgent;

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = globalState.ua;
          return FlClashHttpOverrides.handleFindProxy(uri);
        };
        return client;
      },
    );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      return await _clashDio.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
    } catch (e) {
      commonPrint.log('getFileResponseForUrl error ${e.toString()}');
      if (e is DioException) {
        if (e.type == DioExceptionType.unknown) {
          throw currentAppLocalizations.unknownNetworkError;
        } else if (e.type == DioExceptionType.badResponse) {
          throw currentAppLocalizations.networkException;
        }
        rethrow;
      }
      throw currentAppLocalizations.unknownNetworkError;
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    final response = await _clashDio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response;
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    final response = await dio.get<Uint8List>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) return null;
    return MemoryImage(data);
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      if (!system.isAndroid && !system.isWindows && !system.isMacOS) {
        return null;
      }
      final platform = system.isAndroid
          ? 'android'
          : system.isWindows
          ? 'windows'
          : 'macos';
      final appKey = system.isAndroid
          ? XboardConfig.androidDistributionAppKey
          : XboardConfig.desktopDistributionAppKey;
      final executable = Platform.resolvedExecutable.toLowerCase();
      final arch = system.isAndroid
          ? 'arm64'
          : executable.contains('arm64') ||
                Platform.version.toLowerCase().contains('arm64')
          ? 'arm64'
          : 'x64';
      final runtimeBaseUrl = await xboardDomainResolver.resolve();
      final response = await dio.get(
        '$runtimeBaseUrl${XboardConfig.updatePath}',
        queryParameters: {
          'app_key': appKey,
          'platform': platform,
          'channel': 'stable',
          'version': globalState.packageInfo.version,
          'build': int.tryParse(globalState.packageInfo.buildNumber) ?? 0,
          'arch': arch,
        },
        options: Options(responseType: ResponseType.json),
      );
      if (response.statusCode != 200) return null;
      final body = response.data;
      if (body is! Map) return null;
      final payload = body['data'] is Map ? body['data'] as Map : body;
      if (payload['has_update'] != true || payload['latest'] is! Map) {
        return null;
      }
      final latest = payload['latest'] as Map;
      final version = latest['version']?.toString() ?? '';
      final downloadUrl = latest['download_url']?.toString() ?? '';
      final uri = XboardConfig.secureUri(downloadUrl, baseUrl: runtimeBaseUrl);
      if (version.isEmpty || uri == null) {
        return null;
      }
      return {
        'tag_name': version.startsWith('v') ? version : 'v$version',
        'body': latest['release_notes']?.toString() ?? '',
        'download_url': uri.toString(),
        'force': payload['force'] == true,
        'sha256': latest['sha256']?.toString(),
      };
    } catch (e) {
      commonPrint.log('checkForUpdate failed', logLevel: LogLevel.warning);
      return null;
    }
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    'https://ipwho.is': IpInfo.fromIpWhoIsJson,
    'https://api.myip.com': IpInfo.fromMyIpJson,
    'https://ipapi.co/json': IpInfo.fromIpApiCoJson,
    'https://ident.me/json': IpInfo.fromIdentMeJson,
    'http://ip-api.com/json': IpInfo.fromIpAPIJson,
    'https://api.ip.sb/geoip': IpInfo.fromIpSbJson,
    'https://ipinfo.io/json': IpInfo.fromIpInfoIoJson,
  };

  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    var failureCount = 0;
    final token = cancelToken ?? CancelToken();
    final futures = _ipInfoSources.entries.map((source) async {
      final Completer<Result<IpInfo?>> completer = Completer();
      void handleFailRes() {
        if (!completer.isCompleted && failureCount == _ipInfoSources.length) {
          completer.complete(Result.success(null));
        }
      }

      final future = dio
          .get<Map<String, dynamic>>(
            source.key,
            cancelToken: token,
            options: Options(responseType: ResponseType.json),
          )
          .timeout(const Duration(seconds: 10));
      future
          .then((res) {
            if (res.statusCode == HttpStatus.ok && res.data != null) {
              completer.complete(Result.success(source.value(res.data!)));
              return;
            }
            commonPrint.log('checkIp data empty', logLevel: LogLevel.info);
            failureCount++;
            handleFailRes();
          })
          .catchError((e) {
            failureCount++;
            if (e is DioException && e.type == DioExceptionType.cancel) {
              completer.complete(Result.error('cancelled'));
              return;
            }
            commonPrint.log('checkIp error $e', logLevel: LogLevel.warning);
            handleFailRes();
          });
      return completer.future;
    });
    final res = await Future.any(futures);
    token.cancel();
    return res;
  }
}

final request = Request();
