import 'package:fl_clash/common/ip_quality.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/features/diagnostics/diagnostics_controller.dart';
import 'package:fl_clash/features/diagnostics/quality_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final qualityRepositoryProvider = Provider<QualityRepository>((ref) {
  return QualityRepository(
    dao: database.ipQualitiesDao,
    lookup: (ip, token) => lookupIpQuality(request.dio, ip, cancelToken: token),
  );
});

final diagnosticsProvider = Provider.autoDispose<DiagnosticsController>((ref) {
  final controller = DiagnosticsController(
    core: CoreController(),
    qualityRepository: ref.watch(qualityRepositoryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
