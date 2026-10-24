import 'package:get/get.dart';
import '../../app/local_storage/fast/fast_cache_service.dart';

class SearchHistoryService extends GetxService {
  final FastCacheService _cache = Get.find<FastCacheService>();
  static const String _historyKey = 'recent_search_history';
  static const int _maxHistoryCount = 10;

  final RxList<String> recentSearches = <String>[].obs;

  Future<SearchHistoryService> init() async {
    loadHistory();
    return this;
  }

  void loadHistory() {
    final list = _cache.get<List<dynamic>>(_historyKey);
    if (list != null) {
      recentSearches.value = list.map((e) => e.toString()).toList();
    }
  }

  Future<void> addSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final existingIndex = recentSearches.indexWhere(
      (element) => element.toLowerCase() == trimmed.toLowerCase(),
    );

    if (existingIndex != -1) {
      recentSearches.removeAt(existingIndex);
    }

    recentSearches.insert(0, trimmed);

    if (recentSearches.length > _maxHistoryCount) {
      recentSearches.removeRange(_maxHistoryCount, recentSearches.length);
    }

    await _cache.set(_historyKey, recentSearches.toList());
  }

  Future<void> removeSearch(String query) async {
    recentSearches.removeWhere((element) => element.toLowerCase() == query.toLowerCase());
    await _cache.set(_historyKey, recentSearches.toList());
  }

  Future<void> clearHistory() async {
    recentSearches.clear();
    await _cache.remove(_historyKey);
  }
}
