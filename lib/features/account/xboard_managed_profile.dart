import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

import 'xboard_config.dart';
import 'xboard_models.dart';

bool isXboardProfileForAccount(Profile? profile, String? accountId) {
  return accountId != null &&
      accountId.isNotEmpty &&
      profile?.source == ProfileSource.xboard &&
      profile?.ownerAccountId == accountId;
}

Profile buildXboardManagedProfile({
  required Profile? existing,
  required Uri subscription,
  required XboardAccount account,
}) {
  return (existing ?? Profile.normal(label: XboardConfig.managedProfileLabel))
      .copyWith(
        label: XboardConfig.managedProfileLabel,
        url: subscription.toString(),
        source: ProfileSource.xboard,
        ownerAccountId: account.accountId,
      );
}
