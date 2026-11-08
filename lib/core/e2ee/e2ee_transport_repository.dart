import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase transport for opaque MLS records.
///
/// This class never accepts or returns plaintext message content and never
/// performs cryptographic operations. Callers must pass bytes produced by the
/// native OpenMLS engine. It is intentionally not wired into legacy chat
/// screens until the native engine can create/process MLS messages.
class E2eeTransportRepository {
  E2eeTransportRepository(this._client);

  final SupabaseClient _client;

  static const ciphersuite =
      'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519';

  Future<String> registerDevice({
    required String installationId,
    required String platform,
    required String deviceLabel,
    required Uint8List publicCredential,
    required Uint8List credentialFingerprint,
  }) async {
    if (installationId.trim().length < 16 ||
        !const {'android', 'ios'}.contains(platform) ||
        publicCredential.isEmpty ||
        publicCredential.length > 8192 ||
        credentialFingerprint.length != 32) {
      throw ArgumentError('Invalid E2EE device registration data.');
    }
    final result = await _client.rpc(
      'e2ee_register_device',
      params: {
        'p_installation_id': installationId,
        'p_platform': platform,
        'p_device_label': deviceLabel,
        'p_public_credential': encodePostgresBytea(publicCredential),
        'p_credential_fingerprint': encodePostgresBytea(credentialFingerprint),
      },
    );
    if (result is! String || result.isEmpty) {
      throw StateError('Supabase did not return an E2EE device identifier.');
    }
    return result;
  }

  Future<void> publishKeyPackage({
    required String deviceId,
    required Uint8List keyPackage,
    required Uint8List packageHash,
    DateTime? expiresAt,
  }) async {
    if (keyPackage.isEmpty || keyPackage.length > 65536) {
      throw ArgumentError.value(keyPackage.length, 'keyPackage');
    }
    if (packageHash.length != 32) {
      throw ArgumentError.value(packageHash.length, 'packageHash');
    }
    final expiry = (expiresAt ?? DateTime.now().toUtc().add(const Duration(days: 7)))
        .toUtc();
    if (!expiry.isAfter(DateTime.now().toUtc())) {
      throw ArgumentError('KeyPackage expiry must be in the future.');
    }
    await _client.from('e2ee_key_packages').insert({
      'device_id': deviceId,
      'ciphersuite': ciphersuite,
      'key_package': encodePostgresBytea(keyPackage),
      'package_hash': encodePostgresBytea(packageHash),
      'expires_at': expiry.toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> claimKeyPackage({
    required String scopeType,
    required String scopeId,
    required String targetDeviceId,
    required String claimingDeviceId,
  }) async {
    _validateScope(scopeType, scopeId);
    final rows = await _client.rpc(
      'e2ee_claim_key_package_for_scope',
      params: {
        'p_scope_type': scopeType,
        'p_scope_id': scopeId,
        'p_target_device_id': targetDeviceId,
        'p_claiming_device_id': claimingDeviceId,
      },
    );
    if (rows is! List || rows.isEmpty) return null;
    if (rows.length != 1 || rows.first is! Map) {
      throw StateError('Unexpected KeyPackage claim response.');
    }
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<String> createGroup({
    required String scopeType,
    required String scopeId,
    required Uint8List mlsGroupId,
    required String creatorDeviceId,
  }) async {
    _validateScope(scopeType, scopeId);
    if (mlsGroupId.isEmpty || mlsGroupId.length > 255) {
      throw ArgumentError.value(mlsGroupId.length, 'mlsGroupId');
    }
    final result = await _client.rpc(
      'e2ee_create_group',
      params: {
        'p_scope_type': scopeType,
        'p_scope_id': scopeId,
        'p_mls_group_id': encodePostgresBytea(mlsGroupId),
        'p_creator_device_id': creatorDeviceId,
      },
    );
    if (result is! String || result.isEmpty) {
      throw StateError('Supabase did not return an E2EE group identifier.');
    }
    return result;
  }

  Future<int> applyCommit({
    required String groupId,
    required int expectedEpoch,
    required Uint8List commitCiphertext,
    required List<String> activeDeviceIds,
  }) async {
    if (expectedEpoch < 0 ||
        commitCiphertext.isEmpty ||
        commitCiphertext.length > 1048576 ||
        activeDeviceIds.isEmpty ||
        activeDeviceIds.length > 512 ||
        activeDeviceIds.toSet().length != activeDeviceIds.length) {
      throw ArgumentError('Invalid MLS commit or device roster.');
    }
    final result = await _client.rpc(
      'e2ee_apply_group_commit',
      params: {
        'p_group_id': groupId,
        'p_expected_epoch': expectedEpoch,
        'p_commit_ciphertext': encodePostgresBytea(commitCiphertext),
        'p_active_device_ids': activeDeviceIds,
      },
    );
    if (result is! int) {
      throw StateError('Supabase did not return the committed MLS epoch.');
    }
    return result;
  }

  Future<String> sendCiphertext({
    required String groupId,
    required int epoch,
    required String senderDeviceId,
    required Uint8List ciphertext,
  }) async {
    if (epoch < 0 || ciphertext.isEmpty || ciphertext.length > 1048576) {
      throw ArgumentError('Invalid MLS application ciphertext.');
    }
    final result = await _client.rpc(
      'e2ee_send_group_message',
      params: {
        'p_group_id': groupId,
        'p_epoch': epoch,
        'p_sender_device_id': senderDeviceId,
        'p_ciphertext': encodePostgresBytea(ciphertext),
      },
    );
    if (result is! String || result.isEmpty) {
      throw StateError('Supabase did not return an E2EE message identifier.');
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> fetchCiphertexts({
    required String groupId,
    DateTime? after,
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 500');
    }
    var query = _client
        .from('e2ee_messages')
        .select(
          'id,group_id,sender_user_id,sender_device_id,epoch,message_kind,ciphertext,created_at',
        )
        .eq('group_id', groupId);
    if (after != null) {
      query = query.gt('created_at', after.toUtc().toIso8601String());
    }
    final rows = await query.order('created_at').limit(limit);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> revokeDevice({required String deviceId}) async {
    final result = await _client.rpc(
      'e2ee_revoke_device',
      params: {'p_device_id': deviceId},
    );
    if (result != true) {
      throw StateError('E2EE device could not be revoked.');
    }
  }

  /// Encodes bytes in PostgreSQL's canonical hex bytea input representation.
  static String encodePostgresBytea(Uint8List bytes) {
    final buffer = StringBuffer(r'\x');
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static void _validateScope(String scopeType, String scopeId) {
    if (!const {'direct', 'community_salon'}.contains(scopeType) ||
        scopeId.trim().isEmpty) {
      throw ArgumentError('Invalid E2EE conversation scope.');
    }
  }
}
