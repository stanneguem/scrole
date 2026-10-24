import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../service_global/supabse_service.dart';

class CurrencyModel {
  final String code;
  final String symbol;
  final String name;

  const CurrencyModel({
    required this.code,
    required this.symbol,
    required this.name,
  });

  factory CurrencyModel.fromJson(Map<String, dynamic> json) {
    return CurrencyModel(
      code: json['code']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? (json['code']?.toString() ?? ''),
      name: json['name']?.toString() ?? (json['code']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'symbol': symbol,
      'name': name,
    };
  }

  String get displayLabel => '$symbol ($code) - $name';
}

class CurrencyRepository {
  final SupabaseService _supabase = Get.find();
  SupabaseClient get client => _supabase.client;

  /// Récupère la liste des devises actives depuis la table public.currencies
  Future<List<CurrencyModel>> getCurrencies() async {
    try {
      final response = await client
          .from('currencies')
          .select()
          .order('code');

      final List<dynamic> data = response is List ? response : [];
      return data.map((e) => CurrencyModel.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      debugPrint('[Error] Fetch currencies from public.currencies: $e');
      return [];
    }
  }

  /// Récupère le code de la devise par défaut d'un pays depuis public.countries
  Future<String?> getDefaultCurrencyForCountry(String countryId) async {
    try {
      final response = await client
          .from('countries')
          .select('default_currency_code')
          .eq('id', countryId)
          .maybeSingle();

      if (response == null) return null;
      return response['default_currency_code']?.toString();
    } catch (e) {
      debugPrint('[Error] Fetch default currency for country $countryId: $e');
      return null;
    }
  }
}
