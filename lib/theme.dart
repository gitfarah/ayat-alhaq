import 'package:flutter/material.dart';

/// "Sacred Clarity" design system
class AppColors {
  // ===== Light (Parchment) =====
  static const Color surface = Color(0xFFFBF9F5);
  static const Color surfaceDim = Color(0xFFDBDAD6);
  static const Color surfaceBright = Color(0xFFFBF9F5);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF5F3EF);
  static const Color surfaceContainer = Color(0xFFEFEEEA);
  static const Color surfaceContainerHigh = Color(0xFFEAE8E4);
  static const Color surfaceContainerHighest = Color(0xFFE4E2DE);
  static const Color onSurface = Color(0xFF1B1C1A);
  static const Color onSurfaceVariant = Color(0xFF404944);
  static const Color outline = Color(0xFF707974);
  static const Color outlineVariant = Color(0xFFBFC9C3);
  static const Color background = Color(0xFFFBF9F5);
  static const Color onBackground = Color(0xFF1B1C1A);
  static const Color surfaceVariant = Color(0xFFE4E2DE);

  // Primary — Deep Emerald
  static const Color primary = Color(0xFF003527);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF064E3B);
  static const Color onPrimaryContainer = Color(0xFF80BEA6);
  static const Color inversePrimary = Color(0xFF95D3BA);

  // Secondary — Gold
  static const Color secondary = Color(0xFF735C00);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFFED65B);
  static const Color onSecondaryContainer = Color(0xFF745C00);

  // Tertiary
  static const Color tertiary = Color(0xFF003431);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFF004D49);
  static const Color onTertiaryContainer = Color(0xFF7ABDB7);

  // Error
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  // ===== Dark (Inverse / Deep Emerald overlays) =====
  static const Color darkBg = Color(0xFF0D1411);
  static const Color darkSurface = Color(0xFF161F1B);
  static const Color darkSurfaceAlt = Color(0xFF1E2A24);
  static const Color darkBorder = Color(0xFF2B3A33);
  static const Color darkText = Color(0xFFF2F0ED);
  static const Color darkTextSec = Color(0xFFB8C2BC);
  static const Color darkPrimary = Color(0xFF95D3BA);
  static const Color darkSecondary = Color(0xFFE9C349);

  static const Color inverseSurface = Color(0xFF30312E);
  static const Color inverseOnSurface = Color(0xFFF2F0ED);

  // Brand gold — the metallic gold used across buttons, cards, badges
  // and decorative accents (user-chosen #D4AF37).
  static const Color gold = Color(0xFFD4AF37);

  // Deep emerald used as the bottom-navigation background (matches the
  // brand and the requested layout).
  static const Color navBar = Color(0xFF143D2B);

  // Legacy aliases kept for compatibility with earlier code
  static const Color accent = gold;
  static const Color accentGold = gold;
  static const Color textPrimary = onSurface;
  static const Color textSecondary = onSurfaceVariant;
  static const Color textLight = outline;
  static const Color border = outlineVariant;
  static const Color cardBg = surfaceContainerLowest;
  static const Color primaryDark = Color(0xFF002117);
  static const Color primaryLight = inversePrimary;
  static const Color darkTextSecondary = darkTextSec;

  // Mushaf-specific (Sajdah / madder red)
  static const Color sajdahRed = Color(0xFF991B1B);

  // Mushaf parchment, distinct from app's main surface
  static const Color mushafParchment = Color(0xFFFAF3E0);
  static const Color mushafParchmentDark = Color(0xFF12100A);
  static const Color mushafBorderGold = Color(0xFFD4B483);

  // Highlight palette (kept compatible with HighlightService)
  static const Map<String, Color> highlights = {
    'yellow': Color(0xFFFFEB3B),
    'green': Color(0xFF81C784),
    'blue': Color(0xFF64B5F6),
    'pink': Color(0xFFF06292),
    'purple': Color(0xFFBA68C8),
  };

  static Color highlight(String name) => highlights[name] ?? Colors.transparent;
}

