import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/account/xboard_config.dart';

class AppUpdateClient {
  AppUpdateClient({
    required Dio dio,
    required Future<String> Function() resolveBaseUrl,
    String? platform,
    String? arch,
  }) : _dio = dio,
       _resolveBaseUrl = resolveBaseUrl,
       _platform = platform ?? Platform.operatingSystem,
       _arch = arch ?? Abi.current().toString().split('_').last;

  final Dio _dio;
  final Future<String> Function() _resolveBaseUrl;
  final String _platform;
  final String _arch;

  Future<Map<String, dynamic>?> check({
    required String version,
    required String build,
  }) async {
    if (!const {'android', 'windows', 'macos', 'linux'}.contains(_platform)) {
      return null;
    }
    final baseUrl = await _resolveBaseUrl();
    final response = await _dio.get<Object?>(
      '$baseUrl${XboardConfig.updatePath}',
      queryParameters: {
        'app_key': _platform == 'android'
            ? XboardConfig.androidDistributionAppKey
            : XboardConfig.desktopDistributionAppKey,
        'platform': _platform,
        'channel': 'stable',
        'version': version,
        'build': int.tryParse(build) ?? 0,
        'arch': _arch == 'ia32' ? 'x86' : _arch,
      },
      options: Options(
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 10),
        headers: const {'Cache-Control': 'no-cache'},
      ),
    );
    if (response.statusCode != 200 || response.data is! Map) return null;
    final body = response.data as Map;
    final payload = body['data'] is Map ? body['data'] as Map : body;
    if (payload['has_update'] != true || payload['latest'] is! Map) return null;
    final latest = payload['latest'] as Map;
    final latestVersion = latest['version']?.toString().trim() ?? '';
    final latestBuild = int.tryParse(latest['build_number']?.toString() ?? '');
    final download = XboardConfig.secureUri(
      latest['download_url']?.toString() ?? '',
      baseUrl: baseUrl,
    );
    if (latestVersion.isEmpty ||
        latestBuild == null ||
        latestBuild <= 0 ||
        download == null) {
      return null;
    }
    return {
      'tag_name': latestVersion.startsWith('v')
          ? latestVersion
          : 'v$latestVersion',
      'build_number': latestBuild,
      'body': latest['release_notes']?.toString() ?? '',
      'download_url': download.toString(),
      'sha256': latest['sha256']?.toString(),
      'file_size': latest['file_size'],
      'platform': latest['platform'] ?? _platform,
      'arch': latest['arch'] ?? (_arch == 'ia32' ? 'x86' : _arch),
    };
  }
}
