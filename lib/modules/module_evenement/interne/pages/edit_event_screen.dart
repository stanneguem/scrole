import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/text_input_field.dart';
import '../../../../shared/widgets/location_picker_section.dart';
import '../../../../shared/widgets/city_selected_screen.dart';
import '../../../../shared/widgets/image_source_sheet.dart';
import 'package:image_picker/image_picker.dart';
import '../controllers/edit_event_controller.dart';

class EditEventScreen extends GetView<EditEventController> {
  const EditEventScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'event_edit_info'.tr,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Obx(() => TextButton(
            onPressed: controller.isSaving.value ? null : controller.saveChanges,
            child: controller.isSaving.value 
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
          )),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverSection(),
            const SizedBox(height: 24),
            TextInputField(
              controller: controller.nameController,
              imputTitle: 'event_create_name_hint'.tr,
              imputIcon: const Icon(Icons.event),
              impuHintText: '',
              func: (v) => null,
            ),
            const SizedBox(height: 16),
            
            // Section Slug: Verrouillage basé exclusivement sur slug_locked_until
            TextInputField(
              controller: controller.slugController,
              imputTitle: controller.isSlugLocked
                  ? 'Slug (Verrouillé 🔒)'
                  : 'Slug',
              imputIcon: Icon(controller.isSlugLocked ? Icons.lock_outline_rounded : Icons.link),
              impuHintText: 'slug-evenement',
              readOnly: controller.isSlugLocked,
              enabled: !controller.isSlugLocked,
              func: (v) => null,
            ),
            if (controller.isSlugLocked)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Modification disponible dans ${controller.formattedRemainingSlugTime}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ),
            const SizedBox(height: 16),
            TextInputField(
              controller: controller.descriptionController,
              imputTitle: 'event_create_desc_hint'.tr,
              imputIcon: const Icon(Icons.description_outlined),
              impuHintText: '',
              maxLines: 4,
              func: (v) => null,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            _LocationSection(),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            _DateSection(),
          ],
        ),
      ),
    );
  }
}

class _CoverSection extends GetView<EditEventController> {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final file = controller.coverFile.value;
      final url = controller.currentCoverUrl.value;
      
      return Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          image: file != null 
            ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
            : (url.isNotEmpty ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null),
        ),
        child: InkWell(
          onTap: () => showImageSourceSheet(
            context,
            onCamera: () => controller.pickImage(ImageSource.camera),
            onGallery: () => controller.pickImage(ImageSource.gallery),
            onRemove: (file != null || url.isNotEmpty) ? controller.removeCover : null,
          ),
          child: (file == null && url.isEmpty)
              ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 32, color: AppColors.textSecondary))
              : const SizedBox.shrink(),
        ),
      );
    });
  }
}

class _LocationSection extends GetView<EditEventController> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Localisation', style: AppTextStyles.h5),
        const SizedBox(height: 16),
        Obx(() => SwitchListTile(
          title: Text('event_create_virtual'.tr),
          value: controller.isVirtual.value,
          onChanged: (v) => controller.isVirtual.value = v,
        )),
        const SizedBox(height: 16),
        Obx(() {
          if (controller.isVirtual.value) {
            return TextInputField(
              controller: controller.virtualLinkController,
              imputTitle: 'Lien virtuel (Zoom, Meet, Twitch...)',
              imputIcon: const Icon(Icons.link),
              impuHintText: 'https://...',
              func: (v) => null,
            );
          }
          return Column(
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
                imputTitle: 'event_create_address_hint'.tr,
                imputIcon: const Icon(Icons.location_on_outlined),
                impuHintText: '',
                func: (v) => null,
              ),
            ],
          );
        }),
      ],
    );
  }
}

class _DateSection extends GetView<EditEventController> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dates', style: AppTextStyles.h5),
        const SizedBox(height: 16),
        _DateTimePicker(
          label: 'event_create_start'.tr,
          onSelected: (d) => controller.startDate.value = d,
          selectedDate: controller.startDate,
        ),
        const SizedBox(height: 16),
        _DateTimePicker(
          label: 'event_create_end'.tr,
          onSelected: (d) => controller.endDate.value = d,
          selectedDate: controller.endDate,
        ),
      ],
    );
  }
}

class _DateTimePicker extends StatelessWidget {
  const _DateTimePicker({required this.label, required this.onSelected, required this.selectedDate});
  final String label;
  final Function(DateTime) onSelected;
  final Rx<DateTime?> selectedDate;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final date = selectedDate.value;
      return InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
          );
          if (d != null) {
            final t = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(date ?? DateTime.now()),
            );
            if (t != null) {
              onSelected(DateTime(d.year, d.month, d.day, t.hour, t.minute));
            }
          }
        },
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
                    date != null ? date.toString().substring(0, 16) : 'Sélectionner',
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
