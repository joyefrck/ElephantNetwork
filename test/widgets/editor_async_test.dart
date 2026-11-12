import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'Editor did not settle');
}

Future<void> openEditor(WidgetTester tester, Widget editor) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  globalState.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        builder: (context, child) {
          globalState.measure = Measure.of(context, 1);
          globalState.theme = CommonTheme.of(context, 1);
          return child!;
        },
        home: editor,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'background parsing preserves Chinese text, undo and single save',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      String? saved;
      await openEditor(
        tester,
        EditorPage(
          title: 'Config',
          content: '原文',
          onSave: (_, _, content) async {
            calls++;
            saved = content;
            await pending.future;
          },
        ),
      );
      final controller = tester
          .widget<CodeEditor>(find.byType(CodeEditor))
          .controller!;
      await waitUntil(tester, () => controller.text == '原文');
      controller.replaceSelection('中文🐘');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.save))
            .onPressed,
        isNotNull,
      );
      final edited = controller.text;
      controller.undo();
      await tester.pump();
      expect(controller.text, '原文');
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.save))
            .onPressed,
        isNull,
      );
      controller.redo();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.save));
      await waitUntil(tester, () => calls == 1);
      expect(saved, edited);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.save))
            .onPressed,
        isNull,
      );
      pending.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Chinese IME composition survives asynchronous initialization', (
    tester,
  ) async {
    await openEditor(
      tester,
      EditorPage(title: 'IME', content: '', onSave: (_, _, _) {}),
    );
    await waitUntil(
      tester,
      () => tester.widget<CodeEditor>(find.byType(CodeEditor)).readOnly != true,
    );
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    final state = TextEditingValue.fromJSON(tester.testTextInput.editingState!);
    final offset = state.selection.baseOffset;
    Future<void> delta(
      String old,
      String text,
      int start,
      int end,
      int cursor,
      int composingStart,
      int composingEnd,
    ) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithDeltas', [
            -1,
            {
              'deltas': [
                {
                  'oldText': old,
                  'deltaText': text,
                  'deltaStart': start,
                  'deltaEnd': end,
                  'selectionBase': cursor,
                  'selectionExtent': cursor,
                  'selectionAffinity': 'TextAffinity.downstream',
                  'selectionIsDirectional': false,
                  'composingBase': composingStart,
                  'composingExtent': composingEnd,
                },
              ],
            },
          ]),
        ),
        (_) {},
      );
      await tester.pump();
    }

    await delta(
      state.text,
      'zhong',
      offset,
      offset,
      offset + 5,
      offset,
      offset + 5,
    );
    final composingText = state.text.replaceRange(offset, offset, 'zhong');
    await delta(composingText, '中', offset, offset + 5, offset + 1, -1, -1);
    expect(editor.controller!.text, '中');
    expect(editor.controller!.isComposing, isFalse);
    await tester.pump(const Duration(milliseconds: 150));
    editor.focusNode!.unfocus();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing while a large document loads ignores worker completion',
    (tester) async {
      await openEditor(
        tester,
        EditorPage(
          title: 'Large',
          content: List.filled(30000, '规则: 中文').join('\n'),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
