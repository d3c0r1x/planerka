import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFF8967FF);
  static const mint = Color(0xFF55D8C7);
  static const coral = Color(0xFFFFA56B);
  static const pink = Color(0xFFFF7FB0);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final scheme = brightness == Brightness.dark
        ? base.copyWith(
            primary: const Color(0xFFA48BFF),
            onPrimary: const Color(0xFF171027),
            primaryContainer: const Color(0xFF30254F),
            onPrimaryContainer: const Color(0xFFE9DDFF),
            secondary: mint,
            onSecondary: const Color(0xFF08221F),
            secondaryContainer: const Color(0xFF143B37),
            onSecondaryContainer: const Color(0xFFB8FFF4),
            tertiary: coral,
            onTertiary: const Color(0xFF2A160B),
            tertiaryContainer: const Color(0xFF4A2B1A),
            onTertiaryContainer: const Color(0xFFFFDFC7),
            error: const Color(0xFFFF718B),
            surface: const Color(0xFF000000),
            surfaceContainerLowest: const Color(0xFF000000),
            surfaceContainerLow: const Color(0xFF08090D),
            surfaceContainer: const Color(0xFF1C1E27),
            surfaceContainerHigh: const Color(0xFF242630),
            surfaceContainerHighest: const Color(0xFF2D303B),
            onSurface: const Color(0xFFF5F3FA),
            onSurfaceVariant: const Color(0xFFB7B6C4),
            outline: const Color(0xFF858392),
            outlineVariant: const Color(0xFF3A3B47),
          )
        : base.copyWith(
            primary: const Color(0xFF6843DA),
            secondary: const Color(0xFF087F78),
            tertiary: const Color(0xFFB34E72),
          );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
