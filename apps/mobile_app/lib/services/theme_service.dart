import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class ThemeService {
  static String _themeKey = 'use_legacy_theme';
  
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final useLegacy = prefs.getBool(_themeKey) ?? false;
    if (useLegacy) {
      AppTheme.enableLegacyTheme();
    } else {
      AppTheme.enableModernTheme();
    }
  }

  static Future<void> toggleTheme(bool useLegacy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, useLegacy);
    
    if (useLegacy) {
      AppTheme.enableLegacyTheme();
    } else {
      AppTheme.enableModernTheme();
    }
    
    ThemeNotifier.instance.notify();
  }
  
  static bool get isLegacy => AppTheme.isLegacyTheme;
}

class ThemeNotifier extends ChangeNotifier {
  static final ThemeNotifier instance = ThemeNotifier();
  
  void notify() {
    notifyListeners();
  }
}
