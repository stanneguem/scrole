import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/text_styles.dart';

/// Valeurs de genre utilisées par le backend.
const List<String> availableGenders = ['homme', 'femme'];

class GenderSelectorField extends StatelessWidget {
  const GenderSelectorField({
    super.key,
    required this.selectedGender,
    required this.onChanged,
    this.genders = availableGenders,
  });

  /// Code actuellement sélectionné.
  /// Valeurs possibles : homme, femme.
  final String? selectedGender;

  /// Retourne le code choisi.
  final ValueChanged<String> onChanged;

  /// Liste des genres disponibles.
  final List<String> genders;

  /// Associe le code stocké en base à une clé de traduction.
  String translationKey(String code) {
    switch (code) {
      case 'homme':
        return 'gender_male';
      case 'femme':
        return 'gender_female';
      default:
        return 'gender_male';
    }
  }

  Future<void> _pickGender(BuildContext context) async {
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'gender_label'.tr,
                      style: AppTextStyles.labelLarge,
                    ),
                  ),
                ),

                ...genders.map((gender) {
                  final isSelected = selectedGender == gender;

                  return ListTile(
                    title: Text(translationKey(gender).tr),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, gender),
                  );
                }),

                if (selectedGender != null && selectedGender!.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.close),
                    title: Text('clear_selection'.tr),
                    onTap: () => Navigator.pop(sheetContext, ''),
                  ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null) {
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = selectedGender != null && selectedGender!.isNotEmpty;

    return InkWell(
      onTap: () => _pickGender(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'gender_label'.tr,
          labelStyle: AppTextStyles.labelLarge,
          prefixIcon: const Icon(Icons.wc_outlined),
          border: const OutlineInputBorder(),
        ),
        child: Text(
          hasValue ? translationKey(selectedGender!).tr : 'gender_label'.tr,
          style: hasValue ? null : AppTextStyles.labelLarge,
        ),
      ),
    );
  }
}
