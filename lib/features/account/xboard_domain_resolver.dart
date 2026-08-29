import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xboard_config.dart';

abstract interface class XboardDomainTransport {
  Future<Object?> fetchConfig(Uri uri);

  Future<bool> probe(Uri uri);
}

class DioXboardDomainTransport implements XboardDomainTransport {
  DioXboardDomainTransport({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
            ),
          );

  final Dio _dio;

  @override
  Future<Object?> fetchConfig(Uri uri) async {
    final response = await _dio.getUri<Object?>(uri);
    return response.data;
  }

  @override
  Future<bool> probe(Uri uri) async {
    try {
      final response = await _dio.getUri<Object?>(
        uri,
        options: Options(
          headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final status = response.statusCode ?? 0;
      return status >= 200 && status < 400;
    } catch (_) {
      return false;
    }
  }
}

abstract interface class XboardDomainStore {
  Future<String?> read();

  Future<void> write(String value);
}

class PreferencesXboardDomainStore implements XboardDomainStore {
  static const _key = 'xboard.runtime_api_base_url';

  @override
  Future<String?> read() async {
    return (await SharedPreferences.getInstance()).getString(_key);
  }

  @override
  Future<void> write(String value) async {
    await (await SharedPreferences.getInstance()).setString(_key, value);
  }
}

class XboardDomainResolver {
  XboardDomainResolver({
    XboardDomainTransport? transport,
    XboardDomainStore? store,
  }) : _transport = transport ?? DioXboardDomainTransport(),
       _store = store ?? PreferencesXboardDomainStore();

  final XboardDomainTransport _transport;
  final XboardDomainStore _store;
  Future<String>? _activeResolve;
  String? _current;

  String get current => _current ?? XboardConfig.baseUrl;

  Future<String> resolve({bool force = false}) async {
    if (!force && _current != null) return _current!;
    if (!force && _activeResolve != null) return _activeResolve!;
    final future = _resolve();
    _activeResolve = future;
    try {
      return await future;
    } finally {
      if (identical(_activeResolve, future)) _activeResolve = null;
    }
  }

  Future<String> _resolve() async {
    final cached = _normalize(await _store.read());
    final fallback = cached ?? _normalize(XboardConfig.baseUrl)!;
    final candidates = await _candidates(fallback);
    final probes = await Future.wait(
      candidates.map((candidate) async {
        final stopwatch = Stopwatch()..start();
        final available = await _transport.probe(
          Uri.parse(candidate.url).resolve(candidate.healthPath),
        );
        stopwatch.stop();
        return _Probe(candidate, available, stopwatch.elapsedMilliseconds);
      }),
    );
    final available = probes.where((probe) => probe.available).toList()
      ..sort((left, right) {
        final weight = right.candidate.weight.compareTo(left.candidate.weight);
        return weight != 0 ? weight : left.latency.compareTo(right.latency);
      });
    final selected = available.isEmpty
        ? fallback
        : available.first.candidate.url;
    _current = selected;
    await _store.write(selected);
    return selected;
  }

  Future<List<XboardDomainCandidate>> _candidates(String fallback) async {
    final result = <XboardDomainCandidate>[];
    try {
      final payload = await _transport.fetchConfig(
        Uri.parse(XboardConfig.domainConfigUrl),
      );
      if (payload is Map && payload['domains'] is List) {
        for (final item in payload['domains'] as List) {
          if (item is! Map || item['enabled'] == false) continue;
          final url = _normalize(item['url']?.toString());
          if (url == null) continue;
          final healthPath = item['healthPath']?.toString().trim();
          result.add(
            XboardDomainCandidate(
              url: url,
              weight: int.tryParse(item['weight']?.toString() ?? '') ?? 0,
              healthPath: healthPath == null || healthPath.isEmpty
                  ? XboardConfig.healthPath
                  : healthPath.startsWith('/')
                  ? healthPath
                  : '/$healthPath',
            ),
          );
        }
      }
    } catch (_) {}
    result.add(
      XboardDomainCandidate(
        url: fallback,
        weight: 0,
        healthPath: XboardConfig.healthPath,
      ),
    );
    final seen = <String>{};
    return result.where((candidate) => seen.add(candidate.url)).toList();
  }

  static String? _normalize(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri
        .replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''))
        .toString();
  }
}

class XboardDomainCandidate {
  const XboardDomainCandidate({
    required this.url,
    required this.weight,
    required this.healthPath,
  });

  final String url;
  final int weight;
  final String healthPath;
}

class _Probe {
  const _Probe(this.candidate, this.available, this.latency);

  final XboardDomainCandidate candidate;
  final bool available;
  final int latency;
}

final xboardDomainResolver = XboardDomainResolver();
