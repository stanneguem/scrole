import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/text_input_field.dart';
import '../../../../shared/widgets/location_picker_section.dart';
import '../../../../shared/widgets/city_selected_screen.dart';
import '../../../../shared/widgets/image_source_sheet.dart';
import '../controllers/create_event_controller.dart';

class EventCreationScreen extends GetView<CreateEventController> {
  const EventCreationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'event_create_title'.tr,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        leading: Obx(() {
          final step = controller.currentStep.value;
          return IconButton(
            icon: Icon(step > 0 ? Icons.arrow_back_ios_new_rounded : Icons.close),
            onPressed: () {
              if (step > 0) {
                controller.previousStep();
              } else {
                Get.back();
              }
            },
          );
        }),
        actions: [
          Obx(() {
            final step = controller.currentStep.value;
            final isValid = _isStepValid(step);
            final isLoading = controller.isLoading.value;

            if (isLoading) {
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

            final isLastStep = (step == 3);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: isValid
                    ? (isLastStep ? controller.createEvent : controller.nextStep)
                    : null,
                child: Text(
                  isLastStep ? 'event_create_confirm'.tr : 'event_create_next'.tr,
                  style: TextStyle(
                    color: isValid ? AppColors.primary : AppColors.disabled,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
      body: PageView(
        controller: controller.pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (idx) => controller.currentStep.value = idx,
        children: [
          _BasicInfoStep(),
          _LocationStep(),
          _DatesStep(),
          _SummaryStep(),
        ],
      ),
    );
  }

  bool _isStepValid(int step) {
    if (step == 0) return controller.isBasicInfoValid;
    if (step == 1) return controller.isLocationValid;
    if (step == 2) return controller.isDatesValid;
    return true;
  }
}

/// Helper générique pour créer une rangée d'option style iOS (CupertinoSwitch)
Widget _buildIosToggleRow({
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  final isDark = Get.isDarkMode;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: isDark ? AppColors.surfaceDark : Colors.grey[100],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isDark ? AppColors.border : Colors.grey[200]!,
        width: 1,
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.labelLarge.copyWith(
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Transform.scale(
          scale: 0.85,
          child: CupertinoSwitch(
            value: value,
            activeColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );
}

class _BasicInfoStep extends GetView<CreateEventController> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('event_create_basic_info'.tr, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          _CoverPicker(),
          const SizedBox(height: 24),
          TextInputField(
            controller: controller.nameController,
            imputTitle: 'event_create_name_hint'.tr,
            imputIcon: const Icon(Icons.event),
            impuHintText: 'event_create_name_example'.tr,
            func: (v) => v == null || v.isEmpty ? 'field_required'.tr : null,
          ),
          const SizedBox(height: 16),
          TextInputField(
            controller: controller.slugController,
            imputTitle: 'event_create_slug_hint'.tr,
            imputIcon: const Icon(Icons.link),
            impuHintText: 'event_create_slug_example'.tr,
            func: (v) => v == null || v.isEmpty ? 'field_required'.tr : null,
          ),
          const SizedBox(height: 16),
          TextInputField(
            controller: controller.descriptionController,
            imputTitle: 'event_create_desc_hint'.tr,
            imputIcon: const Icon(Icons.description_outlined),
            impuHintText: 'event_create_desc_example'.tr,
            maxLines: 4,
            func: (v) => null,
          ),
          const SizedBox(height: 20),
          // Section §3: Ancienneté de l'événement
          Obx(() => _buildIosToggleRow(
            title: 'Cet événement est-il récent ?',
            subtitle: controller.isRecent.value
                ? 'Oui, c\'est un nouvel événement'
                : 'Non, cet événement existe déjà depuis un certain temps',
            value: controller.isRecent.value,
            onChanged: (v) => controller.isRecent.value = v,
          )),
          Obx(() {
            if (!controller.isRecent.value) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _DateTimePicker(
                label: 'Date d\'origine de l\'événement',
                onSelected: (d) => controller.realCreatedAt.value = d,
                selectedDate: controller.realCreatedAt,
                showTime: false,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CoverPicker extends GetView<CreateEventController> {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final file = controller.coverFile.value;
      return Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          image: file != null ? DecorationImage(image: FileImage(file), fit: BoxFit.cover) : null,
        ),
        child: InkWell(
          onTap: () => showImageSourceSheet(
            context,
            onCamera: () => controller.pickImage(ImageSource.camera),
            onGallery: () => controller.pickImage(ImageSource.gallery),
            onRemove: file != null ? controller.removeCover : null,
          ),
          borderRadius: BorderRadius.circular(16),
          child: file == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_a_photo_outlined, size: 32, color: AppColors.textSecondary),
                    const SizedBox(height: 8),
                    Text('event_create_cover'.tr, style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      );
    });
  }
}

class _LocationStep extends GetView<CreateEventController> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Localisation de l\'événement', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          Obx(() => _buildIosToggleRow(
            title: 'Comment se déroule l\'événement ?',
            subtitle: controller.isVirtual.value
                ? 'Événement virtuel (en ligne)'
                : 'Événement physique (sur place)',
            value: controller.isVirtual.value,
            onChanged: (v) => controller.isVirtual.value = v,
          )),
          const SizedBox(height: 16),
          Obx(() {
            if (controller.isVirtual.value) {
              // Section Virtuelle (§6)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextInputField(
                    controller: controller.onlineUrlController,
                    imputTitle: 'Lien / canal de l\'événement (Google Meet, Zoom, Discord...)',
                    imputIcon: const Icon(Icons.link_rounded),
                    impuHintText: 'https://...',
                    func: (v) => (v == null || v.trim().isEmpty) ? 'Le lien de l\'événement virtuel est obligatoire' : null,
                  ),
                ],
              );
            } else {
              // Section Physique (§7)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 16),
                  TextInputField(
                    controller: controller.addressController,
                    imputTitle: 'Adresse physique',
                    imputIcon: const Icon(Icons.location_on_outlined),
                    impuHintText: 'Ex: Palais des Sports, Rue 1.024...',
                    func: (v) => (v == null || v.trim().isEmpty) ? 'L\'adresse est obligatoire pour un événement physique' : null,
                  ),
                ],
              );
            }
          }),
        ],
      ),
    );
  }
}

