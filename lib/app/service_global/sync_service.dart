import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../shared/models/sync_models.dart';
import '../local_storage/fast/fast_cache_service.dart';
import '../repository_global/sync_repository.dart';

class SyncService extends GetxService {
  final SyncRepository _repository = SyncRepository();
  final FastCacheService _cache = Get.find<FastCacheService>();
  
  static const String _cursorKey = 'sync_cursor';
  
  final RxInt currentCursor = 0.obs;
  final RxBool isSyncing = false.obs;

  Future<SyncService> init() async {
    final cachedCursor = _cache.get<int>(_cursorKey);
    if (cachedCursor != null) {
      currentCursor.value = cachedCursor;
    }
    return this;
  }

  void updateCursor(int newCursor) {
    currentCursor.value = newCursor;
    _cache.set(_cursorKey, newCursor);
  }

  Future<void> sync() async {
    if (isSyncing.value) return;
    
    try {
      isSyncing.value = true;
      final result = await _repository.getSyncChanges(currentCursor.value);
      
      if (result.changes.isNotEmpty) {
        await _processChanges(result.changes);
      }
      
      updateCursor(result.newCursor);
      debugPrint('[OK] Synchronisation terminée. Nouveau curseur: ${result.newCursor}');
    } catch (e) {
      debugPrint('[Error] Erreur de synchronisation: $e');
    } finally {
      isSyncing.value = false;
    }
  }

  Future<void> _processChanges(List<SyncChange> changes) async {
    for (final change in changes) {
      // Distribuer les changements selon le type d'entité
      switch (change.entityType) {
        case 'profile':
          // Exemple: Get.find<SessionService>().handleProfileSync(change);
          break;
        case 'community':
          // Get.find<CommunityService>().handleSync(change);
          break;
        // Ajouter les autres types ici
        default:
          debugPrint('[Warning] Type d\'entité inconnu pour la synchro: ${change.entityType}');
      }
    }
  }

  Future<void> clearCache() async {
    await _cache.remove(_cursorKey);
    currentCursor.value = 0;
  }
}
