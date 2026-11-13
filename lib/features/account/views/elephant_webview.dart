import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows_webview;

class ElephantWebViewPage extends StatefulWidget {
  const ElephantWebViewPage({
    super.key,
    required this.title,
    required this.uri,
    this.refreshUri,
  });

  final String title;
  final Uri uri;
  final Future<Uri> Function()? refreshUri;

  @override
  State<ElephantWebViewPage> createState() => _ElephantWebViewPageState();
}

class _ElephantWebViewPageState extends State<ElephantWebViewPage> {
  late Uri _uri = widget.uri;
  Timer? _timeout;
  var _attempt = 0;
  var _failed = false;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  void _startLoading() {
    if (!mounted || _failed) return;
    _timeout ??= Timer(const Duration(seconds: 20), _loadFailed);
  }

  void _finishLoading() {
    _timeout?.cancel();
    _timeout = null;
  }

  void _loadFailed() {
    _finishLoading();
    if (mounted) setState(() => _failed = true);
  }

  Future<void> _retry() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final uri = await (widget.refreshUri?.call() ?? Future.value(widget.uri));
      if (!mounted) return;
      setState(() {
        _uri = uri;
        _attempt++;
        _failed = false;
      });
      _startLoading();
    } catch (_) {
      _loadFailed();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void dispose() {
    _finishLoading();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_outlined, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      context.appLocalizations.networkException,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refreshing ? null : _retry,
                      icon: _refreshing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(context.appLocalizations.retry),
                    ),
                  ],
                ),
              ),
            )
          : system.isWindows
          ? _WindowsWebViewPage(
              key: ValueKey(_attempt),
              uri: _uri,
              onStarted: _startLoading,
              onFinished: _finishLoading,
              onFailed: _loadFailed,
            )
          : _MobileWebViewPage(
              key: ValueKey(_attempt),
              uri: _uri,
              onStarted: _startLoading,
              onFinished: _finishLoading,
              onFailed: _loadFailed,
            ),
    );
  }
}

class _MobileWebViewPage extends StatefulWidget {
  const _MobileWebViewPage({
    super.key,
    required this.uri,
    required this.onStarted,
    required this.onFinished,
    required this.onFailed,
  });

  final Uri uri;
  final VoidCallback onStarted;
  final VoidCallback onFinished;
  final VoidCallback onFailed;

  @override
  State<_MobileWebViewPage> createState() => _MobileWebViewPageState();
}

class _MobileWebViewPageState extends State<_MobileWebViewPage> {
  late final mobile_webview.WebViewController _controller;
  late Uri _documentUri = widget.uri.removeFragment();
  var _initialized = false;
  var _progress = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future<void>.value();
    if (!mounted) return;
    try {
      _controller = mobile_webview.WebViewController();
      await _controller.setJavaScriptMode(
        mobile_webview.JavaScriptMode.unrestricted,
      );
      await _controller.setNavigationDelegate(
        mobile_webview.NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            _documentUri = Uri.parse(url).removeFragment();
            setState(() => _progress = 0);
            widget.onStarted();
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _progress = 100);
            widget.onFinished();
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) widget.onFailed();
          },
          onHttpError: (error) {
            if (mounted &&
                error.request?.uri.removeFragment() == _documentUri) {
              widget.onFailed();
            }
          },
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
      );
      if (!mounted) return;
      setState(() => _initialized = true);
      await _controller.loadRequest(widget.uri);
    } catch (_) {
      if (mounted) widget.onFailed();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
        Expanded(child: mobile_webview.WebViewWidget(controller: _controller)),
      ],
    );
  }
}

class _WindowsWebViewPage extends StatefulWidget {
  const _WindowsWebViewPage({
    super.key,
    required this.uri,
    required this.onStarted,
    required this.onFinished,
    required this.onFailed,
  });

  final Uri uri;
  final VoidCallback onStarted;
  final VoidCallback onFinished;
  final VoidCallback onFailed;

  @override
  State<_WindowsWebViewPage> createState() => _WindowsWebViewPageState();
}

class _WindowsWebViewPageState extends State<_WindowsWebViewPage> {
  final _controller = windows_webview.WebviewController();
  StreamSubscription<String>? _urlSubscription;
  StreamSubscription<windows_webview.LoadingState>? _loadingSubscription;
  StreamSubscription<windows_webview.WebErrorStatus>? _errorSubscription;
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
      if (!mounted) return;
      if (version == null) {
        await _fallback();
        return;
      }
      await _controller.initialize();
      if (!mounted) return;
      await _controller.setPopupWindowPolicy(
        windows_webview.WebviewPopupWindowPolicy.sameWindow,
      );
      if (!mounted) return;
      _loadingSubscription = _controller.loadingState.listen((state) {
        if (!mounted) return;
        if (state == windows_webview.LoadingState.loading) {
          widget.onStarted();
        } else if (state == windows_webview.LoadingState.navigationCompleted) {
          widget.onFinished();
        }
      });
      _errorSubscription = _controller.onLoadError.listen((_) {
        if (mounted) widget.onFailed();
      });
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
    if (!mounted || _fallingBack) return;
    _fallingBack = true;
    try {
      final launched = await launchUrl(
        widget.uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        if (mounted) widget.onFailed();
        return;
      }
    } catch (_) {
      if (mounted) widget.onFailed();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.appLocalizations.webviewUnavailable)),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(_urlSubscription?.cancel());
    unawaited(_loadingSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _initialized
        ? windows_webview.Webview(_controller)
        : const Center(child: CircularProgressIndicator());
  }
}
