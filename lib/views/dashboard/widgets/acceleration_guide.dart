import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';

class DashboardAccelerationGuide extends StatelessWidget {
  const DashboardAccelerationGuide({
    super.key,
    required this.targetRect,
    required this.message,
  });

  final Rect targetRect;
  final String message;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final target = Rect.fromLTRB(
          targetRect.left.clamp(0, size.width).toDouble(),
          targetRect.top.clamp(0, size.height).toDouble(),
          targetRect.right.clamp(0, size.width).toDouble(),
          targetRect.bottom.clamp(0, size.height).toDouble(),
        );
        final tooltipWidth = min(320.0, max(0.0, size.width - 32));
        final maxTooltipLeft = max(16.0, size.width - tooltipWidth - 16);
        final tooltipLeft = (target.center.dx - tooltipWidth / 2)
            .clamp(16.0, maxTooltipLeft)
            .toDouble();
        final tooltipBottom = max(16.0, size.height - target.top + 18);
        return Stack(
          key: const Key('dashboard-acceleration-guide'),
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _AccelerationSpotlightPainter(
                    targetRect: target.inflate(8),
                    overlayColor: Colors.black.withValues(alpha: 0.68),
                    outlineColor: context.colorScheme.primaryContainer,
                  ),
                ),
              ),
            ),
            _Blocker(left: 0, top: 0, right: 0, height: target.top),
            _Blocker(left: 0, top: target.bottom, right: 0, bottom: 0),
            _Blocker(
              left: 0,
              top: target.top,
              width: target.left,
              bottom: size.height - target.bottom,
            ),
            _Blocker(
              left: target.right,
              top: target.top,
              right: 0,
              bottom: size.height - target.bottom,
            ),
            Positioned(
              left: tooltipLeft,
              bottom: tooltipBottom,
              width: tooltipWidth,
              child: IgnorePointer(
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: message,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        elevation: 8,
                        color: context.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Text(
                            message,
                            key: const Key(
                              'dashboard-acceleration-guide-message',
                            ),
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyLarge?.copyWith(
                              color: context.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Transform.rotate(
                        angle: pi / 4,
                        child: ColoredBox(
                          color: context.colorScheme.surfaceContainerHighest,
                          child: const SizedBox.square(dimension: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Blocker extends StatelessWidget {
  const _Blocker({
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
  });

  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: const AbsorbPointer(child: ColoredBox(color: Colors.transparent)),
    );
  }
}

class _AccelerationSpotlightPainter extends CustomPainter {
  const _AccelerationSpotlightPainter({
    required this.targetRect,
    required this.overlayColor,
    required this.outlineColor,
  });

  final Rect targetRect;
  final Color overlayColor;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final target = RRect.fromRectAndRadius(
      targetRect,
      Radius.circular(targetRect.height / 2),
    );
    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(target);
    canvas.drawPath(overlayPath, Paint()..color = overlayColor);
    canvas.drawRRect(
      target,
      Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_AccelerationSpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.outlineColor != outlineColor;
  }
}
