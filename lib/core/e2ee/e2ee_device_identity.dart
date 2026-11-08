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
  Future<String> getOrCreate({required String userId}) async {
    final key = _key(userId);
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

    // Re-read before write to avoid replacing an identity created by another
    // startup path racing on the same account.
    final raced = await _storage.read(key: key);
    if (raced != null) {
      if (!_isUuidV4(raced)) {
        throw StateError('Stored E2EE device identity is malformed.');
      }
      return raced;
    }
    await _storage.write(key: key, value: id);
    return id;
  }

  Future<void> delete({required String userId}) =>
      _storage.delete(key: _key(userId));

  bool _isUuidV4(String value) =>
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-'
              r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$')
          .hasMatch(value);
}
