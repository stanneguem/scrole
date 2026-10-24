import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrole/modules/module_profil/interne/controllers/profile_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';
import 'package:scrole/app/repository_global/location_repository.dart';
import 'package:scrole/app/service_global/centre_interrets_service.dart';
import 'package:scrole/shared/models/interest_model.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/app/routes/app_pages.dart';

class EditProfileController extends GetxController {
  late final ProfileController _profileController;
  late final AppController _appController;
  late final LocationRepository _locationRepository;
  late final InterestService _interestService;

  final formKey = GlobalKey<FormState>();

  final nomController = TextEditingController();
  final prenomController = TextEditingController();
  final usernameController = TextEditingController();
  final bioController = TextEditingController();

  final Rx<String?> selectedGender = Rx<String?>(null);
  final Rx<DateTime?> selectedBirthDate = Rx<DateTime?>(null);

  final Rx<LocationOption?> selectedCountry = Rx<LocationOption?>(null);
  final Rx<LocationOption?> selectedCity = Rx<LocationOption?>(null);

  final RxList<LocationOption> countries = <LocationOption>[].obs;
  final RxList<LocationOption> cities = <LocationOption>[].obs;

  final RxList<Interest> allInterests = <Interest>[].obs;
  final RxList<String> selectedInterestIds = <String>[].obs;

  final RxBool isLoadingCountries = false.obs;
  final RxBool isLoadingCities = false.obs;
  final RxBool isLoadingInterests = false.obs;
  final RxBool isSaving = false.obs;

  static const int _lockDays = 90;

  // Verrous individuels : verrouillés par défaut jusqu'à la réponse backend.
  final RxBool canChangeUsername = false.obs;
  final RxBool canChangeGender = false.obs;
  final RxBool canChangeLocation = false.obs;
  final RxBool canChangeBirthDate = false.obs;
  final RxBool lockMetadataLoaded = false.obs;
  final RxBool lockMetadataFailed = false.obs;

