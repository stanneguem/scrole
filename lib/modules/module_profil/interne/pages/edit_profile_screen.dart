import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/widgets/birth_date_picker_field.dart';
import 'package:scrole/shared/widgets/city_selected_screen.dart';
import 'package:scrole/shared/widgets/gender_selector_field.dart';
import 'package:scrole/shared/widgets/location_picker_section.dart';
import 'package:scrole/shared/widgets/text_input_field.dart';
import 'package:scrole/modules/module_activite/interne/widgets/interest_chip_widget.dart';
import 'package:scrole/modules/module_profil/interne/controllers/edit_profil_controller.dart';

class EditProfileScreen extends GetView<EditProfileController> {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'edit_profile_title'.tr,
          style: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
        ),
        actions: [
          Obx(
            () => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: controller.isSaving.value
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: controller.save,
                      child: Text(
                        'edit_profile_save'.tr,
                        style: AppTextStyles.buttonSmall.copyWith(color: colorScheme.primary),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: controller.formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLockedField(
                  label: 'username'.tr,
                  lockedValueBuilder: () => controller.usernameController.text,
                  isLocked: controller.canChangeUsername,
                  daysLeft: controller.usernameDaysLeft,
                  builder: () => TextInputField(
                    controller: controller.usernameController,
                    imputTitle: 'username'.tr,
                    impuHintText: 'username_hint'.tr,
                    imputIcon: const Icon(Icons.alternate_email),
                    func: controller.validateRequired,
                  ),
                ),
                const SizedBox(height: 16),
                TextInputField(
                  controller: controller.prenomController,
                  imputTitle: 'edit_profile_first_name'.tr,
                  impuHintText: 'edit_profile_first_name_hint'.tr,
                  imputIcon: const Icon(Icons.person_outline),
                  func: controller.validateRequired,
                ),
                const SizedBox(height: 16),
                TextInputField(
                  controller: controller.nomController,
                  imputTitle: 'edit_profile_last_name'.tr,
                  impuHintText: 'edit_profile_last_name_hint'.tr,
                  imputIcon: const Icon(Icons.badge_outlined),
                  func: controller.validateRequired,
                ),
                const SizedBox(height: 16),
                TextInputField(
                  controller: controller.bioController,
                  imputTitle: 'edit_profile_bio'.tr,
                  impuHintText: 'edit_profile_bio_hint'.tr,
                  imputIcon: const Icon(Icons.description_outlined),
                  func: (_) => null,
                  maxLines: 4,
                ),
                const SizedBox(height: 24),

                // --- CENTRES D'INTÉRÊT ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'interests_title'.tr,
                      style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface),
                    ),
                    TextButton(
                      onPressed: controller.goToInterestSelection,
                      child: Text(
                        'interests_modify'.tr,
                        style: TextStyle(color: colorScheme.primary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                Obx(() {
                  if (controller.isLoadingInterests.value) {
                    return const SizedBox(
                      height: 40,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }

                  if (controller.selectedInterestIds.isEmpty) {
                    return InkWell(
                      onTap: controller.goToInterestSelection,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outline.withOpacity(0.5)),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.add_circle_outline, color: colorScheme.outline, size: 28),
                            const SizedBox(height: 8),
                            Text(
                              'interests_empty_description'.tr,
                              style: AppTextStyles.caption.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Affichage simplifié des intérêts sélectionnés
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: controller.selectedInterestIds.map((id) {
                      final interest = controller.allInterests.firstWhereOrNull((i) => i.id == id);
                      if (interest == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (interest.iconUrl != null) ...[
                              Text(interest.iconUrl!, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '#${interest.name}',
                              style: AppTextStyles.labelSmall.copyWith(color: colorScheme.primary),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                }),

                const SizedBox(height: 24),
                _buildLockedField(
                  label: 'edit_profile_gender'.tr,
                  lockedValueBuilder: () => controller.selectedGender.value ?? '—',
                  isLocked: controller.canChangeGender,
                  daysLeft: controller.genderDaysLeft,
                  builder: () => GenderSelectorField(
                    selectedGender: controller.selectedGender.value,
                    onChanged: controller.onGenderChanged,
                  ),
                ),
                const SizedBox(height: 16),
                _buildLockedField(
                  label: 'edit_profile_birth_date'.tr,
                  lockedValueBuilder: () {
                    final date = controller.selectedBirthDate.value;
                    return date == null ? '—' : DateFormat('dd/MM/yyyy').format(date);
                  },
                  isLocked: controller.canChangeBirthDate,
                  daysLeft: controller.birthDateDaysLeft,
                  builder: () => BirthDatePickerField(
                    selectedDate: controller.selectedBirthDate.value,
                    onChanged: (v) => controller.selectedBirthDate.value = v,
                  ),
                ),
                const SizedBox(height: 24),
                _buildLockedField(
                  label: 'edit_profile_location_hint'.tr,
                  lockedValueBuilder: () {
                    final country = controller.selectedCountry.value?.nom ?? '';
                    final city = controller.selectedCity.value?.nom ?? '';
                    final location = [city, country].where((value) => value.trim().isNotEmpty).join(', ');
                    return location.isEmpty ? '—' : location;
                  },
                  isLocked: controller.canChangeLocation,
                  daysLeft: controller.locationDaysLeft,
                  builder: () => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_clock_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'edit_profile_location_hint'.tr,
                              style: AppTextStyles.caption.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CountrySelectorField(
                        countries: controller.countries,
                        selectedCountry: controller.selectedCountry.value,
                        isLoading: controller.isLoadingCountries.value,
                        onChanged: controller.onCountryChanged,
                      ),
                      const SizedBox(height: 16),
                      CitySelectorField(
                        cities: controller.cities,
                        selectedCity: controller.selectedCity.value,
                        enabled: controller.selectedCountry.value != null,
                        isLoading: controller.isLoadingCities.value,
                        onChanged: controller.onCityChanged,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockedField({
    required String label,
    String Function()? lockedValueBuilder,
    required RxBool isLocked,
    required RxInt daysLeft,
    required Widget Function() builder,
  }) {
    return Obx(() {
      final canModify = isLocked.value;
      if (!controller.lockMetadataLoaded.value) {
        final colors = Theme.of(Get.context!).colorScheme;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withOpacity(0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 5),
                    Text(
                      controller.lockMetadataFailed.value
                          ? 'edit_profile_lock_check_failed'.tr
                          : 'edit_profile_checking_lock'.tr,
                      style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (controller.lockMetadataFailed.value)
                Icon(Icons.lock_outline, size: 18, color: colors.error)
              else
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        );
      }
      if (!canModify && lockedValueBuilder != null) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(Get.context!).colorScheme.surfaceContainerHighest.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(Get.context!).colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.caption.copyWith(
                      color: Theme.of(Get.context!).colorScheme.onSurfaceVariant,
                    )),
                    const SizedBox(height: 5),
                    Text(
                      lockedValueBuilder(),
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: Theme.of(Get.context!).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'edit_profile_locked_label'.trParams({'days': daysLeft.value.toString()}),
                      style: AppTextStyles.caption.copyWith(color: AppColors.error),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.lock_outline, size: 18, color: Theme.of(Get.context!).colorScheme.onSurfaceVariant),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AbsorbPointer(
            absorbing: !canModify,
            child: Opacity(opacity: canModify ? 1.0 : 0.6, child: builder()),
          ),
        ],
      );
    });
  }
}
