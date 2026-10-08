import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFF9A7BFF);
  static const mint = Color(0xFF5DE1D2);
  static const coral = Color(0xFFFFA56F);
  static const pink = Color(0xFFFF79B5);
  static const night = Color(0xFF000000);
  static const surfaceLow = Color(0xFF10131B);
  static const surface = Color(0xFF171C27);
  static const surfaceHigh = Color(0xFF202737);
  static const surfaceHighest = Color(0xFF2A3447);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final typography = ThemeData(brightness: brightness).textTheme;
    final scheme = brightness == Brightness.dark
        ? base.copyWith(
            primary: const Color(0xFFB69CFF),
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
            surface: night,
            surfaceContainerLowest: night,
            surfaceContainerLow: surfaceLow,
            surfaceContainer: surface,
            surfaceContainerHigh: surfaceHigh,
            surfaceContainerHighest: surfaceHighest,
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
      splashFactory: InkSparkle.splashFactory,
      textTheme: typography.copyWith(
        displaySmall: typography.displaySmall?.copyWith(
          fontSize: 38,
          height: 1.04,
          letterSpacing: -1.2,
          fontWeight: FontWeight.w800,
        ),
        headlineSmall: typography.headlineSmall?.copyWith(
          fontSize: 27,
          height: 1.08,
          letterSpacing: -0.7,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: typography.titleLarge?.copyWith(
          fontSize: 21,
          height: 1.15,
          letterSpacing: -0.35,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: typography.titleMedium?.copyWith(
          fontSize: 17,
          height: 1.2,
          letterSpacing: -0.2,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: typography.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
        labelLarge: typography.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: .1,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .25)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 18,
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
        fillColor: scheme.surfaceContainerHigh.withValues(alpha: .7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
            letterSpacing: .1,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }
}
