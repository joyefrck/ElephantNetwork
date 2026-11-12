import 'dart:io';
import 'dart:typed_data';

const _source = 'assets_source/images/app_icon.svg';
const _android = 'android/app/src/main';
const _macos = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

Future<void> main() async {
  final source = await File(_source).readAsString();
  final temp = await Directory.systemTemp.createTemp('elephant_app_icons_');
  try {
    for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
      await _render(_source, '$_macos/app_icon_$size.png', size);
    }
    await File('$_macos/app_icon_1024.png').copy('assets/images/icon.png');

    final icoFrames = <Uint8List>[];
    const icoSizes = [16, 24, 32, 48, 64, 128, 256];
    for (final size in icoSizes) {
      final frame = '${temp.path}/icon_$size.png';
      await _render(_source, frame, size);
      icoFrames.add(await File(frame).readAsBytes());
    }
    final ico = _buildIco(icoSizes, icoFrames);
    for (final path in [
      'assets/images/icon.ico',
      'windows/runner/resources/app_icon.ico',
    ]) {
      await File(path).writeAsBytes(ico);
    }

    final roundSource = '${temp.path}/round.svg';
    await File(roundSource).writeAsString(
      source.replaceFirst(
        RegExp(r'<rect\b[^>]*/>'),
        '<circle cx="512" cy="512" r="412" fill="#FFFFFF"/>',
      ),
    );
    const densities = {
      'mdpi': (48, 80),
      'hdpi': (72, 120),
      'xhdpi': (96, 160),
      'xxhdpi': (144, 240),
      'xxxhdpi': (192, 320),
    };
    for (final MapEntry(key: density, value: sizes) in densities.entries) {
      for (final round in [false, true]) {
        final png = '${temp.path}/$density-$round.png';
        await _render(round ? roundSource : _source, png, sizes.$1);
        await _run('cwebp', [
          '-quiet',
          '-lossless',
          png,
          '-o',
          '$_android/res/mipmap-$density/'
              'ic_launcher${round ? '_round' : ''}.webp',
        ]);
      }
      final tvPng = '${temp.path}/tv-$density.png';
      await _render(_source, tvPng, sizes.$2);
      await _run('cwebp', [
        '-quiet',
        '-lossless',
        tvPng,
        '-o',
        '$_android/res/mipmap-television-$density/ic_launcher.webp',
      ]);
    }

    final storeSource = '${temp.path}/store.svg';
    await File(storeSource).writeAsString(
      source.replaceFirst(
        'viewBox="0 0 1024 1024"',
        'viewBox="100 100 824 824"',
      ),
    );
    await _render(
      storeSource,
      '$_android/ic_launcher-playstore.png',
      512,
      background: '#FFFFFF',
    );
    await _render(
      'assets/images/banner.svg',
      '$_android/res/mipmap-xhdpi/ic_banner.png',
      320,
      height: 180,
    );

    final adaptive = _adaptiveVector(source);
    for (final suffix in ['', '_tv']) {
      await File(
        '$_android/res/drawable/ic_launcher_foreground$suffix.xml',
      ).writeAsString(adaptive);
    }
    stdout.writeln('Generated shared, macOS, Windows and Android app icons.');
  } finally {
    await temp.delete(recursive: true);
  }
}

String _adaptiveVector(String source) {
  final logo = RegExp(r'<svg\b[^>]*>').allMatches(source).last.group(0)!;
  final viewBox = _attribute(
    logo,
    'viewBox',
  ).split(' ').map(double.parse).toList();
  final tile = RegExp(r'<rect\b[^>]*>').firstMatch(source)!.group(0)!;
  final scale =
      double.parse(_attribute(logo, 'width')) /
      viewBox[2] /
      double.parse(_attribute(tile, 'width')) *
      (100 * 2 / 3);
  final translateX = 50 - (viewBox[0] + viewBox[2] / 2) * scale;
  final translateY = 50 - (viewBox[1] + viewBox[3] / 2) * scale;
  final group = RegExp(r'<g\b[^>]*>').firstMatch(source)!.group(0)!;
  final paths = RegExp(r'<path\b[^>]*/>').allMatches(source).map((match) {
    final path = match.group(0)!;
    return '''        <path
            android:fillColor="@android:color/transparent"
            android:pathData="${_attribute(path, 'd')}"
            android:strokeColor="${_attribute(path, 'stroke')}"
            android:strokeLineCap="round"
            android:strokeLineJoin="round"
            android:strokeWidth="${_attribute(group, 'stroke-width')}" />''';
  });
  return '''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="100"
    android:viewportHeight="100">
    <group
        android:scaleX="${scale.toStringAsFixed(8)}"
        android:scaleY="${scale.toStringAsFixed(8)}"
        android:translateX="${translateX.toStringAsFixed(8)}"
        android:translateY="${translateY.toStringAsFixed(8)}">
${paths.join('\n')}
    </group>
</vector>
''';
}

String _attribute(String tag, String name) {
  return RegExp('$name="([^"]+)"').firstMatch(tag)!.group(1)!;
}

Future<void> _render(
  String source,
  String output,
  int size, {
  int? height,
  String? background,
}) {
  return _run('rsvg-convert', [
    '-w',
    '$size',
    '-h',
    '${height ?? size}',
    if (background != null) ...['--background-color', background],
    '-o',
    output,
    source,
  ]);
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stderr}',
      result.exitCode,
    );
  }
}

Uint8List _buildIco(List<int> sizes, List<Uint8List> frames) {
  final header = ByteData(6)..setUint16(2, 1, Endian.little);
  header.setUint16(4, sizes.length, Endian.little);
  final entries = ByteData(16 * sizes.length);
  var imageOffset = header.lengthInBytes + entries.lengthInBytes;
  for (var i = 0; i < sizes.length; i++) {
    final offset = i * 16;
    final size = sizes[i] == 256 ? 0 : sizes[i];
    entries
      ..setUint8(offset, size)
      ..setUint8(offset + 1, size)
      ..setUint16(offset + 4, 1, Endian.little)
      ..setUint16(offset + 6, 32, Endian.little)
      ..setUint32(offset + 8, frames[i].length, Endian.little)
      ..setUint32(offset + 12, imageOffset, Endian.little);
    imageOffset += frames[i].length;
  }
  final bytes = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(entries.buffer.asUint8List());
  for (final frame in frames) {
    bytes.add(frame);
  }
  return bytes.toBytes();
}