class AppTypography {
  static const String arabicFont = 'Almarai';
  static const String uiFont = 'PlusJakartaSans';
  static const String serifFont = 'SourceSerif4';

  static const TextStyle quranDisplay = TextStyle(
    fontFamily: arabicFont,
    fontSize: 48,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle quranReading = TextStyle(
    fontFamily: arabicFont,
    fontSize: 32,
    fontWeight: FontWeight.w400,
    height: 1.75,
  );
  static const TextStyle headlineLg = TextStyle(
    fontFamily: uiFont,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.33,
  );
  static const TextStyle headlineMd = TextStyle(
    fontFamily: uiFont,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const TextStyle bodyLg = TextStyle(
    fontFamily: serifFont,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.56,
  );
  static const TextStyle bodyMd = TextStyle(
    fontFamily: serifFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle labelSm = TextStyle(
    fontFamily: uiFont,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.33,
    letterSpacing: 0.6,
  );
}

class AppRadii {
  static const double sm = 2;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double full = 9999;
}

class AppSpacing {
  static const double unit = 8;
  static const double containerMargin = 24;
  static const double gutter = 16;
  static const double sectionGap = 40;
}

class AppTheme {
  static ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: AppColors.primary,
    fontFamily: AppTypography.uiFont,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceContainerHighest: AppColors.surfaceVariant,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      inverseSurface: AppColors.inverseSurface,
      onInverseSurface: AppColors.inverseOnSurface,
      inversePrimary: AppColors.inversePrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.onSurface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle:
          AppTypography.headlineMd.copyWith(color: AppColors.onSurface),
      iconTheme: const IconThemeData(color: AppColors.primary),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surfaceContainerLow,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.outline,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.outlineVariant, width: 1),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.primary,
      contentTextStyle: AppTypography.bodyMd.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerColor: AppColors.outlineVariant,
    textTheme: const TextTheme(
      bodyLarge: AppTypography.bodyLg,
      bodyMedium: AppTypography.bodyMd,
      headlineLarge: AppTypography.headlineLg,
      headlineMedium: AppTypography.headlineMd,
      labelSmall: AppTypography.labelSm,
    ).apply(bodyColor: AppColors.onSurface, displayColor: AppColors.onSurface),
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBg,
    primaryColor: AppColors.darkPrimary,
    fontFamily: AppTypography.uiFont,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.primaryDark,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.darkPrimary,
      secondary: AppColors.darkSecondary,
      onSecondary: Color(0xFF241A00),
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: Color(0xFF574500),
      tertiary: AppColors.onTertiaryContainer,
      onTertiary: Color(0xFF00201E),
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      surfaceContainerHighest: AppColors.darkSurfaceAlt,
      onSurfaceVariant: AppColors.darkTextSec,
      outline: AppColors.darkBorder,
      outlineVariant: AppColors.darkBorder,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      inverseSurface: AppColors.surface,
      onInverseSurface: AppColors.onSurface,
      inversePrimary: AppColors.primary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.darkBg,
      foregroundColor: AppColors.darkText,
      elevation: 0,
      centerTitle: true,
      titleTextStyle:
          AppTypography.headlineMd.copyWith(color: AppColors.darkText),
      iconTheme: const IconThemeData(color: AppColors.darkPrimary),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      selectedItemColor: AppColors.darkPrimary,
      unselectedItemColor: AppColors.darkTextSec,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkPrimary,
      contentTextStyle:
          AppTypography.bodyMd.copyWith(color: AppColors.primaryDark),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerColor: AppColors.darkBorder,
    textTheme: const TextTheme(
      bodyLarge: AppTypography.bodyLg,
      bodyMedium: AppTypography.bodyMd,
      headlineLarge: AppTypography.headlineLg,
      headlineMedium: AppTypography.headlineMd,
      labelSmall: AppTypography.labelSm,
    ).apply(bodyColor: AppColors.darkText, displayColor: AppColors.darkText),
  );
}
