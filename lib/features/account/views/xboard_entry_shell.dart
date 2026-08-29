import 'package:flutter/material.dart';

class XboardEntryShell extends StatelessWidget {
  const XboardEntryShell({super.key, required this.child});

  static const backgroundColor = Color(0xFFF6F8F5);
  static const primaryColor = Color(0xFF22B573);
  static const foregroundColor = Color(0xFF18231E);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData.light(useMaterial3: true);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
        ).copyWith(
          primary: primaryColor,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: foregroundColor,
          surfaceContainerHighest: const Color(0xFFF1F5F2),
          outline: const Color(0xFFD8E2DC),
          outlineVariant: const Color(0xFFE6ECE8),
        );
    final theme = baseTheme.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundColor,
      textTheme: baseTheme.textTheme.apply(
        bodyColor: foregroundColor,
        displayColor: foregroundColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFCFA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8E2DC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8E2DC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        labelStyle: const TextStyle(fontSize: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Stack(
          children: [
            const Positioned(
              left: -150,
              top: -170,
              child: _AuroraGlow(size: 430, color: Color(0xFFBFEFD3)),
            ),
            const Positioned(
              right: -150,
              bottom: -190,
              child: _AuroraGlow(size: 450, color: Color(0xFFC9EAF3)),
            ),
            Positioned.fill(child: child),
          ],
        ),
      ),
    );
  }
}

class _AuroraGlow extends StatelessWidget {
  const _AuroraGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.58),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
