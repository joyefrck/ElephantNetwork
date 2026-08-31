import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

import 'xboard_config.dart';
import 'xboard_models.dart';

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
