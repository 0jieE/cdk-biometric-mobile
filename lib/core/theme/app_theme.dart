import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Selectable brand accents (Phase 11). Purple is the default. Changing the
/// accent re-themes the whole app; semantic status colors never change.
enum AppAccent { purple, indigo, teal, rose, slate }

extension AppAccentX on AppAccent {
  /// Seed / primary color for this accent.
  Color get seed => switch (this) {
    AppAccent.purple => const Color(0xFF6D28D9),
    AppAccent.indigo => const Color(0xFF4F46E5),
    AppAccent.teal => const Color(0xFF0D9488),
    AppAccent.rose => const Color(0xFFE11D48),
    AppAccent.slate => const Color(0xFF475569),
  };

  String get label => switch (this) {
    AppAccent.purple => 'Purple',
    AppAccent.indigo => 'Indigo',
    AppAccent.teal => 'Teal',
    AppAccent.rose => 'Rose',
    AppAccent.slate => 'Slate',
  };

  /// Stable key used for persistence.
  String get key => name;
}

AppAccent accentFromKey(String? key) {
  return AppAccent.values.firstWhere(
    (a) => a.key == key,
    orElse: () => AppAccent.purple,
  );
}

/// Material 3 theme + design tokens for the Colegio de Kidapawan (CDK) employee app.
///
/// Brand = purple (swappable accent). Headings use Poppins, body uses Inter.
class AppTheme {
  AppTheme._();

  /// Default brand color (purple), used where a fixed brand hue is needed
  /// before a [BuildContext] is available.
  static const Color brandPurple = Color(0xFF6D28D9);

  // ---- Semantic status colors (Phase 11 spec — never re-themed) ----------
  static const Color present = Color(0xFF16A34A); // on-time / present (green)
  static const Color late = Color(0xFFF97316); // late (orange)
  static const Color halfDay = Color(0xFFF59E0B); // half-day (amber)
  static const Color absent = Color(0xFFDC2626); // absent / missing (red)
  static const Color overtime = Color(0xFF2563EB); // overtime (blue)

  /// Soft card shadow used across the app.
  static List<BoxShadow> get softShadow => const [
    BoxShadow(
      color: Color(0x14141428), // rgba(20,20,40,.08)
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  /// 135° brand gradient derived from [base] (accent-aware).
  static LinearGradient brandGradient(Color base) {
    final hsl = HSLColor.fromColor(base);
    final light = hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0));
    final dark = hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0));
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [light.toColor(), base, dark.toColor()],
    );
  }

  /// Build the theme for the given [accent] and [brightness].
  static ThemeData themeFor(AppAccent accent, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    var scheme = ColorScheme.fromSeed(
      seedColor: accent.seed,
      brightness: brightness,
    );
    // Pin the primary to the exact accent in light mode; keep the tonal
    // (lighter) primary in dark mode for contrast on near-black surfaces.
    if (isLight) {
      scheme = scheme.copyWith(primary: accent.seed);
    }
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    // Poppins for display/headline/title/label; Inter for body.
    final poppins = GoogleFonts.poppinsTextTheme(base.textTheme);
    final inter = GoogleFonts.interTextTheme(base.textTheme);
    final textTheme = inter.copyWith(
      displayLarge: poppins.displayLarge,
      displayMedium: poppins.displayMedium,
      displaySmall: poppins.displaySmall,
      headlineLarge: poppins.headlineLarge,
      headlineMedium: poppins.headlineMedium,
      headlineSmall: poppins.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleLarge: poppins.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: poppins.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: poppins.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: poppins.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// Color for an attendance status string (semantic — never re-themed).
  static Color statusColor(String apiStatus) {
    switch (apiStatus) {
      case 'ON_TIME':
      case 'PRESENT':
        return present;
      case 'LATE':
        return late;
      case 'HALF_DAY':
        return halfDay;
      case 'ABSENT':
        return absent;
      case 'OVERTIME':
        return overtime;
      default:
        return Colors.grey;
    }
  }
}
