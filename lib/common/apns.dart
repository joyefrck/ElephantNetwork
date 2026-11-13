import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/config.dart';

const apnsNetworks = [
  '17.249.0.0/16',
  '17.252.0.0/16',
  '17.57.144.0/22',
  '17.188.128.0/18',
  '17.188.20.0/23',
  '2620:149:a44::/48',
  '2403:300:a42::/48',
  '2403:300:a51::/48',
  '2a01:b740:a42::/48',
];

List<String> apnsProxyTargets(Map<String, dynamic> config) => [
  for (final key in ['proxy-groups', 'proxies'])
    for (final item in config[key] as List? ?? const [])
      if (item is Map &&
          item['name'] is String &&
          ![
            'DIRECT',
            'REJECT',
            'REJECT-DROP',
            'PASS',
            'GLOBAL',
          ].contains(item['name']) &&
          !['direct', 'reject', 'pass'].contains(item['type']))
        item['name'] as String,
];

String? resolveApnsProxy(Map<String, dynamic> config, String? preferred) {
  final targets = apnsProxyTargets(config);
  if (targets.contains(preferred)) return preferred;
  for (final rule in config['rules'] as List? ?? const []) {
    final parts = rule
        .toString()
        .split(',')
        .map((part) => part.trim())
        .toList();
    if (parts.length == 2 &&
        ['MATCH', 'FINAL'].contains(parts.first) &&
        targets.contains(parts[1])) {
      return parts[1];
    }
  }
  return targets.firstOrNull;
}

void applyApnsPolicy(Map<String, dynamic> config, NetworkProps settings) {
  if (!settings.includeApns) return;
  final tun = Map<String, dynamic>.from(config['tun'] as Map? ?? const {});
  final routes = <String>[
    for (final key in [
      'route-address',
      'inet4-route-address',
      'inet6-route-address',
    ])
      ...List<String>.from(tun[key] as List? ?? const []),
  ];
  final dns = config['dns'] as Map?;
  final included = [
    ...apnsNetworks,
    if (routes.isNotEmpty && dns?['enhanced-mode'] == 'fake-ip') ...[
      _Subnet.parse(dns?['fake-ip-range'] as String? ?? '198.18.0.1/16').value,
      if (dns?['fake-ip-range6'] is String)
        _Subnet.parse(dns!['fake-ip-range6'] as String).value,
    ],
  ];
  if (routes.isNotEmpty) {
    tun['route-address'] = {...routes, ...included}.toList();
    tun.remove('inet4-route-address');
    tun.remove('inet6-route-address');
  }
  for (final key in [
    'route-exclude-address',
    'inet4-route-exclude-address',
    'inet6-route-exclude-address',
  ]) {
    if (tun[key] is List) {
      tun[key] = _excludeNetworks(
        List<String>.from(tun[key] as List),
        included,
      );
    }
  }
  config['tun'] = tun;
  final String? target = switch (settings.apnsRoute) {
    ApnsRoute.rule => null,
    ApnsRoute.direct => 'DIRECT',
    ApnsRoute.proxy => resolveApnsProxy(config, settings.apnsProxy),
  };
  if (settings.apnsRoute == ApnsRoute.proxy && target == null) {
    throw StateError('apns_proxy_unavailable');
  }
  if (target == null) return;
  const ports = '(DST-PORT,5223/443)';
  const tcp = '(NETWORK,TCP)';
  config['rules'] = [
    'AND,($tcp,$ports,(DOMAIN-SUFFIX,push.apple.com)),$target',
    'AND,($tcp,$ports,(PROCESS-NAME,apsd)),$target',
    for (final network in apnsNetworks)
      'AND,($tcp,$ports,(${network.contains(':') ? 'IP-CIDR6' : 'IP-CIDR'},$network,no-resolve)),$target',
    ...config['rules'] as List? ?? const [],
  ];
}

List<String> excludeApnsNetworks(List<String> excluded) =>
    _excludeNetworks(excluded, apnsNetworks);

List<String> _excludeNetworks(List<String> excluded, List<String> included) {
  var ranges = excluded;
  for (final network in included) {
    final included = _Subnet.parse(network);
    ranges = [
      for (final range in ranges)
        ..._Subnet.parse(
          range,
        ).subtract(included).map((subnet) => subnet.value),
    ];
  }
  return ranges;
}

class _Subnet {
  final BigInt address;
  final int prefix;
  final int bits;

  const _Subnet(this.address, this.prefix, this.bits);

  factory _Subnet.parse(String value) {
    final parts = value.split('/');
    final ip = InternetAddress(parts.first);
    final bits = ip.rawAddress.length * 8;
    final prefix = parts.length == 2 ? int.parse(parts[1]) : bits;
    if (prefix < 0 || prefix > bits || parts.length > 2) {
      throw FormatException('Invalid subnet', value);
    }
    final address = ip.rawAddress.fold(
      BigInt.zero,
      (value, byte) => (value << 8) | BigInt.from(byte),
    );
    return _Subnet(
      (address >> (bits - prefix)) << (bits - prefix),
      prefix,
      bits,
    );
  }

  BigInt get end => address + (BigInt.one << (bits - prefix)) - BigInt.one;

  Iterable<_Subnet> subtract(_Subnet other) sync* {
    if (bits != other.bits || end < other.address || address > other.end) {
      yield this;
      return;
    }
    if (other.address <= address && other.end >= end) return;
    final half = BigInt.one << (bits - prefix - 1);
    yield* _Subnet(address, prefix + 1, bits).subtract(other);
    yield* _Subnet(address + half, prefix + 1, bits).subtract(other);
  }

  String get value {
    final bytes = [
      for (var index = bits ~/ 8 - 1; index >= 0; index--)
        ((address >> (index * 8)) & BigInt.from(255)).toInt(),
    ];
    return '${InternetAddress.fromRawAddress(Uint8List.fromList(bytes)).address}/$prefix';
  }
}
