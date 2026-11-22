import 'package:material_ui/material_ui.dart';

/// Provides Material 3 light and dark theme configurations and brand tokens
/// derived from VinKit's sunset amber-to-magenta icon identity.
abstract final class AppTheme {
  /// Top-left amber highlight from the VinKit icon gradient.
  static const Color brandAmber = Color(0xFFFF9700);

  /// Core coral-rose brand accent from the center of the VinKit icon gradient.
  static const Color brandCoral = Color(0xFFF05D72);

  /// Bottom-right electric magenta accent from the VinKit icon gradient.
  static const Color brandMagenta = Color(0xFFCD3DE8);

  /// Deep carbon-plum backdrop used by the launch splash and dark surfaces.
  static const Color splashBackground = Color(0xFF121016);

  /// Primary seed color aligned with VinKit's brand gradient.
  static const Color seedColor = brandCoral;

  /// Signature diagonal gradient matching the VinKit app icon.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[brandAmber, brandCoral, brandMagenta],
    stops: <double>[0.0, 0.52, 1.0],
  );

  /// Returns the Material 3 light [ThemeData].
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  /// Returns the Material 3 dark [ThemeData].
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      secondary: brandMagenta,
      tertiary: brandAmber,
      brightness: brightness,
    );

    final colorScheme = isDark
        ? baseScheme.copyWith(
            primary: const Color(0xFFFF7A68),
            onPrimary: const Color(0xFF280604),
            primaryContainer: const Color(0xFF4A1920),
            onPrimaryContainer: const Color(0xFFFFDAD5),
            secondary: const Color(0xFFE07BFF),
            tertiary: const Color(0xFFFFB74D),
            surface: splashBackground,
            surfaceContainerLowest: const Color(0xFF0C0A10),
            surfaceContainerLow: const Color(0xFF18151E),
            surfaceContainer: const Color(0xFF1D1A24),
            surfaceContainerHigh: const Color(0xFF25202E),
            surfaceContainerHighest: const Color(0xFF2F293B),
          )
        : baseScheme.copyWith(
            primary: const Color(0xFFD84358),
            secondary: const Color(0xFF9C27B0),
            tertiary: const Color(0xFFE67E00),
            surface: const Color(0xFFFFFAF8),
          );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: brandCoral,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.55 : 0.7,
            ),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