class _DatesStep extends GetView<CreateEventController> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('event_create_dates'.tr, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          Obx(() => controller.canUseIncludedCertification.value
              ? CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: controller.useIncludedCertification.value,
                  onChanged: (value) {
                    if (value != null) controller.setUseIncludedCertification(value);
                  },
                  title: const Text('Utiliser une certification d’événement incluse'),
                  subtitle: Text(
                    '${controller.remainingIncludedEvents.value} certification(s) incluse(s) restante(s). '
                    'Horizon : ${controller.certifiedEventHorizonMonths.value} mois.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                )
              : const SizedBox.shrink()),
          Obx(() => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              controller.useIncludedCertification.value
                  ? 'Événement certifié : la certification incluse sera consommée lors de la création. Horizon maximal ${controller.certifiedEventHorizonMonths.value} mois.'
                  : 'Événement non certifié : planification dans les ${controller.noncertEventHorizonMonths.value} prochains mois, durée maximale ${controller.noncertEventMaxDurationDays.value} jours.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )),
          Obx(() => _DateTimePicker(
            label: 'event_create_start'.tr,
            onSelected: controller.selectStartDate,
            selectedDate: controller.startDate,
            lastDate: controller.maxStartDate,
          )),
          const SizedBox(height: 16),
          Obx(() => _DateTimePicker(
            label: 'event_create_end'.tr,
            onSelected: (d) => controller.endDate.value = d,
            selectedDate: controller.endDate,
            firstDate: controller.startDate.value ?? DateTime.now(),
            lastDate: controller.maxEndDate,
          )),
        ],
      ),
    );
  }
}

class _DateTimePicker extends StatelessWidget {
  const _DateTimePicker({
    required this.label,
    required this.onSelected,
    required this.selectedDate,
    this.showTime = true,
    this.firstDate,
    this.lastDate,
  });
  final String label;
  final Function(DateTime) onSelected;
  final Rx<DateTime?> selectedDate;
  final bool showTime;
  final DateTime? firstDate;
  final DateTime? lastDate;

  Future<void> _pickDateTime(BuildContext context) async {
    final minDate = firstDate ?? DateTime(1900);
    final maxDate = lastDate ?? DateTime.now().add(const Duration(days: 365 * 10));
    final candidate = selectedDate.value ?? DateTime.now();
    final initial = candidate.isBefore(minDate)
        ? minDate
        : candidate.isAfter(maxDate) ? maxDate : candidate;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minDate,
      lastDate: maxDate,
    );
    if (d == null || !context.mounted) return;

    if (showTime) {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (t != null) {
        onSelected(DateTime(d.year, d.month, d.day, t.hour, t.minute));
      }
    } else {
      onSelected(d);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final date = selectedDate.value;
      return InkWell(
        onTap: () => _pickDateTime(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text(
                    date != null ? (showTime ? date.toString().substring(0, 16) : date.toString().substring(0, 10)) : 'select'.tr,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _SummaryStep extends GetView<CreateEventController> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('event_create_preview'.tr, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          _SummaryItem(label: 'Nom de l\'événement', value: controller.name.value),
          _SummaryItem(
            label: 'Ancienneté',
            value: controller.isRecent.value
                ? 'Nouvel événement (Origine: ${controller.realCreatedAt.value?.toString().substring(0, 10) ?? 'Non spécifiée'})'
                : 'Événement existant',
          ),
          _SummaryItem(
            label: 'Localisation', 
            value: controller.isVirtual.value 
              ? 'Virtuel (${controller.onlineUrlController.text.trim()})' 
              : '${controller.addressController.text.trim()}, ${controller.selectedCity.value?.nom ?? ''}, ${controller.selectedCountry.value?.nom ?? ''}',
          ),
          _SummaryItem(label: 'Date de début', value: controller.startDate.value?.toString().substring(0, 16) ?? ''),
          if (controller.endDate.value != null)
            _SummaryItem(label: 'Date de fin', value: controller.endDate.value?.toString().substring(0, 16) ?? ''),
          const SizedBox(height: 20),
          Obx(() => _buildIosToggleRow(
            title: 'event_create_free_title'.tr,
            subtitle: 'event_create_free_sub'.tr,
            value: controller.isFree.value,
            onChanged: (v) => controller.isFree.value = v,
          )),
          Obx(() => _buildIosToggleRow(
            title: 'event_create_public_title'.tr,
            subtitle: 'event_create_public_sub'.tr,
            value: controller.isPublic.value,
            onChanged: (v) => controller.isPublic.value = v,
          )),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Une fois créé, votre événement sera au statut "En attente de validation admin" avant sa publication publique.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
