import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../modules/module_decouverte/centre/models/discover_models.dart';

class SearchRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<AccountSuggestion>> getSuggestedProfiles({int limit = 30, int offset = 0}) async {
    debugPrint('[FOLLOW] RPC get_suggested_profiles params={p_limit: $limit, p_offset: $offset}');
    try {
      final response = await _client.rpc('get_suggested_profiles', params: {
        'p_limit': limit,
        'p_offset': offset,
      });
      final rawItems = response is List
          ? response
          : response is Map && response['items'] is List
              ? response['items'] as List
              : const <dynamic>[];
      final profiles = rawItems.whereType<Map>().map((raw) {
        final json = Map<String, dynamic>.from(raw);
        final first = (json['first_name'] ?? '').toString().trim();
        final last = (json['last_name'] ?? '').toString().trim();
        final fullName = '$first $last'.trim();
        return AccountSuggestion(
          id: (json['user_id'] ?? json['id'] ?? '').toString(),
          username: (json['username'] ?? json['pseudo'] ?? '').toString(),
          displayName: fullName.isEmpty ? (json['pseudo'] ?? json['username'] ?? '').toString() : fullName,
          avatarUrl: json['photo_url']?.toString(),
          bio: json['bio']?.toString(),
          isVerified: json['is_certified'] == true || json['is_verified'] == true || json['is_certified'] == 1 || json['is_verified'] == 1,
          friendCount: (json['friends_count'] as num?)?.toInt() ?? (json['friend_count'] as num?)?.toInt(),
          followsMe: json['follows_me'] == true,
        );
      }).where((profile) => profile.id.isNotEmpty).toList();
      debugPrint('[FOLLOW] RPC get_suggested_profiles response count=${profiles.length}');
      return profiles;
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC get_suggested_profiles exception=$e\\n$stack');
      rethrow;
    }
  }

  Future<List<SearchResultItem>> searchAll(String query) async {
    try {
      debugPrint('[SearchRepository] calling search_all with query: "$query"');
      final response = await _client.rpc('search_all', params: {
        'p_query': query,
      });

      debugPrint('[SearchRepository] response type: ${response.runtimeType}, data: $response');

      if (response is List) {
        final rawList = response
            .map((item) => SearchResultItem.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();

        final seen = <String>{};
        final uniqueList = <SearchResultItem>[];
        for (final item in rawList) {
          final key = '${item.category}_${item.id}';
          if (seen.add(key)) {
            uniqueList.add(item);
          }
        }
        return uniqueList;
      }
      return [];
    } catch (e, stack) {
      debugPrint('[SearchRepository] error calling search_all: $e');
      debugPrintStack(stackTrace: stack);
      throw Exception(e.toString());
    }
  }
}
