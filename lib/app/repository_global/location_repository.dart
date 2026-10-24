import 'package:supabase_flutter/supabase_flutter.dart';
import '../local_storage/fast/fast_cache_service.dart';


/// Pays ou ville tels que renvoyés par les tables `countries`/`cities`.
class LocationOption {
  const LocationOption({
    required this.id,
    required this.nom,
    this.codeIso,
  });

  final String id;
  final String nom;
  final String? codeIso;

  factory LocationOption.fromCountryJson(Map<String, dynamic> json) {
    return LocationOption(
      id: json['id'] as String,
      nom: json['nom'] as String,
      codeIso: json['code_iso'] as String?,
    );
  }

  factory LocationOption.fromCityJson(Map<String, dynamic> json) {
    return LocationOption(
      id: json['id'] as String,
      nom: json['nom'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    if (codeIso != null) 'code_iso': codeIso,
  };
}
abstract class LocationRepository {
  Future<List<LocationOption>> getCountries();
  Future<List<LocationOption>> getCitiesForCountry(String countryId);
}

class SupabaseLocationRepository implements LocationRepository {
  SupabaseLocationRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<LocationOption>> getCountries() async {
    final rows = await _client
        .from('countries')
        .select()
        .eq('is_active', true)
        .order('nom');
    print(rows.length);

    return rows.map((row) => LocationOption.fromCountryJson(row)).toList();
  }

  @override
  Future<List<LocationOption>> getCitiesForCountry(String countryId) async {
    final rows = await _client
        .from('cities')
        .select()
        .eq('country_id', countryId)
        .eq('is_active', true)
        .order('nom');

    return rows.map((row) => LocationOption.fromCityJson(row)).toList();
  }
}

/// Décorateur cache-first pour les localisations.
/// Pays : cache 30 jours | Villes : cache 7 jours par pays.
class CachedLocationRepository implements LocationRepository {
  CachedLocationRepository(
      this._remote,
      this._cache, {
        this.countriesMaxAge = const Duration(days: 30),
        this.citiesMaxAge = const Duration(days: 7),
      });

  final LocationRepository _remote;
  final FastCacheService _cache;
  final Duration countriesMaxAge;
  final Duration citiesMaxAge;

  static const _countriesKey = 'location_countries';
  String _citiesKey(String countryId) => 'location_cities_$countryId';

  @override
  Future<List<LocationOption>> getCountries() async {
    // 1. Cache d'abord
    final cached = _cache.get<List<dynamic>>(_countriesKey, maxAge: countriesMaxAge);
    if (cached != null && cached.isNotEmpty) {
      return cached.map((e) => LocationOption.fromCountryJson(Map<String, dynamic>.from(e))).toList();
    }

    // 2. Réseau
    final fresh = await _remote.getCountries();
    await _cache.set(_countriesKey, fresh.map((c) => c.toJson()).toList());
    return fresh;
  }

  @override
  Future<List<LocationOption>> getCitiesForCountry(String countryId) async {
    final key = _citiesKey(countryId);

    // 1. Cache d'abord
    final cached = _cache.get<List<dynamic>>(key, maxAge: citiesMaxAge);
    if (cached != null && cached.isNotEmpty) {
      return cached.map((e) => LocationOption.fromCityJson(Map<String, dynamic>.from(e))).toList();
    }

    // 2. Réseau
    final fresh = await _remote.getCitiesForCountry(countryId);
    await _cache.set(key, fresh.map((c) => c.toJson()).toList());
    return fresh;
  }

  /// Force le rechargement réseau (pour le retry manuel)
  Future<List<LocationOption>> refreshCountries() async {
    _cache.remove(_countriesKey);
    return getCountries();
  }

  Future<List<LocationOption>> refreshCities(String countryId) async {
    _cache.remove(_citiesKey(countryId));
    return getCitiesForCountry(countryId);
  }
}