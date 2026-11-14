import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provisions a random 256-bit value in the platform secure-storage plugin.
///
/// IMPORTANT: this is only a bootstrap reservation. It deliberately never
/// returns key bytes to application code. The Rust MLS provider is not allowed
/// to use this value until a native Keystore/Keychain bridge can unwrap it
/// without exposing it to Dart.
class SecureMlsStorageKey {
  SecureMlsStorageKey({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, Future<void>> _pendingCreations = {};

  String _storageKey(String userId, String deviceId) {
    if (userId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('A non-empty userId and deviceId are required.');
    }
    return 'scrole.e2ee.mls.storage_key.v1.$userId.$deviceId';
  }

  /// Ensures a 256-bit placeholder key exists without returning its bytes.
  ///
  /// This is not yet the production native key lifecycle. Do not connect it to
  /// OpenMLS until Android Keystore/iOS Keychain native wrapping is implemented.
  Future<void> ensureProvisioned({
    required String userId,
    required String deviceId,
  }) {
    final key = _storageKey(userId, deviceId);
    final pending = _pendingCreations[key];
    if (pending != null) return pending;

    final creation = _readOrCreate(key);
    _pendingCreations[key] = creation;
    return creation.whenComplete(() => _pendingCreations.remove(key));
  }

  Future<void> _readOrCreate(String key) async {
    final encoded = await _storage.read(key: key);
    if (encoded != null) {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      if (bytes.length != 32) {
        throw StateError('Stored MLS database key has an invalid length.');
      }
      return;
    }

    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256), growable: false),
    );
    await _storage.write(key: key, value: base64UrlEncode(bytes));
    bytes.fillRange(0, bytes.length, 0);
  }

  /// Deletes the placeholder. Production revocation must also destroy the
  /// native wrapped key and encrypted MLS database in a coordinated operation.
  Future<void> delete({
    required String userId,
    required String deviceId,
  }) =>
      _storage.delete(key: _storageKey(userId, deviceId));
}
