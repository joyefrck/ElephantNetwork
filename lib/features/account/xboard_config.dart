class XboardConfig {
  const XboardConfig._();

  static const baseUrl = String.fromEnvironment(
    'XBOARD_BASE_URL',
    defaultValue: 'https://www.elephant111.org',
  );
  static const domainConfigUrl = String.fromEnvironment(
    'XBOARD_DOMAIN_CONFIG_URL',
    defaultValue: 'https://www.elephant-ipcheck.com/api/domains',
  );
  static const loginPath = '/api/v1/passport/auth/login';
  static const userInfoPath = '/api/v1/user/info';
  static const subscribeInfoPath = '/api/v1/user/getSubscribe';
  static const quickLoginPath = '/api/v1/passport/auth/getQuickLoginUrl';
  static const healthPath = '/api/v1/guest/domain/check';
  static const updatePath = '/api/v1/app/update';
  static const desktopDistributionAppKey = String.fromEnvironment(
    'APP_DISTRIBUTION_APP_KEY',
    defaultValue: 'elephant-route-desktop',
  );
  static const androidDistributionAppKey = String.fromEnvironment(
    'ANDROID_APP_DISTRIBUTION_APP_KEY',
    defaultValue: 'elephant-route-android',
  );
  static const managedProfileLabel = '大象网络受管订阅';

  static Uri managedSubscriptionUri(String source) {
    final uri = Uri.parse(source);
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'flag': 'flclash'},
    );
  }

  static Uri? secureUri(String source, {String? baseUrl}) {
    final candidate = Uri.tryParse(source.trim());
    if (candidate == null) return null;
    final uri = candidate.hasScheme
        ? candidate
        : Uri.tryParse(baseUrl ?? '')?.resolveUri(candidate);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }
}
