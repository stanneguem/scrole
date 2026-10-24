import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/text_styles.dart';
import '../../app/repository_global/location_repository.dart';

class CitySelectorField extends StatelessWidget {
  const CitySelectorField({
    super.key,
    required this.cities,
    required this.onChanged,
    required this.enabled,
    this.selectedCity,
    this.isLoading = false,
  });

  /// Villes du pays actuellement sélectionné (déjà filtrées côté
  /// repository : `country_id` + `is_active = true`).
  final List<LocationOption> cities;

  /// Appelé avec la ville choisie.
  final ValueChanged<LocationOption> onChanged;

  /// true si un pays est sélectionné — sinon le champ est désactivé.
  final bool enabled;

  /// Ville actuellement sélectionnée, ou null.
  final LocationOption? selectedCity;

  /// Affiche un indicateur de chargement pendant la récupération des
  /// villes du pays choisi.
  final bool isLoading;

  Future<void> _pickCity(BuildContext context) async {
    if (!enabled || isLoading) return;

    final picked = await showModalBottomSheet<LocationOption>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) =>
          _CitySearchSheet(cities: cities, selectedCity: selectedCity),
    );

    if (picked != null) {
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pickCity(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'city'.tr,
          labelStyle: AppTextStyles.labelLarge,
          prefixIcon: const Icon(Icons.location_city_outlined),
          border: const OutlineInputBorder(),
          enabled: enabled,
        ),
        child: isLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text('loading'.tr, style: AppTextStyles.labelLarge),
                ],
              )
            : Text(
                !enabled
                    ? 'select_country_first'.tr
                    : (selectedCity?.nom ?? 'city'.tr),
                style: (selectedCity == null || !enabled)
                    ? AppTextStyles.labelLarge
                    : null,
              ),
      ),
    );
  }
}

class _CitySearchSheet extends StatefulWidget {
  const _CitySearchSheet({required this.cities, required this.selectedCity});

  final List<LocationOption> cities;
  final LocationOption? selectedCity;

  @override
  State<_CitySearchSheet> createState() => _CitySearchSheetState();
}

class _CitySearchSheetState extends State<_CitySearchSheet> {
  final _searchController = TextEditingController();
  late List<LocationOption> _filtered = widget.cities;

  void _onSearchChanged(String query) {
    final normalized = query.trim().toLowerCase();
    setState(() {
      _filtered = normalized.isEmpty
          ? widget.cities
          : widget.cities
                .where((c) => c.nom.toLowerCase().contains(normalized))
                .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'search_city'.tr,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Flexible(
              child: _filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('no_city_found'.tr),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final city = _filtered[index];
                        final isSelected = city.id == widget.selectedCity?.id;
                        return ListTile(
                          title: Text(city.nom),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, city),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
