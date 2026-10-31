import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'notification_service.dart';
import 'preferences_service.dart';

class AppLanguage {
  const AppLanguage({required this.code, required this.nativeName});
  final String code;
  final String nativeName;
}

class LocaleService extends GetxService {
  final PreferencesService _prefs = Get.find<PreferencesService>();

  static const List<AppLanguage> supportedLanguages = [
    AppLanguage(code: 'fr', nativeName: 'Français'),
    AppLanguage(code: 'en', nativeName: 'English'),
    AppLanguage(code: 'es', nativeName: 'Español'),
    AppLanguage(code: 'de', nativeName: 'Deutsch'),
    AppLanguage(code: 'it', nativeName: 'Italiano'),
    AppLanguage(code: 'pt', nativeName: 'Português'),
    AppLanguage(code: 'zh', nativeName: '中文'),
    AppLanguage(code: 'ja', nativeName: '日本語'),
    AppLanguage(code: 'ru', nativeName: 'Русский'),
  ];

  final Rx<Locale> _locale = const Locale('fr').obs;
  Locale get locale => _locale.value;

  AppLanguage get currentLanguage => supportedLanguages.firstWhere(
        (lang) => lang.code == _locale.value.languageCode,
        orElse: () => supportedLanguages.first,
      );

  Future<LocaleService> init() async {
    final savedLang = _prefs.preferences.value.language;
    final supported = supportedLanguages.any((lang) => lang.code == savedLang);
    _locale.value = Locale(supported ? savedLang : 'fr');
    return this;
  }

  Future<void> changeLocale(String languageCode) async {
    if (!supportedLanguages.any((lang) => lang.code == languageCode)) return;
    final locale = Locale(languageCode);
    _locale.value = locale;
    Get.updateLocale(locale);

    // Persist the selected language before syncing it to the push backend.
    await _prefs.update({'language': languageCode});
    // App-locale changes do not necessarily trigger a device-locale callback.
    // Sync explicitly so server-generated push notifications use this language.
    try {
      await NotificationService.instance.syncLanguage(force: true);
    } catch (_) {
      // The app can still change language if notifications are not initialized yet.
    }
  }
}
