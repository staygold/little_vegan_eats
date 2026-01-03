// lib/theme/app_theme.dart
import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFFECF3F4);

  // Brand
  static const brandDark = Color(0xFF005A4F);
  static const brandActive = Color(0xFF32998D);

  // Primary text: #00484B
  static const textPrimary = Color(0xFF005A4F);

  static const white = Colors.white;

  // Meal plan bands
  static const breakfast = Color(0xFFF3BD4E);
  static const lunch = Color(0xFFE57A3A);
  static const dinner = Color(0xFFE98A97);
  static const snacks = Color(0xFF5AA5B6);
}

class AppRadii {
  static const r4 = BorderRadius.all(Radius.circular(4));
  static const r8 = BorderRadius.all(Radius.circular(8));
  static const r12 = BorderRadius.all(Radius.circular(12));
  static const r16 = BorderRadius.all(Radius.circular(16));
  static const r20 = BorderRadius.all(Radius.circular(20));
}

class AppSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s24 = 24.0;
}

class AppText {
  static const fontFamily = 'Montserrat';
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: AppText.fontFamily,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brandActive,
      brightness: Brightness.light,
      surface: AppColors.white,
      background: AppColors.bg,
    ).copyWith(
      primary: AppColors.brandActive,
      secondary: AppColors.brandDark,
      surface: AppColors.white,

      // default “on” colours
      onSurface: AppColors.textPrimary,
      onPrimary: AppColors.white,
      onSecondary: AppColors.white,
    ),
  );

  final transparentOverlay = WidgetStateProperty.all(Colors.transparent);

  // Explicitly colored text theme (Material 3 won’t override)
  final textTheme = base.textTheme.apply(
    fontFamily: AppText.fontFamily,
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  return base.copyWith(
    // ✅ Kill splash/hover/highlight globally
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,

    // ✅ “Master” text styles + variable wght axis applied everywhere that matters
    textTheme: textTheme.copyWith(
      headlineSmall: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        fontVariations: [FontVariation('wght', 700)],
      ),

      headlineMedium: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.textPrimary,
        fontVariations: [FontVariation('wght', 900)],
      ),

      titleLarge: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 4.0,
        color: AppColors.textPrimary,
        fontVariations: [FontVariation('wght', 700)],
      ),

      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        fontVariations: [FontVariation('wght', 800)],
      ),

      bodyLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        fontVariations: [FontVariation('wght', 600)],
      ),

      bodyMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        fontVariations: [FontVariation('wght', 600)],
      ),

      bodySmall: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        fontVariations: [FontVariation('wght', 600)],
      ),

      labelLarge: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 0.8,
        fontVariations: [FontVariation('wght', 700)],
      ),
    ),

    // ✅ Global card styling
    cardTheme: const CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r20),
    ),

    // ✅ Global list tile defaults
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      iconColor: AppColors.textPrimary,
      textColor: AppColors.textPrimary,
    ),

    // ✅ Elevated buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(AppColors.brandActive),
        foregroundColor: WidgetStateProperty.all(AppColors.white),
        overlayColor: transparentOverlay,
        shape: WidgetStateProperty.all(
          const RoundedRectangleBorder(borderRadius: AppRadii.r4),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontWeight: FontWeight.w700,
            fontVariations: [FontVariation('wght', 700)],
            letterSpacing: 0.6,
          ),
        ),
      ),
    ),

    // ✅ Outlined buttons
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(AppColors.textPrimary),
        overlayColor: transparentOverlay,
        side: WidgetStateProperty.all(
          const BorderSide(color: AppColors.textPrimary, width: 1),
        ),
        shape: WidgetStateProperty.all(
          const RoundedRectangleBorder(borderRadius: AppRadii.r4),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontWeight: FontWeight.w700,
            fontVariations: [FontVariation('wght', 700)],
          ),
        ),
      ),
    ),

    // ✅ Text buttons
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(AppColors.textPrimary),
        overlayColor: transparentOverlay,
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontWeight: FontWeight.w700,
            fontVariations: [FontVariation('wght', 700)],
          ),
        ),
      ),
    ),

    // ✅ Icon buttons
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(AppColors.textPrimary),
        overlayColor: transparentOverlay,
      ),
    ),

    // Optional: dividers
    dividerTheme: DividerThemeData(
      color: AppColors.textPrimary.withOpacity(0.10),
      thickness: 1,
      space: 1,
    ),
  );
}
