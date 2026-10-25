import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/local_storage/fast/fast_cache_service.dart';
import '../../../../app_controller.dart';
import '../../../../app/repository_global/location_repository.dart';
import '../../../../app/repository_global/storage_repository.dart';
import '../../../../app/service_global/media_service.dart';
import '../../centre/services/account_initialization_service.dart';
import '../../centre/services/user_service.dart';
import '../enums/username_status.dart';

class CreateAccountController extends GetxController {
  CreateAccountController({
    UserService? service,
    AccountInitializationService? initService,
    LocationRepository? locationRepository,
    SupabaseClient? supabaseClient,
    MediaService? mediaService,
    StorageRepository? storageRepository,
  })  : _service = service ?? UserService(),
        _initService = initService ?? AccountInitializationService(),
        _locationRepository = locationRepository ??
            CachedLocationRepository(
              SupabaseLocationRepository(supabaseClient ?? Supabase.instance.client),
              Get.find<FastCacheService>(),
            ),
        _supabase = supabaseClient ?? Supabase.instance.client,
        _mediaService = mediaService ?? Get.find<MediaService>(),
        _storageRepository = storageRepository ?? StorageRepository();

  final UserService _service;
  final AccountInitializationService _initService;
  final LocationRepository _locationRepository;
  final SupabaseClient _supabase;
  final MediaService _mediaService;
  final StorageRepository _storageRepository;

  final formKey = GlobalKey<FormState>();
  final surnameController = TextEditingController();
  final nameController = TextEditingController();
  final usernameController = TextEditingController();

  final countries = <LocationOption>[].obs;
  final cities = <LocationOption>[].obs;
  final isLoadingCountries = false.obs;
  final isLoadingCities = false.obs;

  final selectedCountry = Rxn<LocationOption>();
  final selectedCity = Rxn<LocationOption>();
  final selectedBirthDate = Rxn<DateTime>();
  final selectedGender = Rxn<String>();

  final avatarFile = Rxn<File>();
  final coverFile = Rxn<File>();
  final isUploadingImage = false.obs;
  final isUploadingCover = false.obs;

  final isSubmitting = false.obs;
  final submitError = Rxn<String>();
  final usernameStatus = UsernameStatus.idle.obs;

  Timer? _debounce;
  static const minUsernameLength = 3;

  @override
  void onInit() {
    super.onInit();
    usernameController.addListener(_onUsernameChanged);
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    isLoadingCountries.value = true;
    try {
      countries.value = await _locationRepository.getCountries();
    } catch (e) {
      if (countries.isEmpty) rethrow;
    } finally {
      isLoadingCountries.value = false;
    }
  }

  Future<void> retryLoadCountries() async {
    if (_locationRepository is CachedLocationRepository) {
      countries.value = await (_locationRepository as CachedLocationRepository).refreshCountries();
    } else {
      await _loadCountries();
    }
  }

  Future<void> setCountry(LocationOption country) async {
    if (selectedCountry.value?.id == country.id) return;
    selectedCountry.value = country;
    selectedCity.value = null;
    cities.clear();
    isLoadingCities.value = true;
    try {
      cities.value = await _locationRepository.getCitiesForCountry(country.id);
    } catch (e) {
      if (cities.isEmpty) rethrow;
    } finally {
      isLoadingCities.value = false;
    }
  }

  Future<void> retryLoadCities() async {
    final country = selectedCountry.value;
    if (country == null) return;
    if (_locationRepository is CachedLocationRepository) {
      cities.value = await (_locationRepository as CachedLocationRepository).refreshCities(country.id);
    } else {
      await setCountry(country);
    }
  }

  void setCity(LocationOption city) => selectedCity.value = city;

