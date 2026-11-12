import 'dart:io';

import 'package:fl_clash/common/editor_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'large Unicode file is decoded, parsed and encoded off the UI isolate',
    () async {
      final root = await Directory.systemTemp.createTemp('editor-document-');
      addTearDown(() => root.delete(recursive: true));
      final text = List.generate(
        50000,
        (index) => '规则-$index: 大象🐘',
      ).join('\n');
      final file = File('${root.path}/large.yaml');
      await file.writeAsString(text);
      final loaded = await readEditorFile(file.path);
      final lines = await parseEditorText(loaded);
      expect(lines.lineCount, 50000);
      expect(await readEditorLines(lines), text);
      expect(await decodeEditorBytes(await encodeEditorText(text)), text);
    },
  );
  test('missing editor file opens as an empty document', () async {
    final root = await Directory.systemTemp.createTemp('editor-missing-');
    addTearDown(() => root.delete(recursive: true));
    expect(await readEditorFile('${root.path}/missing.yaml'), '');
  });
}
