import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/models/interest_model.dart';
import '../local_storage/structured/app_cache_database.dart';
import '../repository_global/centre_interets_repository.dart';

class InterestService extends GetxService {
  final InterestRepository _repository;
  final AppDatabase _db = Get.find<AppDatabase>();

  InterestService(this._repository);

  static const String _cacheKey = 'global_interests';
  Future<List<Interest>>? _inFlightInterestsFuture;
  List<Interest>? _memoryCache;

  /// Récupère tous les centres d'intérêt disponibles (avec mémoïsation et cache persistant de 5h).
  Future<List<Interest>> getInterests({bool forceRefresh = false}) async {
    if (!forceRefresh && _memoryCache != null && _memoryCache!.isNotEmpty) {
      return _memoryCache!;
    }

    if (!forceRefresh && _inFlightInterestsFuture != null) {
      return await _inFlightInterestsFuture!;
    }

    _inFlightInterestsFuture = _fetchInterests(forceRefresh: forceRefresh);
    try {
      final results = await _inFlightInterestsFuture!;
      _memoryCache = results;
      return results;
    } finally {
      _inFlightInterestsFuture = null;
    }
  }

  Future<List<Interest>> _fetchInterests({required bool forceRefresh}) async {
    final now = DateTime.now();

    if (!forceRefresh) {
      try {
        final db = await _db.database;
        final rows = await db.query('discovery_cache', where: 'key = ?', whereArgs: [_cacheKey], limit: 1);

        if (rows.isNotEmpty) {
          final cachedAt = DateTime.fromMillisecondsSinceEpoch(rows.first['cached_at'] as int);
          final age = now.difference(cachedAt);

          if (age < const Duration(hours: 5)) {
            final List<dynamic> list = jsonDecode(rows.first['payload'] as String);
            debugPrint('[Sync] Loading interests from cache (Age: ${age.inMinutes} min)');
            return list.map((e) => Interest.fromJson(Map<String, dynamic>.from(e))).toList();
          }
        }
      } catch (e) {
        debugPrint('[Warning] Interest cache read failed: $e');
      }
    }

    debugPrint('[Sync] Fetching interests from backend...');
    try {
      final interests = await _repository.getInterests();

      final db = await _db.database;
      await db.insert('discovery_cache', {
        'key': _cacheKey,
        'payload': jsonEncode(interests.map((e) => e.toJson()).toList()),
        'cached_at': now.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      return interests;
    } catch (e) {
      debugPrint('[Error] Interest fetch failed: $e');
      try {
        final db = await _db.database;
        final rows = await db.query('discovery_cache', where: 'key = ?', whereArgs: [_cacheKey], limit: 1);
        if (rows.isNotEmpty) {
          final List<dynamic> list = jsonDecode(rows.first['payload'] as String);
          return list.map((e) => Interest.fromJson(Map<String, dynamic>.from(e))).toList();
        }
      } catch (_) {}
      return [];
    }
  }

  /// Récupère les intérêts d'un utilisateur spécifique.
  Future<List<String>> getUserInterestIds(String userId) async {
    return await _repository.getUserInterestIds(userId);
  }

  /// Met à jour les intérêts de l'utilisateur.
  Future<void> saveUserInterests(String userId, List<String> interestIds) async {
    await _repository.updateUserInterests(userId, interestIds);
  }

  /// Vide le cache global.
  Future<void> clearCache() async {
    _memoryCache = null;
    final db = await _db.database;
    await db.delete('discovery_cache', where: 'key = ?', whereArgs: [_cacheKey]);
  }
}
