import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../../../../app/utils/supabase_error_mapper.dart';

class AuthRepository {
  final SupabaseService _supabase = Get.find();
  SupabaseClient get client => _supabase.client;

  User? get currentUser => client.auth.currentUser;

  bool get isAuthenticated => client.auth.currentUser != null;

  Session? get currentSession => client.auth.currentSession;

  Future<bool> signInWithGoogle() async {
    try {
      await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb
            ? 'http://localhost:45265/login-callback'
            : 'com.scrole.app://login-callback',
      );
      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('[AuthRepository] OAuth sign-in failed: $e\n$stackTrace');
      final appError = mapSupabaseError(e);
      Get.snackbar(appError.title, appError.message);
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (e) {
      throw Exception('Erreur lors de la déconnexion: $e');
    }
  }

  Stream<AuthState> onAuthStateChange() {
    return client.auth.onAuthStateChange;
  }
}