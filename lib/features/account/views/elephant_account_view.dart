import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

typedef XboardWebsiteUrlLauncher =
    Future<bool> Function(Uri uri, {LaunchMode mode});

Future<bool> launchXboardWebsite({
  required XboardApi api,
  required String token,
  XboardWebsiteUrlLauncher launcher = launchUrl,
}) async {
  final uri = await api.quickLogin(token, 'dashboard');
  return launcher(uri, mode: LaunchMode.externalApplication);
}

class ElephantAccountView extends ConsumerWidget {
  const ElephantAccountView({super.key});

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String title,
    String redirect,
  ) async {
    final session = ref.read(xboardSessionControllerProvider).session;
    if (session == null) return;
    final uri = await globalState.loadingRun(
      () => ref.read(xboardApiProvider).quickLogin(session.token, redirect),
      tag: null,
      title: title,
    );
    if (uri == null || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ElephantWebViewPage(title: title, uri: uri),
      ),
    );
  }

  Future<void> _openWebsite(BuildContext context, WidgetRef ref) async {
    final session = ref.read(xboardSessionControllerProvider).session;
    if (session == null) return;
    await globalState.loadingRun(
      () => launchXboardWebsite(
        api: ref.read(xboardApiProvider),
        token: session.token,
      ),
      tag: null,
      title: context.appLocalizations.openWebsite,
    );
  }

  String _traffic(int bytes) {
    final value = bytes.traffic;
    return '${value.value} ${value.unit}';
  }

  String _expiry(BuildContext context, int? seconds) {
    if (seconds == null || seconds <= 0) {
      return context.appLocalizations.neverExpires;
    }
    return DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(DateTime.fromMillisecondsSinceEpoch(seconds * 1000));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final state = ref.watch(xboardSessionControllerProvider);
    final account = state.session?.account;
    if (account == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return CommonScaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                l10n.accountOverview,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              key: const Key('open-website-button'),
              onPressed: () => _openWebsite(context, ref),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                l10n.openWebsite,
                style: context.textTheme.labelLarge?.copyWith(
                  color: context.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: context.colorScheme.primary,
                  decorationThickness: 1.2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.retry,
            onPressed: () =>
                ref.read(xboardSessionControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.email,
                          style: context.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 32,
                          runSpacing: 20,
                          children: [
                            _Metric(
                              label: l10n.balance,
                              value: '¥${(account.balance / 100).fixed()}',
                            ),
                            _Metric(
                              label: l10n.expiration,
                              value: _expiry(context, account.expiredAt),
                            ),
                            _Metric(
                              label: l10n.remaining,
                              value: _traffic(
                                account.effectiveRemainingTraffic,
                              ),
                            ),
                            _Metric(
                              label: l10n.used,
                              value: _traffic(
                                account.upload + account.download,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.data_usage),
                        title: Text(l10n.planTraffic),
                        subtitle: Text(
                          '${_traffic(account.planRemainingTraffic)} / '
                          '${_traffic(account.planTransferEnable)}',
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.add_chart),
                        title: Text(l10n.trafficPackage),
                        subtitle: Text(
                          '${_traffic(account.trafficPackageRemaining)} / '
                          '${_traffic(account.trafficPackageTotal)}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      _WebEntry(
                        icon: Icons.shopping_bag_outlined,
                        label: l10n.plans,
                        onTap: () => _open(context, ref, l10n.plans, 'plan'),
                      ),
                      const Divider(height: 0),
                      _WebEntry(
                        icon: Icons.receipt_long_outlined,
                        label: l10n.orders,
                        onTap: () => _open(context, ref, l10n.orders, 'order'),
                      ),
                      const Divider(height: 0),
                      _WebEntry(
                        icon: Icons.support_agent,
                        label: l10n.supportTickets,
                        onTap: () =>
                            _open(context, ref, l10n.supportTickets, 'ticket'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => ref
                      .read(xboardSessionControllerProvider.notifier)
                      .logout(),
                  icon: const Icon(Icons.logout),
                  label: Text(l10n.signOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.labelMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: context.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _WebEntry extends StatelessWidget {
  const _WebEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
