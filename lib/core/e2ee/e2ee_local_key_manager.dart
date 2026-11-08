import 'dart:typed_data';

import 'e2ee_device_identity.dart';
import 'secure_mls_storage_key.dart';

/// Resolves the installation identity and local database wrapping key for an
/// authenticated Scrole account.
///
/// This is preparation for the persistent OpenMLS provider; it does not create
/// an MLS credential, publish a KeyPackage, or enable message encryption.
class E2eeLocalKeyManager {
  E2eeLocalKeyManager({
    E2eeDeviceIdentity? identity,
    SecureMlsStorageKey? storageKey,
  })  : _identity = identity ?? E2eeDeviceIdentity(),
        _storageKey = storageKey ?? SecureMlsStorageKey();

  final E2eeDeviceIdentity _identity;
  final SecureMlsStorageKey _storageKey;

  Future<({String deviceId, Uint8List databaseKey})> prepareAccount({
    required String userId,
  }) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    final deviceId = await _identity.getOrCreate(userId: userId);
    final databaseKey = await _storageKey.getOrCreate(
      userId: userId,
      deviceId: deviceId,
    );
    if (databaseKey.length != 32) {
      throw StateError('MLS database wrapping key must be 256 bits.');
    }
    return (deviceId: deviceId, databaseKey: databaseKey);
  }

  /// Deletes local identity material for a signed-out/revoked account.
  ///
  /// Call only after explicit account-device revocation or a deliberate
  /// local reset. Deleting the key without a recoverable backup destroys
  /// access to the encrypted MLS state on this installation.
  Future<void> deleteAccountMaterial({required String userId}) async {
    final deviceId = await _identity.getExisting(userId: userId);
    if (deviceId == null) return;
    await _storageKey.delete(userId: userId, deviceId: deviceId);
    await _identity.delete(userId: userId);
  }
}
