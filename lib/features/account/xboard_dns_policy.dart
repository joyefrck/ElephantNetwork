const _proxyDnsAddresses = ['1.1.1.1', '8.8.8.8'];

void applyXboardDnsPolicy(Map<String, dynamic> config) {
  final rules = List<String>.from(config['rules'] as List? ?? const []);
  final proxyNames = <String>{
    for (final key in ['proxy-groups', 'proxies'])
      for (final proxy in config[key] as List? ?? const [])
        if (proxy is Map && proxy['name'] is String) proxy['name'] as String,
  };
  String? proxyTarget;
  for (final rule in rules) {
    final parts = rule.split(',').map((part) => part.trim()).toList();
    if (parts.length < 2 || !['MATCH', 'FINAL'].contains(parts.first)) {
      continue;
    }
    if (proxyNames.contains(parts[1]) &&
        !['DIRECT', 'REJECT', 'PASS'].contains(parts[1].toUpperCase())) {
      proxyTarget = parts[1];
    }
    break;
  }
  if (proxyTarget == null) {
    throw StateError('managed_profile_missing_dns_proxy');
  }

  config['dns'] = {
    'enable': true,
    'listen': '127.0.0.1:1053',
    'ipv6': false,
    'prefer-h3': false,
    'use-hosts': true,
    'use-system-hosts': true,
    'respect-rules': true,
    'enhanced-mode': 'fake-ip',
    'fake-ip-range': '198.18.0.1/16',
    'fake-ip-filter': [
      '*.lan',
      '*.local',
      'localhost.ptlogin2.qq.com',
      'dns.msftnsci.com',
      'www.msftnsci.com',
      'www.msftconnecttest.com',
    ],
    'default-nameserver': ['223.5.5.5', '119.29.29.29'],
    'nameserver': [
      for (final address in _proxyDnsAddresses)
        'https://$address/dns-query#RULES',
    ],
    'fallback': <String>[],
    'nameserver-policy': {
      'geosite:cn': ['https://223.5.5.5/dns-query#RULES'],
    },
    'proxy-server-nameserver': [
      'https://223.5.5.5/dns-query#DIRECT',
      'https://223.6.6.6/dns-query#DIRECT',
    ],
  };
  config['tun'] = {
    ...Map<String, dynamic>.from(config['tun'] as Map? ?? const {}),
    'dns-hijack': ['any:53'],
  };
  config['rules'] = [
    for (final address in _proxyDnsAddresses)
      'IP-CIDR,$address/32,$proxyTarget,no-resolve',
    ...rules.where((rule) {
      final parts = rule.split(',').map((part) => part.trim()).toList();
      return parts.length < 2 ||
          parts.first != 'IP-CIDR' ||
          !_proxyDnsAddresses.any((address) => parts[1] == '$address/32');
    }),
  ];
}
