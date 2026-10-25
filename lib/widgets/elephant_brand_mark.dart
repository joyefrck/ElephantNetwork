import 'package:flutter/material.dart';

class ElephantBrandMark extends StatelessWidget {
  const ElephantBrandMark({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size ?? IconTheme.of(context).size ?? 24,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 425,
          height: 362,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 1024,
              maxWidth: 1024,
              minHeight: 1024,
              maxHeight: 1024,
              child: Transform.translate(
                offset: const Offset(-306, -331),
                child: Image.asset(
                  'assets/images/icon.png',
                  width: 1024,
                  height: 1024,
                  excludeFromSemantics: true,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
