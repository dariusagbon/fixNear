import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF1E7AF9);
  static const Color primaryDark = Color(0xFF12314D);
  static const Color neutralBg = Color(0xFFF5F7FB);
  static const Color surfaceWhite = Colors.white;
  static const Color textPrimary = Color(0xFF132238);
  static const Color textSecondary = Color(0xFF5F6F85);
  static const Color successGreen = Color(0xFF1D8D63);
  static const Color warningAmber = Color(0xFFF6B445);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: neutralBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: const Color(0xFF0B6B9E),
        surface: surfaceWhite,
        brightness: Brightness.light,
      ),
      textTheme: ThemeData.light().textTheme.copyWith(
        headlineLarge: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          color: textPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: textPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          color: textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: neutralBg,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
    );
  }
}
