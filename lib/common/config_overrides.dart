import 'package:fl_clash/models/clash_config.dart';

bool supportsRuntimeConfig(Object? value) => switch (value) {
  String() => !value.toLowerCase().startsWith('rule-set:'),
  Map() => value.entries.every(
    (entry) =>
        supportsRuntimeConfig(entry.key) && supportsRuntimeConfig(entry.value),
  ),
  List() => value.every(supportsRuntimeConfig),
  _ => true,
};

const optionalGeneralKeys = {
  'tcp-concurrent',
  'unified-delay',
  'ipv6',
  'geodata-loader',
  'keep-alive-interval',
  'global-ua',
};

Map<String, dynamic> captureConfigOverrides(Map<String, dynamic> config) => {
  for (final key in [...optionalGeneralKeys, 'tun', 'dns', 'ntp', 'sniffer'])
    if (config.containsKey(key)) key: _copyConfigValue(config[key]),
};

dynamic _copyConfigValue(dynamic value) => switch (value) {
  Map() => value.map((key, value) => MapEntry(key, _copyConfigValue(value))),
  List() => value.map(_copyConfigValue).toList(),
  _ => value,
};

Map<String, dynamic> _mergeSelected(
  Object? inherited,
  Map<String, dynamic> values,
  Set<String> keys,
) => {
  if (inherited is Map) ...Map<String, dynamic>.from(inherited),
  for (final key in keys)
    if (values.containsKey(key)) key: values[key],
};

void applyConfigOverrides(
  Map<String, dynamic> config,
  Map<String, dynamic> inherited,
  PatchClashConfig patch, {
  bool android = false,
}) {
  final generalKeys = patch.generalOverrideKeys;
  if (generalKeys != null) {
    for (final key in optionalGeneralKeys.difference(generalKeys)) {
      if (inherited.containsKey(key)) {
        config[key] = inherited[key];
      } else {
        config.remove(key);
      }
    }
  }
  final dnsKeys = patch.dnsOverrideKeys;
  if (dnsKeys != null) {
    final dns = patch.dns.toJson();
    for (final name in [
      'nameserver-policy',
      'proxy-server-nameserver-policy',
    ]) {
      final policy = dns[name];
      if (policy is Map) {
        dns[name] = policy.map(
          (key, value) => MapEntry(
            key,
            value is String
                ? value
                      .split(RegExp(r'[\s,]+'))
                      .where((v) => v.isNotEmpty)
                      .toList()
                : value,
          ),
        );
      }
    }
    config['dns'] = _mergeSelected(inherited['dns'], dns, dnsKeys);
    if (config['dns']['enable'] != false &&
        config['dns']['nameserver'] == null) {
      config['dns']['enable'] = true;
      config['dns']['nameserver'] = patch.dns.nameserver;
    }
  }
  final tunKeys = patch.tunOverrideKeys;
  if (tunKeys != null) {
    final owned = <String>{'enable', 'device', if (android) 'stack'};
    final current = Map<String, dynamic>.from(config['tun'] as Map);
    config['tun'] = _mergeSelected(
      inherited['tun'],
      patch.tun.toJson(),
      tunKeys,
    )..addAll({for (final key in owned) key: current[key]});
    if (!android) {
      config['tun']['auto-route'] = true;
      config['tun']['auto-detect-interface'] = true;
    }
  }
  final ntp = patch.ntp;
  if (ntp != null) {
    config['ntp'] = _mergeSelected(
      inherited['ntp'],
      ntp.toJson(),
      patch.ntpOverrideKeys ?? ntp.toJson().keys.toSet(),
    );
  }
  final sniffer = patch.sniffer;
  if (sniffer != null) {
    config['sniffer'] = _mergeSelected(
      inherited['sniffer'],
      sniffer.toJson(),
      patch.snifferOverrideKeys ?? sniffer.toJson().keys.toSet(),
    );
  }
}
