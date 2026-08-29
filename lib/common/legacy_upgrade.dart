import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'file.dart';
import 'system.dart';

class LegacyUpgradeCleaner {
  const LegacyUpgradeCleaner._();

  static const helperPath = '/Library/PrivilegedHelperTools/ElephantTunHelper';
  static const plistPath =
      '/Library/LaunchDaemons/com.elphantroute.elephantNetwork.tunhelper.plist';

  static Future<void> run() async {
    if (!system.isMacOS) return;
    if (!await File(helperPath).exists() && !await File(plistPath).exists()) {
      return;
    }
    final script = await rootBundle.loadString(
      'assets/scripts/cleanup_legacy_macos.sh',
    );
    final tempDirectory = await Directory.systemTemp.createTemp(
      'elephant_network_upgrade_',
    );
    try {
      final scriptFile = File(
        path.join(tempDirectory.path, 'elephant_network_legacy_cleanup.sh'),
      );
      await scriptFile.safeWriteAsString(script);
      final escaped = scriptFile.path
          .replaceAll('\\', '\\\\')
          .replaceAll('"', '\\"');
      final result = await Process.run('/usr/bin/osascript', [
        '-e',
        'do shell script "/bin/sh \\"$escaped\\"" with administrator privileges',
      ]);
      if (result.exitCode != 0) {
        throw StateError('legacy_macos_cleanup_failed');
      }
    } finally {
      await tempDirectory.safeDelete(recursive: true);
    }
  }
}
