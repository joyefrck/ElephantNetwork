import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/diagnostics/diagnostics_controller.dart';
import 'package:fl_clash/providers/diagnostics.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiagnosticsView extends ConsumerStatefulWidget {
  const DiagnosticsView({super.key});
  @override
  ConsumerState<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends ConsumerState<DiagnosticsView>
    with WidgetsBindingObserver {
  late final DiagnosticsController _controller;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ref.read(diagnosticsProvider);
    ref.listenManual(coreStatusProvider, (_, _) => _configure());
    ref.listenManual(isStartProvider, (_, _) => _configure());
    ref.listenManual(suspendProvider, (_, _) => _configure());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _configure();
    });
  }

  void _configure() {
    _controller.setEnvironment(
      connected: ref.read(coreStatusProvider) == CoreStatus.connected,
      running: ref.read(isStartProvider) && !ref.read(suspendProvider),
      visible: _visible,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _configure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.setEnvironment(
      connected: false,
      running: _controller.running,
      visible: false,
    );
    super.dispose();
  }

  String _status(String value) {
    final l10n = context.appLocalizations;
    return switch (value) {
      'available' => l10n.probeAvailable,
      'unavailable' => l10n.probeUnavailable,
      'restricted' => l10n.probeRestricted,
      'disallowed-isp' => l10n.probeDisallowedIsp,
      'blocked' => l10n.probeBlocked,
      'unsupported-region' => l10n.probeUnsupportedRegion,
      'originals-only' => l10n.probeOriginalsOnly,
      'coming-soon' => l10n.probeComingSoon,
      'timeout' => l10n.probeTimeout,
      _ => l10n.probeFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(diagnosticsProvider);
    final l10n = context.appLocalizations;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final ip = _controller.outbound;
        final quality = _controller.quality;
        return CommonScaffold(
          title: l10n.networkDiagnostics,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _controller.running
                    ? l10n.diagnosticsRouting
                    : l10n.diagnosticsDirect,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: !_controller.available
                      ? null
                      : _controller.busy
                      ? _controller.cancel
                      : _controller.refresh,
                  icon: Icon(_controller.busy ? Icons.stop : Icons.refresh),
                  label: Text(
                    _controller.busy ? l10n.cancel : l10n.diagnosticsRefresh,
                  ),
                ),
              ),
              if (_controller.busy) const LinearProgressIndicator(),
              if (!_controller.available) Text(l10n.diagnosticsNotReady),
              if (_controller.routeChanged) Text(l10n.diagnosticsRouteChanged),
              if (_controller.failed) Text(l10n.diagnosticsFailed),
              if (ip?.ip != null) ...[
                ListTile(
                  title: Text(l10n.outboundIp),
                  subtitle: SelectableText(ip!.ip!),
                ),
                ListTile(
                  title: Text(l10n.diagnosticsRoute),
                  subtitle: Text(ip.chains.join(' → ')),
                ),
                ListTile(
                  title: Text(l10n.diagnosticsSource),
                  subtitle: Text(ip.source),
                ),
              ],
              if (quality != null) ...[
                const Divider(),
                ListTile(
                  title: Text(l10n.ipQuality),
                  subtitle: Text(switch (quality.type) {
                    IpType.residential => l10n.ipResidential,
                    IpType.mobile => l10n.ipMobile,
                    IpType.business => l10n.ipBusiness,
                    IpType.hosting => l10n.ipHosting,
                  }),
                ),
                if (quality.organization != null)
                  ListTile(title: Text(quality.organization!)),
                if (quality.asn != null)
                  ListTile(title: Text('AS${quality.asn}')),
                ListTile(
                  title: Text(l10n.diagnosticsSource),
                  subtitle: Text(quality.source.label),
                ),
                if (quality.isProxy ||
                    quality.isVpn ||
                    quality.isTor ||
                    quality.isAbuser)
                  ListTile(
                    title: Text(l10n.ipReportedFlags),
                    subtitle: Text(
                      [
                        if (quality.isProxy) l10n.ipProxy,
                        if (quality.isVpn) 'VPN',
                        if (quality.isTor) 'Tor',
                        if (quality.isAbuser) l10n.ipAbuser,
                      ].join(' · '),
                    ),
                  ),
              ],
              if (_controller.qualityFailed) Text(l10n.ipQualityUnavailable),
              if (_controller.services.isNotEmpty) ...[
                const Divider(),
                ListHeader(title: l10n.serviceAvailability),
                for (final service in _controller.services)
                  ListTile(
                    title: Text(service.name),
                    subtitle: Text(
                      [
                        _status(service.status),
                        if (service.region?.isNotEmpty == true) service.region!,
                        if (service.delay != null && service.delay! > 0)
                          '${service.delay} ms',
                        if (service.chains.isNotEmpty)
                          service.chains.join(' → '),
                      ].join(' · '),
                    ),
                    leading: Icon(
                      service.status == 'available'
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
