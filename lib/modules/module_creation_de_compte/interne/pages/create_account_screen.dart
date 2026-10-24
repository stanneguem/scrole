import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:image_picker/image_picker.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/birth_date_picker_field.dart';
import '../../../../shared/widgets/city_selected_screen.dart';
import '../../../../shared/widgets/gender_selector_field.dart';
import '../../../../shared/widgets/image_source_sheet.dart';
import '../../../../shared/widgets/location_picker_section.dart';
import '../../../../shared/widgets/text_input_field.dart';
import '../controllers/create_account_controller.dart';
import '../enums/username_status.dart';

class CreateAccountScreen extends GetView<CreateAccountController> {
  const CreateAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: color.surface,
      appBar: AppBar(
        backgroundColor: color.surface,
        elevation: 0,
        title: Text(
          'create_new_account'.tr,
          style: AppTextStyles.h5,
        ),
        actions: [
          Obx(
                () => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: controller.isSubmitting.value
                    ? null
                    : controller.submit,
                style: TextButton.styleFrom(
                  foregroundColor: color.primary,
                  disabledForegroundColor:
                  color.onSurface.withValues(alpha: 0.35),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: controller.isSubmitting.value
                    ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: color.primary,
                  ),
                )
                    : Text(
                  'create_account_button'.tr,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: controller.formKey,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // ── HEADER : COUVERTURE & AVATAR ──
              _buildHeader(context, color),

              const SizedBox(height: 55),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Nom + Prénom ──
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextInputField(
                            controller: controller.surnameController,
                            imputTitle: 'last_name'.tr,
                            imputIcon: const Icon(Icons.person_2_outlined),
                            impuHintText: 'last_name'.tr,
                            func: controller.validateName,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextInputField(
                            controller: controller.nameController,
                            imputTitle: 'first_name'.tr,
                            imputIcon: const Icon(Icons.person_outline),
                            impuHintText: 'first_name'.tr,
                            func: controller.validateName,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Nom d'utilisateur ──
                    TextInputField(
                      controller: controller.usernameController,
                      imputTitle: 'username'.tr,
                      imputIcon: const Icon(Icons.alternate_email),
                      impuHintText: 'username_hint'.tr,
                      func: controller.validateUsername,
                    ),
                    const SizedBox(height: 6),
                    Obx(() => _UsernameStatusLabel(
                          status: controller.usernameStatus.value,
                        )),

                    const SizedBox(height: 20),

                    // ── PAYS : avec retry ──
                    Obx(() {
                      if (controller.isLoadingCountries.value) {
                        return const _LoadingTile(label: 'Chargement des pays...');
                      }

                      if (controller.countries.isEmpty && controller.isLoadingCountries.value == false) {
                        return _RetryTile(
                          label: 'Impossible de charger les pays',
                          onRetry: controller.retryLoadCountries,
                        );
                      }

                      return CountrySelectorField(
                        countries: controller.countries,
                        isLoading: false,
                        selectedCountry: controller.selectedCountry.value,
                        onChanged: controller.setCountry,
                      );
                    }),
                    const SizedBox(height: 16),

                    // ── VILLES : avec retry ──
                    Obx(() {
                      if (controller.selectedCountry.value == null) {
                        return const SizedBox.shrink();
                      }

                      if (controller.isLoadingCities.value) {
                        return const _LoadingTile(label: 'Chargement des villes...');
                      }

                      if (controller.isLoadingCities.value == false && controller.cities.isEmpty) {
                        return _RetryTile(
                          label: 'Impossible de charger les villes',
                          onRetry: controller.retryLoadCities,
                        );
                      }

                      return CitySelectorField(
                        cities: controller.cities,
                        isLoading: false,
                        enabled: controller.selectedCountry.value != null,
                        selectedCity: controller.selectedCity.value,
                        onChanged: controller.setCity,
                      );
                    }),
                    const SizedBox(height: 20),

                    // ── Date de naissance ──
                    Obx(() => BirthDatePickerField(
                          selectedDate: controller.selectedBirthDate.value,
                          onChanged: (DateTime value) {
                            controller.selectedBirthDate.value = value;
                            controller.formKey.currentState?.validate();
                          },
                        )),
                    const SizedBox(height: 20),

                    // ── Genre ──
                    Obx(() => GenderSelectorField(
                          selectedGender: controller.selectedGender.value,
                          onChanged: (String value) {
                            controller.selectedGender.value = value.isEmpty ? null : value;
                          },
                        )),

                    const SizedBox(height: 24),

                    // ── Erreur de soumission ──
                    Obx(() {
                      if (controller.submitError.value == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: color.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                controller.submitError.value!,
                                style: TextStyle(color: color.error, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // HEADER : COUVERTURE & AVATAR
  // ============================================
  Widget _buildHeader(BuildContext context, ColorScheme color) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── COUVERTURE ──
        GestureDetector(
          onTap: () => showImageSourceSheet(
            context,
            onCamera: () => controller.pickCover(ImageSource.camera),
            onGallery: () => controller.pickCover(ImageSource.gallery),
            onRemove: controller.coverFile.value != null ? controller.removeCover : null,
          ),
          child: Obx(() => Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: color.surfaceContainerHighest.withValues(alpha: 0.5),
                  image: controller.coverFile.value != null
                      ? DecorationImage(
                          image: FileImage(controller.coverFile.value!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: controller.coverFile.value == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, color: color.onSurfaceVariant.withValues(alpha: 0.5)),
                            const SizedBox(height: 4),
                            Text(
                              'Ajouter une couverture',
                              style: TextStyle(
                                fontSize: 11,
                                color: color.onSurfaceVariant.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
              )),
        ),

        // ── AVATAR (Chevauchement) ──
        Positioned(
          bottom: -45,
          left: 20,
          child: GestureDetector(
            onTap: () => showImageSourceSheet(
              context,
              onCamera: () => controller.pickAvatar(ImageSource.camera),
              onGallery: () => controller.pickAvatar(ImageSource.gallery),
              onRemove: controller.avatarFile.value != null ? controller.removeAvatar : null,
            ),
            child: Stack(
              children: [
                Obx(() => Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.surface,
                          width: 5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: color.surfaceContainerHighest,
                        backgroundImage: controller.avatarFile.value != null ? FileImage(controller.avatarFile.value!) : null,
                        child: controller.avatarFile.value == null
                            ? Icon(Icons.person_outline_rounded, size: 40, color: color.onSurfaceVariant.withValues(alpha: 0.5))
                            : null,
                      ),
                    )),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: color.surface, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
                Obx(() {
                  if (controller.isUploadingImage.value) {
                    return Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Widgets utilitaires ──

class _LoadingTile extends StatelessWidget {
  final String label;
  const _LoadingTile({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _RetryTile extends StatelessWidget {
  final String label;
  final VoidCallback onRetry;

  const _RetryTile({required this.label, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: color.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: color.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color.error, fontSize: 14),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

// ── Indicateur pseudo ──
class _UsernameStatusLabel extends StatelessWidget {
  final UsernameStatus status;
  const _UsernameStatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    late final IconData icon;
    late final Color color;
    late final String text;
    bool showSpinner = false;

    switch (status) {
      case UsernameStatus.idle:
        icon = Icons.info_outline;
        color = theme.colorScheme.onSurface.withValues(alpha: 0.5);
        text = 'Minimum 3 caractères';
        break;
      case UsernameStatus.checking:
        icon = Icons.hourglass_empty;
        color = theme.colorScheme.onSurface.withValues(alpha: 0.5);
        text = 'Vérification...';
        showSpinner = true;
        break;
      case UsernameStatus.available:
        icon = Icons.check_circle;
        color = Colors.green;
        text = 'Disponible';
        break;
      case UsernameStatus.taken:
        icon = Icons.cancel;
        color = Colors.redAccent;
        text = 'Déjà utilisé';
        break;
      case UsernameStatus.error:
        icon = Icons.error_outline;
        color = Colors.orangeAccent;
        text = 'Impossible de vérifier, réessaie';
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}