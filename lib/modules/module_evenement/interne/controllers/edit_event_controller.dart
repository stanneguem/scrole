import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/repository_global/location_repository.dart';
import '../../../../app/service_global/media_service.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../enums/event_enum.dart';
import 'package:image_picker/image_picker.dart';

class EditEventController extends GetxController {
  final EventModel event;
  final EventRepository _repository;

  EditEventController({
    required this.event,
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  final MediaService _mediaService = Get.find<MediaService>();

  // --- Données du formulaire ---
  late final TextEditingController nameController;
  late final TextEditingController slugController;
  late final TextEditingController descriptionController;
  late final TextEditingController virtualLinkController;
  final Rx<File?> coverFile = Rx<File?>(null);
  final RxString currentCoverUrl = ''.obs;

  final RxBool isVirtual = false.obs;
  final Rx<LocationOption?> selectedCountry = Rx<LocationOption?>(null);
  final Rx<LocationOption?> selectedCity = Rx<LocationOption?>(null);
  final RxList<LocationOption> countries = <LocationOption>[].obs;
  final RxList<LocationOption> cities = <LocationOption>[].obs;
  final RxBool isLoadingCountries = false.obs;
  final RxBool isLoadingCities = false.obs;
  
  late final TextEditingController addressController;

  final Rx<DateTime?> startDate = Rx<DateTime?>(null);
  final Rx<DateTime?> endDate = Rx<DateTime?>(null);
  final RxSet<String> selectedInterestIds = <String>{}.obs;
  
  final RxBool isSaving = false.obs;

  // --- Verrouillage du Slug basé sur slug_locked_until ---
  bool get isSlugLocked {
    if (event.slugLockedUntil != null) {
      return DateTime.now().isBefore(event.slugLockedUntil!);
    }
    return false;
  }

  bool get isSlugEditable => !isSlugLocked;

  Duration get remainingSlugTime {
    if (event.slugLockedUntil != null) {
      final diff = event.slugLockedUntil!.difference(DateTime.now());
      return diff.isNegative ? Duration.zero : diff;
    }
    return Duration.zero;
  }

  String get formattedRemainingSlugTime {
    final d = remainingSlugTime;
    if (d.inSeconds <= 0) return '';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return '$days jour${days > 1 ? 's' : ''}';
    if (hours > 0) return '$hours heure${hours > 1 ? 's' : ''}';
    return '$minutes minute${minutes > 1 ? 's' : ''}';
  }

  @override
  void onInit() {
    super.onInit();
    nameController = TextEditingController(text: event.name);
    slugController = TextEditingController(text: event.slug);
    descriptionController = TextEditingController(text: event.description);
    addressController = TextEditingController(text: event.address);
    virtualLinkController = TextEditingController(text: event.onlineUrl);
    currentCoverUrl.value = event.coverImageUrl ?? '';
    isVirtual.value = event.isOnline;
    startDate.value = event.startsAt;
    endDate.value = event.endsAt;

    _loadCountries();
  }

  Future<void> _loadCountries() async {
    isLoadingCountries.value = true;
    try {
      final repo = Get.find<LocationRepository>();
      final result = await repo.getCountries();
      countries.assignAll(result);

      if (event.countryId != null) {
        selectedCountry.value = result.firstWhereOrNull((c) => c.id == event.countryId);
        if (selectedCountry.value != null) {
          await _loadCities(selectedCountry.value!.id);
        }
      }
    } catch (e) {
      print('[Error] EditEventController._loadCountries: $e');
    } finally {
      isLoadingCountries.value = false;
    }
  }

  Future<void> _loadCities(String countryId) async {
    isLoadingCities.value = true;
    try {
      final repo = Get.find<LocationRepository>();
      final result = await repo.getCitiesForCountry(countryId);
      cities.assignAll(result);

      if (event.cityId != null) {
        selectedCity.value = result.firstWhereOrNull((c) => c.id == event.cityId);
      }
    } catch (e) {
      print('[Error] EditEventController._loadCities: $e');
    } finally {
      isLoadingCities.value = false;
    }
  }

  void onCountryChanged(LocationOption country) {
    if (selectedCountry.value?.id == country.id) return;
    selectedCountry.value = country;
    selectedCity.value = null;
    _loadCities(country.id);
  }

  void onCityChanged(LocationOption city) => selectedCity.value = city;

  Future<void> pickImage(ImageSource source) async {
    final file = await _mediaService.pickCoverImage(source: source);
    if (file != null) {
      coverFile.value = file;
    }
  }

  void removeCover() {
    coverFile.value = null;
    currentCoverUrl.value = '';
  }

  bool _validateForm() {
    if (nameController.text.trim().isEmpty) {
      Get.snackbar('Champ requis', 'Le nom de l\'événement est obligatoire.');
      return false;
    }
    if (startDate.value == null) {
      Get.snackbar('Champ requis', 'La date de début est obligatoire.');
      return false;
    }
    if (endDate.value != null && startDate.value != null && endDate.value!.isBefore(startDate.value!)) {
      Get.snackbar('Date invalide', 'La date de fin doit être postérieure à la date de début.');
      return false;
    }
    return true;
  }

  Future<void> saveChanges() async {
    if (isSaving.value) return;

    if (!_validateForm()) {
      return;
    }

    isSaving.value = true;

    String? newUploadedPhotoUrl;
    bool isNewPhotoUploaded = false;
    final String oldPhotoUrl = event.coverImageUrl ?? '';

    try {
      final userId = Get.find<AuthService>().userId ?? event.creatorId;

      // 1. Upload new photo if selected
      if (coverFile.value != null) {
        try {
          newUploadedPhotoUrl = await _repository.uploadCover(event.id, coverFile.value!);
          isNewPhotoUploaded = true;
        } catch (uploadError) {
          Get.snackbar('Erreur d\'upload', 'Impossible de téléverser la nouvelle photo: $uploadError');
          isSaving.value = false;
          return;
        }
      }

      final name = nameController.text.trim();
      final slug = slugController.text.trim();
      final description = descriptionController.text.trim();
      final virtualLink = virtualLinkController.text.trim();
      final address = addressController.text.trim();

      final updates = <String, dynamic>{
        'nom': name,
        if (!isSlugLocked) 'slug': slug,
        'description': description,
        'est_virtuel': isVirtual.value,
        'lien_virtuel': virtualLink,
        'pays_id': selectedCountry.value?.id,
        'ville_id': selectedCity.value?.id,
        'adresse': address,
        'date_debut': startDate.value?.toIso8601String(),
        'date_fin': endDate.value?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (isNewPhotoUploaded && newUploadedPhotoUrl != null) {
        updates['photo'] = newUploadedPhotoUrl;
      } else if (coverFile.value == null && currentCoverUrl.value.isEmpty && oldPhotoUrl.isNotEmpty) {
        // User explicitly removed the photo
        updates['photo'] = '';
      }

      // 2. Perform database & local cache update
      late final EventModel updatedEvent;
      try {
        updatedEvent = await _repository.updateEventOptimistic(event.id, userId, updates);
      } catch (updateError) {
        // If database update fails, clean up the newly uploaded orphan photo
        if (isNewPhotoUploaded && newUploadedPhotoUrl != null) {
          try {
            await _repository.deleteEventCover(newUploadedPhotoUrl);
          } catch (cleanupError) {
            debugPrint('[EditEventController] Failed to clean up orphan uploaded photo: $cleanupError');
          }
        }
        rethrow;
      }

      // Old-media cleanup is performed only after the backend confirms the update.

      if (selectedInterestIds.isNotEmpty) {
        await _repository.updateEventInterestsOptimistic(
          eventId: event.id,
          interestIds: selectedInterestIds.toList(),
        );
      }
      
      Get.back(result: updatedEvent);
      Get.snackbar(
        'Modification en cours…',
        'Les modifications ont été enregistrées localement et sont en cours de synchronisation.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    } finally {
      isSaving.value = false;
    }
  }

  @override
  void onClose() {
    nameController.dispose();
    slugController.dispose();
    descriptionController.dispose();
    addressController.dispose();
    virtualLinkController.dispose();
    super.onClose();
  }
}
