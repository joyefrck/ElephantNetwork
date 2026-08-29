import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows_webview;

class ElephantWebViewPage extends StatelessWidget {
  const ElephantWebViewPage({
    super.key,
    required this.title,
    required this.uri,
  });

  final String title;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    if (system.isWindows) {
      return _WindowsWebViewPage(title: title, uri: uri);
    }
    return _MobileWebViewPage(title: title, uri: uri);
  }
}

class _MobileWebViewPage extends StatefulWidget {
  const _MobileWebViewPage({required this.title, required this.uri});

  final String title;
  final Uri uri;

  @override
  State<_MobileWebViewPage> createState() => _MobileWebViewPageState();
}

class _MobileWebViewPageState extends State<_MobileWebViewPage> {
  late final mobile_webview.WebViewController _controller;
  var _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = mobile_webview.WebViewController()
      ..setJavaScriptMode(mobile_webview.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        mobile_webview.NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return mobile_webview.NavigationDecision.prevent;
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return mobile_webview.NavigationDecision.navigate;
            }
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
            return mobile_webview.NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          Expanded(
            child: mobile_webview.WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}

class _WindowsWebViewPage extends StatefulWidget {
  const _WindowsWebViewPage({required this.title, required this.uri});

  final String title;
  final Uri uri;

  @override
  State<_WindowsWebViewPage> createState() => _WindowsWebViewPageState();
}

class _WindowsWebViewPageState extends State<_WindowsWebViewPage> {
  final _controller = windows_webview.WebviewController();
  StreamSubscription<String>? _urlSubscription;
  var _initialized = false;
  var _fallingBack = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final version =
          await windows_webview.WebviewController.getWebViewVersion();
      if (version == null) {
        await _fallback();
        return;
      }
      await _controller.initialize();
      await _controller.setPopupWindowPolicy(
        windows_webview.WebviewPopupWindowPolicy.sameWindow,
      );
      _urlSubscription = _controller.url.listen((value) {
        final uri = Uri.tryParse(value);
        if (uri == null || uri.scheme == 'http' || uri.scheme == 'https') {
          return;
        }
        unawaited(_controller.stop());
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
      });
      await _controller.loadUrl(widget.uri.toString());
      if (mounted) setState(() => _initialized = true);
    } catch (_) {
      await _fallback();
    }
  }

  Future<void> _fallback() async {
    if (_fallingBack) return;
    _fallingBack = true;
    await launchUrl(widget.uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.appLocalizations.webviewUnavailable)),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(_urlSubscription?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _initialized
          ? windows_webview.Webview(_controller)
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
