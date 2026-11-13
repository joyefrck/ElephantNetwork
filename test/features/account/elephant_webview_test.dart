import 'dart:async';

import 'package:fl_clash/features/account/views/elephant_webview.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  late _WebViewPlatform platform;

  setUp(() {
    platform = _WebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  testWidgets('stalled loading exposes retry after twenty seconds', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.pump(const Duration(seconds: 19));
    expect(find.text('重试'), findsNothing);
    platform.delegate.started('https://working.example/app');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('重试'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('completed loading cancels the timeout', (tester) async {
    await _pumpPage(tester);
    platform.delegate.finished('https://working.example/app');
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('重试'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('main frame errors expose retry but subresource errors do not', (
    tester,
  ) async {
    await _pumpPage(tester);
    platform.delegate.error(
      const WebResourceError(
        errorCode: -1,
        description: 'unreachable image',
        isForMainFrame: false,
      ),
    );
    await tester.pump();
    expect(find.text('重试'), findsNothing);
    platform.delegate.error(
      const WebResourceError(
        errorCode: -1,
        description: 'connection failed',
        isForMainFrame: true,
      ),
    );
    await tester.pump();
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('HTTP errors only fail the active document', (tester) async {
    await _pumpPage(tester);
    platform.delegate.httpError(
      HttpResponseError(
        request: WebResourceRequest(
          uri: Uri.parse('https://working.example/favicon.ico'),
        ),
        response: const WebResourceResponse(statusCode: 404, uri: null),
      ),
    );
    await tester.pump();
    expect(find.text('重试'), findsNothing);
    platform.delegate.httpError(
      HttpResponseError(
        request: WebResourceRequest(
          uri: Uri.parse('https://working.example/app'),
        ),
        response: const WebResourceResponse(statusCode: 503, uri: null),
      ),
    );
    await tester.pump();
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('retry obtains a fresh grant and ignores duplicate taps', (
    tester,
  ) async {
    final grant = Completer<Uri>();
    var refreshes = 0;
    await _pumpPage(
      tester,
      refreshUri: () {
        refreshes++;
        return grant.future;
      },
    );
    await tester.pump(const Duration(seconds: 20));
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.tap(find.text('重试'));
    expect(refreshes, 1);
    final fresh = Uri.parse(
      'https://working.example/app#/login?verify=fresh&redirect=order',
    );
    grant.complete(fresh);
    await tester.pump();
    await tester.pump();
    expect(platform.requests.last, fresh);
    expect(find.text('重试'), findsNothing);
    platform.delegate.finished(fresh.toString());
    await tester.pump();
  });

  testWidgets('failed grant refresh leaves an enabled retry', (tester) async {
    await _pumpPage(
      tester,
      refreshUri: () async => throw StateError('offline'),
    );
    await tester.pump(const Duration(seconds: 20));
    await tester.tap(find.text('重试'));
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('initialization failures expose retry', (tester) async {
    platform.failInitialization = true;
    await _pumpPage(tester);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during loading cancels timers and late callbacks', (
    tester,
  ) async {
    await _pumpPage(tester);
    final delegate = platform.delegate;
    await tester.pumpWidget(const SizedBox());
    delegate.started('https://working.example/app');
    delegate.finished('https://working.example/app');
    delegate.error(
      const WebResourceError(
        errorCode: -1,
        description: 'late',
        isForMainFrame: true,
      ),
    );
    await tester.pump(const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during grant refresh does not reopen the page', (
    tester,
  ) async {
    final grant = Completer<Uri>();
    await _pumpPage(tester, refreshUri: () => grant.future);
    await tester.pump(const Duration(seconds: 20));
    await tester.tap(find.text('重试'));
    await tester.pumpWidget(const SizedBox());
    grant.complete(
      Uri.parse('https://working.example/app#/login?verify=fresh'),
    );
    await tester.pump(const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
    expect(platform.requests, hasLength(1));
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  Future<Uri> Function()? refreshUri,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: ElephantWebViewPage(
        title: '我的订单',
        uri: Uri.parse(
          'https://working.example/app#/login?verify=initial&redirect=order',
        ),
        refreshUri: refreshUri,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _WebViewPlatform extends WebViewPlatform {
  late _NavigationDelegate delegate;
  final requests = <Uri>[];
  var failInitialization = false;

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return delegate = _NavigationDelegate(params);
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _WebViewController(params, this);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _WebViewWidget(params);
}

class _NavigationDelegate extends PlatformNavigationDelegate {
  _NavigationDelegate(super.params) : super.implementation();

  late PageEventCallback started;
  late PageEventCallback finished;
  late WebResourceErrorCallback error;
  late HttpResponseErrorCallback httpError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async =>
      started = callback;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async =>
      finished = callback;

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async =>
      error = callback;

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async =>
      httpError = callback;
}

class _WebViewController extends PlatformWebViewController {
  _WebViewController(super.params, this.platform) : super.implementation();

  final _WebViewPlatform platform;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    if (platform.failInitialization) throw StateError('unavailable');
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      platform.requests.add(params.uri);
}

class _WebViewWidget extends PlatformWebViewWidget {
  _WebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
