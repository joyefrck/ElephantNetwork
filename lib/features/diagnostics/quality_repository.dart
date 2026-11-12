import 'package:dio/dio.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';

typedef QualityLookup =
    Future<IpQuality> Function(String ip, CancelToken cancelToken);

class QualityRepository {
  QualityRepository({
    required this.dao,
    required this.lookup,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  static const maxAge = Duration(days: 3);
  static const cooldown = Duration(minutes: 5);
  final IpQualitiesDao dao;
  final QualityLookup lookup;
  final DateTime Function() now;
  final _failures = <String, ({DateTime at, Object error})>{};

  Future<IpQuality> get(String ip, CancelToken token) async {
    if (token.isCancelled) throw token.cancelError!;
    final cached = await dao.fresh(ip, maxAge, now());
    if (token.isCancelled) throw token.cancelError!;
    if (cached != null) return cached.quality;
    final failed = _failures[ip];
    if (failed != null &&
        !failed.at.isAfter(now()) &&
        now().difference(failed.at) < cooldown) {
      throw failed.error;
    }
    try {
      final quality = await lookup(ip, token);
      if (token.isCancelled) throw token.cancelError!;
      if (quality.ip != ip) throw const FormatException('IP mismatch');
      await dao.put(quality, now(), maxAge);
      _failures.remove(ip);
      return quality;
    } catch (error) {
      if (!token.isCancelled &&
          !(error is DioException && CancelToken.isCancel(error))) {
        _failures[ip] = (at: now(), error: error);
      }
      rethrow;
    }
  }
}
