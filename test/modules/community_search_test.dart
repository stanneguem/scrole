import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_decouverte/centre/models/discover_models.dart';
import 'package:scrole/app/translation/app_translation_additions.dart';

void main() {
  group('Community Search Integration Tests', () {
    test('SearchResultItem.fromJson correctly parses community search results', () {
      final jsonResponse = {
        'id': '2e0df023-ac20-4399-a12f-80ad0d33cfa9',
        'category': 'community',
        'title': 'Zimbaya Community',
        'subtitle': 'La communauté des passionnés de Zimbaya',
        'photo_url': 'https://example.com/zimbaya.jpg',
        'friend_count': 12, // Generic field from RPC search_all, must be ignored for community
        'is_certified': false,
      };

      final item = SearchResultItem.fromJson(jsonResponse);
      expect(item.id, equals('2e0df023-ac20-4399-a12f-80ad0d33cfa9'));
      expect(item.category, equals('community'));
      expect(item.title, equals('Zimbaya Community'));
      expect(item.subtitle, equals('La communauté des passionnés de Zimbaya'));
      expect(item.photoUrl, equals('https://example.com/zimbaya.jpg'));
    });

    test('SearchResultItem handles null photo_url and subtitle cleanly', () {
      final jsonResponse = {
        'id': 'comm_999',
        'category': 'community',
        'title': 'Minimal Community',
        'subtitle': null,
        'photo_url': null,
      };

      final item = SearchResultItem.fromJson(jsonResponse);
      expect(item.id, equals('comm_999'));
      expect(item.category, equals('community'));
      expect(item.title, equals('Minimal Community'));
      expect(item.subtitle, isNull);
      expect(item.photoUrl, isNull);
    });

    test('All 9 language catalogs contain search and community translation keys', () {
      final keysMap = AppTranslationAdditions.keys;
      final requiredLanguages = ['fr', 'en', 'es', 'de', 'it', 'pt', 'zh', 'ja', 'ru'];

      for (final lang in requiredLanguages) {
        expect(keysMap.containsKey(lang), isTrue, reason: 'Missing language catalog: $lang');
        final catalog = keysMap[lang]!;
        expect(catalog.containsKey('filter_communities'), isTrue, reason: 'Missing filter_communities in $lang');
        expect(catalog.containsKey('no_communities_found'), isTrue, reason: 'Missing no_communities_found in $lang');
        expect(catalog.containsKey('search_error_msg'), isTrue, reason: 'Missing search_error_msg in $lang');
        expect(catalog.containsKey('retry'), isTrue, reason: 'Missing retry in $lang');
      }
    });

    test('Filter logic isolates community items without modifying query or list', () {
      final allItems = [
        const SearchResultItem(
          id: 'u1',
          category: 'user',
          title: 'Gabi User',
        ),
        const SearchResultItem(
          id: 'c1',
          category: 'community',
          title: 'Otaku CM',
          subtitle: 'Manga & anime fans',
        ),
        const SearchResultItem(
          id: 'e1',
          category: 'event',
          title: 'Festival Yaoundé',
        ),
      ];

      final communitiesOnly = allItems.where((item) => item.category == 'community').toList();
      expect(communitiesOnly.length, equals(1));
      expect(communitiesOnly.first.title, equals('Otaku CM'));
      expect(communitiesOnly.first.id, equals('c1'));
    });
  });
}
