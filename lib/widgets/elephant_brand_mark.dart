import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ElephantBrandMark extends StatelessWidget {
  const ElephantBrandMark({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size ?? IconTheme.of(context).size ?? 24,
      child: SvgPicture.asset(
        'assets/images/brand_mark.svg',
        excludeFromSemantics: true,
      ),
    );
  }
}
