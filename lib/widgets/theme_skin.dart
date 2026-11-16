import 'dart:io';
import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/widgets/theme_skin_characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeSkinOverlay extends ConsumerWidget {
  final Widget child;

  const ThemeSkinOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(themeSettingProvider.select((state) => state.skin));
    final imagePath = ref.watch(
      themeSettingProvider.select((state) => state.skinImagePath),
    );
    final opacity = ref.watch(
      themeSettingProvider.select((state) => state.skinOpacity),
    );
    final layer = ThemeSkinLayer(skin: skin, imagePath: imagePath);
    if (!layer.isVisible) {
      return child;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: Opacity(
                  opacity: opacity.clamp(minSkinOpacity, maxSkinOpacity),
                  child: layer,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ThemeSkinLayer extends StatelessWidget {
  final ThemeSkin skin;
  final String? imagePath;

  const ThemeSkinLayer({super.key, required this.skin, this.imagePath});

  bool get isVisible => switch (skin) {
    ThemeSkin.none => false,
    ThemeSkin.custom => imagePath != null && imagePath!.isNotEmpty,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    if (skin == ThemeSkin.custom) {
      final path = imagePath;
      if (path == null || path.isEmpty) {
        return const SizedBox.shrink();
      }
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    if (skin == ThemeSkin.none) {
      return const SizedBox.shrink();
    }
    return CustomPaint(
      painter: ThemeSkinPainter(
        skin: skin,
        brightness: Theme.of(context).brightness,
      ),
      size: Size.infinite,
    );
  }
}

class ThemeSkinPainter extends CustomPainter {
  final ThemeSkin skin;
  final Brightness brightness;

  const ThemeSkinPainter({required this.skin, required this.brightness});

  bool get _isDark => brightness == Brightness.dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (skin) {
      case ThemeSkin.crayon:
        _paintCrayon(canvas, size);
      case ThemeSkin.ocean:
        _paintOcean(canvas, size);
      case ThemeSkin.sakura:
        _paintSakura(canvas, size);
      case ThemeSkin.starry:
        _paintStarry(canvas, size);
      case ThemeSkin.kitty:
        SkinCharacters(canvas, size, _isDark).paintKitty();
      case ThemeSkin.detective:
        SkinCharacters(canvas, size, _isDark).paintDetective();
      case ThemeSkin.captain:
        SkinCharacters(canvas, size, _isDark).paintCaptain();
      case ThemeSkin.lantern:
        SkinCharacters(canvas, size, _isDark).paintLantern();
      case ThemeSkin.none:
      case ThemeSkin.custom:
        break;
    }
    canvas.restore();
  }

  Color _tone(Color color) {
    if (!_isDark) {
      return color;
    }
    return Color.lerp(color, Colors.white, 0.35)!;
  }

  Paint _stroke(Color color, double width) {
    return Paint()
      ..color = _tone(color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }

  Paint _fill(Color color) {
    return Paint()
      ..color = _tone(color)
      ..style = PaintingStyle.fill;
  }

  Path _wobblyPath(List<Offset> points, Random random, double jitter) {
    final path = Path();
    if (points.isEmpty) {
      return path;
    }
    Offset shake(Offset point) => point.translate(
      (random.nextDouble() - 0.5) * jitter,
      (random.nextDouble() - 0.5) * jitter,
    );
    var previous = shake(points.first);
    path.moveTo(previous.dx, previous.dy);
    for (var i = 1; i < points.length; i++) {
      final current = shake(points[i]);
      final mid = Offset.lerp(previous, current, 0.5)!;
      path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
      previous = current;
    }
    path.lineTo(previous.dx, previous.dy);
    return path;
  }

  void _crayonStroke(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    Random random,
  ) {
    canvas.drawPath(
      _wobblyPath(points, random, width * 0.6),
      _stroke(color, width),
    );
    canvas.drawPath(
      _wobblyPath(points, random, width * 0.9),
      _stroke(color.withValues(alpha: 0.45), width * 0.6),
    );
  }

  List<Offset> _circlePoints(Offset center, double radius, int count) {
    return [
      for (var i = 0; i <= count; i++)
        center +
            Offset(
              cos(i / count * pi * 2) * radius,
              sin(i / count * pi * 2) * radius,
            ),
    ];
  }

  Path _starPath(Offset center, double outer, double inner, int points) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -pi / 2 + i * pi / points;
      final point = center + Offset(cos(angle) * radius, sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  void _paintCrayon(Canvas canvas, Size size) {
    final random = Random(7);
    final w = size.width;
    final h = size.height;
    final unit = min(w, h);
    const orange = Color(0xFFF08A24);
    const yellow = Color(0xFFF2C12E);
    const sky = Color(0xFF4FA3D9);
    const grass = Color(0xFF5DAA4B);
    const pink = Color(0xFFE5698F);
    const red = Color(0xFFD9483B);

    final sunCenter = Offset(w * 0.86, h * 0.14);
    final sunRadius = unit * 0.07;
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      _fill(yellow.withValues(alpha: 0.6)),
    );
    _crayonStroke(
      canvas,
      _circlePoints(sunCenter, sunRadius, 18),
      orange,
      unit * 0.008,
      random,
    );
    for (var i = 0; i < 10; i++) {
      final angle = i / 10 * pi * 2;
      final from = sunCenter + Offset(cos(angle), sin(angle)) * sunRadius * 1.3;
      final to = sunCenter + Offset(cos(angle), sin(angle)) * sunRadius * 1.9;
      _crayonStroke(canvas, [from, to], orange, unit * 0.007, random);
    }

    void cloud(Offset origin, double scale) {
      final bumps = <Offset>[];
      for (var i = 0; i <= 24; i++) {
        final t = i / 24 * pi * 2;
        final bump = 1 + 0.18 * sin(t * 5).abs();
        bumps.add(
          origin + Offset(cos(t) * scale * 1.6 * bump, sin(t) * scale * bump),
        );
      }
      canvas.drawPath(
        _wobblyPath(bumps, random, scale * 0.08)..close(),
        _fill(sky.withValues(alpha: 0.18)),
      );
      _crayonStroke(canvas, bumps, sky, unit * 0.006, random);
    }

    cloud(Offset(w * 0.18, h * 0.16), unit * 0.06);
    cloud(Offset(w * 0.55, h * 0.1), unit * 0.045);

    final stars = [
      Offset(w * 0.38, h * 0.3),
      Offset(w * 0.7, h * 0.36),
      Offset(w * 0.08, h * 0.45),
      Offset(w * 0.92, h * 0.55),
      Offset(w * 0.45, h * 0.6),
    ];
    final starColors = [pink, yellow, orange, sky, red];
    for (var i = 0; i < stars.length; i++) {
      final star = _starPath(stars[i], unit * 0.025, unit * 0.011, 5);
      canvas.drawPath(star, _fill(starColors[i].withValues(alpha: 0.35)));
      canvas.drawPath(star, _stroke(starColors[i], unit * 0.004));
    }

    for (var i = 0; i < 4; i++) {
      final center = Offset(
        w * (0.2 + random.nextDouble() * 0.6),
        h * (0.4 + random.nextDouble() * 0.3),
      );
      final spiral = <Offset>[
        for (var t = 0.0; t < pi * 5; t += 0.3)
          center + Offset(cos(t), sin(t)) * (t * unit * 0.004),
      ];
      _crayonStroke(canvas, spiral, starColors[i], unit * 0.004, random);
    }

    final hillPoints = <Offset>[
      for (var x = -0.05; x <= 1.05; x += 0.05)
        Offset(w * x, h * (0.88 - 0.04 * sin(x * pi * 2.4))),
    ];
    final hill = _wobblyPath(hillPoints, random, unit * 0.01)
      ..lineTo(w * 1.05, h * 1.05)
      ..lineTo(-w * 0.05, h * 1.05)
      ..close();
    canvas.drawPath(hill, _fill(grass.withValues(alpha: 0.28)));
    _crayonStroke(canvas, hillPoints, grass, unit * 0.008, random);
    for (var x = 0.03; x < 1; x += 0.035) {
      final base = Offset(w * x, h * (0.9 - 0.04 * sin(x * pi * 2.4)));
      _crayonStroke(
        canvas,
        [base, base.translate(unit * 0.008, -unit * 0.03)],
        grass,
        unit * 0.004,
        random,
      );
    }

    final houseBase = Offset(w * 0.12, h * 0.84);
    final houseSize = unit * 0.11;
    final wall = [
      houseBase,
      houseBase.translate(houseSize, 0),
      houseBase.translate(houseSize, -houseSize * 0.8),
      houseBase.translate(0, -houseSize * 0.8),
      houseBase,
    ];
    canvas.drawPath(
      Path()..addPolygon(wall, true),
      _fill(yellow.withValues(alpha: 0.35)),
    );
    final roof = [
      houseBase.translate(-houseSize * 0.15, -houseSize * 0.8),
      houseBase.translate(houseSize * 0.5, -houseSize * 1.35),
      houseBase.translate(houseSize * 1.15, -houseSize * 0.8),
    ];
    canvas.drawPath(
      Path()..addPolygon(roof, true),
      _fill(red.withValues(alpha: 0.4)),
    );
    final door = [
      houseBase.translate(houseSize * 0.38, 0),
      houseBase.translate(houseSize * 0.38, -houseSize * 0.42),
      houseBase.translate(houseSize * 0.62, -houseSize * 0.42),
      houseBase.translate(houseSize * 0.62, 0),
    ];
    canvas.drawPath(
      Path()..addPolygon(door, true),
      _fill(orange.withValues(alpha: 0.5)),
    );
    for (var i = 0; i < wall.length - 1; i++) {
      _crayonStroke(
        canvas,
        [wall[i], wall[i + 1]],
        orange,
        unit * 0.006,
        random,
      );
    }
    for (var i = 0; i < roof.length; i++) {
      _crayonStroke(
        canvas,
        [roof[i], roof[(i + 1) % roof.length]],
        red,
        unit * 0.006,
        random,
      );
    }

    final flowerCenter = Offset(w * 0.8, h * 0.8);
    for (var i = 0; i < 6; i++) {
      final angle = i / 6 * pi * 2;
      canvas.drawCircle(
        flowerCenter + Offset(cos(angle), sin(angle)) * unit * 0.022,
        unit * 0.016,
        _fill(pink.withValues(alpha: 0.5)),
      );
    }
    canvas.drawCircle(flowerCenter, unit * 0.014, _fill(yellow));
    _crayonStroke(
      canvas,
      [
        flowerCenter.translate(0, unit * 0.03),
        flowerCenter.translate(unit * 0.01, unit * 0.12),
      ],
      grass,
      unit * 0.006,
      random,
    );
  }

  void _paintOcean(Canvas canvas, Size size) {
    final random = Random(11);
    final w = size.width;
    final h = size.height;
    final unit = min(w, h);
    const deep = Color(0xFF1F5F99);
    const sea = Color(0xFF3C93C9);
    const foam = Color(0xFF8FD0EA);
    const sand = Color(0xFFE2B66B);
    const wood = Color(0xFF9A6A3A);
    const sail = Color(0xFFF4EBDD);
    const mark = Color(0xFFD9483B);

    for (var layer = 0; layer < 3; layer++) {
      final baseline = h * (0.78 + layer * 0.07);
      final amplitude = unit * (0.018 - layer * 0.003);
      final frequency = 3.0 + layer;
      final path = Path()..moveTo(0, baseline);
      for (var x = 0.0; x <= w; x += 6) {
        path.lineTo(
          x,
          baseline + sin(x / w * pi * 2 * frequency + layer) * amplitude,
        );
      }
      path
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      final color = [foam, sea, deep][layer];
      canvas.drawPath(
        path,
        _fill(color.withValues(alpha: 0.35 + layer * 0.15)),
      );
    }

    final boatBase = Offset(w * 0.68, h * 0.77);
    final boatWidth = unit * 0.2;
    final hull = Path()
      ..moveTo(boatBase.dx - boatWidth / 2, boatBase.dy - unit * 0.03)
      ..lineTo(boatBase.dx + boatWidth / 2, boatBase.dy - unit * 0.03)
      ..lineTo(boatBase.dx + boatWidth * 0.35, boatBase.dy + unit * 0.01)
      ..lineTo(boatBase.dx - boatWidth * 0.35, boatBase.dy + unit * 0.01)
      ..close();
    canvas.drawPath(hull, _fill(wood));
    final mastTop = boatBase.translate(0, -unit * 0.22);
    canvas.drawLine(
      boatBase.translate(0, -unit * 0.03),
      mastTop,
      _stroke(wood, unit * 0.006),
    );
    final mainSail = Path()
      ..moveTo(mastTop.dx + unit * 0.006, mastTop.dy + unit * 0.01)
      ..quadraticBezierTo(
        mastTop.dx + boatWidth * 0.5,
        mastTop.dy + unit * 0.09,
        mastTop.dx + unit * 0.006,
        boatBase.dy - unit * 0.05,
      )
      ..close();
    canvas.drawPath(mainSail, _fill(sail));
    canvas.drawPath(mainSail, _stroke(wood, unit * 0.003));
    final jib = Path()
      ..moveTo(mastTop.dx - unit * 0.006, mastTop.dy + unit * 0.03)
      ..lineTo(mastTop.dx - boatWidth * 0.38, boatBase.dy - unit * 0.05)
      ..lineTo(mastTop.dx - unit * 0.006, boatBase.dy - unit * 0.05)
      ..close();
    canvas.drawPath(jib, _fill(sail));
    canvas.drawPath(jib, _stroke(wood, unit * 0.003));
    final flag = Path()
      ..moveTo(mastTop.dx, mastTop.dy)
      ..lineTo(mastTop.dx + unit * 0.04, mastTop.dy + unit * 0.012)
      ..lineTo(mastTop.dx, mastTop.dy + unit * 0.024)
      ..close();
    canvas.drawPath(flag, _fill(mark));

    final compassCenter = Offset(w * 0.13, h * 0.17);
    final compassRadius = unit * 0.075;
    canvas.drawCircle(
      compassCenter,
      compassRadius,
      _stroke(deep, unit * 0.004),
    );
    canvas.drawCircle(
      compassCenter,
      compassRadius * 0.82,
      _stroke(deep.withValues(alpha: 0.6), unit * 0.002),
    );
    for (var i = 0; i < 4; i++) {
      final angle = i * pi / 2;
      final needle = Path()
        ..moveTo(
          compassCenter.dx + cos(angle) * compassRadius * 0.95,
          compassCenter.dy + sin(angle) * compassRadius * 0.95,
        )
        ..lineTo(
          compassCenter.dx + cos(angle + pi / 2) * compassRadius * 0.14,
          compassCenter.dy + sin(angle + pi / 2) * compassRadius * 0.14,
        )
        ..lineTo(compassCenter.dx, compassCenter.dy)
        ..close();
      canvas.drawPath(needle, _fill(i == 3 ? mark : deep));
    }
    for (var i = 0; i < 4; i++) {
      final angle = pi / 4 + i * pi / 2;
      canvas.drawLine(
        compassCenter,
        compassCenter + Offset(cos(angle), sin(angle)) * compassRadius * 0.6,
        _stroke(sea, unit * 0.003),
      );
    }

    final islandCenter = Offset(w * 0.25, h * 0.79);
    final island = Path()
      ..moveTo(islandCenter.dx - unit * 0.12, islandCenter.dy)
      ..quadraticBezierTo(
        islandCenter.dx,
        islandCenter.dy - unit * 0.07,
        islandCenter.dx + unit * 0.12,
        islandCenter.dy,
      )
      ..close();
    canvas.drawPath(island, _fill(sand));
    final trunkTop = islandCenter.translate(unit * 0.02, -unit * 0.17);
    final trunk = Path()
      ..moveTo(islandCenter.dx - unit * 0.01, islandCenter.dy - unit * 0.04)
      ..quadraticBezierTo(
        islandCenter.dx - unit * 0.02,
        islandCenter.dy - unit * 0.11,
        trunkTop.dx,
        trunkTop.dy,
      );
    canvas.drawPath(trunk, _stroke(wood, unit * 0.01));
    for (var i = 0; i < 5; i++) {
      final angle = -pi + i * pi / 4 - pi / 8;
      final tip = trunkTop + Offset(cos(angle), sin(angle) + 0.6) * unit * 0.07;
      final leaf = Path()
        ..moveTo(trunkTop.dx, trunkTop.dy)
        ..quadraticBezierTo(
          trunkTop.dx + cos(angle) * unit * 0.05,
          trunkTop.dy + sin(angle) * unit * 0.05 - unit * 0.02,
          tip.dx,
          tip.dy,
        );
      canvas.drawPath(leaf, _stroke(const Color(0xFF3E9A57), unit * 0.008));
    }

    final route = <Offset>[
      Offset(w * 0.32, h * 0.32),
      Offset(w * 0.45, h * 0.24),
      Offset(w * 0.56, h * 0.4),
      Offset(w * 0.72, h * 0.3),
      Offset(w * 0.84, h * 0.42),
    ];
    final routePath = _wobblyPath(route, random, 0);
    for (final metric in routePath.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += unit * 0.03) {
        final segment = metric.extractPath(d, d + unit * 0.015);
        canvas.drawPath(
          segment,
          _stroke(mark.withValues(alpha: 0.7), unit * 0.004),
        );
      }
    }
    final x = route.last;
    final cross = unit * 0.02;
    canvas.drawLine(
      x.translate(-cross, -cross),
      x.translate(cross, cross),
      _stroke(mark, unit * 0.007),
    );
    canvas.drawLine(
      x.translate(cross, -cross),
      x.translate(-cross, cross),
      _stroke(mark, unit * 0.007),
    );

    for (var i = 0; i < 5; i++) {
      final gull = Offset(
        w * (0.4 + random.nextDouble() * 0.5),
        h * (0.08 + random.nextDouble() * 0.15),
      );
      final span = unit * (0.015 + random.nextDouble() * 0.012);
      final path = Path()
        ..moveTo(gull.dx - span, gull.dy - span * 0.3)
        ..quadraticBezierTo(
          gull.dx - span * 0.5,
          gull.dy - span * 0.7,
          gull.dx,
          gull.dy,
        )
        ..quadraticBezierTo(
          gull.dx + span * 0.5,
          gull.dy - span * 0.7,
          gull.dx + span,
          gull.dy - span * 0.3,
        );
      canvas.drawPath(path, _stroke(deep, unit * 0.004));
    }

    for (var i = 0; i < 12; i++) {
      final bubble = Offset(
        w * random.nextDouble(),
        h * (0.86 + random.nextDouble() * 0.12),
      );
      canvas.drawCircle(
        bubble,
        unit * (0.004 + random.nextDouble() * 0.006),
        _stroke(foam, unit * 0.002),
      );
    }
  }

  void _paintBlossom(Canvas canvas, Offset center, double radius, double turn) {
    const petal = Color(0xFFF2A7BE);
    const petalEdge = Color(0xFFE07A9A);
    const heart = Color(0xFFF7D774);
    for (var i = 0; i < 5; i++) {
      final angle = turn + i * pi * 2 / 5;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final shape = Path()
        ..moveTo(0, 0)
        ..cubicTo(
          radius * 0.5,
          -radius * 0.35,
          radius * 1.05,
          -radius * 0.3,
          radius,
          0,
        )
        ..lineTo(radius * 0.85, radius * 0.06)
        ..lineTo(radius, radius * 0.12)
        ..cubicTo(
          radius * 1.05,
          radius * 0.3,
          radius * 0.5,
          radius * 0.35,
          0,
          0,
        )
        ..close();
      canvas.drawPath(shape, _fill(petal));
      canvas.drawPath(
        shape,
        _stroke(petalEdge.withValues(alpha: 0.6), radius * 0.05),
      );
      canvas.restore();
    }
    canvas.drawCircle(center, radius * 0.18, _fill(heart));
  }

  void _paintSakura(Canvas canvas, Size size) {
    final random = Random(23);
    final w = size.width;
    final h = size.height;
    final unit = min(w, h);
    const bark = Color(0xFF6B4A3E);
    const petal = Color(0xFFF2A7BE);

    final branches = <List<Offset>>[
      [
        Offset(w * 1.02, h * 0.02),
        Offset(w * 0.86, h * 0.1),
        Offset(w * 0.72, h * 0.14),
        Offset(w * 0.58, h * 0.13),
      ],
      [
        Offset(w * 0.86, h * 0.1),
        Offset(w * 0.82, h * 0.22),
        Offset(w * 0.74, h * 0.3),
      ],
      [
        Offset(w * 0.72, h * 0.14),
        Offset(w * 0.66, h * 0.06),
        Offset(w * 0.6, h * 0.02),
      ],
      [
        Offset(-w * 0.02, h * 0.9),
        Offset(w * 0.1, h * 0.84),
        Offset(w * 0.2, h * 0.86),
      ],
    ];
    for (var i = 0; i < branches.length; i++) {
      final points = branches[i];
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var j = 1; j < points.length; j++) {
        final prev = points[j - 1];
        final current = points[j];
        final control = Offset(
          (prev.dx + current.dx) / 2,
          min(prev.dy, current.dy) - unit * 0.01,
        );
        path.quadraticBezierTo(control.dx, control.dy, current.dx, current.dy);
      }
      canvas.drawPath(path, _stroke(bark, unit * (i == 0 ? 0.014 : 0.008)));
    }

    final blossoms = [
      Offset(w * 0.6, h * 0.12),
      Offset(w * 0.66, h * 0.16),
      Offset(w * 0.77, h * 0.11),
      Offset(w * 0.73, h * 0.29),
      Offset(w * 0.8, h * 0.2),
      Offset(w * 0.63, h * 0.04),
      Offset(w * 0.9, h * 0.06),
      Offset(w * 0.12, h * 0.83),
      Offset(w * 0.19, h * 0.86),
    ];
    for (final blossom in blossoms) {
      _paintBlossom(
        canvas,
        blossom,
        unit * (0.022 + random.nextDouble() * 0.012),
        random.nextDouble() * pi,
      );
    }

    for (var i = 0; i < 26; i++) {
      final center = Offset(
        w * random.nextDouble(),
        h * (0.2 + random.nextDouble() * 0.75),
      );
      final length = unit * (0.008 + random.nextDouble() * 0.01);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(random.nextDouble() * pi * 2);
      final shape = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(length, -length * 0.7, length * 2, 0)
        ..quadraticBezierTo(length, length * 0.7, 0, 0)
        ..close();
      canvas.drawPath(
        shape,
        _fill(petal.withValues(alpha: 0.5 + random.nextDouble() * 0.4)),
      );
      canvas.restore();
    }

    for (var i = 0; i < 3; i++) {
      final path = Path();
      final y = h * (0.45 + i * 0.13);
      path.moveTo(w * (0.05 + i * 0.25), y);
      path.cubicTo(
        w * (0.2 + i * 0.25),
        y - unit * 0.06,
        w * (0.3 + i * 0.25),
        y + unit * 0.06,
        w * (0.45 + i * 0.25),
        y,
      );
      canvas.drawPath(
        path,
        _stroke(petal.withValues(alpha: 0.35), unit * 0.003),
      );
    }
  }

  void _paintStarry(Canvas canvas, Size size) {
    final random = Random(31);
    final w = size.width;
    final h = size.height;
    final unit = min(w, h);
    const night = Color(0xFF3A3A9E);
    const star = Color(0xFFF2C94C);
    const planet = Color(0xFFB57BE0);
    const ring = Color(0xFF6FC3DF);
    const moon = Color(0xFFF7DE8A);

    final moonCenter = Offset(w * 0.84, h * 0.17);
    final moonRadius = unit * 0.08;
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: moonCenter, radius: moonRadius)),
      Path()..addOval(
        Rect.fromCircle(
          center: moonCenter.translate(moonRadius * 0.45, -moonRadius * 0.3),
          radius: moonRadius * 0.85,
        ),
      ),
    );
    canvas.drawPath(crescent, _fill(moon));
    canvas.drawCircle(
      moonCenter,
      moonRadius * 1.3,
      _fill(moon.withValues(alpha: 0.05)),
    );

    final planetCenter = Offset(w * 0.16, h * 0.72);
    final planetRadius = unit * 0.06;
    final ringRect = Rect.fromCenter(
      center: planetCenter,
      width: planetRadius * 3.6,
      height: planetRadius * 0.9,
    );
    canvas.save();
    canvas.translate(planetCenter.dx, planetCenter.dy);
    canvas.rotate(-0.35);
    canvas.translate(-planetCenter.dx, -planetCenter.dy);
    canvas.drawArc(ringRect, pi, pi, false, _stroke(ring, unit * 0.008));
    canvas.drawCircle(planetCenter, planetRadius, _fill(planet));
    canvas.drawCircle(
      planetCenter.translate(-planetRadius * 0.3, -planetRadius * 0.25),
      planetRadius * 0.25,
      _fill(Colors.white.withValues(alpha: 0.25)),
    );
    canvas.drawArc(ringRect, 0, pi, false, _stroke(ring, unit * 0.008));
    canvas.restore();

    for (var i = 0; i < 60; i++) {
      final center = Offset(w * random.nextDouble(), h * random.nextDouble());
      final radius = unit * (0.002 + random.nextDouble() * 0.004);
      canvas.drawCircle(
        center,
        radius,
        _fill(
          (i.isEven ? star : night).withValues(
            alpha: 0.4 + random.nextDouble() * 0.5,
          ),
        ),
      );
    }

    void sparkle(Offset center, double radius, Color color) {
      canvas.drawPath(
        _starPath(center, radius, radius * 0.28, 4),
        _fill(color),
      );
    }

    for (var i = 0; i < 9; i++) {
      sparkle(
        Offset(w * random.nextDouble(), h * (0.05 + random.nextDouble() * 0.6)),
        unit * (0.012 + random.nextDouble() * 0.014),
        i % 3 == 0 ? ring : star,
      );
    }

    final constellation = [
      Offset(w * 0.34, h * 0.14),
      Offset(w * 0.42, h * 0.22),
      Offset(w * 0.5, h * 0.18),
      Offset(w * 0.58, h * 0.27),
      Offset(w * 0.55, h * 0.37),
      Offset(w * 0.64, h * 0.4),
    ];
    for (var i = 1; i < constellation.length; i++) {
      canvas.drawLine(
        constellation[i - 1],
        constellation[i],
        _stroke(night.withValues(alpha: 0.5), unit * 0.002),
      );
    }
    for (final point in constellation) {
      sparkle(point, unit * 0.012, star);
    }

    final meteorHead = Offset(w * 0.72, h * 0.6);
    final meteorTail = meteorHead.translate(-unit * 0.22, -unit * 0.1);
    canvas.drawLine(
      meteorTail,
      meteorHead,
      Paint()
        ..shader = LinearGradient(
          colors: [_tone(star).withValues(alpha: 0), _tone(star)],
        ).createShader(Rect.fromPoints(meteorTail, meteorHead))
        ..strokeWidth = unit * 0.006
        ..strokeCap = StrokeCap.round,
    );
    sparkle(meteorHead, unit * 0.016, star);

    final hills = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w; x += 8) {
      hills.lineTo(x, h * (0.93 - 0.03 * sin(x / w * pi * 3)));
    }
    hills
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(hills, _fill(night.withValues(alpha: 0.4)));
  }

  @override
  bool shouldRepaint(covariant ThemeSkinPainter oldDelegate) {
    return oldDelegate.skin != skin || oldDelegate.brightness != brightness;
  }
}
