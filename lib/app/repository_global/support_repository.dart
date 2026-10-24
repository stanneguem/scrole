import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../service_global/supabse_service.dart';

class SupportRepository {
  final SupabaseClient _client = Get.find<SupabaseService>().client;

  Future<void> sendBugReport({
    required String title,
    required String description,
    String? screenshotUrl,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _client.from('bug_reports').insert({
        'user_id': _client.auth.currentUser?.id,
        'title': title,
        'description': description,
        'screenshot_url': screenshotUrl,
        'metadata': metadata,
      });
    } catch (e) {
      throw Exception('Erreur lors de l\'envoi du rapport: $e');
    }
  }
}
