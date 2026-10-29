import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkDetection extends ConsumerStatefulWidget {
  const NetworkDetection({super.key});

  @override
  ConsumerState<NetworkDetection> createState() => _NetworkDetectionState();
}

class _NetworkDetectionState extends ConsumerState<NetworkDetection> {
  String _countryCodeToEmoji(String countryCode) {
    final String code = countryCode.toUpperCase();
    if (code.length != 2) {
      return countryCode;
    }
    final int firstLetter = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int secondLetter = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final networkDetection = ref.watch(networkDetectionProvider);
    final ipInfo = networkDetection.ipInfo;
    final isLoading = networkDetection.isLoading;
    final isStart = ref.watch(isStartProvider) && !ref.watch(suspendProvider);
    final mode = ref.watch(
      patchClashConfigProvider.select((config) => config.mode),
    );
    final groups = ref.watch(groupsProvider);
    final group = mode == Mode.global
        ? groups.getGroup(GroupName.GLOBAL.name)
        : groups
              .where(
                (group) =>
                    group.name != GroupName.GLOBAL.name && group.hidden != true,
              )
              .firstOrNull;
    final proxyName = !isStart
        ? appLocalizations.disconnected
        : mode == Mode.direct
        ? appLocalizations.direct
        : group == null
        ? '--'
        : ref.watch(realSelectedProxyStateProvider(group.name)).proxyName;
    final emojiTextStyle = context.textTheme.titleMedium?.toLight.copyWith(
      fontFamily: FontFamily.twEmoji.value,
    );
    final titleTextStyle = context.colorScheme.onSurfaceVariant;
    final descTextStyle = context.textTheme.titleSmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {},
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              height: globalState.measure.titleMediumHeight + 6.mAp,
              padding: baseInfoEdgeInsets.copyWith(top: 6.mAp, bottom: 0),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  ipInfo != null
                      ? Text(
                          _countryCodeToEmoji(ipInfo.countryCode),
                          style: emojiTextStyle,
                        )
                      : Icon(Icons.network_check, color: titleTextStyle),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 1,
                    child: TooltipText(
                      text: Text(
                        appLocalizations.networkDetection,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: descTextStyle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AspectRatio(
                    aspectRatio: 1,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        globalState.showMessage(
                          title: appLocalizations.tip,
                          message: TextSpan(
                            text: appLocalizations.detectionTip,
                          ),
                          cancelable: false,
                        );
                      },
                      icon: Icon(
                        size: 16.ap,
                        Icons.info_outline,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: baseInfoEdgeInsets.copyWith(top: 0, bottom: 6.mAp),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          appLocalizations.currentNodeLabel,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: context.colorScheme.outline,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: TooltipText(
                              text: Text(
                                proxyName.isEmpty ? '--' : proxyName,
                                style: context.textTheme.bodyMedium?.toLight
                                    .adjustSize(1),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: globalState.measure.bodySmallHeight + 2,
                      child: FadeThroughBox(
                        child: ipInfo != null
                            ? TooltipText(
                                text: Text(
                                  ipInfo.ip,
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: context.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            : isLoading == false && ipInfo == null
                            ? Text(
                                'Timeout',
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: Colors.red,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : Container(
                                padding: const EdgeInsets.all(2),
                                child: const AspectRatio(
                                  aspectRatio: 1,
                                  child: CommonCircleLoading(),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
