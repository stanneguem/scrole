import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../../../../shared/models/user_models.dart';

class AccountRepository {
  final SupabaseClient _client = Get.find<SupabaseService>().client;

  /// Appelle la RPC initialize_account pour créer profil, préférences et privacy
  Future<UserSessionData> initializeAccount(Map<String, dynamic> params) async {
    try {
      final response = await _client.rpc(
        'initialize_account',
        params: params,
      );

      final data = Map<String, dynamic>.from(response);
      final error = data['error'];

      // La RPC peut retourner un objet JSON d'erreur sans lever de PostgrestException.
      // On doit donc vérifier explicitement la présence de la clé `error` avant le parsing.
      if (error != null) {
        throw Exception(_mapInitializationError(error.toString()));
      }

      return UserSessionData.fromJson(data);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Échec de l\'initialisation du compte: $e');
    }
  }

  String _mapInitializationError(String error) {
    switch (error) {
      case 'unauthenticated':
        return 'Session utilisateur invalide. Reconnecte-toi puis réessaie.';
      case 'invalid_profile_data':
        return 'Les informations du profil sont invalides.';
      case 'profile_already_exists':
        return 'Ton profil existe déjà.';
      case 'username_already_taken':
        return 'Ce pseudo est déjà pris.';
      default:
        return 'Impossible d\'initialiser le compte.';
    }
  }
}
