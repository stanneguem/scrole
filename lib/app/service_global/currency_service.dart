import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../local_storage/fast/fast_cache_service.dart';
import '../repository_global/currency_repository.dart';

class CurrencyService extends GetxService {
  final CurrencyRepository _repository = CurrencyRepository();
  FastCacheService? _cache;

  static const String _cacheKey = 'app_currencies';

  final RxList<CurrencyModel> currencies = <CurrencyModel>[].obs;
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    try {
      if (Get.isRegistered<FastCacheService>()) {
        _cache = Get.find<FastCacheService>();
      }
    } catch (_) {}
    loadCurrencies();
  }

  Future<void> loadCurrencies({bool forceRefresh = false}) async {
    isLoading.value = true;
    try {
      // 1. Essai depuis le cache rapide local
      if (!forceRefresh && _cache != null && _cache!.isReady) {
        final cachedData = _cache!.get<List<dynamic>>(_cacheKey);
        if (cachedData != null && cachedData.isNotEmpty) {
          final list = cachedData
              .map((e) => CurrencyModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          currencies.assignAll(list);
          isLoading.value = false;
          // Synchronisation en arrière-plan
          _fetchRemote();
          return;
        }
      }

      await _fetchRemote();
    } catch (e) {
      debugPrint('[Error] CurrencyService.loadCurrencies: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _fetchRemote() async {
    final remoteList = await _repository.getCurrencies();
    if (remoteList.isNotEmpty) {
      currencies.assignAll(remoteList);
      if (_cache != null && _cache!.isReady) {
        await _cache!.set(_cacheKey, remoteList.map((c) => c.toJson()).toList());
      }
    } else if (currencies.isEmpty) {
      // Fallback de sécurité minimale si la table distante est temporairement inaccessible
      currencies.assignAll(const [
        CurrencyModel(code: 'XAF', symbol: 'FCFA', name: 'Franc CFA (CEMAC)'),
        CurrencyModel(code: 'XOF', symbol: 'FCFA', name: 'Franc CFA (UEMOA)'),
        CurrencyModel(code: 'EUR', symbol: '€', name: 'Euro'),
        CurrencyModel(code: 'USD', symbol: '\$', name: 'Dollar US'),
      ]);
    }
  }

  /// Retourne le symbole associé à un code devise
  String getSymbol(String code) {
    final match = currencies.firstWhereOrNull((c) => c.code.toUpperCase() == code.toUpperCase());
    return match?.symbol ?? code;
  }

  /// Code devise par défaut (XAF ou premier disponible)
  String get defaultCurrencyCode {
    if (currencies.any((c) => c.code == 'XAF')) return 'XAF';
    return currencies.isNotEmpty ? currencies.first.code : 'XAF';
  }

  /// Récupère la devise par défaut pour un pays spécifique
  Future<String> getDefaultCurrencyForCountry(String? countryId) async {
    if (countryId == null || countryId.isEmpty) return defaultCurrencyCode;
    final code = await _repository.getDefaultCurrencyForCountry(countryId);
    if (code != null && currencies.any((c) => c.code == code)) {
      return code;
    }
    return defaultCurrencyCode;
  }
}
