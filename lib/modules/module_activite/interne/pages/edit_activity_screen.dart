import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import '../../../../app/service_global/currency_service.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/services/activity_service.dart';

class EditActivityScreen extends StatefulWidget {
  final Activity activity;
  final bool isManagerOnly;

  const EditActivityScreen({
    super.key,
    required this.activity,
    this.isManagerOnly = false,
  });

  @override
  State<EditActivityScreen> createState() => _EditActivityScreenState();
}

class _EditActivityScreenState extends State<EditActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late String _currencyCode;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.activity.name);
    _descriptionController = TextEditingController(text: widget.activity.description ?? '');
    _priceController = TextEditingController(
      text: widget.activity.basePrice > 0 ? widget.activity.basePrice.toString() : '',
    );
    _currencyCode = widget.activity.currencyCode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;

    setState(() => _isSaving = true);

    final service = Get.find<ActivityService>();
    await service.updateActivity(
      id: widget.activity.id,
      name: name,
      description: description,
      basePrice: price,
      currencyCode: _currencyCode,
    );

    Get.back();
    Get.snackbar(
      'Activité modifiée',
      'Votre activité a été mise à jour !',
      backgroundColor: Colors.black87,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final colorScheme = Theme.of(context).colorScheme;
    final currencyService = Get.isRegistered<CurrencyService>()
        ? Get.find<CurrencyService>()
        : null;

    final availableCurrencies = currencyService?.currencies ?? const [];
    final validCode = availableCurrencies.any((c) => c.code == _currencyCode)
        ? _currencyCode
        : (availableCurrencies.isNotEmpty ? availableCurrencies.first.code : _currencyCode);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Modifier l\'activité'),
        titleTextStyle: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 28),
          onPressed: () => Get.back(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _isSaving ? null : _save,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Enregistrer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Informations de l\'activité',
                  style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 16),

                // Champ Nom
                Text(
                  'Nom de l\'activité',
                  style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  style: AppTextStyles.input.copyWith(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.title_rounded, color: AppColors.primary, size: 20),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceDark : AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom obligatoire' : null,
                ),
                const SizedBox(height: 16),

                // Champ Description
                Text(
                  'Description',
                  style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  style: AppTextStyles.input.copyWith(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.description_outlined, color: AppColors.primary, size: 20),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceDark : AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),

                // Champ Prix + Devise dynamique depuis public.currencies
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Prix', style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _priceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: AppTextStyles.input.copyWith(color: colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: '0',
                              prefixIcon: const Icon(Icons.monetization_on_outlined, color: AppColors.primary, size: 20),
                              filled: true,
                              fillColor: isDark ? AppColors.surfaceDark : AppColors.surface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Devise', style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface)),
                          const SizedBox(height: 6),
                          Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceDark : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? AppColors.border : AppColors.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: validCode,
                                isExpanded: true,
                                dropdownColor: isDark ? AppColors.surfaceDark : AppColors.surface,
                                style: AppTextStyles.input.copyWith(color: colorScheme.onSurface, fontSize: 13.5),
                                items: availableCurrencies.map<DropdownMenuItem<String>>((c) {
                                  return DropdownMenuItem<String>(
                                    value: c.code,
                                    child: Text('${c.symbol} (${c.code})', overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _currencyCode = val);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
