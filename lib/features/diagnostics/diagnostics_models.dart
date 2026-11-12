import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class RouteStamp {
  const RouteStamp(this.epoch, this.version);
  factory RouteStamp.fromJson(Map<String, dynamic> json) => RouteStamp(
    (json['core-epoch'] as num).toInt(),
    (json['route-version'] as num).toInt(),
  );
  final int epoch;
  final int version;
  @override
  bool operator ==(Object other) =>
      other is RouteStamp && epoch == other.epoch && version == other.version;
  @override
  int get hashCode => Object.hash(epoch, version);
}

class OutboundProbe {
  OutboundProbe.fromJson(Map<String, dynamic> json)
    : stamp = RouteStamp.fromJson(json),
      source = json['url'] as String? ?? '',
      chains = List<String>.from(json['chains'] as List? ?? []),
      error = json['error'] as String?,
      body = json['body'] as String? ?? '';
  final RouteStamp stamp;
  final String source;
  final List<String> chains;
  final String? error;
  final String body;
  String? get ip {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final value = (json['ip'] ?? json['query']) as String?;
      final address = InternetAddress.tryParse(value ?? '');
      if (address == null ||
          address.isLoopback ||
          address.isLinkLocal ||
          address.isMulticast ||
          address.address == '0.0.0.0' ||
          address.address == '::') {
        return null;
      }
      return address.address;
    } catch (_) {
      return null;
    }
  }
}

class ServiceProbe {
  ServiceProbe.fromJson(Map<String, dynamic> json)
    : stamp = RouteStamp.fromJson(json),
      name = json['name'] as String,
      status = json['status'] as String,
      region = json['region'] as String?,
      delay = (json['delay'] as num?)?.toInt(),
      chains = List<String>.from(json['chains'] as List? ?? []);
  final RouteStamp stamp;
  final String name;
  final String status;
  final String? region;
  final int? delay;
  final List<String> chains;
}

abstract interface class DiagnosticsCore {
  Future<RouteStamp> watchRoute(bool watch);
  Future<OutboundProbe> probeOutboundIp(String taskId, String proxyName);
  Future<List<ServiceProbe>> probeServices(String taskId, String proxyName);
  Future<void> cancelProbe(String taskId);
}
