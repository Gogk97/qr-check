import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 3-Tone Architectural Palette (Anti-AI Slop / Fintech Utilitarian System)
///
/// Tone 1 (Ground & Surface):
///   - Warm Alabaster (#F5F6F3) & Pure Chalk (#FFFFFF) in Light
///   - Carbon Obsidian (#0A0E0D) & Matte Graphite (#121816) in Dark
/// Tone 2 (Structural Ink & Neutral Slate):
///   - Deep Carbon Ink (#111715) & Mineral Slate (#5B6660)
/// Tone 3 (Signal Emerald & Warm Brass):
///   - Precision Emerald (#0B8760 / #065F43) for QRIS Verification & Active States
///   - Editorial Brass (#C67D15) for Standard QR & PRO Tier Distinction
class AppTheme {
  // Tone 1: Ground & Tactile Surfaces
  static const Color backgroundLight = Color(0xFFF5F6F3); // Warm Alabaster
  static const Color surfaceLight = Color(0xFFFFFFFF); // Pure Surface
  static const Color surfaceSubtleLight = Color(0xFFECEEE9); // Recessed Well
  static const Color borderLight = Color(0xFFDCDFD9); // 1px Structural Hairline

  static const Color backgroundDark = Color(0xFF0A0E0D); // Carbon Obsidian
  static const Color surfaceDark = Color(0xFF121816); // Elevated Graphite
  static const Color surfaceSubtleDark = Color(0xFF18201D); // Recessed Dark Well
  static const Color borderDark = Color(0xFF232D29); // 1px Dark Hairline

  // Tone 2: Structural Ink & Typography
  static const Color textDark = Color(0xFF111715); // Deep Carbon Ink
  static const Color textMuted = Color(0xFF5B6660); // Mineral Slate
  static const Color textMutedDark = Color(0xFF8E9993); // Muted Silver-Slate
  static const Color textLight = Color(0xFFF1F5F3); // Crisp Off-White
  static const Color nonQrGrey = Color(0xFF68736D); // Neutral Structural Slate

  // Tone 3: Fintech Emerald & Editorial Brass Accent
  static const Color primary = Color(0xFF0B8760); // Precision Emerald (No AI Violet!)
  static const Color primaryDark = Color(0xFF065F43); // Deep Forest Ink
  static const Color qrisGreen = Color(0xFF0B8760); // Unified Verification Emerald
  static const Color qrisGreenDark = Color(0xFF065F43); // Deep Emerald Action
  static const Color qrAmber = Color(0xFFC67D15); // Warm Editorial Brass
  static const Color dangerRed = Color(0xFFDC2626); // Semantic Destructive

  // Helper getters for adaptive 3-tone surfaces
  static Color cardColor(bool isDark) => isDark ? surfaceDark : surfaceLight;
  static Color subtleBg(bool isDark) => isDark ? surfaceSubtleDark : surfaceSubtleLight;
  static Color borderColor(bool isDark) => isDark ? borderDark : borderLight;
  static Color inkColor(bool isDark) => isDark ? textLight : textDark;
  static Color mutedColor(bool isDark) => isDark ? textMutedDark : textMuted;

  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: backgroundLight,
      dividerColor: borderLight,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: qrisGreenDark,
        surface: surfaceLight,
        onPrimary: Colors.white,
        onSurface: textDark,
        outline: borderLight,
      ),
      textTheme: baseTextTheme.copyWith(
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: textDark,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: textDark,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: textDark,
          height: 1.45,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: textMuted,
          height: 1.4,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceLight,
        foregroundColor: textDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: const Border(
          bottom: BorderSide(color: borderLight, width: 1),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: textDark,
        ),
      ),
      cardTheme: CardTheme(
        color: surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: textDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundDark,
      dividerColor: borderDark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: qrisGreen,
        surface: surfaceDark,
        onPrimary: Colors.white,
        onSurface: textLight,
        outline: borderDark,
      ),
      textTheme: baseTextTheme.copyWith(
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: textLight,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: textLight,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: textLight,
          height: 1.45,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: textMutedDark,
          height: 1.4,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceDark,
        foregroundColor: textLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: const Border(
          bottom: BorderSide(color: borderDark, width: 1),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: textLight,
        ),
      ),
      cardTheme: CardTheme(
        color: surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderDark, width: 1),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderDark, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}
