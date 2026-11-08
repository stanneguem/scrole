import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores only the random wrapping key used by the native MLS database.
///
/// The MLS database itself remains owned by the Rust engine. Never store MLS
/// signing private keys, KeyPackages, group secrets or plaintext messages here.
class SecureMlsStorageKey {
  SecureMlsStorageKey({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, Future<Uint8List>> _pendingCreations = {};

  String _storageKey(String userId, String deviceId) {
    if (userId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('A non-empty userId and deviceId are required.');
    }
    return 'scrole.e2ee.mls.storage_key.v1.$userId.$deviceId';
  }

  /// Returns the existing 256-bit database key or creates it once.
  ///
  /// Calls made concurrently through this instance are serialized per key.
  /// Keep this service as an application-level singleton.
  ///
  /// The key is persisted through the platform secure-storage plugin. This
  /// Dart API is a bootstrap stage only: do not pass the key to production MLS
  /// code until the native bridge can keep and zeroize it on the Rust side.
  Future<Uint8List> getOrCreate({
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

  Future<Uint8List> _readOrCreate(String key) async {
    final encoded = await _storage.read(key: key);
    if (encoded != null) {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      if (bytes.length != 32) {
        throw StateError('Stored MLS database key has an invalid length.');
      }
      return Uint8List.fromList(bytes);
    }

    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256), growable: false),
    );
    await _storage.write(key: key, value: base64UrlEncode(bytes));
    return Uint8List.fromList(bytes);
  }

  /// Deletes the local database wrapping key. This makes the corresponding
  /// encrypted MLS database unrecoverable unless a separately designed,
  /// authenticated recovery mechanism exists.
  Future<void> delete({
    required String userId,
    required String deviceId,
  }) =>
      _storage.delete(key: _storageKey(userId, deviceId));
}
