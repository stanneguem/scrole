import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService extends GetxService {
  SupabaseClient? _client;
  SupabaseClient get client {
    if (_client == null) {
      throw Exception('SupabaseService not initialized. Call init() first.');
    }
    return _client!;
  }

  Future<SupabaseService> init() async {
    // Supabase est déjà initialisé dans main.dart
    _client = Supabase.instance.client;
    return this;
  }

  bool get isInitialized => _client != null;
}