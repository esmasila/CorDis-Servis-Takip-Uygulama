import 'package:flutter/material.dart';
import 'cache_service.dart';
class ThemeService extends ChangeNotifier {
  ThemeService._internal();
  static final ThemeService instance = ThemeService._internal();
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  Future<void> initialize() async {
    try {
      final String current = CacheService.instance.getTheme();
      _themeMode = ThemeMode.light;
    } catch (_) {
      _themeMode = ThemeMode.light;
    }
  }
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = ThemeMode.light;
    notifyListeners();
    try {
      await CacheService.instance.setTheme('light');
    } catch (_) {}
  }
  Future<void> toggle() async {
    await setThemeMode(ThemeMode.light);
  }
}
