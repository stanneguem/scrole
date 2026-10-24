import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/text_styles.dart';
import '../models/target_country.dart';

class TargetCountrySelector extends StatelessWidget {
  const TargetCountrySelector({
    super.key,
    required this.countries,
    required this.selectedCountryId,
    required this.onChanged,
    this.isLoading = false,
  });

  /// Pays disponibles à afficher dans le dropdown.
  final List<TargetCountry> countries;

  /// `packageName` du pays actuellement sélectionné (null si aucun).
  final String? selectedCountryId;

  /// Appelé avec le pays choisi quand l'utilisateur sélectionne une option.
  final ValueChanged<TargetCountry> onChanged;

  /// Affiche une barre de chargement à la place du dropdown pendant que
  /// la liste des pays est récupérée.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const LinearProgressIndicator();
    }

    final matches = countries.where((c) => c.packageName == selectedCountryId);
    final currentValue = matches.isEmpty ? null : matches.first;

    return DropdownButtonFormField<TargetCountry>(
      value: currentValue,
      decoration: InputDecoration(
        labelText: 'Pays',
        labelStyle: AppTextStyles.labelLarge,
        prefixIcon: const Icon(Icons.public_outlined),
        border: const OutlineInputBorder(),
      ),
      items: countries
          .map(
            (country) => DropdownMenuItem<TargetCountry>(
          value: country,
          child: Text(country.displayName),
        ),
      )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      validator: (value) => value == null ? 'country_required'.tr : null,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
  }
}