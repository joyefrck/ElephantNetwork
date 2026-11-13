import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/acceleration_guide.dart';
import 'widgets/core_status_button.dart';
import 'widgets/start_button.dart';

const _maxCrossAxisCount = 16;
const _maxGridWidth = 280.0 * _maxCrossAxisCount / 4;

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  final _guideOverlayController = OverlayPortalController();
  final _startButtonKey = GlobalKey();
  Rect? _guideTargetRect;
  bool _guideUpdateScheduled = false;

  void _completeAccelerationGuide() {
    final appSetting = ref.read(appSettingProvider);
    if (!appSetting.dashboardAccelerationGuideCompleted) {
      ref
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(dashboardAccelerationGuideCompleted: true),
          );
    }
    if (_guideOverlayController.isShowing) {
      _guideOverlayController.hide();
    }
    if (_guideTargetRect != null && mounted) {
      setState(() {
        _guideTargetRect = null;
      });
    }
  }

  void _clearAccelerationGuideTarget() {
    if (_guideOverlayController.isShowing) {
      _guideOverlayController.hide();
    }
    if (_guideTargetRect != null && mounted) {
      setState(() {
        _guideTargetRect = null;
      });
    }
  }

  void _scheduleAccelerationGuideUpdate({required bool eligible}) {
    if (_guideUpdateScheduled) {
      return;
    }
    _guideUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guideUpdateScheduled = false;
      if (!mounted) {
        return;
      }
      final latestEligible =
          ref.read(initProvider) &&
          ref.read(profilesProvider).isNotEmpty &&
          ref.read(currentPageLabelProvider) == PageLabel.dashboard &&
          !ref.read(appSettingProvider).dashboardAccelerationGuideCompleted;
      if (!eligible || !latestEligible) {
        _clearAccelerationGuideTarget();
        return;
      }
      if (ref.read(isStartProvider)) {
        _completeAccelerationGuide();
        return;
      }
      final layerBox =
          Overlay.of(context, rootOverlay: true).context.findRenderObject()
              as RenderBox?;
      final buttonBox =
          _startButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (layerBox == null ||
          buttonBox == null ||
          !layerBox.hasSize ||
          !buttonBox.hasSize) {
        return;
      }
      final targetRect =
          buttonBox.localToGlobal(Offset.zero, ancestor: layerBox) &
          buttonBox.size;
      if (_guideTargetRect == targetRect) {
        if (!_guideOverlayController.isShowing) {
          _guideOverlayController.show();
        }
        return;
      }
      setState(() {
        _guideTargetRect = targetRect;
      });
      if (!_guideOverlayController.isShowing) {
        _guideOverlayController.show();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardStateProvider);
    final guideCompleted = ref.watch(
      appSettingProvider.select(
        (state) => state.dashboardAccelerationGuideCompleted,
      ),
    );
    final isInitialized = ref.watch(initProvider);
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    ref.watch(isStartProvider);
    final isCurrentDashboard = ref.watch(
      currentPageLabelProvider.select((state) => state == PageLabel.dashboard),
    );
    final guideEligible =
        isInitialized && hasProfile && isCurrentDashboard && !guideCompleted;
    final spacing = 14.mAp;
    final children = [
      ...dashboardState.dashboardWidgets
          .where(
            (item) => item.platforms.contains(SupportPlatform.currentPlatform),
          )
          .map((item) => item.widget),
    ];
    return LayoutBuilder(
      builder: (_, _) {
        _scheduleAccelerationGuideUpdate(eligible: guideEligible);
        return OverlayPortal(
          controller: _guideOverlayController,
          overlayLocation: OverlayChildLocation.rootOverlay,
          overlayChildBuilder: (overlayContext) {
            final targetRect = _guideTargetRect;
            if (targetRect == null) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: DashboardAccelerationGuide(
                targetRect: targetRect,
                message:
                    overlayContext.appLocalizations.dashboardAccelerationGuide,
              ),
            );
          },
          child: CommonScaffold(
            title: context.appLocalizations.dashboard,
            actions: [if (coreLib == null) const CoreStatusButton()],
            floatingActionButton: StartButton(
              key: _startButtonKey,
              onToggleRequested: _completeAccelerationGuide,
            ),
            body: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16).copyWith(bottom: 88),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxGridWidth),
                    child: LayoutBuilder(
                      builder: (_, constraints) {
                        final columns = min(
                          max(4 * ((constraints.maxWidth / 280).ceil()), 8),
                          _maxCrossAxisCount,
                        );
                        return Grid(
                          crossAxisCount: columns,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          children: children,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
