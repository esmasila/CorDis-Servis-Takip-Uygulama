import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  ThemeProvider() {
    _loadThemeMode();
  }
  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt(_themeKey) ?? 0;
      _themeMode = ThemeMode.light;
      notifyListeners();
    } catch (e) {
      print('Tema yüklenirken hata: $e');
    }
  }
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeKey, ThemeMode.light.index);
    } catch (e) {
      print('Tema kaydedilirken hata: $e');
    }
    notifyListeners();
  }
}



 Again


