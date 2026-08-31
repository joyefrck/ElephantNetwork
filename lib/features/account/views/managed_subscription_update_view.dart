import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ManagedSubscriptionSync = Future<bool> Function();

class ManagedSubscriptionUpdateView extends ConsumerStatefulWidget {
  const ManagedSubscriptionUpdateView({super.key, this.sync});

  final ManagedSubscriptionSync? sync;

  @override
  ConsumerState<ManagedSubscriptionUpdateView> createState() =>
      _ManagedSubscriptionUpdateViewState();
}

class _ManagedSubscriptionUpdateViewState
    extends ConsumerState<ManagedSubscriptionUpdateView> {
  bool _isSyncing = false;

  Future<void> _sync() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
    });
    var succeeded = false;
    try {
      succeeded =
          await (widget.sync?.call() ??
              ref
                  .read(xboardSessionControllerProvider.notifier)
                  .syncManagedProfile());
    } catch (_) {
      succeeded = false;
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
    if (!succeeded && mounted) {
      context.showNotifier(
        context.appLocalizations.managedSubscriptionUnavailable,
      );
    }
  }

  Profile? _findManagedProfile(List<Profile> profiles, String? accountId) {
    if (accountId == null) return null;
    for (final profile in profiles) {
      if (profile.source == ProfileSource.xboard &&
          profile.ownerAccountId == accountId) {
        return profile;
      }
    }
    return null;
  }

  void _updateProfile(
    Profile profile,
    Profile Function(Profile profile) builder,
  ) {
    ref.read(profilesProvider.notifier).updateProfile(profile.id, builder);
  }

  Widget _buildSyncButton() {
    return FilledButton.tonalIcon(
      key: const Key('managed-subscription-sync'),
      onPressed: _isSyncing ? null : _sync,
      icon: _isSyncing
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      label: Text(context.appLocalizations.updateNow),
    );
  }

  Widget _buildProfile(Profile profile) {
    final appLocalizations = context.appLocalizations;
    final interval = profile.autoUpdateDuration.inMinutes;
    final items = [
      ...generateSection(
        title: profile.realLabel,
        items: [
          ListItem(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: Text(appLocalizations.updateNow),
            subtitle: profile.lastUpdateDate == null
                ? null
                : TickBuilder(
                    duration: const Duration(minutes: 1),
                    builder: (context, _) {
                      return Text(
                        profile.lastUpdateDate!.getLastUpdateTimeDesc(context),
                      );
                    },
                  ),
            trailing: _buildSyncButton(),
          ),
        ],
      ),
      ...generateSection(
        title: appLocalizations.settings,
        items: [
          ListItem.toggle(
            key: const Key('managed-subscription-auto-update'),
            leading: const Icon(Icons.update),
            title: Text(appLocalizations.autoUpdate),
            value: profile.autoUpdate,
            onChanged: (value) {
              _updateProfile(
                profile,
                (current) => current.copyWith(autoUpdate: value),
              );
            },
          ),
          if (profile.autoUpdate)
            ListItem.input(
              key: const Key('managed-subscription-update-interval'),
              leading: const Icon(Icons.schedule),
              title: Text(appLocalizations.autoUpdateInterval),
              subtitle: Text(interval.toString()),
              dialogTitle: appLocalizations.autoUpdateInterval,
              value: interval.toString(),
              maxLength: TextInputLimits.interval,
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return appLocalizations
                      .profileAutoUpdateIntervalNullValidationDesc;
                }
                final minutes = int.tryParse(value);
                if (minutes == null) {
                  return appLocalizations
                      .profileAutoUpdateIntervalInvalidValidationDesc;
                }
                if (minutes <= 0) {
                  return appLocalizations
                      .profileAutoUpdateIntervalPositiveValidationDesc;
                }
                return null;
              },
              onChanged: (value) {
                final minutes = int.tryParse(value ?? '');
                if (minutes == null || minutes <= 0) return;
                _updateProfile(
                  profile,
                  (current) => current.copyWith(
                    autoUpdateDuration: Duration(minutes: minutes),
                  ),
                );
              },
            ),
        ],
      ),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountId = ref.watch(
      xboardSessionControllerProvider.select(
        (state) => state.session?.account.accountId,
      ),
    );
    final profile = _findManagedProfile(ref.watch(profilesProvider), accountId);
    return CommonScaffold(
      title: context.appLocalizations.subscriptionUpdate,
      isLoading: _isSyncing,
      floatingActionButton: profile == null
          ? CommonFloatingActionButton(
              onPressed: _isSyncing ? null : _sync,
              icon: const Icon(Icons.refresh),
              label: context.appLocalizations.retry,
            )
          : null,
      body: profile == null
          ? NullStatus(
              label: context.appLocalizations.managedSubscriptionUnavailable,
              illustration: const ProfileEmptyIllustration(),
            )
          : _buildProfile(profile),
    );
  }
}
