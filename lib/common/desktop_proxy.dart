import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/models/models.dart';

Config normalizeDesktopProxyConfig(Config config) {
  if (!system.isDesktop ||
      config.patchClashConfig.tun.enable != config.networkProps.systemProxy) {
    return config;
  }
  return config.copyWith(
    patchClashConfig: config.patchClashConfig.copyWith.tun(enable: false),
    networkProps: config.networkProps.copyWith(systemProxy: true),
  );
}
