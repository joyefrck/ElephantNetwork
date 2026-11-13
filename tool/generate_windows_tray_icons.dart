import 'dart:io';
import 'dart:typed_data';

const _sizes = [16, 20, 24, 28, 32, 40, 48, 64, 128, 256];

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('windows_tray_icons_');
  try {
    for (final state in ['active', 'inactive']) {
      final name = 'tray_windows_$state';
      final frames = <Uint8List>[];
      for (final size in _sizes) {
        final output = '${temp.path}/$name-$size.png';
        final arguments = [
          '-w',
          '$size',
          '-h',
          '$size',
          '-o',
          output,
          'assets_source/images/$name.svg',
        ];
        final result = await Process.run('rsvg-convert', arguments);
        if (result.exitCode != 0) {
          throw ProcessException(
            'rsvg-convert',
            arguments,
            '${result.stderr}',
            result.exitCode,
          );
        }
        frames.add(await File(output).readAsBytes());
      }
      await File('assets/images/$name.ico').writeAsBytes(_buildIco(frames));
      stdout.writeln('Generated assets/images/$name.ico');
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

Uint8List _buildIco(List<Uint8List> frames) {
  final header = ByteData(6)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, frames.length, Endian.little);
  final entries = ByteData(16 * frames.length);
  var imageOffset = header.lengthInBytes + entries.lengthInBytes;
  for (var i = 0; i < frames.length; i++) {
    final offset = i * 16;
    final size = _sizes[i] == 256 ? 0 : _sizes[i];
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
