import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/service_global/supabse_service.dart';

class ProfileCreationException implements Exception {
  ProfileCreationException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isConflict => statusCode == 409 || statusCode == 23505;

  @override
  String toString() => message;
}

class AuthAccountMissingException implements Exception {
  AuthAccountMissingException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UserRepository {
  final SupabaseService _supabase = Get.find();
  SupabaseClient get client => _supabase.client;

  Future<Map<String, dynamic>> createProfile(String userId, Map<String, dynamic> data) async {
    try {
      final params = {...data};
      final response = await client.rpc('create_user_profile', params: params);

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      } else if (response is List && response.isNotEmpty) {
        return Map<String, dynamic>.from(response.first);
      } else {
        return {'user_id': userId, ...data};
      }
    } on PostgrestException catch (e) {
      throw ProfileCreationException(
        e.message,
        statusCode: e.code == '23505' ? 409 : null,
      );
    } catch (e) {
      throw ProfileCreationException(e.toString());
    }
  }

  /// Profil personnel : même source de vérité que le backend de profil.
  /// get_myprofile() calcule notamment is_verified depuis user_certifications.
  Future<Map<String, dynamic>?> getMyProfile() async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await client.rpc('get_myprofile');

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      if (response is List && response.isNotEmpty && response.first is Map) {
        return Map<String, dynamic>.from(response.first as Map);
      }

      return null;
    } on PostgrestException catch (e) {
      debugPrint('Erreur get_myprofile: ${e.message} (${e.code})');
      if (e.code == 'P0001' || e.code == 'A0001') {
        throw AuthAccountMissingException(e.message);
      }
      rethrow;
    } catch (e) {
      debugPrint('Erreur lors de la récupération du profil: $e');
      rethrow;
    }
  }

  @Deprecated('Utilisez getMyProfile() à la place')
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      return await client
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
    } catch (e) {
      debugPrint('Erreur lors de la récupération du profil: $e');
      return null;
    }
  }

  Future<bool> profileExists(String userId) async {
    final profile = await getProfile(userId);
    return profile != null;
  }

  Stream<List<Map<String, dynamic>>> watchUser(String userId) {
    try {
      return client
          .from('user_profiles')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .map((event) => event.cast<Map<String, dynamic>>());
    } catch (e) {
      debugPrint('Erreur lors de l\'écoute du profil: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> updateProfile(String userId, Map<String, dynamic> data) async {
    try {
      final Map<String, dynamic> profileData = Map<String, dynamic>.from(data);
      if (profileData.isNotEmpty) {
        await client.from('user_profiles').update(profileData).eq('user_id', userId);
      }
      return await getMyProfile();
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour du profil: $e');
      return null;
    }
  }

  Future<bool> deleteProfile(String userId) async {
    try {
      await client.from('user_profiles').delete().eq('user_id', userId);
      return true;
    } catch (e) {
      debugPrint('Erreur lors de la suppression du profil: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String term) async {
    try {
      final response = await client
          .from('user_profiles')
          .select()
          .or('username.ilike.%$term%,first_name.ilike.%$term%,last_name.ilike.%$term%')
          .limit(20);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Erreur recherche utilisateurs: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> upsertProfile(String userId, Map<String, dynamic> data) async {
    try {
      final params = {...data, 'user_id': userId};
      final response = await client
          .from('user_profiles')
          .upsert(params, onConflict: 'user_id')
          .select()
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Erreur lors de l\'upsert du profil: $e');
      return null;
    }
  }
}