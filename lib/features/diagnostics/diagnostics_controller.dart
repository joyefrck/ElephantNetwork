import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/local_control.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/models/ip_quality.dart';
import 'package:flutter/foundation.dart';

import 'diagnostics_models.dart';
import 'quality_repository.dart';

class DiagnosticsController extends ChangeNotifier with CoreEventListener {
  DiagnosticsController({
    required this.core,
    required this.qualityRepository,
    CoreEventManager? events,
  }) : _events = events ?? CoreEventManager.instance {
    _events.addListener(this);
  }
  final DiagnosticsCore core;
  final QualityRepository qualityRepository;
  final CoreEventManager _events;
  bool available = false;
  bool running = false;
  bool busy = false;
  bool failed = false;
  bool qualityFailed = false;
  bool routeChanged = false;
  OutboundProbe? outbound;
  IpQuality? quality;
  List<ServiceProbe> services = const [];
  RouteStamp? _stamp;
  CancelToken? _qualityToken;
  final _tasks = <String>{};
  int _generation = 0;
  bool _disposed = false;
  bool _watching = false;

  void setEnvironment({
    required bool connected,
    required bool running,
    bool visible = true,
  }) {
    final next = connected && visible;
    if (available == next && this.running == running) return;
    available = next;
    this.running = running;
    _invalidate();
    unawaited(_watch(next));
  }

  Future<void> _watch(bool watch) async {
    _watching = watch;
    final generation = _generation;
    try {
      final stamp = await core.watchRoute(watch);
      if (!_disposed && generation == _generation) onRouteChanged(stamp);
    } catch (_) {
      if (!_disposed && generation == _generation && watch) {
        failed = true;
        _notify();
      }
    }
  }

  @override
  void onRouteChanged(RouteStamp stamp) {
    if (_disposed) return;
    if (_stamp != null && _stamp != stamp) {
      _invalidate();
      routeChanged = true;
    }
    _stamp = stamp;
    _notify();
  }

  void cancel() {
    _generation++;
    _qualityToken?.cancel();
    _qualityToken = null;
    for (final id in _tasks) {
      unawaited(core.cancelProbe(id).catchError((Object _) {}));
    }
    _tasks.clear();
    busy = false;
    _notify();
  }

  void _invalidate() {
    cancel();
    outbound = null;
    quality = null;
    services = const [];
    failed = false;
    qualityFailed = false;
    _stamp = null;
    _notify();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> refresh() async {
    if (!available || busy || _disposed) return;
    cancel();
    final generation = _generation;
    busy = true;
    failed = false;
    qualityFailed = false;
    routeChanged = false;
    outbound = null;
    quality = null;
    services = const [];
    _notify();
    try {
      _watching = true;
      final stamp = await core.watchRoute(true);
      if (!_current(generation)) return;
      _stamp = stamp;
      final proxy = running ? '' : 'DIRECT';
      final ipTask = createLocalSecret(16);
      final serviceTask = createLocalSecret(16);
      _tasks.addAll([ipTask, serviceTask]);
      await Future.wait([
        _checkIp(ipTask, proxy, generation),
        _checkServices(serviceTask, proxy, generation),
      ]);
    } catch (_) {
      if (_current(generation)) failed = true;
    } finally {
      if (_current(generation)) {
        _tasks.clear();
        busy = false;
        _notify();
      }
    }
  }

  Future<bool> _accept(RouteStamp stamp, int generation) async {
    if (!_current(generation)) return false;
    final actual = await core.watchRoute(true);
    if (!_current(generation)) return false;
    if (actual != stamp || _stamp != stamp) {
      onRouteChanged(actual);
      return false;
    }
    return true;
  }

  Future<void> _checkIp(String taskId, String proxy, int generation) async {
    try {
      final result = await core.probeOutboundIp(taskId, proxy);
      if (!await _accept(result.stamp, generation)) return;
      outbound = result;
      if (result.error != null || result.ip == null) {
        failed = true;
        _notify();
        return;
      }
      _notify();
      final token = CancelToken();
      _qualityToken = token;
      try {
        final resultQuality = await qualityRepository.get(result.ip!, token);
        if (_current(generation)) quality = resultQuality;
      } catch (_) {
        if (_current(generation)) qualityFailed = true;
      }
      if (_current(generation)) _notify();
    } catch (_) {
      if (_current(generation)) {
        failed = true;
        _notify();
      }
    }
  }

  Future<void> _checkServices(
    String taskId,
    String proxy,
    int generation,
  ) async {
    try {
      final results = await core.probeServices(taskId, proxy);
      if (results.isEmpty) {
        if (_current(generation)) {
          failed = true;
          _notify();
        }
        return;
      }
      if (!await _accept(results.first.stamp, generation)) return;
      if (results.any((item) => item.stamp != _stamp)) {
        _invalidate();
        routeChanged = true;
        _notify();
        return;
      }
      services = results;
      _notify();
    } catch (_) {
      if (_current(generation)) {
        failed = true;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events.removeListener(this);
    cancel();
    if (_watching) {
      _watching = false;
      unawaited(
        core.watchRoute(false).catchError((Object _) => const RouteStamp(0, 0)),
      );
    }
    super.dispose();
  }
}
