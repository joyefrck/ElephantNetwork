import 'package:fl_clash/common/navigation.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary navigation starts with dashboard and keeps account third', () {
    final items = navigation.getItems();
    List<PageLabel> labelsFor(NavigationItemMode mode) => items
        .where((item) => item.modes.contains(mode))
        .map((item) => item.label)
        .toList();

    const expected = [
      PageLabel.dashboard,
      PageLabel.proxies,
      PageLabel.account,
      PageLabel.tools,
    ];
    expect(labelsFor(NavigationItemMode.desktop), expected);
    expect(labelsFor(NavigationItemMode.mobile), expected);
  });
}
