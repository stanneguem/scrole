import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/service_global/language_service.dart';
import '../../../../app/service_global/theme_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app_controller.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../pages/bug_report_screen.dart';
import '../pages/certification_plans_screen.dart';
import '../pages/connected_devices_screen.dart';
import '../pages/credits_screen.dart';
import '../pages/help_center_screen.dart';
import '../pages/language_screen.dart';
import '../pages/privacy_data_screen.dart';
import '../pages/preferences_screen.dart';
import '../pages/whats_new_screen.dart';

/// Contrôleur de [SettingsScreen].
class SettingsController extends GetxController {
  final LocaleService _localeService = Get.find<LocaleService>();
  final ThemeService _themeService = Get.find<ThemeService>();
  final AuthService _authService = Get.find<AuthService>();

  /// Contrôleur du champ de recherche des paramètres.
  final TextEditingController searchController = TextEditingController();

  /// Texte de recherche courant, réactif.
  final RxString query = ''.obs;

  /// Déconnexion en cours (pour désactiver le bouton / afficher un spinner).
  final RxBool isLoggingOut = false.obs;

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  void onSearchChanged(String value) => query.value = value;

  /// Filtre une liste de tuiles selon [query], en comparant leur label
  /// (déjà traduit) au texte recherché.
  List<T> filterTiles<T>(List<T> tiles, String Function(T tile) labelOf) {
    final q = query.value.trim().toLowerCase();
    if (q.isEmpty) return tiles;
    return tiles.where((t) => labelOf(t).toLowerCase().contains(q)).toList();
  }

  /// Nom natif de la langue actuellement sélectionnée (ne se traduit pas
  /// selon la locale : on affiche toujours le nom dans sa propre langue).
  String get currentLanguageNativeName => _localeService.currentLanguage.nativeName;

  /// Thème sombre actif ou non, réactif (persisté via [ThemeService]/Hive).
  bool get isDarkMode => _themeService.isDarkMode.value;

  // --- Navigation / actions ---------------------------------------------
  void openMyEvents() => Get.toNamed(AppPages.myEvents);
  void openMyActivities() => Get.toNamed(AppPages.myActivities);
  void openLanguageScreen() => Get.to(() => const LanguageScreen());
  void toggleTheme() => _themeService.toggleTheme();
  void openPremium() => Get.to(() => const CertificationPlansScreen());
  void openMyAccount() {}
  void openPrivacyData() => Get.to(() => const PrivacyDataScreen());
  void openPreferences() => Get.to(() => const PreferencesScreen());
  void openConnectedDevices() => Get.to(() => const ConnectedDevicesScreen());
  void openScanQr() {}
  void openChats() {}
  void openNotifications() {}
  void openAppIcon() {}
  void openHelpCenter() => Get.to(() => const HelpCenterScreen());
  void openReportBug() => Get.to(() => const BugReportScreen());
  void openCredits() => Get.to(() => const CreditsScreen());
  void openWhatsNew() => Get.to(() => const WhatsNewScreen());

  /// Demande confirmation avant de déconnecter l'utilisateur.
  ///
  /// Ne pilote plus le statut de l'app directement : AppController est
  /// l'unique responsable de cette transition (via son listener sur
  /// AuthService.currentUser), pour garantir que le nettoyage complet
  /// (Realtime, polling, cache) se fait TOUJOURS en même temps que le
  /// changement de statut — jamais l'un sans l'autre, et jamais si
  /// signOut() échoue en cours de route.
  Future<void> logout() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('settings_logout_confirm_title'.tr),
        content: Text('settings_logout_confirm_message'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('settings_logout_confirm_cancel'.tr),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('settings_logout_confirm_yes'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    isLoggingOut.value = true;
    try {
      // Ne fait QUE la déconnexion Supabase. Dès que currentUser passe
      // à null, AppController._handleSignedOut() bascule le statut ET
      // nettoie tout (timer, Realtime, cache) en une seule séquence
      // atomique — voir app_controller.dart.
      await _authService.signOut();
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Impossible de se déconnecter. Réessaie.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      isLoggingOut.value = false;
    }
  }
}