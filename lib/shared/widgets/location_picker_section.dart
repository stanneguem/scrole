import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/text_styles.dart';
import '../../app/repository_global/location_repository.dart';

class CountrySelectorField extends StatelessWidget {
  const CountrySelectorField({
    super.key,
    required this.countries,
    required this.onChanged,
    this.selectedCountry,
    this.isLoading = false,
  });

  /// Pays disponibles (déjà filtrés `is_active = true` côté repository).
  final List<LocationOption> countries;

  /// Appelé avec le pays choisi.
  final ValueChanged<LocationOption> onChanged;

  /// Pays actuellement sélectionné, ou null.
  final LocationOption? selectedCountry;

  /// Affiche un indicateur de chargement à la place du champ tant que
  /// la liste des pays n'est pas encore arrivée.
  final bool isLoading;

  static String flagEmoji(String? isoCode) {
    if (isoCode == null || isoCode.length != 2) return '';
    return isoCode.toUpperCase().codeUnits
        .map((c) => String.fromCharCode(0x1F1E6 + (c - 65)))
        .join();
  }

  Future<void> _pickCountry(BuildContext context) async {
    if (isLoading || countries.isEmpty) return;

    final picked = await showModalBottomSheet<LocationOption>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _CountrySearchSheet(
        countries: countries,
        selectedCountry: selectedCountry,
      ),
    );

    if (picked != null) {
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pickCountry(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'country'.tr,
          labelStyle: AppTextStyles.labelLarge,
          prefixIcon: const Icon(Icons.public_outlined),
          border: const OutlineInputBorder(),
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
          selectedCountry != null
              ? '${flagEmoji(selectedCountry!.codeIso)}  ${selectedCountry!.nom}'
              : 'country'.tr,
          style: selectedCountry == null ? AppTextStyles.labelLarge : null,
        ),
      ),
    );
  }
}

class _CountrySearchSheet extends StatefulWidget {
  const _CountrySearchSheet({
    required this.countries,
    required this.selectedCountry,
  });

  final List<LocationOption> countries;
  final LocationOption? selectedCountry;

  @override
  State<_CountrySearchSheet> createState() => _CountrySearchSheetState();
}

class _CountrySearchSheetState extends State<_CountrySearchSheet> {
  final _searchController = TextEditingController();
  late List<LocationOption> _filtered = widget.countries;

  void _onSearchChanged(String query) {
    final normalized = query.trim().toLowerCase();
    setState(() {
      _filtered = normalized.isEmpty
          ? widget.countries
          : widget.countries
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
                  hintText: 'search_country'.tr,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintStyle: AppTextStyles.bodyLarge,
                ),
              ),
            ),
            Flexible(
              child: _filtered.isEmpty
                  ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'no_country_found'.tr,
                  style: AppTextStyles.bodyLarge,
                ),
              )
                  : ListView.builder(
                shrinkWrap: true,
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final country = _filtered[index];
                  final isSelected =
                      country.id == widget.selectedCountry?.id;
                  return ListTile(
                    leading: Text(
                      CountrySelectorField.flagEmoji(country.codeIso),
                      style: const TextStyle(fontSize: 22),
                    ),
                    title: Text(country.nom),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                        color: Colors.green)
                        : null,
                    onTap: () => Navigator.pop(context, country),
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