  Future<void> pickAvatar(ImageSource source) async {
    isUploadingImage.value = true;
    try {
      final file = await _mediaService.pickProfileImage(source: source);
      if (file != null) avatarFile.value = file;
    } catch (e) {
      debugPrint('[Error] Erreur lors de la sélection de l\'image: $e');
      Get.snackbar('Erreur', 'Impossible de charger l\'image. Vérifie les permissions.', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      isUploadingImage.value = false;
    }
  }

  void removeAvatar() => avatarFile.value = null;

  Future<void> pickCover(ImageSource source) async {
    isUploadingCover.value = true;
    try {
      final file = await _mediaService.pickCoverImage(source: source);
      if (file != null) coverFile.value = file;
    } catch (e) {
      debugPrint('[Error] Erreur lors de la sélection de la couverture: $e');
      Get.snackbar('Erreur', 'Impossible de charger l\'image de couverture.', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      isUploadingCover.value = false;
    }
  }

  void removeCover() => coverFile.value = null;

  void _onUsernameChanged() {
    final value = usernameController.text.trim();
    _debounce?.cancel();
    if (value.length < minUsernameLength) {
      usernameStatus.value = UsernameStatus.idle;
      return;
    }
    usernameStatus.value = UsernameStatus.checking;
    _debounce = Timer(const Duration(milliseconds: 500), () => _checkUsername(value));
  }

  Future<void> _checkUsername(String username) async {
    try {
      final response = await _supabase.rpc('check_username_availability', params: {'p_username': username});
      final isAvailable = response == true;
      if (usernameController.text.trim() != username) return;
      usernameStatus.value = isAvailable ? UsernameStatus.available : UsernameStatus.taken;
    } catch (_) {
      usernameStatus.value = UsernameStatus.error;
    }
  }

  String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ce champ est requis';
    if (value.trim().length < 2) return 'Minimum 2 caractères';
    return null;
  }

  String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ce champ est requis';
    if (value.trim().length < minUsernameLength) return 'Minimum $minUsernameLength caractères';
    if (usernameStatus.value == UsernameStatus.taken) return 'Ce pseudo est déjà pris';
    if (usernameStatus.value != UsernameStatus.available) return 'Vérifie la disponibilité du pseudo';
    return null;
  }

  Future<bool> submit() async {
    submitError.value = null;
    if (!formKey.currentState!.validate()) return false;
    if (usernameStatus.value != UsernameStatus.available) {
      submitError.value = 'Choisis un pseudo disponible.';
      return false;
    }
    if (selectedCountry.value == null) {
      submitError.value = 'Sélectionne ton pays.';
      return false;
    }
    if (selectedBirthDate.value == null) {
      submitError.value = 'Sélectionne ta date de naissance.';
      return false;
    }
    final user = _supabase.auth.currentUser;
    if (user == null) {
      submitError.value = 'Ta session a expiré. Reconnecte-toi.';
      return false;
    }

    final userId = user.id;
    isSubmitting.value = true;
    String? avatarUrl;
    String? coverUrl;
    try {
      if (avatarFile.value != null) {
        avatarUrl = await _storageRepository.uploadProfilePicture(userId, avatarFile.value!);
      }
      if (coverFile.value != null) {
        coverUrl = await _storageRepository.uploadProfileCover(userId, coverFile.value!);
      }
      await _initService.initializeAccount(
        userId: userId,
        firstName: nameController.text.trim(),
        lastName: surnameController.text.trim(),
        username: usernameController.text.trim(),
        countryId: selectedCountry.value!.id,
        birthDate: selectedBirthDate.value!,
        cityId: selectedCity.value?.id,
        gender: selectedGender.value,
        avatarUrl: avatarUrl,
        coverUrl: coverUrl,
      );
      debugPrint('[OK] Initialisation du compte réussie');
      if (Get.isRegistered<AppController>()) {
        Get.find<AppController>().startOnboarding();
      }
      return true;
    } on StorageException catch (e) {
      debugPrint('[Storage] ${e.message} (status ${e.statusCode})');
      if (avatarUrl != null) await _storageRepository.deletePublicFile(bucket: 'avatars', publicUrl: avatarUrl);
      if (coverUrl != null) await _storageRepository.deletePublicFile(bucket: 'avatars', publicUrl: coverUrl);
      submitError.value = 'Impossible d\'envoyer la photo. Vérifie ta session puis réessaie.';
      return false;
    } catch (e) {
      if (avatarUrl != null) await _storageRepository.deletePublicFile(bucket: 'avatars', publicUrl: avatarUrl);
      if (coverUrl != null) await _storageRepository.deletePublicFile(bucket: 'avatars', publicUrl: coverUrl);
      submitError.value = e.toString().contains('Exception:') ? e.toString().replaceAll('Exception: ', '') : 'Une erreur est survenue. Réessaie.';
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    usernameController.removeListener(_onUsernameChanged);
    surnameController.dispose();
    nameController.dispose();
    usernameController.dispose();
    super.onClose();
  }
}
