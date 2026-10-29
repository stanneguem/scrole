import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:scrole/app/routes/app_pages.dart';
import '../../../../app/service_global/currency_service.dart';
import '../../../../app/repository_global/currency_repository.dart';
import '../../centre/models/activity_creation_data.dart';
import '../../centre/services/activity_service.dart';

class CreateActivityController extends GetxController {
  final ActivityService _activityService = Get.find<ActivityService>();
  final CurrencyService currencyService = Get.find<CurrencyService>();

  final String? eventId = Get.arguments is Map ? Get.arguments['eventId']?.toString() : null;

  // Form
  final formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final priceController = TextEditingController();

  // Devise sélectionnée
  final selectedCurrencyCode = 'XAF'.obs;

  // Utilisation : Event-Only vs Globale
  final isEventOnly = false.obs;

  // Observables
  final isLoading = false.obs;
  final isCreating = false.obs;

  @override
  void onInit() {
    super.onInit();
    selectedCurrencyCode.value = currencyService.defaultCurrencyCode;
    isEventOnly.value = (eventId != null && eventId!.isNotEmpty);
    _initDefaultCurrencyForCountry();
  }

  Future<void> _initDefaultCurrencyForCountry() async {
    try {
      final defaultCode = await currencyService.getDefaultCurrencyForCountry(null);
      selectedCurrencyCode.value = defaultCode;
    } catch (_) {}
  }

  List<CurrencyModel> get availableCurrencies => currencyService.currencies;

  /// Valide le formulaire
  bool validateForm() {
    return formKey.currentState?.validate() ?? false;
  }

  /// Crée l'activité
  Future<void> createActivity() async {
    if (!validateForm()) return;

    try {
      isCreating.value = true;

      final data = ActivityCreationData(
        title: titleController.text.trim(),
        description: descriptionController.text.trim(),
        priceGeneral: double.tryParse(priceController.text) ?? 0.0,
        currencyCode: selectedCurrencyCode.value,
        interestIds: const [],
      );

      // 1. Création de l'activité
      final activity = await _activityService.createActivity(
        data,
        eventOnly: isEventOnly.value,
        eventId: eventId,
      );

      Get.back();
      Get.snackbar(
        'Activité créée',
        'Votre activité "${activity.name}" a été créée avec succès.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      Get.snackbar(
        'error'.tr,
        '${'Impossible de créer l\'activité'}: ${e.toString()}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      isCreating.value = false;
    }
  }

  @override
  void onClose() {
    titleController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    super.onClose();
  }
}
