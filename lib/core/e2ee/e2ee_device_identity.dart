import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stable, account-scoped identity for one app installation.
///
/// This identifier is not a hardware fingerprint. It is a random UUIDv4
/// generated locally and persisted in the platform secure store. A different
/// Scrole account on the same installation receives a different MLS device
/// identifier.
class E2eeDeviceIdentity {
  E2eeDeviceIdentity({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'scrole.e2ee.device_identity.v1';
  final FlutterSecureStorage _storage;
  final Map<String, Future<String>> _pendingCreations = {};

  String _key(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    return '$_prefix.$normalized';
  }

  /// Returns the current identity without creating a new one.
  Future<String?> getExisting({required String userId}) async {
    final value = await _storage.read(key: _key(userId));
    if (value == null) return null;
    if (!_isUuidV4(value)) {
      throw StateError('Stored E2EE device identity is malformed.');
    }
    return value;
  }

  /// Returns a persistent random UUIDv4 for this account on this installation.
  ///
  /// Calls made concurrently through this instance are serialized per account.
  /// Keep this service as an application-level singleton.
  Future<String> getOrCreate({required String userId}) {
    final key = _key(userId);
    final pending = _pendingCreations[key];
    if (pending != null) return pending;

    final creation = _readOrCreate(key);
    _pendingCreations[key] = creation;
    return creation.whenComplete(() => _pendingCreations.remove(key));
  }

  Future<String> _readOrCreate(String key) async {
    final existing = await _storage.read(key: key);
    if (existing != null) {
      if (!_isUuidV4(existing)) {
        throw StateError('Stored E2EE device identity is malformed.');
      }
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // RFC 4122 UUIDv4 version and variant bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final id = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
    await _storage.write(key: key, value: id);
    return id;
  }

  /// Returns the current identity without creating a new one.
  Future<String?> getExisting({required String userId}) async {
    final value = await _storage.read(key: _key(userId));
    if (value == null) return null;
    if (!_isUuidV4(value)) {
      throw StateError('Stored E2EE device identity is malformed.');
    }
    return value;
  }

  Future<void> delete({required String userId}) =>
      _storage.delete(key: _key(userId));

  bool _isUuidV4(String value) =>
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-'
              r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$')
          .hasMatch(value);
}
