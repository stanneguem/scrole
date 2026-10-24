import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/service_global/language_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';

/// Écran listant toutes les langues disponibles dans l'application.
///
/// Tape sur une langue pour l'appliquer immédiatement via [LocaleService] :
/// toute l'UI se retraduit sans redémarrage. La langue active est cochée.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final LocaleService localeService = Get.find<LocaleService>();
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
              child: Obx(() {
                final currentCode = localeService.locale.languageCode;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: LocaleService.supportedLanguages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final lang = LocaleService.supportedLanguages[index];
                    final selected = lang.code == currentCode;
                    return _LanguageTile(
                      label: lang.nativeName,
                      selected: selected,
                      surface: surface,
                      border: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      onTap: () => localeService.changeLocale(lang.code),
                    );
                  },
                );
              }),
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
            onPressed: () => Get.back(),
            icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          ),
          const SizedBox(width: 4),
          Text('settings_language'.tr, style: AppTextStyles.h3.copyWith(color: textPrimary)),
        ],
      ),
    );
  }
}

// =========================================================================
// Language row
// =========================================================================

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.selected,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? AppColors.primary : textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
