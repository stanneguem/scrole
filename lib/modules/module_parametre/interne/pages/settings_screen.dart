import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../controllers/settings_controller.dart';



class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // NB : en production, préfère enregistrer SettingsController via un
    // Binding (ex. SettingsBinding) sur la route plutôt qu'ici. Get.put
    // ici garde l'écran autonome et fonctionne très bien pour démarrer.
    final SettingsController controller = Get.put(SettingsController());

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.background;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final border = isDark ? AppColors.black1 : AppColors.border;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(textPrimary: textPrimary),
            Expanded(
              child: Obx(
                    () => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _SearchField(
                      controller: controller.searchController,
                      onChanged: controller.onSearchChanged,
                      surface: surface,
                      border: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),
                    const SizedBox(height: 24),

                    _SectionLabel('settings_section_account'.tr, textSecondary),
                    _SettingsCard(
                      surface: surface,
                      border: border,
                      children: controller.filterTiles<_SettingsTile>(
                        [
                          _SettingsTile(
                            icon: Icons.workspace_premium_rounded,
                            iconBg: AppColors.primary,
                            label: 'settings_go_premium'.tr,
                            onTap: controller.openPremium,
                          ),
                          _SettingsTile(
                            icon: Icons.person_rounded,
                            label: 'settings_my_account'.tr,
                            onTap: controller.openMyAccount,
                          ),
                          _SettingsTile(
                            icon: Icons.privacy_tip_rounded,
                            label: 'settings_privacy_data'.tr,
                            onTap: controller.openPrivacyData,
                          ),

                          _SettingsTile(
                            icon: Icons.devices_rounded,
                            label: 'settings_connected_devices'.tr,
                            onTap: controller.openConnectedDevices,
                          ),

                          _SettingsTile(
                            icon: Icons.qr_code_scanner_rounded,
                            label: 'settings_scan_qr'.tr,
                            onTap: controller.openScanQr,
                          ),
                        ],
                            (t) => t.label,
                      ),
                    ),

                    const SizedBox(height: 24),
                    _SectionLabel('settings_section_app'.tr, textSecondary),
                    _SettingsCard(
                      surface: surface,
                      border: border,
                      children: controller.filterTiles<_SettingsTile>(
                        [
                          _SettingsTile(
                            icon: Icons.translate_rounded,
                            label: 'settings_language'.tr,
                            trailingText: controller.currentLanguageNativeName,
                            onTap: controller.openLanguageScreen,
                          ),
                          _SettingsTile(
                            icon: Icons.tune_rounded,
                            label: 'settings_preferences_title'.tr,
                            onTap: controller.openPreferences,
                          ),
                          _SettingsTile(
                            icon: Icons.chat_bubble_rounded,
                            label: 'settings_chats'.tr,
                            onTap: controller.openChats,
                          ),

                          _SettingsTile(
                            icon: Icons.notifications_rounded,
                            label: 'settings_notifications'.tr,
                            onTap: controller.openNotifications,
                          ),
                          _SettingsTile(
                            icon: Icons.dark_mode_rounded,
                            label: 'settings_theme'.tr,
                            trailingText: controller.isDarkMode
                                ? 'settings_theme_dark'.tr
                                : 'settings_theme_light'.tr,
                            onTap: controller.toggleTheme,
                          ),
                          _SettingsTile(
                            icon: Icons.apps_rounded,
                            label: 'settings_app_icon'.tr,
                            // badge: 'NOUVEAU',
                            onTap: controller.openAppIcon,
                          ),
                        ],
                            (t) => t.label,
                      ),
                    ),

                    const SizedBox(height: 24),
                    _SectionLabel('settings_section_support'.tr, textSecondary),
                    _SettingsCard(
                      surface: surface,
                      border: border,
                      children: controller.filterTiles<_SettingsTile>(
                        [
                          _SettingsTile(
                            icon: Icons.help_rounded,
                            label: 'settings_help_center'.tr,
                            onTap: controller.openHelpCenter,
                          ),
                          _SettingsTile(
                            icon: Icons.bug_report_rounded,
                            label: 'settings_report_bug'.tr,
                            onTap: controller.openReportBug,
                          ),
                          _SettingsTile(
                            icon: Icons.info_rounded,
                            label: 'settings_credits'.tr,
                            onTap: controller.openCredits,
                          ),
                        ],
                            (t) => t.label,
                      ),
                    ),

                    const SizedBox(height: 24),
                    _SectionLabel('settings_section_whats_new'.tr, textSecondary),
                    _SettingsCard(
                      surface: surface,
                      border: border,
                      children: controller.filterTiles<_SettingsTile>(
                        [
                          _SettingsTile(
                            icon: Icons.celebration_rounded,
                            label: 'settings_whats_new_scrole'.tr,
                            onTap: controller.openWhatsNew,
                          ),
                        ],
                            (t) => t.label,
                      ),
                    ),

                    const SizedBox(height: 24),
                    _SettingsCard(
                      surface: surface,
                      border: border,
                      children: [
                        _SettingsTile(
                          icon: Icons.logout_rounded,
                          label: 'settings_logout'.tr,
                          iconColor: AppColors.error,
                          labelColor: AppColors.error,
                          onTap: controller.logout,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Scrole',
                        style: AppTextStyles.caption.copyWith(color: textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Header
// =========================================================================

class _Header extends StatelessWidget {
  const _Header({required this.textPrimary});

  final Color textPrimary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: textPrimary),
          ),
          const SizedBox(width: 4),
          Text('settings_title'.tr, style: AppTextStyles.h3.copyWith(color: textPrimary)),
        ],
      ),
    );
  }
}

// =========================================================================
// Search field
// =========================================================================

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppTextStyles.input.copyWith(color: textPrimary),
      decoration: InputDecoration(
        hintText: 'settings_search_hint'.tr,
        hintStyle: AppTextStyles.inputHint.copyWith(color: textSecondary),
        prefixIcon: Icon(Icons.search_rounded, color: textSecondary),
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}

// =========================================================================
// Section label
// =========================================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: AppTextStyles.overline.copyWith(color: color),
      ),
    );
  }
}

// =========================================================================
// Card container grouping tiles
// =========================================================================

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.children,
    this.surface,
    this.border,
  });

  final List<Widget> children;
  final Color? surface;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border ?? AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, thickness: 1, color: (border ?? AppColors.border).withValues(alpha: .6)),
          ],
        ],
      ),
    );
  }
}

// =========================================================================
// Single settings row
// =========================================================================

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconBg,
    this.iconColor,
    this.labelColor,
    this.trailingText,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconBg;
  final Color? iconColor;
  final Color? labelColor;
  final String? trailingText;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final secondaryColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg ?? Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 20,
                color: iconColor ?? (iconBg != null ? AppColors.white : secondaryColor),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: labelColor ?? defaultTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge!,
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.white),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: AppTextStyles.bodySmall.copyWith(color: secondaryColor),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right_rounded, color: secondaryColor, size: 20),
          ],
        ),
      ),
    );
  }
}