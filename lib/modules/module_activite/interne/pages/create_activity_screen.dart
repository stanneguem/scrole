import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../controllers/create_activity_controller.dart';

class CreateActivityScreen extends GetView<CreateActivityController> {
  const CreateActivityScreen({super.key});

  void _showUsagePickerSheet(BuildContext context) {
    ScroleBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Utilisation de l\'activité', style: AppTextStyles.h4),
          ),
          ScroleBottomSheetGroup(
            children: [
              ScroleBottomSheetAction(
                icon: Icons.event_note_rounded,
                label: 'Uniquement pour cet événement',
                subtitle: 'L\'activité reste contextualisée à cet événement',
                onTap: () {
                  controller.isEventOnly.value = true;
                  Get.back();
                },
              ),
              const ScroleBottomSheetDivider(),
              ScroleBottomSheetAction(
                icon: Icons.public_rounded,
                label: 'Disponible sur Scrole',
                subtitle: 'L\'activité peut être réutilisée dans d\'autres événements',
                onTap: () {
                  controller.isEventOnly.value = false;
                  Get.back();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text(
          'create_activity_title'.tr,
          style: AppTextStyles.h3.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Obx(() {
            if (controller.isCreating.value) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: controller.createActivity,
                child: Text(
                  'create_activity_submit'.tr,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Form(
          key: controller.formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section Titre
              Text(
                'create_activity_general_info'.tr,
                style: AppTextStyles.h4.copyWith(
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Champ Nom de l'activité
              _buildTextField(
                controller: controller.titleController,
                label: 'create_activity_name_label'.tr,
                hint: 'create_activity_name_hint'.tr,
                icon: Icons.title_rounded,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'create_activity_err_title_req'.tr;
                  }
                  if (value.trim().length < 3) {
                    return 'create_activity_err_title_short'.tr;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Champ Description de l'activité
              _buildTextField(
                controller: controller.descriptionController,
                label: 'Description (optionnel)',
                hint: 'Décrivez ce que propose cette activité...',
                icon: Icons.description_outlined,
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Champ Prix + Sélecteur de Devise
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: controller.priceController,
                      label: 'create_activity_price_label'.tr,
                      hint: '0',
                      icon: Icons.monetization_on_outlined,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'create_activity_err_price_req'.tr;
                        }
                        final price = double.tryParse(value);
                        if (price == null || price < 0) {
                          return 'create_activity_err_price_invalid'.tr;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Devise',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Obx(() {
                          final list = controller.availableCurrencies;
                          final selectedCode = controller.selectedCurrencyCode.value;
                          final validCode = list.any((c) => c.code == selectedCode)
                              ? selectedCode
                              : (list.isNotEmpty ? list.first.code : 'XAF');

                          return Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceDark : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark ? AppColors.border : AppColors.border,
                                width: 1,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: validCode,
                                isExpanded: true,
                                dropdownColor: isDark ? AppColors.surfaceDark : AppColors.surface,
                                style: AppTextStyles.input.copyWith(
                                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                                  fontSize: 13.5,
                                ),
                                items: list.map((c) {
                                  return DropdownMenuItem<String>(
                                    value: c.code,
                                    child: Text(
                                      '${c.symbol} (${c.code})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    controller.selectedCurrencyCode.value = val;
                                  }
                                },
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sélecteur d'utilisation de l'activité (§26 & §27)
              Text(
                'Utilisation de l\'activité',
                style: AppTextStyles.labelLarge.copyWith(
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Obx(() => InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showUsagePickerSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceDark : AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? AppColors.border : AppColors.border,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            controller.isEventOnly.value ? Icons.event_note_rounded : Icons.public_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  controller.isEventOnly.value
                                      ? 'Uniquement pour cet événement'
                                      : 'Disponible sur Scrole',
                                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  controller.isEventOnly.value
                                      ? 'L\'activité reste liée au contexte de cet événement'
                                      : 'L\'activité peut être réutilisée par d\'autres événements',
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper pour construire des champs de texte fins et élégants
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final isDark = Get.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: AppTextStyles.input.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.inputHint.copyWith(
              color: AppColors.textSecondary,
            ),
            prefixIcon: Icon(
              icon,
              color: AppColors.primary,
              size: 20,
            ),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? AppColors.border : AppColors.border,
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? AppColors.border : AppColors.border,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}
