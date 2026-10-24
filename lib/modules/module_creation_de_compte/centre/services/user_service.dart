import 'dart:async';

import 'package:get/get.dart';

import '../../../../app/local_storage/fast/fast_cache_key.dart';
import '../../../../app/local_storage/fast/fast_cache_service.dart';
import '../../externe/repositories/user_repository.dart';

class UserService extends GetxService {
  final UserRepository _repository = UserRepository();
  FastCacheService? _cache;

  bool get isCacheAvailable {
    try {
      if (!Get.isRegistered<FastCacheService>()) return false;
      _cache = Get.find<FastCacheService>();
      return _cache!.isReady;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic>? getCachedProfile() {
    if (!isCacheAvailable) return null;
    try {
      return _cache!.get<Map<String, dynamic>>(
        FastCacheKey.profile,
        maxAge: const Duration(days: 30),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getProfile(String id) async {
    if (isCacheAvailable) {
      try {
        final cachedData = _cache!.get<Map<String, dynamic>>(
          FastCacheKey.profile,
          maxAge: const Duration(days: 30),
        );
        if (cachedData != null) {
          unawaited(_validateCacheInBackground(id));
          return cachedData;
        }
      } catch (_) {}
    }
    return await backendGetProfile(id);
  }

  Future<void> _validateCacheInBackground(String id) async {
    try {
      final exists = await _repository.profileExists(id);
      if (!exists && isCacheAvailable) {
        await _cache!.remove(FastCacheKey.profile);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> backendGetProfile(String id) async {
    final profile = await _repository.getMyProfile();
    if (profile != null) {
      if (isCacheAvailable) {
        await _cache!.set(FastCacheKey.profile, profile);
      } else {
        await _tryInitCache();
        if (isCacheAvailable) {
          await _cache!.set(FastCacheKey.profile, profile);
        }
      }
    }
    return profile;
  }

  Future<void> _tryInitCache() async {
    try {
      if (!Get.isRegistered<FastCacheService>()) {
        await Get.putAsync(() async => FastCacheService().init());
      }
      _cache = Get.find<FastCacheService>();
      if (!_cache!.isReady) await _cache!.init();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> createProfile({
    required String userId,
    required String firstName,
    required String lastName,
    required String username,
    required String countryId,
    required DateTime birthDate,
    String? cityId,
    String? gender,
  }) async {
    final data = {
      'p_username': username.trim().toLowerCase(),
      'p_first_name': firstName.trim(),
      'p_last_name': lastName.trim(),
      'p_birth_date': _formatDate(birthDate),
      'p_country_id': countryId,
      if (cityId != null) 'p_city_id': cityId,
      if (gender != null) 'p_gender': gender,
    };
    final profile = await _repository.createProfile(userId, data);
    if (isCacheAvailable) await _cache!.set(FastCacheKey.profile, profile);
    return profile;
  }

  Future<Map<String, dynamic>?> updateProfile(String id, Map<String, dynamic> data) async {
    try {
      final updated = await _repository.updateProfile(id, data);
      if (updated != null) {
        // updateProfile() retourne user_profiles brut. Ne l'écrit pas dans
        // le cache du profil personnel, car il peut contenir un is_verified
        // obsolète. On recharge get_myprofile(), source de vérité complète.
        final fresh = await _repository.getMyProfile();
        if (fresh != null && isCacheAvailable) {
          await _cache!.set(FastCacheKey.profile, fresh);
        }
        return fresh ?? updated;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteProfile(String id) async {
    try {
      final success = await _repository.deleteProfile(id);
      if (success && isCacheAvailable) await _cache!.remove(FastCacheKey.profile);
      return success;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> refreshProfile(String id) async {
    if (isCacheAvailable) await _cache!.remove(FastCacheKey.profile);
    return await backendGetProfile(id);
  }

  Stream<List<Map<String, dynamic>>> watchProfile(String id) {
    // Important : ne jamais écrire le payload brut de user_profiles dans le
    // cache du profil personnel. La certification vient de user_certifications
    // et est calculée par get_myprofile(). Le SessionService déclenche le
    // re-fetch backend après un événement Realtime.
    return _repository.watchUser(id);
  }

  Future<void> clearCache() async {
    try {
      if (isCacheAvailable) await _cache!.remove(FastCacheKey.profile);
    } catch (_) {}
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}