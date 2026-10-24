import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/sync_models.dart';
import '../service_global/supabse_service.dart';

class SyncRepository {
  final SupabaseClient _client = Get.find<SupabaseService>().client;

  /// Récupère les changements depuis le dernier curseur
  Future<SyncResult> getSyncChanges(int lastCursor) async {
    try {
      final response = await _client.rpc(
        'sync_changes',
        params: {'p_last_cursor': lastCursor},
      );

      return SyncResult.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      throw Exception('Erreur lors de la synchronisation: $e');
    }
  }
}
