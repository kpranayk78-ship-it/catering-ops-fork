import 'package:flutter/material.dart';

class AppTheme {
  static bool isLegacyTheme = false;

  // --- 60-30-10 Colors ---
  // The Foundation (60%)
  static Color background = Color(0xFFF9FAFB); // Light Gray
  static Color cardColor = Color(0xFFFFFFFF); // Pure White

  // The Structure (Borders)
  static Color borderColor = Color(0xFFE5E7EB); // Ultra-thin 1px borders

  // The Typography
  static Color titleColor = Color(0xFF111827); // Slate/Charcoal for titles
  static Color labelColor = Color(0xFF6B7280); // Slate for labels

  // The Semantic Indicators (10% and state colors)
  static Color activeEmerald = Color(0xFF10B981); // Active/Live
  static Color pendingAmber = Color(0xFFF59E0B); // Upcoming/Pending
  static Color primaryAction = Color(0xFF2563EB); // Deep Royal Blue

  // Other helpful semantics based on theme
  static Color errorRed = Color(0xFFEF4444);

  // --- Premium UI Properties ---
  static Color glassBackground = Color(0x99FFFFFF); // 60% opacity white for glassmorphism
  static Color darkGlass = Color(0x66111827); // subtle dark glass
  
  static void enableModernTheme() {
    isLegacyTheme = false;
    background = Color(0xFFF9FAFB);
    cardColor = Color(0xFFFFFFFF);
    borderColor = Color(0xFFE5E7EB);
    titleColor = Color(0xFF111827);
    labelColor = Color(0xFF6B7280);
    activeEmerald = Color(0xFF10B981);
    pendingAmber = Color(0xFFF59E0B);
    primaryAction = Color(0xFF2563EB);
    errorRed = Color(0xFFEF4444);
    glassBackground = Color(0x99FFFFFF);
    darkGlass = Color(0x66111827);
  }

  static void enableLegacyTheme() {
    isLegacyTheme = true;
    background = Color(0xFF111827); // Deep dark blue/black background
    cardColor = Color(0xFF1F2937);  // Dark gray card
    borderColor = Color(0xFF374151); // Darker borders
    titleColor = Color(0xFFF9FAFB); // White titles
    labelColor = Color(0xFF9CA3AF); // Light gray labels
    activeEmerald = Color(0xFF10B981); // Glowing emerald
    pendingAmber = Color(0xFFF59E0B); // Glowing amber
    primaryAction = Color(0xFF3B82F6); // Bright blue
    errorRed = Color(0xFFEF4444); // Red
    glassBackground = Color(0x33000000); // Darker glass
    darkGlass = Color(0xAA000000); 
  }
  
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: titleColor.withOpacity(0.04),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: titleColor.withOpacity(0.02),
          blurRadius: 4,
          offset: Offset(0, 2),
          spreadRadius: 0,
        ),
      ];

  static LinearGradient get subtleGradient => isLegacyTheme
      ? LinearGradient(
          colors: [Color(0xFF1F2937), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : LinearGradient(
          colors: [Color(0xFFF9FAFB), Color(0xFFF3F4F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      
  static LinearGradient get primaryGradient => LinearGradient(
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
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: titleColor,
        elevation: 0,
        centerTitle: true,
      ),
      colorScheme: ColorScheme.light(
        primary: primaryAction,
        secondary: pendingAmber,
        surface: cardColor,
        error: errorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: titleColor,
      ),
      dividerColor: borderColor,
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: titleColor),
        bodyMedium: TextStyle(color: labelColor),
        titleLarge: TextStyle(color: titleColor, fontWeight: FontWeight.bold),
      ),
    );
  }
}
