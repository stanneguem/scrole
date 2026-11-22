import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../repositories/search_repository.dart';
import '../services/search_history_service.dart';
import '../../modules/module_decouverte/centre/models/discover_models.dart';
import '../../modules/module_communautes/centre/services/community_service.dart';
import '../../modules/module_communautes/interne/pages/community_feed_screen.dart';
import '../../modules/module_communautes/interne/pages/community_preview_screen.dart';
import '../../app/routes/app_pages.dart';

enum SearchState { initial, loading, success, empty, error }
enum SearchFilter { all, users, events, activities, communities, tags }

class AppSearchController extends GetxController {
  final SearchRepository _repository = SearchRepository();
  final SearchHistoryService _historyService = Get.find<SearchHistoryService>();

  final TextEditingController textController = TextEditingController();
  final RxString query = ''.obs;
  final Rx<SearchState> state = SearchState.initial.obs;
  final Rx<SearchFilter> filter = SearchFilter.all.obs;
  final RxList<SearchResultItem> results = <SearchResultItem>[].obs;
  final RxList<AccountSuggestion> suggestedProfiles = <AccountSuggestion>[].obs;
  final RxBool isLoadingSuggestions = false.obs;
  final RxString errorMessage = ''.obs;

  final Map<String, List<SearchResultItem>> _sessionCache = {};
  String _latestExecutingQuery = '';

  List<String> get recentSearches => _historyService.recentSearches;

  @override
  void onInit() {
    super.onInit();
    debounce(query, _onQueryChanged, time: const Duration(milliseconds: 400));
    unawaited(loadSuggestedProfiles());
  }

  @override
  void onClose() {
    textController.dispose();
    super.onClose();
  }

  Future<void> loadSuggestedProfiles({int limit = 30, int offset = 0}) async {
    isLoadingSuggestions.value = true;
    try {
      final profiles = await _repository.getSuggestedProfiles(limit: limit, offset: offset);
      if (offset == 0) {
        suggestedProfiles.assignAll(profiles);
      } else {
        suggestedProfiles.addAll(profiles);
      }
    } catch (e, stack) {
      debugPrint('[FOLLOW] get_suggested_profiles UI exception=$e\\n$stack');
    } finally {
      isLoadingSuggestions.value = false;
    }
  }

  void onQueryChanged(String val) {
    query.value = val;
  }

  void _onQueryChanged(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      state.value = SearchState.initial;
      results.clear();
      return;
    }

    executeSearch(trimmed);
  }

  Future<void> executeSearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;

    _latestExecutingQuery = trimmed;
    await _historyService.addSearch(trimmed);

    if (_sessionCache.containsKey(trimmed)) {
      results.value = _sessionCache[trimmed]!;
      state.value = results.isEmpty ? SearchState.empty : SearchState.success;
      return;
    }

    state.value = SearchState.loading;
    try {
      final res = await _repository.searchAll(trimmed);
      if (_latestExecutingQuery == trimmed) {
        _sessionCache[trimmed] = res;
        results.value = res;
        state.value = res.isEmpty ? SearchState.empty : SearchState.success;
      }
    } catch (e) {
      if (_latestExecutingQuery == trimmed) {
        debugPrint('[SearchController] error in executeSearch: $e');
        errorMessage.value = 'search_error_msg'.tr;
        state.value = SearchState.error;
      }
    }
  }

  void retryLastSearch() {
    if (query.value.trim().isNotEmpty) {
      executeSearch(query.value);
    }
  }

  void selectRecentSearch(String q) {
    textController.text = q;
    query.value = q;
    executeSearch(q);
  }

  void setFilter(SearchFilter f) {
    filter.value = f;
  }

  List<SearchResultItem> get filteredResults {
    final list = results;
    switch (filter.value) {
      case SearchFilter.all:
        return list;
      case SearchFilter.users:
        return list.where((item) => item.category == 'user').toList();
      case SearchFilter.events:
        return list.where((item) => item.category == 'event').toList();
      case SearchFilter.activities:
        return list.where((item) => item.category == 'activity').toList();
      case SearchFilter.communities:
        return list.where((item) => item.category == 'community').toList();
      case SearchFilter.tags:
        return list.where((item) => item.category == 'tag' || item.category == 'hashtag').toList();
    }
  }

  void clearQuery() {
    textController.clear();
    query.value = '';
    state.value = SearchState.initial;
    results.clear();
  }

  void clearHistory() {
    _historyService.clearHistory();
  }

  void invalidateSearchCache() {
    _sessionCache.clear();
  }

  bool isOpeningCommunity = false;

  Future<void> _openCommunity(SearchResultItem item) async {
    if (isOpeningCommunity) return;
    isOpeningCommunity = true;

    try {
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      final communityService = Get.isRegistered<CommunityService>()
          ? Get.find<CommunityService>()
          : Get.put(CommunityService());

      final openResult = await communityService.openCommunity(item.id);

      if (Get.isDialogOpen == true) {
        Get.back();
      }

      isOpeningCommunity = false;

      if (openResult.destination == 'community') {
        Get.to(() => CommunityFeedScreen(
              communityId: item.id,
              communityName: openResult.name ?? item.title,
            ));
      } else if (openResult.destination == 'preview') {
        if (Get.context != null) {
          showCommunityPreviewSheet(Get.context!, result: openResult);
        }
      } else {
        Get.snackbar(
          'community_unavailable_msg'.tr,
          'community_unavailable_msg'.tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      isOpeningCommunity = false;
      debugPrint('[SearchController] openCommunity error: $e');
      Get.snackbar(
        'community_unavailable_msg'.tr,
        e.toString().replaceFirst('Exception: ', '').tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void onItemTap(SearchResultItem item) {
    switch (item.category) {
      case 'user':
        Get.toNamed(AppPages.externalProfilePath(item.id));
        break;
      case 'event':
        Get.toNamed(AppPages.eventPreview.replaceFirst(':id', item.id));
        break;
      case 'activity':
        Get.toNamed(AppPages.eventPreview.replaceFirst(':id', item.id));
        break;
      case 'community':
        _openCommunity(item);
        break;
      case 'tag':
      case 'hashtag':
        Get.toNamed(AppPages.hashtagFeedPath(item.title.replaceFirst(RegExp(r'^#+'), '')));
        break;
      default:
        break;
    }
  }
}
