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
  bool _hasThemePreference = false;
  Future<void> _persistenceQueue = Future<void>.value();

  /// Initialise le service et récupère la préférence sauvegardée.
  Future<ThemeService> init() async {
    _box = await Hive.openBox(_boxName);

    _hasThemePreference =
        _box?.get(_hasThemePreferenceKey, defaultValue: false) == true;

    if (_hasThemePreference) {
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
    if (!_hasThemePreference) {
      return ThemeMode.system;
    }

    return isDarkMode.value ? ThemeMode.dark : ThemeMode.light;
  }

  /// Change entre Light et Dark.
  void toggleTheme() {
    // En mode système, partir de la luminosité réellement affichée.
    final currentMode = themeMode;
    final currentlyDark = currentMode == ThemeMode.system
        ? WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
        : isDarkMode.value;

    isDarkMode.value = !currentlyDark;
    _hasThemePreference = true;

    final mode = isDarkMode.value ? ThemeMode.dark : ThemeMode.light;
    final themeStr = isDarkMode.value ? 'dark' : 'light';

    // Appliquer immédiatement le mode explicite : ne pas attendre Hive.
    Get.changeThemeMode(mode);
    _saveThemePreference();
    _syncToPreferencesService(themeStr);
  }

  /// Définit explicitement un thème.
  void setThemeMode(ThemeMode mode) {
    if (mode == ThemeMode.system) {
      _hasThemePreference = false;
      Get.changeThemeMode(ThemeMode.system);
      _removeThemePreference();
      _syncToPreferencesService('system');
      return;
    }

    isDarkMode.value = mode == ThemeMode.dark;
    _hasThemePreference = true;
    final themeStr = isDarkMode.value ? 'dark' : 'light';

    // Le rendu ne dépend plus du délai d'écriture de la préférence.
    Get.changeThemeMode(mode);
    _saveThemePreference();
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
  bool get hasThemePreference => _hasThemePreference;

  /// Sérialise les écritures Hive pour éviter qu'un ancien clic écrase
  /// la préférence issue d'un clic plus récent.
  void _enqueuePersistence(Future<void> Function() operation) {
    _persistenceQueue = _persistenceQueue
        .then((_) => operation())
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[ThemeService] Preference persistence failed: $error');
        });
  }

  /// Sauvegarde le choix manuel de l'utilisateur.
  void _saveThemePreference() {
    final darkMode = isDarkMode.value;
    _enqueuePersistence(() async {
      await _box?.put(_themeKey, darkMode);
      await _box?.put(_hasThemePreferenceKey, true);
    });
  }

  /// Supprime le choix manuel et revient au thème système.
  void _removeThemePreference() {
    _enqueuePersistence(() async {
      await _box?.delete(_themeKey);
      await _box?.put(_hasThemePreferenceKey, false);
    });
  }
}