  final RxInt usernameDaysLeft = 0.obs;
  final RxInt genderDaysLeft = 0.obs;
  final RxInt locationDaysLeft = 0.obs;
  final RxInt birthDateDaysLeft = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _appController = Get.find<AppController>();
    _profileController = Get.find<ProfileController>();
    _locationRepository = Get.find<LocationRepository>();
    _interestService = Get.find<InterestService>();
    _prefillFromProfile();
    _loadCountries();
    _loadInterests();
    unawaited(_refreshLockMetadata());
  }

  void _prefillFromProfile() {
    nomController.text = _profileController.nom.value;
    prenomController.text = _profileController.prenom.value;
    usernameController.text = _profileController.username.value;
    bioController.text = _profileController.bio.value;

    final genre = _profileController.gender.value.toLowerCase();
    selectedGender.value = genre.isEmpty ? null : genre;

    selectedBirthDate.value = _profileController.birthDate.value;
    
    selectedInterestIds.assignAll(
      _profileController.userInterests.map((i) => i.id).toList(),
    );
  }

  Future<void> _loadInterests() async {
    try {
      isLoadingInterests.value = true;
      debugPrint('Début du chargement des intérêts...');
      
      // Utilisation du cache 5h (plus de forceRefresh systématique)
      final interests = await _interestService.getInterests();
      
      debugPrint('[OK] ${interests.length} intérêts récupérés');
      allInterests.assignAll(interests);
      
      if (interests.isEmpty) {
        debugPrint('[Warning] La liste des intérêts retournée par le service est VIDE');
      }
    } catch (e) {
      debugPrint('[Error] Erreur critique chargement intérêts: $e');
    } finally {
      isLoadingInterests.value = false;
    }
  }

  Future<void> goToInterestSelection() async {
    final result = await Get.toNamed(
      AppPages.interestSelection,
      arguments: {
        'allInterests': allInterests.toList(),
        'selectedIds': selectedInterestIds.toList(),
      },
    );

    if (result != null && result is List<String>) {
      selectedInterestIds.assignAll(result);
    }
  }

  void toggleInterest(String id) {
    if (selectedInterestIds.contains(id)) {
      selectedInterestIds.remove(id);
    } else {
      if (selectedInterestIds.length < 5) {
        selectedInterestIds.add(id);
      } else {
        Get.snackbar(
          'Limite atteinte',
          'Tu ne peux choisir que 5 centres d\'intérêt maximum.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    }
  }

  Future<void> _refreshLockMetadata() async {
    lockMetadataFailed.value = false;
    try {
      // Le cache local peut précéder l'ajout des horodatages au payload.
      // Cette lecture récupère les restrictions actuelles depuis la source de vérité.
      final response = await Supabase.instance.client.rpc('get_myprofile');
      final Map<String, dynamic>? data = response is Map
          ? Map<String, dynamic>.from(response)
          : response is List && response.isNotEmpty && response.first is Map
              ? Map<String, dynamic>.from(response.first as Map)
              : null;
      if (isClosed) return;
      if (data == null) throw StateError('get_myprofile returned no profile data');

      _profileController.usernameUpdatedAt.value = _parseLockDate(data['username_updated_at']);
      _profileController.genderUpdatedAt.value = _parseLockDate(data['gender_updated_at']);
      _profileController.locationUpdatedAt.value = _parseLockDate(data['location_updated_at']);
      _profileController.birthDateUpdatedAt.value = _parseLockDate(data['birth_date_updated_at']);
      _computeAllLocks();
      lockMetadataLoaded.value = true;
    } catch (e) {
      // Le backend reste l'autorité : le trigger continuera de refuser toute
      // modification prématurée même si cette lecture informative échoue.
      debugPrint('[EditProfile] Impossible de rafraîchir les verrous: $e');
      lockMetadataFailed.value = true;
      lockMetadataLoaded.value = false;
    }
  }

  DateTime? _parseLockDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  void _computeAllLocks() {
    _checkLock(_profileController.usernameUpdatedAt.value, canChangeUsername, usernameDaysLeft);
    _checkLock(_profileController.genderUpdatedAt.value, canChangeGender, genderDaysLeft);
    _checkLock(_profileController.locationUpdatedAt.value, canChangeLocation, locationDaysLeft);
    _checkLock(_profileController.birthDateUpdatedAt.value, canChangeBirthDate, birthDateDaysLeft);
  }

  void _checkLock(DateTime? lastUpdate, RxBool canChange, RxInt daysLeft) {
    if (lastUpdate == null) {
      canChange.value = true;
      daysLeft.value = 0;
      return;
    }

    final unlockAt = lastUpdate.toUtc().add(const Duration(days: _lockDays));
    final remaining = unlockAt.difference(DateTime.now().toUtc());
    final secondsLeft = remaining.inSeconds;
    canChange.value = secondsLeft <= 0;
    daysLeft.value = secondsLeft > 0 ? (secondsLeft + 86399) ~/ 86400 : 0;
  }

  Future<void> _loadCountries() async {
    isLoadingCountries.value = true;
    try {
      final result = await _locationRepository.getCountries().timeout(const Duration(seconds: 10));
      countries.assignAll(result);

      final currentCountry = _profileController.country.value;
      if (currentCountry.isNotEmpty) {
        // Chercher par nom ou par ID
        final match = result.firstWhereOrNull(
          (c) => c.nom.toLowerCase() == currentCountry.toLowerCase() || c.id == currentCountry,
        );

        if (match != null) {
          selectedCountry.value = match;
          // On n'attend pas forcément le chargement des villes pour libérer le loader pays
          isLoadingCountries.value = false;
          await _loadCities(match.id, preselectFromProfile: true);
          return; // Sortir pour éviter le second isLoadingCountries.value = false
        }
      }
    } catch (e) {
      debugPrint('[Error] Erreur chargement pays: $e');
      Get.snackbar(
        'edit_profile_error_title'.tr,
        'edit_profile_error_load_countries'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoadingCountries.value = false;
    }
  }

  Future<void> _loadCities(String countryId, {bool preselectFromProfile = false}) async {
    isLoadingCities.value = true;
    cities.clear();
    if (!preselectFromProfile) selectedCity.value = null;
    try {
      final result = await _locationRepository.getCitiesForCountry(countryId).timeout(const Duration(seconds: 10));
      cities.assignAll(result);

      if (preselectFromProfile) {
        final currentCity = _profileController.city.value;
        if (currentCity.isNotEmpty) {
          final match = result.firstWhereOrNull(
            (c) => c.nom.toLowerCase() == currentCity.toLowerCase() || c.id == currentCity,
          );
          if (match != null) selectedCity.value = match;
        }
      }
    } catch (e) {
      debugPrint('[Error] Erreur chargement villes: $e');
      Get.snackbar(
        'edit_profile_error_title'.tr,
        'edit_profile_error_load_cities'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoadingCities.value = false;
    }
  }

  void onCountryChanged(LocationOption country) {
    if (!canChangeLocation.value) return;
    if (selectedCountry.value?.id == country.id) return;
    selectedCountry.value = country;
    _loadCities(country.id);
  }

  void onCityChanged(LocationOption city) {
    if (!canChangeLocation.value) return;
    selectedCity.value = city;
  }

  void onGenderChanged(String value) => selectedGender.value = value;

  String? validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return 'field_required'.tr;
    return null;
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> save() async {
    if (isSaving.value) return;
    if (!lockMetadataLoaded.value) {
      await _refreshLockMetadata();
      if (!lockMetadataLoaded.value) {
        Get.snackbar(
          'profile_error_title'.tr,
          'edit_profile_lock_check_failed'.tr,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 5),
        );
        return;
      }
    }
    if (!(formKey.currentState?.validate() ?? false)) return;

    final Map<String, dynamic> payload = {
      'last_name': nomController.text.trim(),
      'first_name': prenomController.text.trim(),
      'bio': bioController.text.trim(),
      if (canChangeUsername.value) 'username': usernameController.text.trim(),
      if (canChangeGender.value && selectedGender.value != null) 'gender': selectedGender.value,
      if (canChangeBirthDate.value && selectedBirthDate.value != null)
        'birth_date': _formatDate(selectedBirthDate.value!),
      if (canChangeLocation.value && selectedCountry.value != null)
        'country_id': selectedCountry.value!.id,
      if (canChangeLocation.value && selectedCity.value != null)
        'city_id': selectedCity.value!.id,
    };

    final interestIds = selectedInterestIds.toList();
    final userId = _profileController.userId.value;
    isSaving.value = true;

    // Retour immédiat au profil : la persistance continue sans garder
    // l'utilisateur sur le formulaire pendant les appels réseau.
    Get.back();
    Get.snackbar(
      'edit_profile_title'.tr,
      'edit_profile_saving'.tr,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 30),
      showProgressIndicator: true,
      isDismissible: false,
    );

    unawaited(_persistProfile(payload, interestIds, userId));
  }

  Future<void> _persistProfile(
    Map<String, dynamic> payload,
    List<String> interestIds,
    String userId,
  ) async {
    try {
      final success = await _profileController.updateProfile(
        payload,
        showLoading: false,
        showFeedback: false,
      );
      if (!success) {
        throw StateError('profile_update_failed');
      }

      await _interestService.saveUserInterests(userId, interestIds);
      await _profileController.refreshProfile();

      Get.closeCurrentSnackbar();
      Get.snackbar(
        'profile_success_title'.tr,
        'edit_profile_saved'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e, stack) {
      debugPrint('[EditProfile] Erreur enregistrement profil: $e\\n$stack');
      Get.closeCurrentSnackbar();
      Get.snackbar(
        'profile_error_title'.tr,
        'edit_profile_save_failed'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    } finally {
      if (!isClosed) isSaving.value = false;
    }
  }

  @override
  void onClose() {
    nomController.dispose();
    prenomController.dispose();
    usernameController.dispose();
    bioController.dispose();
    super.onClose();
  }
}