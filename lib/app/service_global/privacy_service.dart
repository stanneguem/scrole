import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/user_models.dart';
import '../local_storage/fast/fast_cache_service.dart';

class PrivacyService extends GetxService {
  final FastCacheService _cache = Get.find<FastCacheService>();

  static const String _cacheKey = 'user_privacy';

  final Rx<AppPrivacy> privacy = AppPrivacy.defaultValues().obs;
  final RxBool isSyncing = false.obs;

  Future<PrivacyService> init() async {
    final cached = _cache.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null) {
      privacy.value = AppPrivacy.fromJson(cached);
    }
    return this;
  }

  /// Loads the signed-in user's authoritative privacy settings from Supabase.
  /// Cache is only a fallback for temporary network errors.
  Future<void> loadFromBackend() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    isSyncing.value = true;
    try {
      final row = await Supabase.instance.client
          .from('user_privacy')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row != null) {
        final loaded = AppPrivacy.fromJson(Map<String, dynamic>.from(row));
        privacy.value = loaded;
        _cache.set(_cacheKey, loaded.toJson());
      } else {
        // A first-time account may not have a row yet. Seed the server with
        // the same explicit defaults used by the UI/model.
        final defaults = AppPrivacy.defaultValues();
        await saveToBackend(defaults);
      }
    } catch (e, stack) {
      debugPrint('[PRIVACY] load from Supabase failed: $e\n$stack');
      rethrow;
    } finally {
      isSyncing.value = false;
    }
  }

  /// Persists settings first; local state/cache change only after success.
  Future<void> saveToBackend(AppPrivacy value) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('not_authenticated');

    await client.from('user_privacy').upsert({
      'user_id': userId,
      ...value.toJson(),
    }, onConflict: 'user_id');

    privacy.value = value;
    _cache.set(_cacheKey, value.toJson());
  }

  void applyPrivacy(AppPrivacy newPrivacy) {
    privacy.value = newPrivacy;
    _cache.set(_cacheKey, newPrivacy.toJson());
  }

  Future<void> clearCache() async {
    await _cache.remove(_cacheKey);
    privacy.value = AppPrivacy.defaultValues();
  }
}
