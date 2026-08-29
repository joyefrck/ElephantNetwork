import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup no longer blocks on disclaimer acceptance', () {
    final source = File('lib/state.dart').readAsStringSync();

    expect(source, isNot(contains('_handlerDisclaimer')));
    expect(source, isNot(contains('showDisclaimer')));
  });
}
