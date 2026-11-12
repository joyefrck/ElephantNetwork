import 'package:flutter/material.dart';

class ElephantBrandMark extends StatelessWidget {
  const ElephantBrandMark({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size ?? IconTheme.of(context).size ?? 24,
      child: Image.asset(
        'assets/images/icon.png',
        excludeFromSemantics: true,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
