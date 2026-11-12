import 'dart:math';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const appSafeMode = bool.fromEnvironment('SAFE_MODE');

String createLocalSecret([int bytes = 32]) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

bool isValidControllerSecret(String secret) =>
    secret.length >= 32 && !RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(secret);

bool isValidProxyUsername(String value) =>
    value.isNotEmpty && !RegExp(r'[:\s\x00-\x1f\x7f]').hasMatch(value);

bool isValidProxyPassword(String value) =>
    value.isNotEmpty && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

extension LocalAuthentication on AuthenticationProps {
  bool get isValid =>
      isValidProxyUsername(username) && isValidProxyPassword(password);

  List<String> get credentials {
    if (!enable) return const [];
    if (!isValid) throw StateError('Invalid local proxy credentials');
    return ['$username:$password'];
  }

  AuthenticationProps ensureCredentials() => isValid
      ? this
      : copyWith(
          username: createLocalSecret(8),
          password: createLocalSecret(16),
        );
}

Config normalizeLocalControlConfig(Config config) {
  var patch = config.patchClashConfig;
  if (patch.externalController == ExternalControllerStatus.open &&
      !isValidControllerSecret(patch.secret)) {
    patch = patch.copyWith(secret: createLocalSecret());
  }
  var network = config.networkProps;
  if (network.authentication.enable) {
    network = network.copyWith(
      authentication: network.authentication.ensureCredentials(),
    );
  }
  return config.copyWith(patchClashConfig: patch, networkProps: network);
}

ExternalControllerStatus effectiveController(
  PatchClashConfig patch, {
  bool safeMode = appSafeMode,
}) => safeMode || !isValidControllerSecret(patch.secret)
    ? ExternalControllerStatus.close
    : patch.externalController;
