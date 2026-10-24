import 'package:get/get.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:supabase/supabase.dart';
import '../../centre/services/auth_service.dart';

class AuthController extends GetxController {
  final isLoading = false.obs;
  final AuthService _authService = Get.find<AuthService>();

  Future<void> authentification() async {
    try {
      isLoading.value = true;
      await _authService.signInWithGoogle();
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de se connecter');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    try {
      isLoading.value = true;
      await _authService.signOut();
      Get.offAllNamed(AppPages.authentificationscreen);
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de se déconnecter');
    } finally {
      isLoading.value = false;
    }
  }

  bool get isAuthenticated => _authService.isLoggedIn;
  User? get currentUser => _authService.currentUser.value;
}