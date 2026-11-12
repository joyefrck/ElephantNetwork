import 'dart:async';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/diagnostics/diagnostics_controller.dart';
import 'package:fl_clash/features/diagnostics/diagnostics_models.dart';
import 'package:fl_clash/features/diagnostics/quality_repository.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCore implements DiagnosticsCore {
  RouteStamp stamp = const RouteStamp(1, 1);
  final ip = Completer<OutboundProbe>();
  final services = Completer<List<ServiceProbe>>();
  final proxies = <String>[];
  final canceled = <String>[];
  final watches = <bool>[];
  @override
  Future<RouteStamp> watchRoute(bool watch) async {
    watches.add(watch);
    return stamp;
  }

  @override
  Future<OutboundProbe> probeOutboundIp(String id, String proxy) {
    proxies.add(proxy);
    return ip.future;
  }

  @override
  Future<List<ServiceProbe>> probeServices(String id, String proxy) {
    proxies.add(proxy);
    return services.future;
  }

  @override
  Future<void> cancelProbe(String id) async {
    canceled.add(id);
  }
}

OutboundProbe outbound([int version = 1]) => OutboundProbe.fromJson({
  'core-epoch': 1,
  'route-version': version,
  'url': 'https://example.test',
  'body': '{"ip":"8.8.8.8"}',
  'chains': ['node-a'],
});
ServiceProbe service([int version = 1]) => ServiceProbe.fromJson({
  'core-epoch': 1,
  'route-version': version,
  'name': 'google',
  'status': 'available',
});

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Database db;
  late FakeCore core;
  late DiagnosticsController controller;
  setUp(() {
    db = Database(NativeDatabase.memory());
    core = FakeCore();
    controller = DiagnosticsController(
      core: core,
      qualityRepository: QualityRepository(
        dao: db.ipQualitiesDao,
        lookup: (ip, _) async => IpQuality(
          ip: ip,
          source: IpQualitySource.ipQuery,
          type: IpType.hosting,
        ),
      ),
    );
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test('stopped proxy probes DIRECT and retains current results', () async {
    controller.setEnvironment(connected: true, running: false);
    await flush();
    final task = controller.refresh();
    await flush();
    expect(core.proxies, ['DIRECT', 'DIRECT']);
    core.ip.complete(outbound());
    core.services.complete([service()]);
    await task;
    expect(controller.outbound!.ip, '8.8.8.8');
    expect(controller.quality!.ip, '8.8.8.8');
    expect(controller.services, hasLength(1));
    expect(controller.busy, isFalse);
  });

  test('route event cancels work and discards all late answers', () async {
    controller.setEnvironment(connected: true, running: true);
    await flush();
    final task = controller.refresh();
    await flush();
    expect(core.proxies, ['', '']);
    core.stamp = const RouteStamp(1, 2);
    controller.onRouteChanged(core.stamp);
    core.ip.complete(outbound());
    core.services.complete([service()]);
    await task;
    expect(core.canceled, hasLength(2));
    expect(controller.outbound, isNull);
    expect(controller.services, isEmpty);
    expect(controller.routeChanged, isTrue);
  });

  test(
    'fresh Core stamp rejects results before a delayed event arrives',
    () async {
      controller.setEnvironment(connected: true, running: true);
      await flush();
      final task = controller.refresh();
      await flush();
      core.stamp = const RouteStamp(1, 3);
      core.ip.complete(outbound());
      core.services.complete([service()]);
      await task;
      expect(controller.outbound, isNull);
      expect(controller.services, isEmpty);
      expect(controller.busy, isFalse);
    },
  );

  test('backgrounding cancels probes and route subscription', () async {
    controller.setEnvironment(connected: true, running: true);
    await flush();
    final task = controller.refresh();
    await flush();
    controller.setEnvironment(connected: true, running: true, visible: false);
    core.ip.complete(outbound());
    core.services.complete([service()]);
    await task;
    await flush();
    expect(core.canceled, hasLength(2));
    expect(core.watches.last, isFalse);
    expect(controller.available, isFalse);
    expect(controller.outbound, isNull);
  });

  test('disconnected Core does not start work', () async {
    await controller.refresh();
    expect(core.proxies, isEmpty);
  });
}
