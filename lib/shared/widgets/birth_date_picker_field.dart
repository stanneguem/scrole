import 'package:flutter/material.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';

import '../../app/theme/text_styles.dart';

class BirthDatePickerField extends StatelessWidget {
  const BirthDatePickerField({
    super.key,
    required this.selectedDate,
    required this.onChanged,
    this.minimumAge = 13,
  });

  /// Date actuellement sélectionnée, ou null si aucune.
  final DateTime? selectedDate;

  /// Appelé avec la date choisie une fois le picker validé.
  final ValueChanged<DateTime> onChanged;

  /// Âge minimum autorisé (borne la date la plus récente sélectionnable).
  final int minimumAge;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final initialDate =
        selectedDate ?? DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - minimumAge, now.month, now.day),
      helpText: 'date_of_birth'.tr,
    );

    if (picked != null) {
      onChanged(picked);
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  /// Calcule l'âge en années révolues à partir de la date de naissance.
  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    final hasHadBirthdayThisYear =
        (now.month > birthDate.month) ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!hasHadBirthdayThisYear) age--;
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final hasDate = selectedDate != null;

    return InkWell(
      onTap: () => _pickDate(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'date_of_birth'.tr,
          labelStyle: AppTextStyles.labelLarge,
          prefixIcon: const Icon(Icons.cake_outlined),
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Text(
              hasDate ? _formatDate(selectedDate!) : 'date_of_birth'.tr,
              style: hasDate ? null : AppTextStyles.labelLarge,
            ),
            if (hasDate) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_calculateAge(selectedDate!)} ans',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
