import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TunnelConfigView extends ConsumerStatefulWidget {
  const TunnelConfigView({super.key});

  @override
  ConsumerState<TunnelConfigView> createState() => _TunnelConfigViewState();
}

class _TunnelConfigViewState extends ConsumerState<TunnelConfigView> {
  bool _busy = false;
  String? _message;

  Future<void> _change(NetworkProps settings, {bool enableTun = false}) async {
    if (_busy) return;
    final action = ref.read(systemActionProvider.notifier);
    final labels = context.appLocalizations;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action.configureApns(settings, enableTun: enableTun);
      if (mounted) setState(() => _message = labels.apnsSaved);
    } catch (_) {
      if (mounted) {
        setState(() => _message = labels.apnsApplyFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = context.appLocalizations;
    final settings = ref.watch(networkSettingProvider);
    final tun = ref.watch(
      patchClashConfigProvider.select((value) => value.tun.enable),
    );
    final mode = ref.watch(
      patchClashConfigProvider.select((value) => value.mode),
    );
    final groups = ref.watch(groupsProvider);
    final targets = {
      for (final group in groups)
        if (group.name != GroupName.GLOBAL.name && group.hidden != true)
          group.name,
    }.toList();
    final selected = targets.contains(settings.apnsProxy)
        ? settings.apnsProxy!
        : '';
    String routeLabel(ApnsRoute route) => switch (route) {
      ApnsRoute.rule => labels.apnsFollowRules,
      ApnsRoute.proxy => labels.apnsViaProxy,
      ApnsRoute.direct => labels.apnsDirect,
    };

    return BaseScaffold(
      title: labels.tunnelSettings,
      body: AbsorbPointer(
        absorbing: _busy,
        child: generateListView([
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      final preferred = ref
                          .read(currentProfileProvider)
                          ?.currentGroupName;
                      _change(
                        settings.copyWith(
                          includeApns: true,
                          apnsRoute: ApnsRoute.proxy,
                          apnsProxy: targets.contains(preferred)
                              ? preferred
                              : null,
                        ),
                        enableTun: true,
                      );
                    },
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_outlined),
              label: Text(_busy ? labels.apnsApplying : labels.apnsOneClick),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              labels.apnsOneClickDesc,
              style: context.textTheme.bodyMedium,
            ),
          ),
          ListItem.toggle(
            title: Text(labels.apnsInclude),
            subtitle: Text(labels.apnsIncludeDesc),
            value: settings.includeApns,
            onChanged: (value) =>
                _change(settings.copyWith(includeApns: value)),
          ),
          if (settings.includeApns) ...[
            ListItem<ApnsRoute>.options(
              title: Text(labels.apnsConnection),
              subtitle: Text(routeLabel(settings.apnsRoute)),
              dialogTitle: labels.apnsConnection,
              value: settings.apnsRoute,
              options: ApnsRoute.values,
              textBuilder: routeLabel,
              onChanged: (value) {
                if (value != null) _change(settings.copyWith(apnsRoute: value));
              },
            ),
            if (settings.apnsRoute == ApnsRoute.proxy)
              ListItem<String>.options(
                title: Text(labels.apnsProxyTarget),
                subtitle: Text(
                  selected.isEmpty ? labels.apnsAutomatic : selected,
                ),
                dialogTitle: labels.apnsProxyTarget,
                value: selected,
                options: ['', ...targets],
                textBuilder: (value) =>
                    value.isEmpty ? labels.apnsAutomatic : value,
                onChanged: (value) {
                  if (value == null) return;
                  _change(
                    settings.copyWith(apnsProxy: value.isEmpty ? null : value),
                  );
                },
              ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              !tun
                  ? labels.apnsTunRequired
                  : mode != Mode.rule
                  ? labels.apnsModeNotice
                  : labels.apnsTunnelNotice,
              style: context.textTheme.bodyMedium,
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_message!),
            ),
        ]),
      ),
    );
  }
}
