import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS Dock reopen restores and raises the main window', () {
    final appDelegateSource = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final windowSource = File('lib/common/window.dart').readAsStringSync();

    expect(appDelegateSource, contains('sender.setActivationPolicy(.regular)'));
    expect(appDelegateSource, contains('if let window = mainFlutterWindow'));
    expect(appDelegateSource, contains('window.makeKeyAndOrderFront(self)'));
    expect(
      appDelegateSource,
      contains('sender.activate(ignoringOtherApps: true)'),
    );
    expect(appDelegateSource, isNot(contains('if !flag')));
    expect(appDelegateSource, isNot(contains('for window in NSApp.windows')));
    expect(
      windowSource,
      matches(
        RegExp(
          r'Future<void> hide\(\) async \{[\s\S]*?'
          r'windowManager\.hide\(\);[\s\S]*?'
          r'if \(!system\.isMacOS\) \{[\s\S]*?'
          r'windowManager\.setSkipTaskbar\(true\)',
        ),
      ),
    );
  });
}
