import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'preferences_service.dart';

class ThemeService extends GetxService {
  static const String _boxName = 'settings';
  static const String _themeKey = 'isDarkMode';
  static const String _hasThemePreferenceKey = 'hasThemePreference';

  final RxBool isDarkMode = false.obs;

  Box? _box;

  /// Initialise le service et récupère la préférence sauvegardée.
  Future<ThemeService> init() async {
    _box = await Hive.openBox(_boxName);

    final hasPreference =
        _box?.get(_hasThemePreferenceKey, defaultValue: false) ?? false;

    if (hasPreference) {
      final savedDarkMode = _box?.get(_themeKey);
      isDarkMode.value = savedDarkMode == true;
      Get.changeThemeMode(themeMode);
    } else {
      Get.changeThemeMode(ThemeMode.system);
    }

    return this;
  }

  /// Le ThemeMode réellement utilisé par l'application.
  ThemeMode get themeMode {
    final hasPreference =
        _box?.get(_hasThemePreferenceKey, defaultValue: false) ?? false;

    if (!hasPreference) {
      return ThemeMode.system;
    }

    return isDarkMode.value ? ThemeMode.dark : ThemeMode.light;
  }

  /// Change entre Light et Dark.
  void toggleTheme() {
    final systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    if (!hasThemePreference) {
      isDarkMode.value = systemBrightness == Brightness.light;
    } else {
      isDarkMode.value = !isDarkMode.value;
    }

    final themeStr = isDarkMode.value ? 'dark' : 'light';
    _saveThemePreference();
    Get.changeThemeMode(themeMode);

    _syncToPreferencesService(themeStr);
  }

  /// Définit explicitement un thème.
  void setThemeMode(ThemeMode mode) {
    if (mode == ThemeMode.system) {
      _removeThemePreference();
      Get.changeThemeMode(ThemeMode.system);
      _syncToPreferencesService('system');
      return;
    }

    isDarkMode.value = mode == ThemeMode.dark;
    final themeStr = isDarkMode.value ? 'dark' : 'light';

    _saveThemePreference();
    Get.changeThemeMode(mode);

    _syncToPreferencesService(themeStr);
  }

  void _syncToPreferencesService(String themeStr) {
    try {
      if (Get.isRegistered<PreferencesService>()) {
        Get.find<PreferencesService>().update({'theme': themeStr});
      }
    } catch (_) {}
  }

  /// Indique si l'utilisateur a déjà choisi manuellement un thème.
  bool get hasThemePreference {
    return _box?.get(
      _hasThemePreferenceKey,
      defaultValue: false,
    ) ??
        false;
  }

  /// Sauvegarde le choix manuel de l'utilisateur.
  Future<void> _saveThemePreference() async {
    await _box?.put(_themeKey, isDarkMode.value);
    await _box?.put(_hasThemePreferenceKey, true);
  }

  /// Supprime le choix manuel et revient au thème système.
  Future<void> _removeThemePreference() async {
    await _box?.delete(_themeKey);
    await _box?.put(_hasThemePreferenceKey, false);
  }
}
