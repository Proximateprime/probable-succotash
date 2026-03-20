import 'package:flutter/material.dart';

import 'local_storage_service.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this._storageService);

  final LocalStorageService _storageService;
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> initialize() async {
    final stored = _storageService.getThemeMode();
    _themeMode = _themeModeFromString(stored);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _storageService.setThemeMode(_themeModeToString(mode));
    notifyListeners();
  }

  static ThemeMode _themeModeFromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
