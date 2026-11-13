import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fork identity and GPL notices remain explicit', () {
    final constants = File('lib/common/constant.dart').readAsStringSync();
    final submodules = File('.gitmodules').readAsStringSync();
    final notice = File('NOTICE');
    final upstream = File('docs/UPSTREAM.md');

    expect(constants, contains("const appName = 'Elephant Network';"));
    expect(
      constants,
      contains("const repository = 'joyefrck/ElephantNetwork';"),
    );
    expect(
      submodules,
      contains('url = https://github.com/chen08209/Clash.Meta.git'),
    );
    expect(File('LICENSE').existsSync(), isTrue);
    expect(notice.existsSync(), isTrue);
    expect(notice.readAsStringSync(), contains('GNU General Public License'));
    expect(notice.readAsStringSync(), contains('chen08209/FlClash'));
    expect(upstream.existsSync(), isTrue);
    expect(upstream.readAsStringSync(), contains('upstream/main'));
  });

  test('macOS and shared app icons use the same artwork', () {
    expect(
      File('assets/images/icon.png').readAsBytesSync(),
      File(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      ).readAsBytesSync(),
    );
  });

  test(
    'Windows taskbar is transparent and desktop shortcut has a white tile',
    () async {
      for (final path in [
        'windows/runner/resources/app_icon.ico',
        'assets/images/icon.ico',
      ]) {
        final bytes = await File(path).readAsBytes();
        final data = ByteData.sublistView(bytes);
        final frameCount = data.getUint16(4, Endian.little);
        for (var i = 0; i < frameCount; i++) {
          final entry = 6 + i * 16;
          final offset = data.getUint32(entry + 12, Endian.little);
          final length = data.getUint32(entry + 8, Endian.little);
          final codec = await ui.instantiateImageCodec(
            Uint8List.sublistView(bytes, offset, offset + length),
          );
          final image = (await codec.getNextFrame()).image;
          try {
            final pixels = (await image.toByteData())!;
            final hasWhiteTile = List.generate(image.width * image.height, (
              index,
            ) {
              final pixel = index * 4;
              return pixels.getUint32(pixel) == 0xffffffff;
            }).any((white) => white);
            expect(
              hasWhiteTile,
              path == 'assets/images/icon.ico',
              reason: '$path frame ${image.width}',
            );
            expect(pixels.getUint8(3), 0, reason: path);
          } finally {
            image.dispose();
            codec.dispose();
          }
        }
      }
    },
  );

  test(
    'launcher artwork has a pure white tile and the E brand colors',
    () async {
      final files = [
        File('assets/images/icon.png'),
        File('android/app/src/main/ic_launcher-playstore.png'),
        ...Directory('android/app/src/main/res')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.webp')),
      ];
      for (final file in files) {
        final codec = await ui.instantiateImageCodec(await file.readAsBytes());
        final image = (await codec.getNextFrame()).image;
        try {
          final pixels = (await image.toByteData())!;
          List<int> pixel(double x, double y) {
            final offset =
                ((image.height * y).floor() * image.width +
                    (image.width * x).floor()) *
                4;
            return List.generate(4, (index) => pixels.getUint8(offset + index));
          }

          expect(pixel(0.5, 0.14), [255, 255, 255, 255], reason: file.path);
          expect(pixel(0.5, 0.32), [15, 23, 42, 255], reason: file.path);
          expect(pixel(0.5, 0.5), [16, 185, 129, 255], reason: file.path);
        } finally {
          image.dispose();
          codec.dispose();
        }
      }
    },
  );

  test('Windows icons contain native small and high resolution frames', () {
    final bytes = File(
      'windows/runner/resources/app_icon.ico',
    ).readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    expect(data.getUint16(2, Endian.little), 1);
    final frameCount = data.getUint16(4, Endian.little);
    final sizes = <int>{};
    for (var i = 0; i < frameCount; i++) {
      final offset = 6 + i * 16;
      final width = data.getUint8(offset);
      expect(data.getUint8(offset + 1), width);
      sizes.add(width == 0 ? 256 : width);
      expect(
        data.getUint32(offset + 12, Endian.little) +
            data.getUint32(offset + 8, Endian.little),
        lessThanOrEqualTo(bytes.length),
      );
    }
    expect(sizes, containsAll([16, 24, 32, 48, 64, 128, 256]));
  });
}
