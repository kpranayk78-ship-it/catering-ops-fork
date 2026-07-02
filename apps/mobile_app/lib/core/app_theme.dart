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

  // --- Premium UI Properties ---
  static const Color glassBackground = Color(0x99FFFFFF); // 60% opacity white for glassmorphism
  static const Color darkGlass = Color(0x66111827); // subtle dark glass
  
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: titleColor.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: titleColor.withOpacity(0.02),
          blurRadius: 4,
          offset: const Offset(0, 2),
          spreadRadius: 0,
        ),
      ];

  static LinearGradient get subtleGradient => const LinearGradient(
        colors: [Color(0xFFF9FAFB), Color(0xFFF3F4F6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      
  static LinearGradient get primaryGradient => const LinearGradient(
        colors: [Color(0xFF3B82F6), Color(0xFF2563EB)], // Lighter to deeper blue
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

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
