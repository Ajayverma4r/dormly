// core/theme/app_theme.dart
//
// Design tokens for Dormly. Brand primary is the Payments purple used on
// "New Invoice" and active tab indicators. Sora carries headlines/numbers;
// Inter carries body and captions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const ink = Color(0xFF111827);
  static const slate = Color(0xFF6B7280);
  static const canvas = Color(0xFFF3F4F7);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFF7C3AED);
  static const primarySoft = Color(0xFFF3E8FF);
  static const primaryMuted = Color(0xFFEDE4FF);
  static const primaryDark = Color(0xFF5B21B6);

  /// Logo / splash blue — not the app primary (which is Payments purple).
  static const logoBlue = Color(0xFF2451B4);
  static const logoBlueDark = Color(0xFF1A3A8F);

  /// Brand primary — kept as an alias for existing call sites.
  static const blueprint = primary;
  static const positive = Color(0xFF1F9D55);
  static const caution = Color(0xFFB45309);
  static const danger = Color(0xFFB91C1C);
  static const hairline = Color(0xFFE5E7EB);
}

class AppTheme {
  static const systemUi = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: true,
  );

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    final headlineFont = GoogleFonts.sora();
    final bodyFont = GoogleFonts.inter();

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.canvas,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primarySoft,
        onPrimaryContainer: AppColors.primaryDark,
        surface: AppColors.surface,
      ),
      textTheme: base.textTheme.copyWith(
        displaySmall: headlineFont.copyWith(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink),
        headlineSmall: headlineFont.copyWith(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
        titleLarge: headlineFont.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink),
        titleMedium: headlineFont.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
        bodyLarge: bodyFont.copyWith(fontSize: 15, color: AppColors.ink),
        bodyMedium: bodyFont.copyWith(fontSize: 13, color: AppColors.slate),
        labelSmall: bodyFont.copyWith(fontSize: 11, color: AppColors.slate, letterSpacing: 0.4),
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero, color: AppColors.surface),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        foregroundColor: AppColors.ink,
        centerTitle: false,
        titleTextStyle: headlineFont.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
        systemOverlayStyle: AppTheme.systemUi,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.hairline, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: bodyFont.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        surfaceTintColor: Colors.transparent,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
