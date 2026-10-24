import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

class FastCacheService extends GetxService {
  Box? _box;
  bool _ready = false;
  bool get isReady => _ready;

  Future<FastCacheService> init() async {
    if (_ready) return this;
    
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox('app_cache');
      _ready = true;
      return this;
    } catch (e) {
      print('FastCacheService Error: $e');
      _ready = false;
      rethrow;
    }
  }

  Box get box {
    if (!_ready || _box == null) {
      throw Exception('FastCacheService not initialized');
    }
    return _box!;
  }

  T? get<T>(String key, {Duration? maxAge}) {
    if (!_ready) return null;
    
    try {
      final raw = box.get(key);
      if (raw == null) return null;
      if (raw is! Map || raw['t'] == null) {
        return _deepCast(raw) as T?;
      }
      
      final entry = _CacheEntry.fromMap(raw);
      if (maxAge != null) {
        final age = DateTime.now().difference(entry.storedAt);
        if (age > maxAge) {
          box.delete(key);
          return null;
        }
      }
      return _deepCast(entry.data) as T?;
    } catch (e) {
      return null;
    }
  }

  Future<void> set(String key, dynamic value) async {
    if (!_ready) return;
    try {
      final entry = _CacheEntry(data: value, storedAt: DateTime.now());
      await box.put(key, entry.toMap());
    } catch (e) {
      print('Cache set error: $e');
    }
  }

  Future<void> remove(String key) async {
    if (!_ready) return;
    try {
      await box.delete(key);
    } catch (e) {
      print('Cache remove error: $e');
    }
  }

  Future<void> clear() async {
    if (!_ready) return;
    try {
      await box.clear();
    } catch (e) {
      print('Cache clear error: $e');
    }
  }

  Future<void> clearPattern(String pattern) async {
    if (!_ready) return;
    try {
      final keysToDelete = box.keys
          .where((k) => k is String && k.startsWith(pattern))
          .toList();
      for (final k in keysToDelete) {
        await box.delete(k);
      }
    } catch (e) {
      print('Cache clearPattern error: $e');
    }
  }

  dynamic _deepCast(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _deepCast(v)));
    }
    if (value is List) {
      return value.map(_deepCast).toList();
    }
    return value;
  }
}

class _CacheEntry {
  _CacheEntry({required this.data, required this.storedAt});
  final dynamic data;
  final DateTime storedAt;

  Map<String, dynamic> toMap() => {
    'd': data,
    't': storedAt.millisecondsSinceEpoch,
  };

  factory _CacheEntry.fromMap(Map<dynamic, dynamic> map) {
    return _CacheEntry(
      data: map['d'],
      storedAt: DateTime.fromMillisecondsSinceEpoch(map['t'] as int),
    );
  }
}
