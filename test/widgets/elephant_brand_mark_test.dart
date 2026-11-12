import 'package:fl_clash/widgets/elephant_brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('brand mark displays the full icon within its requested size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: ElephantBrandMark(size: 40))),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ElephantBrandMark)), const Size(40, 40));
    expect(
      tester.getRect(find.byType(Image)),
      tester.getRect(find.byType(ElephantBrandMark)),
    );
    expect(tester.takeException(), isNull);
  });
}
