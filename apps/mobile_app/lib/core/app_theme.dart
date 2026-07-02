import 'package:flutter/material.dart';

class AppTheme {
  // --- 60-30-10 Colors ---
  // The Foundation (60%)
  static const Color background = Color(0xFFF9FAFB); // Light Gray
  static const Color cardColor = Color(0xFFFFFFFF); // Pure White

  // The Structure (Borders)
  static const Color borderColor = Color(0xFFE5E7EB); // Ultra-thin 1px borders

  // The Typography
  static const Color titleColor = Color(0xFF111827); // Slate/Charcoal for titles
  static const Color labelColor = Color(0xFF6B7280); // Slate for labels

  // The Semantic Indicators (10% and state colors)
  static const Color activeEmerald = Color(0xFF10B981); // Active/Live
  static const Color pendingAmber = Color(0xFFF59E0B); // Upcoming/Pending
  static const Color primaryAction = Color(0xFF2563EB); // Deep Royal Blue

  // Other helpful semantics based on theme
  static const Color errorRed = Color(0xFFEF4444);

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryAction,
      scaffoldBackgroundColor: background,
      cardColor: cardColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: titleColor,
        elevation: 0,
        centerTitle: true,
      ),
      colorScheme: const ColorScheme.light(
        primary: primaryAction,
        secondary: pendingAmber,
        surface: cardColor,
        error: errorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: titleColor,
        background: background,
        onBackground: titleColor,
      ),
      dividerColor: borderColor,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: titleColor),
        bodyMedium: TextStyle(color: labelColor),
        titleLarge: TextStyle(color: titleColor, fontWeight: FontWeight.bold),
      ),
    );
  }
}
