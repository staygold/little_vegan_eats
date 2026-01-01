import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart'; // for AppColors

class AppText {
  // ---- Helpers ----
  static TextStyle _m(
    double size,
    int w, {
    double height = 1.2,
    double letterSpacing = 0,
    Color color = AppColors.brandDark,
  }) {
    return TextStyle(
      fontFamily: 'Montserrat',
      fontSize: size,
      fontWeight: FontWeight.values[(w ~/ 100) - 1], // 100..900 -> enum index
      fontVariations: [FontVariation('wght', w.toDouble())],
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  // ---- Core system styles (use everywhere) ----
  static final h1 = _m(28, 900, height: 1.05, letterSpacing: 0.2);
  static final h2 = _m(24, 800, height: 1.1);
  static final section = _m(22, 900, height: 1.0, letterSpacing: 0.2);
  static final title = _m(18, 800, height: 1.1);
  static final body = _m(16, 700, height: 1.25, color:AppColors.brandDark);
  static final bodySoft =
      _m(14, 700, height: 1.25, color: AppColors.brandDark.withOpacity(0.70));
  static final chip = _m(12, 700, height: 1.0, color:AppColors.brandDark);

  // Small helper for “muted” text without copy/paste everywhere
  static TextStyle muted(TextStyle base, [double opacity = 0.70]) =>
      base.copyWith(color: (base.color ?? AppColors.brandDark).withOpacity(opacity));
}
