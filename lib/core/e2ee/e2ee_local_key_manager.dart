import 'e2ee_device_identity.dart';
import 'secure_mls_storage_key.dart';

/// Resolves account-scoped installation identity and provisions the local
/// secure-storage placeholder. No key material is returned to Dart callers.
class E2eeLocalKeyManager {
  E2eeLocalKeyManager({
    E2eeDeviceIdentity? identity,
    SecureMlsStorageKey? storageKey,
  })  : _identity = identity ?? E2eeDeviceIdentity(),
        _storageKey = storageKey ?? SecureMlsStorageKey();

  final E2eeDeviceIdentity _identity;
  final SecureMlsStorageKey _storageKey;

  Future<({String deviceId, bool storageKeyProvisioned})> prepareAccount({
    required String userId,
  }) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    final deviceId = await _identity.getOrCreate(userId: userId);
    await _storageKey.ensureProvisioned(userId: userId, deviceId: deviceId);
    return (deviceId: deviceId, storageKeyProvisioned: true);
  }

  /// Deletes local placeholder material after an explicit local reset.
  ///
  /// This does not revoke a server device or provide recovery. Those operations
  /// must be coordinated with a future native MLS lifecycle implementation.
  Future<void> deleteAccountMaterial({required String userId}) async {
    final deviceId = await _identity.getExisting(userId: userId);
    if (deviceId == null) return;
    await _storageKey.delete(userId: userId, deviceId: deviceId);
    await _identity.delete(userId: userId);
  }
}
