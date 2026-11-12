import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

Future<String> readEditorFile(String path) => compute(_readFile, path);
String _readFile(String path) {
  try {
    return File(path).readAsStringSync();
  } on PathNotFoundException {
    return '';
  }
}

Future<CodeLines> parseEditorText(String text) =>
    compute(CodeLines.fromText, text);
Future<String> readEditorLines(CodeLines lines) => compute(_readLines, lines);
String _readLines(CodeLines lines) => lines.asString(TextLineBreak.lf);
Future<String> decodeEditorBytes(Uint8List bytes) =>
    compute(_decodeBytes, bytes);
String _decodeBytes(Uint8List bytes) => utf8.decode(bytes);
Future<Uint8List> encodeEditorText(String text) => compute(_encodeText, text);
Uint8List _encodeText(String text) => Uint8List.fromList(utf8.encode(text));
