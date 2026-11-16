import 'dart:math';

import 'package:flutter/material.dart';

const _ink = Color(0xFF3B2C2A);
const _skin = Color(0xFFFFE8D8);
const _blushColor = Color(0xFFFF8FA3);
const _gold = Color(0xFFF2C14E);

class SkinCharacters {
  final Canvas c;
  final Size size;
  final bool isDark;

  SkinCharacters(this.c, this.size, this.isDark);

  double get w => size.width;

  double get h => size.height;

  double get unit => min(w, h);

  Color tone(Color color) {
    if (!isDark) {
      return color;
    }
    return Color.lerp(color, Colors.white, 0.3)!.withValues(alpha: color.a);
  }

  Paint fill(Color color) => Paint()..color = tone(color);

  Paint line(Color color, double width) => Paint()
    ..color = tone(color)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Path oval(Offset o, double rx, double ry) =>
      Path()
        ..addOval(Rect.fromCenter(center: o, width: rx * 2, height: ry * 2));

  void shape(Path p, Color color, [double w = 0.012]) {
    c.drawPath(p, fill(color));
    c.drawPath(p, line(_ink, w));
  }

  void limb(List<Offset> points, Color color, double width) {
    final p = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      p.lineTo(point.dx, point.dy);
    }
    c.drawPath(p, line(_ink, width + 0.024));
    c.drawPath(p, line(color, width));
  }

  Path face(Offset o, double rx, double ry) => Path()
    ..moveTo(o.dx - rx, o.dy)
    ..cubicTo(
      o.dx - rx,
      o.dy - ry * 1.36,
      o.dx + rx,
      o.dy - ry * 1.36,
      o.dx + rx,
      o.dy,
    )
    ..cubicTo(
      o.dx + rx,
      o.dy + ry * 0.62,
      o.dx + rx * 0.38,
      o.dy + ry,
      o.dx,
      o.dy + ry,
    )
    ..cubicTo(
      o.dx - rx * 0.38,
      o.dy + ry,
      o.dx - rx,
      o.dy + ry * 0.62,
      o.dx - rx,
      o.dy,
    )
    ..close();

  void eye(
    Offset o,
    double ew,
    double eh,
    Color iris,
    double side, {
    bool star = false,
  }) {
    final sclera = oval(o, ew / 2, eh / 2);
    c.drawPath(sclera, fill(Colors.white));
    c.save();
    c.clipPath(sclera);
    final irisRect = Rect.fromCenter(
      center: o.translate(-side * ew * 0.03, eh * 0.07),
      width: ew * 0.88,
      height: eh * 0.94,
    );
    c.drawOval(
      irisRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tone(Color.lerp(iris, Colors.black, 0.6)!),
            tone(iris),
            tone(Color.lerp(iris, Colors.white, 0.5)!),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(irisRect),
    );
    c.drawOval(
      Rect.fromCenter(
        center: irisRect.center.translate(0, eh * 0.02),
        width: ew * 0.38,
        height: eh * 0.44,
      ),
      fill(Color.lerp(iris, Colors.black, 0.72)!),
    );
    c.drawArc(
      Rect.fromCenter(
        center: irisRect.center.translate(0, eh * 0.1),
        width: ew * 0.6,
        height: eh * 0.56,
      ),
      0.35,
      pi - 0.7,
      false,
      line(Color.lerp(iris, Colors.white, 0.75)!, ew * 0.06),
    );
    c.drawOval(
      irisRect,
      line(Color.lerp(iris, Colors.black, 0.65)!, ew * 0.035),
    );
    c.restore();
    c.drawOval(
      Rect.fromCenter(
        center: o.translate(-ew * 0.15, -eh * 0.14),
        width: ew * 0.36,
        height: eh * 0.3,
      ),
      fill(Colors.white),
    );
    c.drawCircle(
      o.translate(ew * 0.17, eh * 0.2),
      ew * 0.075,
      fill(Colors.white),
    );
    if (star) {
      sparkle(o.translate(ew * 0.12, -eh * 0.02), ew * 0.16, Colors.white);
    }
    final lash = Path()
      ..moveTo(o.dx - side * ew * 0.48, o.dy - eh * 0.2)
      ..quadraticBezierTo(
        o.dx - side * ew * 0.1,
        o.dy - eh * 0.74,
        o.dx + side * ew * 0.46,
        o.dy - eh * 0.36,
      )
      ..quadraticBezierTo(
        o.dx + side * ew * 0.58,
        o.dy - eh * 0.3,
        o.dx + side * ew * 0.7,
        o.dy - eh * 0.48,
      );
    c.drawPath(lash, line(_ink, eh * 0.12));
    c.drawLine(
      o.translate(side * ew * 0.4, eh * 0.4),
      o.translate(side * ew * 0.12, eh * 0.5),
      line(_ink, eh * 0.04),
    );
  }

  void happyEye(Offset o, double ew, double eh) {
    final p = Path()
      ..moveTo(o.dx - ew * 0.46, o.dy + eh * 0.12)
      ..quadraticBezierTo(
        o.dx,
        o.dy - eh * 0.42,
        o.dx + ew * 0.46,
        o.dy + eh * 0.12,
      );
    c.drawPath(p, line(_ink, eh * 0.13));
  }

  void blush(Offset o, double rx) {
    c.drawPath(
      oval(o, rx, rx * 0.55),
      fill(_blushColor.withValues(alpha: 0.55)),
    );
    for (var i = -1; i <= 1; i++) {
      final x = o.dx + i * rx * 0.42;
      c.drawLine(
        Offset(x + rx * 0.12, o.dy - rx * 0.25),
        Offset(x - rx * 0.12, o.dy + rx * 0.25),
        line(const Color(0xFFE5677F), rx * 0.12),
      );
    }
  }

  void sparkle(Offset o, double r, Color color) {
    final p = Path();
    for (var i = 0; i < 8; i++) {
      final rr = i.isEven ? r : r * 0.28;
      final a = -pi / 2 + i * pi / 4;
      final pt = o + Offset(cos(a), sin(a)) * rr;
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    c.drawPath(p..close(), fill(color));
  }

  void note(Offset o, double s, Color color) {
    c.drawPath(oval(o, s * 0.32, s * 0.24), fill(color));
    c.drawLine(
      o.translate(s * 0.28, 0),
      o.translate(s * 0.28, -s),
      line(color, s * 0.12),
    );
    final flag = Path()
      ..moveTo(o.dx + s * 0.28, o.dy - s)
      ..quadraticBezierTo(
        o.dx + s * 0.7,
        o.dy - s * 0.8,
        o.dx + s * 0.6,
        o.dy - s * 0.45,
      );
    c.drawPath(flag, line(color, s * 0.12));
  }

  void heart(Offset o, double s, Color color) {
    final p = Path()
      ..moveTo(o.dx, o.dy + s * 0.4)
      ..cubicTo(
        o.dx - s * 1.1,
        o.dy - s * 0.3,
        o.dx - s * 0.45,
        o.dy - s * 1.05,
        o.dx,
        o.dy - s * 0.4,
      )
      ..cubicTo(
        o.dx + s * 0.45,
        o.dy - s * 1.05,
        o.dx + s * 1.1,
        o.dy - s * 0.3,
        o.dx,
        o.dy + s * 0.4,
      )
      ..close();
    c.drawPath(p, fill(color));
  }

  void motion(
    Offset o,
    double angle,
    double len,
    int count,
    double gap,
    Color color,
    double w,
  ) {
    final dir = Offset(cos(angle), sin(angle));
    final normal = Offset(-dir.dy, dir.dx);
    for (var i = 0; i < count; i++) {
      final start = o + normal * (gap * (i - (count - 1) / 2));
      final l = len * (i.isEven ? 1 : 0.7);
      c.drawLine(start, start + dir * l, line(color, w));
    }
  }

  void hairShine(Path hair, Offset o, double rx, double ry) {
    c.save();
    c.clipPath(hair);
    c.drawArc(
      Rect.fromCenter(center: o, width: rx * 2, height: ry * 2),
      pi * 1.15,
      pi * 0.7,
      false,
      line(Colors.white.withValues(alpha: 0.45), ry * 0.12),
    );
    c.restore();
  }

  Path spikes(
    Offset o,
    double rx,
    double ry,
    double from,
    double to,
    int n,
    double depth,
  ) {
    final p = Path();
    for (var i = 0; i <= n * 2; i++) {
      final t = from + (to - from) * i / (n * 2);
      final k = i.isEven ? 1.0 : 1.0 - depth;
      final pt = o + Offset(cos(t) * rx * k, sin(t) * ry * k);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  // ---------------- Cat ----------------
  void _cat() {
    const fur = Color(0xFFFFB866);
    const furDark = Color(0xFFE8863A);
    const cream = Color(0xFFFFF4E4);
    const pink = Color(0xFFFF9EB0);

    c.drawPath(
      oval(const Offset(0, 0), 0.24, 0.03),
      fill(Colors.black.withValues(alpha: 0.08)),
    );
    final tail = Path()
      ..moveTo(-0.14, -0.1)
      ..cubicTo(-0.42, -0.08, -0.48, -0.36, -0.36, -0.52);
    c.drawPath(tail, line(_ink, 0.11));
    c.drawPath(tail, line(fur, 0.085));
    shape(oval(const Offset(-0.36, -0.53), 0.045, 0.045), cream);
    for (final a in [0.0, 0.5]) {
      c.drawArc(
        Rect.fromCircle(
          center: const Offset(-0.36, -0.5),
          radius: 0.11 + a * 0.08,
        ),
        pi * 1.05,
        pi * 0.35,
        false,
        line(furDark.withValues(alpha: 0.6), 0.012),
      );
    }

    shape(oval(const Offset(0, -0.17), 0.21, 0.17), fur);
    c.drawPath(oval(const Offset(0, -0.13), 0.12, 0.11), fill(cream));
    for (final s in [-1.0, 1.0]) {
      if (s > 0) {
        continue;
      }
      shape(oval(Offset(0.09 * s, -0.025), 0.07, 0.045), fur);
    }
    shape(oval(const Offset(0.07, -0.025), 0.07, 0.045), fur);

    limb([const Offset(0.13, -0.24), const Offset(0.27, -0.4)], fur, 0.075);
    shape(oval(const Offset(0.29, -0.44), 0.08, 0.075), fur);
    c.drawPath(oval(const Offset(0.29, -0.425), 0.034, 0.026), fill(pink));
    for (final p in [
      const Offset(0.245, -0.465),
      const Offset(0.29, -0.485),
      const Offset(0.335, -0.465),
    ]) {
      c.drawCircle(p, 0.015, fill(pink));
    }
    motion(
      const Offset(0.42, -0.46),
      -0.2,
      0.08,
      3,
      0.035,
      furDark.withValues(alpha: 0.7),
      0.012,
    );

    shape(
      Path()..addRRect(
        RRect.fromLTRBR(
          -0.15,
          -0.355,
          0.15,
          -0.31,
          const Radius.circular(0.02),
        ),
      ),
      const Color(0xFFE5484D),
    );
    shape(oval(const Offset(0, -0.29), 0.038, 0.038), _gold);
    c.drawLine(
      const Offset(0, -0.285),
      const Offset(0, -0.26),
      line(_ink, 0.01),
    );

    for (final s in [-1.0, 1.0]) {
      final ear = Path()
        ..moveTo(0.33 * s, -0.68)
        ..quadraticBezierTo(0.38 * s, -0.98, 0.26 * s, -1.01)
        ..quadraticBezierTo(0.18 * s, -0.97, 0.07 * s, -0.86)
        ..close();
      shape(ear, fur);
      final inner = Path()
        ..moveTo(0.28 * s, -0.74)
        ..quadraticBezierTo(0.31 * s, -0.93, 0.25 * s, -0.94)
        ..quadraticBezierTo(0.19 * s, -0.91, 0.13 * s, -0.85)
        ..close();
      c.drawPath(inner, fill(pink));
      c.drawLine(
        Offset(0.2 * s, -0.84),
        Offset(0.24 * s, -0.9),
        line(cream, 0.012),
      );
    }
    var head = oval(const Offset(0, -0.62), 0.37, 0.3);
    for (final s in [-1.0, 1.0]) {
      final tuft = Path()
        ..moveTo(0.33 * s, -0.62)
        ..lineTo(0.45 * s, -0.57)
        ..lineTo(0.35 * s, -0.53)
        ..lineTo(0.43 * s, -0.47)
        ..lineTo(0.3 * s, -0.46)
        ..close();
      head = Path.combine(PathOperation.union, head, tuft);
    }
    shape(head, fur);
    c.drawPath(oval(const Offset(0, -0.49), 0.15, 0.085), fill(cream));
    for (final x in [-0.07, 0.0, 0.07]) {
      final stripe = Path()
        ..moveTo(x - 0.02, -0.91)
        ..lineTo(x + 0.02, -0.91)
        ..lineTo(x, -0.82)
        ..close();
      c.drawPath(stripe, fill(furDark));
    }
    final ahoge = Path()
      ..moveTo(0.02, -0.91)
      ..quadraticBezierTo(0.06, -1.02, 0.12, -0.99)
      ..quadraticBezierTo(0.08, -0.97, 0.07, -0.93);
    c.drawPath(ahoge, line(_ink, 0.03));
    c.drawPath(ahoge, line(fur, 0.016));

    eye(
      const Offset(-0.15, -0.62),
      0.15,
      0.185,
      const Color(0xFF26A58C),
      -1,
      star: true,
    );
    eye(
      const Offset(0.15, -0.62),
      0.15,
      0.185,
      const Color(0xFF26A58C),
      1,
      star: true,
    );
    blush(const Offset(-0.25, -0.52), 0.05);
    blush(const Offset(0.25, -0.52), 0.05);
    final nose = Path()
      ..moveTo(-0.022, -0.535)
      ..quadraticBezierTo(0, -0.545, 0.022, -0.535)
      ..lineTo(0, -0.515)
      ..close();
    c.drawPath(nose, fill(pink));
    final mouthOpen = Path()
      ..moveTo(-0.035, -0.497)
      ..quadraticBezierTo(0, -0.43, 0.035, -0.497)
      ..close();
    shape(mouthOpen, const Color(0xFFB8434F), 0.01);
    c.drawPath(oval(const Offset(0, -0.468), 0.018, 0.012), fill(pink));
    final omega = Path()
      ..moveTo(-0.075, -0.5)
      ..quadraticBezierTo(-0.04, -0.47, 0, -0.513)
      ..quadraticBezierTo(0.04, -0.47, 0.075, -0.5);
    c.drawPath(omega, line(_ink, 0.012));
    final fang = Path()
      ..moveTo(-0.028, -0.5)
      ..lineTo(-0.01, -0.5)
      ..lineTo(-0.019, -0.478)
      ..close();
    c.drawPath(fang, fill(Colors.white));
    for (final s in [-1.0, 1.0]) {
      c.drawLine(
        Offset(0.31 * s, -0.56),
        Offset(0.45 * s, -0.59),
        line(_ink, 0.009),
      );
      c.drawLine(
        Offset(0.31 * s, -0.52),
        Offset(0.45 * s, -0.5),
        line(_ink, 0.009),
      );
    }
  }

  // ---------------- Detective ----------------
  void _detective() {
    const coat = Color(0xFFC99C5E);
    const coatDark = Color(0xFFA97C43);
    const hair = Color(0xFF2E3550);
    const cap = Color(0xFF9B7A52);
    const capDark = Color(0xFF6E5233);
    const scarf = Color(0xFF2F9C95);
    const pants = Color(0xFF4A4038);
    const iris = Color(0xFFC07F35);

    c.drawPath(
      oval(const Offset(0, 0), 0.2, 0.028),
      fill(Colors.black.withValues(alpha: 0.08)),
    );
    for (final s in [-1.0, 1.0]) {
      shape(
        Path()..addRRect(
          RRect.fromLTRBR(
            s < 0 ? -0.095 : 0.025,
            -0.15,
            s < 0 ? -0.025 : 0.095,
            -0.03,
            const Radius.circular(0.02),
          ),
        ),
        pants,
      );
      shape(
        oval(Offset(0.065 * s, -0.025), 0.07, 0.033),
        const Color(0xFF5B4030),
      );
    }
    final scarfTail = Path()
      ..moveTo(-0.06, -0.36)
      ..quadraticBezierTo(-0.2, -0.38, -0.33, -0.31)
      ..lineTo(-0.3, -0.27)
      ..quadraticBezierTo(-0.18, -0.32, -0.05, -0.32)
      ..close();
    shape(scarfTail, scarf);
    motion(
      const Offset(-0.38, -0.3),
      pi + 0.2,
      0.07,
      3,
      0.03,
      scarf.withValues(alpha: 0.6),
      0.01,
    );
    final body = Path()
      ..moveTo(-0.13, -0.35)
      ..lineTo(0.13, -0.35)
      ..lineTo(0.17, -0.12)
      ..quadraticBezierTo(0, -0.09, -0.17, -0.12)
      ..close();
    shape(body, coat);
    c.drawLine(
      const Offset(0, -0.34),
      const Offset(0, -0.11),
      line(_ink.withValues(alpha: 0.5), 0.008),
    );
    for (final y in [-0.27, -0.2]) {
      c.drawCircle(Offset(0.03, y), 0.011, fill(_ink));
    }
    limb(
      [
        const Offset(-0.12, -0.31),
        const Offset(-0.23, -0.22),
        const Offset(-0.15, -0.16),
      ],
      coat,
      0.06,
    );
    final capeShape = Path()
      ..moveTo(-0.15, -0.36)
      ..quadraticBezierTo(0, -0.4, 0.15, -0.36)
      ..lineTo(0.23, -0.22)
      ..quadraticBezierTo(0, -0.18, -0.23, -0.22)
      ..close();
    shape(capeShape, coatDark);
    shape(
      Path()..addRRect(
        RRect.fromLTRBR(
          -0.13,
          -0.4,
          0.13,
          -0.345,
          const Radius.circular(0.025),
        ),
      ),
      scarf,
    );
    limb([const Offset(0.12, -0.31), const Offset(0.29, -0.36)], coat, 0.06);

    final backHair = Path.combine(
      PathOperation.union,
      oval(const Offset(0, -0.64), 0.36, 0.31),
      spikes(const Offset(0, -0.58), 0.38, 0.3, pi * 0.18, pi * 0.82, 4, 0.25),
    );
    shape(backHair, hair);
    for (final s in [-1.0, 1.0]) {
      shape(oval(Offset(0.31 * s, -0.57), 0.045, 0.05), _skin);
    }
    shape(face(const Offset(0, -0.62), 0.31, 0.27), _skin);
    final bangs = Path()
      ..moveTo(-0.34, -0.76)
      ..lineTo(-0.31, -0.56)
      ..lineTo(-0.25, -0.68)
      ..lineTo(-0.19, -0.58)
      ..lineTo(-0.12, -0.7)
      ..lineTo(-0.05, -0.61)
      ..lineTo(0.0, -0.72)
      ..lineTo(0.07, -0.62)
      ..lineTo(0.13, -0.71)
      ..lineTo(0.2, -0.59)
      ..lineTo(0.25, -0.69)
      ..lineTo(0.31, -0.56)
      ..lineTo(0.34, -0.76)
      ..close();
    shape(bangs, hair);
    hairShine(bangs, const Offset(0, -0.62), 0.3, 0.14);

    c.save();
    c.translate(0, -0.82);
    c.rotate(-0.13);
    c.translate(0, 0.82);
    final dome = Path()
      ..moveTo(-0.36, -0.75)
      ..cubicTo(-0.37, -1.1, 0.37, -1.1, 0.36, -0.75)
      ..quadraticBezierTo(0, -0.7, -0.36, -0.75)
      ..close();
    for (final s in [-1.0, 1.0]) {
      final brim = Path()
        ..moveTo(0.28 * s, -0.77)
        ..quadraticBezierTo(0.5 * s, -0.81, 0.49 * s, -0.72)
        ..quadraticBezierTo(0.39 * s, -0.69, 0.28 * s, -0.73)
        ..close();
      shape(brim, capDark);
    }
    c.drawPath(dome, fill(cap));
    c.save();
    c.clipPath(dome);
    for (var x = -0.36; x <= 0.36; x += 0.075) {
      c.drawLine(
        Offset(x, -1.1),
        Offset(x, -0.7),
        line(capDark.withValues(alpha: 0.55), 0.012),
      );
    }
    for (var y = -1.04; y <= -0.72; y += 0.075) {
      c.drawLine(
        Offset(-0.4, y),
        Offset(0.4, y),
        line(capDark.withValues(alpha: 0.55), 0.012),
      );
    }
    c.drawArc(
      Rect.fromCenter(
        center: const Offset(-0.05, -0.86),
        width: 0.5,
        height: 0.3,
      ),
      pi * 1.1,
      pi * 0.5,
      false,
      line(Colors.white.withValues(alpha: 0.35), 0.03),
    );
    c.restore();
    c.drawPath(dome, line(_ink, 0.012));
    for (final s in [-1.0, 1.0]) {
      shape(oval(Offset(0.045 * s, -1.0), 0.045, 0.025), capDark, 0.01);
    }
    c.drawCircle(const Offset(0, -1.0), 0.018, fill(_ink));
    c.restore();

    eye(const Offset(-0.13, -0.59), 0.13, 0.16, iris, -1);
    final browL = Path()
      ..moveTo(-0.2, -0.69)
      ..quadraticBezierTo(-0.14, -0.73, -0.07, -0.7);
    c.drawPath(browL, line(hair, 0.014));
    blush(const Offset(-0.2, -0.49), 0.045);
    final smirk = Path()
      ..moveTo(-0.05, -0.47)
      ..quadraticBezierTo(0.01, -0.43, 0.07, -0.49);
    c.drawPath(smirk, line(_ink, 0.014));
    c.drawLine(
      const Offset(0.07, -0.49),
      const Offset(0.085, -0.5),
      line(_ink, 0.012),
    );

    const lens = Offset(0.16, -0.59);
    const r = 0.155;
    limb(
      [const Offset(0.26, -0.48), const Offset(0.31, -0.39)],
      const Color(0xFF7A4B2A),
      0.035,
    );
    shape(oval(const Offset(0.31, -0.375), 0.042, 0.042), _skin);
    final lensPath = oval(lens, r, r);
    c.drawPath(lensPath, fill(const Color(0xFFDDF2FF)));
    c.save();
    c.clipPath(lensPath);
    shape(face(const Offset(0, -0.62), 0.31, 0.27), _skin);
    eye(lens.translate(0.0, 0.01), 0.2, 0.245, iris, 1, star: true);
    final browR = Path()
      ..moveTo(0.06, -0.73)
      ..quadraticBezierTo(0.15, -0.79, 0.25, -0.74);
    c.drawPath(browR, line(hair, 0.02));
    c.drawPath(lensPath, fill(const Color(0xFFBFE6FF).withValues(alpha: 0.25)));
    c.drawArc(
      Rect.fromCircle(center: lens, radius: r * 0.72),
      pi * 1.1,
      pi * 0.35,
      false,
      line(Colors.white.withValues(alpha: 0.8), 0.02),
    );
    c.restore();
    c.drawPath(lensPath, line(_ink, 0.05));
    c.drawPath(lensPath, line(_gold, 0.032));

    final burst = spikes(
      const Offset(0.42, -0.95),
      0.1,
      0.1,
      0,
      pi * 2,
      8,
      0.35,
    );
    shape(burst, const Color(0xFFFFE07A), 0.01);
    c.drawPath(
      Path()..addRRect(
        RRect.fromLTRBR(
          0.408,
          -1.0,
          0.432,
          -0.935,
          const Radius.circular(0.012),
        ),
      ),
      fill(_ink),
    );
    c.drawCircle(const Offset(0.42, -0.912), 0.013, fill(_ink));
    motion(
      const Offset(0.5, -0.8),
      -0.5,
      0.06,
      3,
      0.03,
      _ink.withValues(alpha: 0.5),
      0.01,
    );
  }

  // ---------------- Captain ----------------
  void _captain() {
    const navy = Color(0xFF26355A);
    const stripe = Color(0xFF3C7DD9);
    const hair = Color(0xFFE07B39);
    const shorts = Color(0xFF2E4A7A);
    const kerchief = Color(0xFFF2C14E);
    const iris = Color(0xFF2E8FE0);
    const wood = Color(0xFF8A5A33);
    const boot = Color(0xFF6B4226);

    c.drawPath(
      oval(const Offset(0, 0), 0.15, 0.022),
      fill(Colors.black.withValues(alpha: 0.08)),
    );
    for (var i = -1; i <= 1; i++) {
      c.drawLine(
        Offset(i * 0.06, 0.03),
        Offset(i * 0.06, 0.08),
        line(_ink.withValues(alpha: 0.35), 0.01),
      );
    }
    c.save();
    c.translate(0, -0.08);
    c.rotate(-0.07);
    limb(
      [const Offset(-0.05, -0.14), const Offset(-0.07, -0.03)],
      _skin,
      0.055,
    );
    shape(oval(const Offset(-0.075, -0.015), 0.06, 0.035), boot);
    limb(
      [
        const Offset(0.05, -0.14),
        const Offset(0.14, -0.09),
        const Offset(0.21, -0.15),
      ],
      _skin,
      0.055,
    );
    shape(oval(const Offset(0.225, -0.16), 0.055, 0.035), boot);
    shape(
      Path()..addRRect(
        RRect.fromLTRBR(-0.12, -0.21, 0.12, -0.11, const Radius.circular(0.03)),
      ),
      shorts,
    );
    final shirt = Path()
      ..moveTo(-0.12, -0.35)
      ..lineTo(0.12, -0.35)
      ..lineTo(0.14, -0.19)
      ..lineTo(-0.14, -0.19)
      ..close();
    c.drawPath(shirt, fill(Colors.white));
    c.save();
    c.clipPath(shirt);
    for (var y = -0.34; y < -0.19; y += 0.045) {
      c.drawRect(Rect.fromLTRB(-0.2, y, 0.2, y + 0.022), fill(stripe));
    }
    c.restore();
    c.drawPath(shirt, line(_ink, 0.012));
    c.drawRect(const Rect.fromLTRB(-0.14, -0.215, 0.14, -0.19), fill(wood));
    limb(
      [
        const Offset(-0.11, -0.32),
        const Offset(-0.21, -0.4),
        const Offset(-0.23, -0.52),
      ],
      _skin,
      0.055,
    );
    shape(oval(const Offset(-0.235, -0.55), 0.048, 0.048), _skin);
    motion(
      const Offset(-0.32, -0.6),
      -pi / 2 - 0.4,
      0.06,
      3,
      0.03,
      _ink.withValues(alpha: 0.4),
      0.01,
    );
    limb([const Offset(0.11, -0.32), const Offset(0.25, -0.42)], _skin, 0.055);
    const g0 = Offset(0.25, -0.43);
    const g1 = Offset(0.36, -0.52);
    const g2 = Offset(0.48, -0.62);
    c.drawLine(g0, g1, line(_ink, 0.085));
    c.drawLine(g0, g1, line(wood, 0.06));
    c.drawLine(g1, g2, line(_ink, 0.07));
    c.drawLine(g1, g2, line(_gold, 0.046));
    shape(oval(const Offset(0.255, -0.425), 0.042, 0.042), _skin);
    final kerchiefPath = Path()
      ..moveTo(-0.11, -0.36)
      ..lineTo(0.11, -0.36)
      ..lineTo(0.0, -0.27)
      ..close();
    shape(kerchiefPath, kerchief);

    var back = oval(const Offset(0, -0.66), 0.35, 0.3);
    for (final range in [
      const [-0.08, 0.3],
      const [0.7, 1.08],
    ]) {
      back = Path.combine(
        PathOperation.union,
        back,
        spikes(
          const Offset(0, -0.64),
          0.45,
          0.32,
          pi * range[0],
          pi * range[1],
          2,
          0.3,
        ),
      );
    }
    shape(back, hair);
    shape(face(const Offset(0, -0.62), 0.31, 0.27), _skin);
    final bangs = Path()
      ..moveTo(-0.33, -0.74)
      ..lineTo(-0.29, -0.6)
      ..lineTo(-0.22, -0.7)
      ..lineTo(-0.15, -0.6)
      ..lineTo(-0.08, -0.71)
      ..lineTo(0.0, -0.63)
      ..lineTo(0.07, -0.72)
      ..lineTo(0.14, -0.61)
      ..lineTo(0.21, -0.71)
      ..lineTo(0.29, -0.6)
      ..lineTo(0.33, -0.74)
      ..close();
    shape(bangs, hair);
    hairShine(bangs, const Offset(0, -0.64), 0.3, 0.13);

    c.save();
    c.translate(0, -0.84);
    c.rotate(0.12);
    c.translate(0, 0.84);
    final hat = Path()
      ..moveTo(-0.44, -0.76)
      ..quadraticBezierTo(-0.26, -0.69, 0, -0.74)
      ..quadraticBezierTo(0.26, -0.69, 0.44, -0.76)
      ..quadraticBezierTo(0.39, -0.9, 0.24, -0.87)
      ..quadraticBezierTo(0.16, -1.07, 0, -1.03)
      ..quadraticBezierTo(-0.16, -1.07, -0.24, -0.87)
      ..quadraticBezierTo(-0.39, -0.9, -0.44, -0.76)
      ..close();
    shape(hat, navy);
    final trim = Path()
      ..moveTo(-0.42, -0.765)
      ..quadraticBezierTo(-0.26, -0.71, 0, -0.755)
      ..quadraticBezierTo(0.26, -0.71, 0.42, -0.765);
    c.drawPath(trim, line(_gold, 0.02));
    _anchor(const Offset(0, -0.88), 0.065, _gold, 0.018);
    c.restore();

    eye(const Offset(-0.13, -0.59), 0.13, 0.165, iris, -1, star: true);
    eye(const Offset(0.13, -0.59), 0.13, 0.165, iris, 1, star: true);
    for (final s in [-1.0, 1.0]) {
      final brow = Path()
        ..moveTo(0.06 * s, -0.7)
        ..quadraticBezierTo(0.13 * s, -0.75, 0.2 * s, -0.71);
      c.drawPath(brow, line(hair, 0.015));
    }
    blush(const Offset(-0.21, -0.49), 0.045);
    blush(const Offset(0.21, -0.49), 0.045);
    final mouth = Path()
      ..moveTo(-0.09, -0.49)
      ..quadraticBezierTo(0, -0.475, 0.09, -0.49)
      ..quadraticBezierTo(0.08, -0.38, 0, -0.38)
      ..quadraticBezierTo(-0.08, -0.38, -0.09, -0.49)
      ..close();
    c.drawPath(mouth, fill(const Color(0xFFB23A45)));
    c.save();
    c.clipPath(mouth);
    c.drawRect(
      const Rect.fromLTRB(-0.1, -0.5, 0.1, -0.465),
      fill(Colors.white),
    );
    c.drawPath(
      oval(const Offset(0, -0.39), 0.05, 0.03),
      fill(const Color(0xFFFF8C9B)),
    );
    c.restore();
    c.drawPath(mouth, line(_ink, 0.012));
    c.restore();

    c.save();
    c.translate(-0.46, -1.02);
    c.rotate(-0.25);
    const green = Color(0xFF43B05C);
    const greenDark = Color(0xFF2E7D45);
    for (final s in [-1.0, 1.0]) {
      final wing = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(0.08 * s, -0.12, 0.17 * s, -0.08)
        ..quadraticBezierTo(0.1 * s, -0.04, 0.12 * s, 0.01)
        ..quadraticBezierTo(0.06 * s, 0.0, 0, 0.03)
        ..close();
      shape(wing, s < 0 ? greenDark : green, 0.01);
    }
    final ptail = Path()
      ..moveTo(-0.02, 0.05)
      ..lineTo(0.0, 0.16)
      ..lineTo(0.03, 0.05)
      ..close();
    shape(ptail, const Color(0xFFE5484D), 0.01);
    shape(oval(const Offset(0, 0.02), 0.045, 0.06), green, 0.01);
    shape(oval(const Offset(0, -0.05), 0.04, 0.04), green, 0.01);
    final beak = Path()
      ..moveTo(0.03, -0.06)
      ..quadraticBezierTo(0.08, -0.05, 0.05, -0.02)
      ..close();
    shape(beak, kerchief, 0.008);
    c.drawCircle(const Offset(0.012, -0.055), 0.01, fill(_ink));
    c.restore();

    for (final p in [
      const Offset(0.36, -0.95),
      const Offset(0.5, -0.78),
      const Offset(-0.45, -0.45),
    ]) {
      sparkle(p, 0.03, _gold);
    }
  }

  void _anchor(Offset o, double s, Color color, double w) {
    final p = line(color, w);
    c.drawCircle(o.translate(0, -s * 0.85), s * 0.2, p);
    c.drawLine(o.translate(0, -s * 0.65), o.translate(0, s * 0.75), p);
    c.drawLine(
      o.translate(-s * 0.4, -s * 0.35),
      o.translate(s * 0.4, -s * 0.35),
      p,
    );
    c.drawArc(
      Rect.fromCircle(center: o.translate(0, s * 0.15), radius: s * 0.6),
      0.2,
      pi - 0.4,
      false,
      p,
    );
  }

  // ---------------- Lantern girl ----------------
  void _lanternGirl() {
    const hair = Color(0xFF3A2E4F);
    const ribbon = Color(0xFFE5484D);
    const yukata = Color(0xFFF9C2D3);
    const obi = Color(0xFF7A5CC0);
    const iris = Color(0xFF8A5CD6);
    const spirit = Color(0xFFF7FAFF);
    const leaf = Color(0xFF6DC07A);
    const lanternRed = Color(0xFFE8663D);

    c.drawPath(
      oval(const Offset(0, 0), 0.2, 0.028),
      fill(Colors.black.withValues(alpha: 0.08)),
    );
    final backHair = Path()
      ..moveTo(-0.3, -0.7)
      ..cubicTo(-0.4, -0.42, -0.3, -0.22, -0.25, -0.15)
      ..lineTo(0.25, -0.15)
      ..cubicTo(0.3, -0.22, 0.4, -0.42, 0.3, -0.7)
      ..close();
    shape(backHair, hair);
    for (final s in [-1.0, 1.0]) {
      shape(
        Path()..addRRect(
          RRect.fromLTRBR(
            0.07 * s - 0.045,
            -0.04,
            0.07 * s + 0.045,
            -0.01,
            const Radius.circular(0.01),
          ),
        ),
        const Color(0xFF9A6A3A),
        0.01,
      );
    }
    final robe = Path()
      ..moveTo(-0.12, -0.35)
      ..lineTo(0.12, -0.35)
      ..lineTo(0.19, -0.04)
      ..quadraticBezierTo(0, -0.01, -0.19, -0.04)
      ..close();
    c.drawPath(robe, fill(yukata));
    c.save();
    c.clipPath(robe);
    for (final f in [
      const Offset(-0.1, -0.12),
      const Offset(0.09, -0.08),
      const Offset(0.12, -0.18),
      const Offset(-0.03, -0.17),
    ]) {
      for (var i = 0; i < 5; i++) {
        final a = i * pi * 2 / 5;
        c.drawCircle(
          f + Offset(cos(a), sin(a)) * 0.017,
          0.013,
          fill(Colors.white),
        );
      }
      c.drawCircle(f, 0.008, fill(_gold));
    }
    c.restore();
    c.drawPath(robe, line(_ink, 0.012));
    final collar = Path()
      ..moveTo(-0.07, -0.35)
      ..lineTo(0.01, -0.27)
      ..moveTo(0.07, -0.35)
      ..lineTo(-0.01, -0.29);
    c.drawPath(collar, line(Colors.white, 0.02));
    shape(
      Path()..addRect(const Rect.fromLTRB(-0.135, -0.27, 0.135, -0.21)),
      obi,
    );
    shape(
      oval(const Offset(-0.02, -0.24), 0.035, 0.02),
      const Color(0xFFF2C14E),
      0.008,
    );
    final leftSleeve = Path()
      ..moveTo(-0.11, -0.34)
      ..lineTo(-0.27, -0.29)
      ..quadraticBezierTo(-0.31, -0.17, -0.25, -0.12)
      ..lineTo(-0.13, -0.18)
      ..close();
    shape(leftSleeve, yukata);
    final rightSleeve = Path()
      ..moveTo(0.11, -0.34)
      ..lineTo(0.27, -0.42)
      ..lineTo(0.31, -0.29)
      ..lineTo(0.14, -0.23)
      ..close();
    shape(rightSleeve, yukata);

    const tip = Offset(0.47, -0.66);
    limb([const Offset(0.3, -0.37), tip], const Color(0xFF9A6A3A), 0.016);
    c.drawLine(tip, tip.translate(0, 0.05), line(_ink, 0.008));
    _paperLantern(tip.translate(0, 0.13), 0.075, lanternRed);
    shape(oval(const Offset(0.3, -0.365), 0.036, 0.036), _skin);

    c.save();
    c.translate(0, -0.6);
    c.rotate(0.12);
    c.translate(0, 0.6);
    for (final s in [-1.0, 1.0]) {
      shape(oval(Offset(0.25 * s, -0.88), 0.1, 0.1), hair);
      final bowCenter = Offset(0.3 * s, -0.96);
      for (final d in [-1.0, 1.0]) {
        final loop = Path()
          ..moveTo(bowCenter.dx, bowCenter.dy)
          ..quadraticBezierTo(
            bowCenter.dx + 0.07 * d,
            bowCenter.dy - 0.06,
            bowCenter.dx + 0.08 * d,
            bowCenter.dy + 0.0,
          )
          ..quadraticBezierTo(
            bowCenter.dx + 0.06 * d,
            bowCenter.dy + 0.05,
            bowCenter.dx,
            bowCenter.dy,
          )
          ..close();
        shape(loop, ribbon, 0.01);
      }
      shape(oval(bowCenter, 0.018, 0.018), ribbon, 0.008);
    }
    shape(face(const Offset(0, -0.6), 0.3, 0.27), _skin);
    final bangs = Path()
      ..moveTo(-0.32, -0.56)
      ..cubicTo(-0.36, -0.98, 0.36, -0.98, 0.32, -0.56)
      ..lineTo(0.28, -0.52)
      ..lineTo(0.23, -0.7)
      ..lineTo(0.15, -0.66)
      ..lineTo(0.09, -0.74)
      ..lineTo(0.01, -0.68)
      ..lineTo(-0.06, -0.75)
      ..lineTo(-0.13, -0.67)
      ..lineTo(-0.21, -0.72)
      ..lineTo(-0.28, -0.52)
      ..close();
    shape(bangs, hair);
    for (final s in [-1.0, 1.0]) {
      final lock = Path()
        ..moveTo(0.29 * s, -0.62)
        ..quadraticBezierTo(0.34 * s, -0.48, 0.28 * s, -0.36)
        ..quadraticBezierTo(0.27 * s, -0.48, 0.24 * s, -0.58)
        ..close();
      shape(lock, hair, 0.01);
    }
    hairShine(bangs, const Offset(0, -0.66), 0.28, 0.16);
    for (var i = 0; i < 5; i++) {
      final a = i * pi * 2 / 5;
      c.drawCircle(
        const Offset(-0.17, -0.77) + Offset(cos(a), sin(a)) * 0.022,
        0.017,
        fill(const Color(0xFFF5A3BE)),
      );
    }
    c.drawCircle(const Offset(-0.17, -0.77), 0.011, fill(_gold));

    eye(const Offset(-0.12, -0.56), 0.13, 0.165, iris, -1, star: true);
    happyEye(const Offset(0.12, -0.55), 0.12, 0.13);
    c.drawLine(
      const Offset(0.19, -0.6),
      const Offset(0.21, -0.62),
      line(_ink, 0.012),
    );
    blush(const Offset(-0.2, -0.46), 0.045);
    blush(const Offset(0.2, -0.46), 0.045);
    final mouth = Path()
      ..moveTo(-0.035, -0.45)
      ..quadraticBezierTo(0, -0.445, 0.035, -0.45)
      ..quadraticBezierTo(0.03, -0.405, 0, -0.405)
      ..quadraticBezierTo(-0.03, -0.405, -0.035, -0.45)
      ..close();
    shape(mouth, const Color(0xFFC2414F), 0.01);
    c.restore();

    c.save();
    c.translate(-0.42, -0.5);
    c.rotate(-0.12);
    final mochi = Path()
      ..moveTo(-0.12, 0.04)
      ..cubicTo(-0.14, -0.13, 0.14, -0.13, 0.12, 0.04)
      ..quadraticBezierTo(0, 0.07, -0.12, 0.04)
      ..close();
    for (final s in [-1.0, 1.0]) {
      final arm = Path()
        ..moveTo(0.1 * s, -0.01)
        ..quadraticBezierTo(0.17 * s, -0.05, 0.16 * s, -0.1);
      c.drawPath(arm, line(_ink, 0.03));
      c.drawPath(arm, line(spirit, 0.016));
    }
    shape(mochi, spirit);
    c.drawPath(
      Path()
        ..moveTo(0, -0.1)
        ..quadraticBezierTo(0.01, -0.15, 0, -0.17),
      line(leaf, 0.012),
    );
    for (final s in [-1.0, 1.0]) {
      final lf = Path()
        ..moveTo(0, -0.165)
        ..quadraticBezierTo(0.05 * s, -0.22, 0.085 * s, -0.18)
        ..quadraticBezierTo(0.04 * s, -0.15, 0, -0.165)
        ..close();
      shape(lf, leaf, 0.008);
    }
    happyEye(const Offset(-0.045, -0.03), 0.045, 0.05);
    happyEye(const Offset(0.045, -0.03), 0.045, 0.05);
    c.drawPath(
      oval(const Offset(-0.075, 0.0), 0.02, 0.012),
      fill(_blushColor.withValues(alpha: 0.6)),
    );
    c.drawPath(
      oval(const Offset(0.075, 0.0), 0.02, 0.012),
      fill(_blushColor.withValues(alpha: 0.6)),
    );
    final smile = Path()
      ..moveTo(-0.015, 0.0)
      ..quadraticBezierTo(0, 0.02, 0.015, 0.0);
    c.drawPath(smile, line(_ink, 0.008));
    c.restore();
    note(const Offset(-0.28, -0.72), 0.06, obi);
    sparkle(const Offset(-0.5, -0.75), 0.025, _gold);
    sparkle(const Offset(0.4, -0.92), 0.03, _gold);
  }

  void _paperLantern(Offset o, double s, Color body) {
    c.drawCircle(
      o,
      s * 2.3,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFD27A).withValues(alpha: 0.55),
            const Color(0xFFFFD27A).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: o, radius: s * 2.3)),
    );
    final shell = RRect.fromRectAndRadius(
      Rect.fromCenter(center: o, width: s * 1.6, height: s * 1.9),
      Radius.circular(s * 0.75),
    );
    c.drawRRect(shell, fill(body));
    c.save();
    c.clipRRect(shell);
    for (var i = -2; i <= 2; i++) {
      c.drawLine(
        o.translate(-s, i * s * 0.38),
        o.translate(s, i * s * 0.38),
        line(_ink.withValues(alpha: 0.35), s * 0.06),
      );
    }
    c.drawArc(
      Rect.fromCenter(center: o, width: s * 1.1, height: s * 1.5),
      pi * 1.15,
      pi * 0.4,
      false,
      line(Colors.white.withValues(alpha: 0.5), s * 0.12),
    );
    c.restore();
    c.drawRRect(shell, line(_ink, s * 0.12));
    for (final d in [-1.0, 1.0]) {
      c.drawRect(
        Rect.fromCenter(
          center: o.translate(0, d * s * 0.98),
          width: s * 0.9,
          height: s * 0.22,
        ),
        fill(_ink),
      );
    }
    c.drawLine(
      o.translate(0, s * 1.08),
      o.translate(0, s * 1.5),
      line(body, s * 0.12),
    );
  }

  void _character(void Function() draw) {
    final scale = min(h * 0.66, w * 0.42);
    c.save();
    c.translate(w - scale * 0.58, h * 0.97);
    c.scale(scale);
    draw();
    c.restore();
  }

  void _pawPrint(Offset o, double r, double angle, Color color) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(angle);
    c.drawPath(oval(Offset.zero, r, r * 0.85), fill(color));
    for (var i = 0; i < 4; i++) {
      final x = (i - 1.5) * r * 0.62;
      final y = -r * (i == 0 || i == 3 ? 1.05 : 1.4);
      c.drawPath(oval(Offset(x, y), r * 0.32, r * 0.38), fill(color));
    }
    c.restore();
  }

  void paintKitty() {
    const trail = Color(0xFFE2A27F);
    const yarn = Color(0xFF7FB3E0);
    const pink = Color(0xFFFF9EB0);
    for (var i = 0; i < 8; i++) {
      final t = i / 7;
      _pawPrint(
        Offset(
          w * (0.05 + t * 0.5),
          h * (0.7 - sin(t * pi) * 0.22) +
              (i.isEven ? -unit * 0.02 : unit * 0.02),
        ),
        unit * 0.016,
        0.5 + t * 0.5,
        trail.withValues(alpha: 0.7),
      );
    }
    final yarnCenter = Offset(w * 0.14, h * 0.88);
    final r = unit * 0.06;
    final thread = Path()
      ..moveTo(yarnCenter.dx + r * 0.8, yarnCenter.dy + r * 0.5)
      ..cubicTo(w * 0.3, h * 0.99, w * 0.42, h * 0.82, w * 0.55, h * 0.94);
    c.drawPath(thread, line(yarn, unit * 0.004));
    c.drawCircle(yarnCenter, r, fill(yarn));
    c.save();
    c.clipPath(oval(yarnCenter, r, r));
    for (var i = -3; i <= 3; i++) {
      final d = i * r * 0.32;
      c.drawArc(
        Rect.fromCircle(
          center: yarnCenter.translate(d, -d * 0.4),
          radius: r * 1.1,
        ),
        pi * 0.15,
        pi * 0.7,
        false,
        line(const Color(0xFF5B95C9), unit * 0.004),
      );
    }
    c.restore();
    c.drawCircle(yarnCenter, r, line(_ink, unit * 0.004));
    heart(Offset(w * 0.3, h * 0.2), unit * 0.03, pink);
    heart(Offset(w * 0.4, h * 0.14), unit * 0.02, pink.withValues(alpha: 0.7));
    note(Offset(w * 0.52, h * 0.3), unit * 0.05, const Color(0xFFE8863A));
    sparkle(Offset(w * 0.12, h * 0.16), unit * 0.02, _gold);
    sparkle(Offset(w * 0.58, h * 0.12), unit * 0.016, _gold);
    _character(_cat);
  }

  void paintDetective() {
    const clue = Color(0xFF8C6A45);
    const teal = Color(0xFF2F9C95);
    for (var i = 0; i < 9; i++) {
      final t = i / 8;
      final center = Offset(
        w * (0.05 + t * 0.48),
        h * (0.93 - t * 0.06) + (i.isEven ? -unit * 0.022 : unit * 0.022),
      );
      c.save();
      c.translate(center.dx, center.dy);
      c.rotate(-0.12);
      c.drawPath(
        oval(Offset(unit * 0.012, 0), unit * 0.02, unit * 0.011),
        fill(clue.withValues(alpha: 0.45)),
      );
      c.drawPath(
        oval(Offset(-unit * 0.022, 0), unit * 0.01, unit * 0.009),
        fill(clue.withValues(alpha: 0.45)),
      );
      c.restore();
    }
    void question(Offset o, double size, Color color) {
      final path = Path()
        ..moveTo(o.dx - size * 0.5, o.dy - size * 0.55)
        ..cubicTo(
          o.dx - size * 0.5,
          o.dy - size * 1.2,
          o.dx + size * 0.6,
          o.dy - size * 1.2,
          o.dx + size * 0.5,
          o.dy - size * 0.55,
        )
        ..quadraticBezierTo(o.dx + size * 0.4, o.dy - size * 0.15, o.dx, o.dy)
        ..lineTo(o.dx, o.dy + size * 0.25);
      c.drawPath(path, line(color, size * 0.22));
      c.drawCircle(o.translate(0, size * 0.62), size * 0.13, fill(color));
    }

    question(Offset(w * 0.1, h * 0.22), unit * 0.06, teal);
    question(Offset(w * 0.42, h * 0.14), unit * 0.04, clue);
    question(
      Offset(w * 0.5, h * 0.5),
      unit * 0.035,
      teal.withValues(alpha: 0.7),
    );
    final note = Rect.fromCenter(
      center: Offset(w * 0.26, h * 0.44),
      width: unit * 0.12,
      height: unit * 0.15,
    );
    c.save();
    c.translate(note.center.dx, note.center.dy);
    c.rotate(-0.15);
    c.translate(-note.center.dx, -note.center.dy);
    final paper = RRect.fromRectAndRadius(note, Radius.circular(unit * 0.008));
    c.drawRRect(paper, fill(const Color(0xFFFFF6DD)));
    c.drawRRect(paper, line(clue, unit * 0.003));
    for (var i = 0; i < 4; i++) {
      final y = note.top + note.height * (0.25 + i * 0.17);
      c.drawLine(
        Offset(note.left + note.width * 0.15, y),
        Offset(note.right - note.width * (i == 3 ? 0.45 : 0.15), y),
        line(clue.withValues(alpha: 0.6), unit * 0.003),
      );
    }
    c.restore();
    final key = Offset(w * 0.14, h * 0.62);
    c.drawCircle(key, unit * 0.018, line(_gold, unit * 0.006));
    c.drawLine(
      key.translate(unit * 0.018, 0),
      key.translate(unit * 0.07, 0),
      line(_gold, unit * 0.006),
    );
    for (final dx in [0.05, 0.065]) {
      c.drawLine(
        key.translate(unit * dx, 0),
        key.translate(unit * dx, unit * 0.015),
        line(_gold, unit * 0.005),
      );
    }
    _character(_detective);
  }

  void paintCaptain() {
    const navy = Color(0xFF26355A);
    const wood = Color(0xFF8A5A33);
    const sea = Color(0xFF6FB7D6);
    final wave = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w; x += 6) {
      wave.lineTo(x, h * (0.94 + 0.015 * sin(x / w * pi * 6)));
    }
    wave
      ..lineTo(w, h)
      ..close();
    c.drawPath(wave, fill(sea.withValues(alpha: 0.45)));
    final wheel = Offset(w * 0.13, h * 0.2);
    final wr = unit * 0.07;
    c.drawCircle(wheel, wr, line(wood, unit * 0.01));
    c.drawCircle(wheel, wr * 0.3, line(wood, unit * 0.008));
    for (var i = 0; i < 8; i++) {
      final d = Offset(cos(i * pi / 4), sin(i * pi / 4));
      c.drawLine(
        wheel + d * wr * 0.3,
        wheel + d * wr * 1.35,
        line(wood, unit * 0.007),
      );
      c.drawCircle(wheel + d * wr * 1.4, unit * 0.008, fill(wood));
    }
    final chest = Rect.fromLTWH(w * 0.08, h * 0.79, unit * 0.15, unit * 0.09);
    final lid = Path()
      ..moveTo(chest.left, chest.top)
      ..quadraticBezierTo(
        chest.center.dx,
        chest.top - chest.height * 0.8,
        chest.right,
        chest.top,
      )
      ..close();
    c.drawPath(lid, fill(wood));
    c.drawPath(lid, line(_ink, unit * 0.003));
    c.drawRect(chest, fill(wood));
    c.drawRect(chest, line(_ink, unit * 0.003));
    c.drawRect(
      Rect.fromCenter(
        center: Offset(chest.center.dx, chest.top + chest.height * 0.2),
        width: chest.width * 0.16,
        height: chest.height * 0.3,
      ),
      fill(_gold),
    );
    for (var i = 0; i < 4; i++) {
      c.drawCircle(
        Offset(
          chest.right + unit * (0.02 + i * 0.025),
          chest.bottom - unit * 0.005,
        ),
        unit * 0.009,
        fill(_gold),
      );
    }
    final pole = Offset(w * 0.42, h * 0.1);
    c.drawLine(pole, pole.translate(0, unit * 0.18), line(wood, unit * 0.005));
    final flag = Path()
      ..moveTo(pole.dx, pole.dy)
      ..quadraticBezierTo(
        pole.dx + unit * 0.05,
        pole.dy + unit * 0.02,
        pole.dx + unit * 0.11,
        pole.dy,
      )
      ..lineTo(pole.dx + unit * 0.11, pole.dy + unit * 0.07)
      ..quadraticBezierTo(
        pole.dx + unit * 0.05,
        pole.dy + unit * 0.09,
        pole.dx,
        pole.dy + unit * 0.07,
      )
      ..close();
    c.drawPath(flag, fill(navy));
    _anchor(
      pole.translate(unit * 0.055, unit * 0.035),
      unit * 0.022,
      _gold,
      unit * 0.004,
    );
    for (var i = 0; i < 3; i++) {
      final gull = Offset(w * (0.24 + i * 0.1), h * (0.12 + (i % 2) * 0.06));
      final span = unit * 0.02;
      final path = Path()
        ..moveTo(gull.dx - span, gull.dy - span * 0.3)
        ..quadraticBezierTo(
          gull.dx - span * 0.5,
          gull.dy - span * 0.8,
          gull.dx,
          gull.dy,
        )
        ..quadraticBezierTo(
          gull.dx + span * 0.5,
          gull.dy - span * 0.8,
          gull.dx + span,
          gull.dy - span * 0.3,
        );
      c.drawPath(path, line(navy, unit * 0.004));
    }
    _character(_captain);
  }

  void paintLantern() {
    final start = Offset(-w * 0.02, h * 0.08);
    final end = Offset(w * 1.02, h * 0.05);
    final rope = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(w * 0.5, h * 0.22, end.dx, end.dy);
    c.drawPath(rope, line(const Color(0xFF7A5A46), unit * 0.003));
    final metric = rope.computeMetrics().first;
    for (var i = 1; i < 8; i++) {
      final tangent = metric.getTangentForOffset(metric.length * i / 8);
      if (tangent == null) {
        continue;
      }
      _paperLantern(
        tangent.position.translate(0, unit * 0.035),
        unit * 0.026,
        i.isEven ? const Color(0xFFE8663D) : const Color(0xFFF2A541),
      );
    }
    final moon = Offset(w * 0.1, h * 0.3);
    final crescent = Path.combine(
      PathOperation.difference,
      oval(moon, unit * 0.05, unit * 0.05),
      oval(
        moon.translate(unit * 0.022, -unit * 0.016),
        unit * 0.043,
        unit * 0.043,
      ),
    );
    c.drawPath(crescent, fill(const Color(0xFFF7DE8A)));
    final random = Random(53);
    for (var i = 0; i < 14; i++) {
      final o = Offset(
        w * (0.05 + random.nextDouble() * 0.55),
        h * (0.35 + random.nextDouble() * 0.5),
      );
      c.drawCircle(
        o,
        unit * 0.012,
        fill(const Color(0xFFFFD27A).withValues(alpha: 0.25)),
      );
      c.drawCircle(o, unit * 0.004, fill(const Color(0xFFFFD27A)));
    }
    for (var i = 0; i < 4; i++) {
      c.drawPath(
        oval(
          Offset(w * (0.1 + i * 0.12), h * (0.95 - i * 0.025)),
          unit * 0.045,
          unit * 0.014,
        ),
        fill(const Color(0xFFB9B4C7).withValues(alpha: 0.7)),
      );
    }
    _character(_lanternGirl);
  }
}
