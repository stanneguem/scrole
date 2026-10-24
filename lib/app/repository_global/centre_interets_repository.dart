import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/interest_model.dart';


class InterestRepository {
  final SupabaseClient client;

  InterestRepository(this.client);

  /// Récupère la liste complète des centres d'intérêt.
  Future<List<Interest>> getInterests() async {
    try {
      debugPrint('[Supabase] Récupération des intérêts...');
      final response = await client
          .from('interests')
          .select()
          .order('name');
          
      debugPrint('[Supabase] Response: $response');
      
      final List<dynamic> data = response is List ? response : [];
      return data
          .map((e) => Interest.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[Error] Erreur Supabase getInterests: $e');
      return []; // On retourne une liste vide au lieu de crash
    }
  }

  /// Récupère les IDs des centres d'intérêt d'un utilisateur.
  Future<List<String>> getUserInterestIds(String userId) async {
    try {
      final response = await client
          .from('user_interests')
          .select('interest_id')
          .eq('user_id', userId);
          
      final List<dynamic> data = response is List ? response : [];
      return data.map((e) => e['interest_id'].toString()).toList();
    } catch (e) {
      debugPrint('Erreur lors de la récupération des intérêts utilisateur: $e');
      return [];
    }
  }

  /// Met à jour les centres d'intérêt d'un utilisateur.
  /// Remplace tous les anciens par les nouveaux.
  Future<void> updateUserInterests(String userId, List<String> interestIds) async {
    try {
      // 1. Supprimer les anciens
      await client.from('user_interests').delete().eq('user_id', userId);
      
      // 2. Insérer les nouveaux
      if (interestIds.isNotEmpty) {
        final List<Map<String, dynamic>> toInsert = interestIds.map((id) => {
          'user_id': userId,
          'interest_id': id,
        }).toList();
        
        await client.from('user_interests').insert(toInsert);
      }
    } catch (e) {
      throw Exception('Erreur lors de la mise à jour des intérêts: $e');
    }
  }
}