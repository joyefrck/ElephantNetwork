import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/features/account/xboard_managed_profile.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const account = XboardAccount(
    email: 'Owner@Example.com',
    balance: 0,
    upload: 0,
    download: 0,
    planTransferEnable: 0,
    planUsedTraffic: 0,
    planRemainingTraffic: 0,
    trafficPackageTotal: 0,
    trafficPackageRemaining: 0,
    effectiveTransferEnable: 0,
    effectiveRemainingTraffic: 0,
  );
  final subscription = Uri.parse('https://example.com/subscription');

  test('new managed profile uses automatic daily updates', () {
    final profile = buildXboardManagedProfile(
      existing: null,
      subscription: subscription,
      account: account,
    );

    expect(profile.label, XboardConfig.managedProfileLabel);
    expect(profile.url, subscription.toString());
    expect(profile.source, ProfileSource.xboard);
    expect(profile.ownerAccountId, 'owner@example.com');
    expect(profile.autoUpdate, isTrue);
    expect(profile.autoUpdateDuration, const Duration(days: 1));
  });

  test('existing managed profile keeps update preferences during sync', () {
    final existing = Profile.normal(label: 'Old').copyWith(
      autoUpdate: false,
      autoUpdateDuration: const Duration(minutes: 45),
      source: ProfileSource.xboard,
      ownerAccountId: account.accountId,
    );

    final profile = buildXboardManagedProfile(
      existing: existing,
      subscription: subscription,
      account: account,
    );

    expect(profile.id, existing.id);
    expect(profile.autoUpdate, isFalse);
    expect(profile.autoUpdateDuration, const Duration(minutes: 45));
    expect(profile.url, subscription.toString());
  });
}
