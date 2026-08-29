import 'package:dio/dio.dart';

import 'xboard_config.dart';
import 'xboard_domain_resolver.dart';
import 'xboard_models.dart';

abstract interface class XboardTransport {
  Future<Object?> request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? data,
  });
}

class DioXboardTransport implements XboardTransport {
  DioXboardTransport({
    String? baseUrl,
    Dio? dio,
    XboardDomainResolver? domainResolver,
  }) : _domainResolver = domainResolver ?? xboardDomainResolver,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl ?? XboardConfig.baseUrl,
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 12),
               sendTimeout: const Duration(seconds: 8),
               responseType: ResponseType.json,
               validateStatus: (status) => status != null && status < 500,
             ),
           );

  final Dio _dio;
  final XboardDomainResolver _domainResolver;

  @override
  Future<Object?> request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? data,
  }) async {
    _dio.options.baseUrl = await _domainResolver.resolve();
    Response<Object?> response;
    try {
      response = await _send(method, path, token: token, data: data);
    } on DioException catch (error) {
      if (!_isSafeRetry(method) || error.response != null) rethrow;
      final previous = _dio.options.baseUrl;
      final next = await _domainResolver.resolve(force: true);
      if (next == previous) rethrow;
      _dio.options.baseUrl = next;
      response = await _send(method, path, token: token, data: data);
    }
    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw XboardApiException(statusCode: statusCode);
    }
    return response.data;
  }

  Future<Response<Object?>> _send(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? data,
  }) {
    return _dio.request<Object?>(
      path,
      data: data,
      options: Options(
        method: method,
        headers: {
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ),
    );
  }

  bool _isSafeRetry(String method) {
    return const {'GET', 'HEAD', 'OPTIONS'}.contains(method.toUpperCase());
  }
}

class XboardApi {
  XboardApi({XboardTransport? transport})
    : _transport = transport ?? DioXboardTransport();

  final XboardTransport _transport;

  Future<String> login(String email, String password) async {
    final payload = await _transport.request(
      'POST',
      XboardConfig.loginPath,
      data: {'email': email.trim(), 'password': password},
    );
    final data = _dataMap(payload);
    final token = data['auth_data'] as String?;
    if (token == null || token.trim().isEmpty) {
      throw const XboardApiException(message: 'missing_auth_data');
    }
    return token;
  }

  Future<XboardAccount> account(String token) async {
    final payload = await _transport.request(
      'GET',
      XboardConfig.userInfoPath,
      token: token,
    );
    return XboardAccount.fromJson(_dataMap(payload));
  }

  Future<Uri> managedSubscription(String token) async {
    final payload = await _transport.request(
      'GET',
      XboardConfig.subscribeInfoPath,
      token: token,
    );
    final source = _dataMap(payload)['subscribe_url'] as String?;
    if (source == null || source.trim().isEmpty) {
      throw const XboardApiException(message: 'missing_subscribe_url');
    }
    final uri = XboardConfig.managedSubscriptionUri(source);
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const XboardApiException(message: 'invalid_subscribe_url');
    }
    return uri;
  }

  Future<Uri> quickLogin(String token, String redirect) async {
    final payload = await _transport.request(
      'POST',
      XboardConfig.quickLoginPath,
      token: token,
      data: {'redirect': redirect},
    );
    final value = _data(payload);
    if (value is! String) {
      throw const XboardApiException(message: 'missing_quick_login_url');
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const XboardApiException(message: 'invalid_quick_login_url');
    }
    return uri;
  }

  static Map<String, Object?> _dataMap(Object? payload) {
    final value = _data(payload);
    if (value is! Map) {
      throw const XboardApiException(message: 'invalid_response');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static Object? _data(Object? payload) {
    if (payload is! Map) {
      throw const XboardApiException(message: 'invalid_response');
    }
    final status = payload['status'];
    if (status is String && status != 'success') {
      throw const XboardApiException(message: 'request_rejected');
    }
    return payload['data'];
  }
}

class XboardApiException implements Exception {
  const XboardApiException({this.statusCode, this.message = 'request_failed'});

  final int? statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'XboardApiException($message, $statusCode)';
}
