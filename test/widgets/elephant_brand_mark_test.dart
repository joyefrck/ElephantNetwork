import 'dart:ui' as ui;

import 'package:fl_clash/widgets/elephant_brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('brand mark displays the glyph within its requested size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: ElephantBrandMark(size: 40))),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ElephantBrandMark)), const Size(40, 40));
    expect(
      tester.getRect(find.byType(SvgPicture)),
      tester.getRect(find.byType(ElephantBrandMark)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('brand mark matches adjacent navigation icon sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: IconTheme(
            data: IconThemeData(size: 28),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElephantBrandMark(),
                Icon(Icons.article),
                Icon(Icons.account_circle),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(ElephantBrandMark));
    expect(size, tester.getSize(find.byIcon(Icons.article)));
    expect(size, tester.getSize(find.byIcon(Icons.account_circle)));
    expect(size, const Size(28, 28));
  });

  testWidgets(
    'brand glyph has a transparent background and black-green strokes',
    (tester) async {
      const boundaryKey = ValueKey('brand-mark');
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: ElephantBrandMark(size: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final pixels = data!.buffer.asUint8List();
          expect(pixels[3], 0);
          final colors = <int>{};
          for (var index = 0; index < pixels.length; index += 4) {
            if (pixels[index + 3] == 255) {
              colors.add(
                pixels[index] << 16 |
                    pixels[index + 1] << 8 |
                    pixels[index + 2],
              );
            }
          }
          expect(colors, containsAll([0x0F172A, 0x10B981]));
          expect(colors, isNot(contains(0xFFFFFF)));
        } finally {
          image.dispose();
        }
      });
    },
  );
}
