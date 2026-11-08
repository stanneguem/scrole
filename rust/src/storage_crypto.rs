//! Authenticated encryption for persistent OpenMLS storage records.
//!
//! This module is intentionally not exposed through the Flutter bridge yet.
//! The 256-bit key must eventually be obtained and used inside the native
//! platform boundary, not passed through ordinary Dart application code.

use chacha20poly1305::{
    XChaCha20Poly1305, XNonce,
    aead::{Aead, KeyInit, Payload},
};
use zeroize::{Zeroize, Zeroizing};

const MAGIC: &[u8; 4] = b"SCM1";
const NONCE_LEN: usize = 24;
const KEY_LEN: usize = 32;
const DOMAIN: &[u8] = b"scrole/openmls-storage/v1\0";

/// Native-only wrapping key. Zeroized when its owner is dropped.
pub(crate) struct StorageKey(Zeroizing<[u8; KEY_LEN]>);

impl StorageKey {
    pub(crate) fn from_bytes(bytes: [u8; KEY_LEN]) -> Self {
        Self(Zeroizing::new(bytes))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum StorageCryptoError {
    InvalidKey,
    InvalidRecord,
    RandomnessUnavailable,
    AuthenticationFailed,
}

impl core::fmt::Display for StorageCryptoError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::InvalidKey => f.write_str("invalid MLS storage key"),
            Self::InvalidRecord => f.write_str("invalid encrypted MLS storage record"),
            Self::RandomnessUnavailable => f.write_str("secure randomness unavailable"),
            Self::AuthenticationFailed => f.write_str("MLS storage record authentication failed"),
        }
    }
}

impl std::error::Error for StorageCryptoError {}

fn associated_data(storage_key: &[u8]) -> Vec<u8> {
    let mut aad = Vec::with_capacity(DOMAIN.len() + 8 + storage_key.len());
    aad.extend_from_slice(DOMAIN);
    aad.extend_from_slice(&(storage_key.len() as u64).to_be_bytes());
    aad.extend_from_slice(storage_key);
    aad
}

/// Encrypts one serialized OpenMLS value using a fresh 192-bit nonce.
///
/// The storage key is authenticated as AAD, preventing a valid ciphertext
/// from being copied to a different OpenMLS storage slot.
pub(crate) fn seal_record(
    key: &StorageKey,
    storage_key: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>, StorageCryptoError> {
    let cipher = XChaCha20Poly1305::new_from_slice(&key.0[..])
        .map_err(|_| StorageCryptoError::InvalidKey)?;
    let mut nonce_bytes = [0u8; NONCE_LEN];
    getrandom::fill(&mut nonce_bytes)
        .map_err(|_| StorageCryptoError::RandomnessUnavailable)?;

    let aad = associated_data(storage_key);
    let ciphertext = cipher
        .encrypt(
            XNonce::from_slice(&nonce_bytes),
            Payload { msg: plaintext, aad: &aad },
        )
        .map_err(|_| StorageCryptoError::AuthenticationFailed)?;

    let mut record = Vec::with_capacity(MAGIC.len() + NONCE_LEN + ciphertext.len());
    record.extend_from_slice(MAGIC);
    record.extend_from_slice(&nonce_bytes);
    record.extend_from_slice(&ciphertext);
    nonce_bytes.zeroize();
    Ok(record)
}

/// Authenticates and decrypts one record for its original storage slot.
pub(crate) fn open_record(
    key: &StorageKey,
    storage_key: &[u8],
    record: &[u8],
) -> Result<Vec<u8>, StorageCryptoError> {
    if record.len() < MAGIC.len() + NONCE_LEN + 16 || !record.starts_with(MAGIC) {
        return Err(StorageCryptoError::InvalidRecord);
    }

    let nonce_start = MAGIC.len();
    let ciphertext_start = nonce_start + NONCE_LEN;
    let nonce = XNonce::from_slice(&record[nonce_start..ciphertext_start]);
    let aad = associated_data(storage_key);
    let cipher = XChaCha20Poly1305::new_from_slice(&key.0[..])
        .map_err(|_| StorageCryptoError::InvalidKey)?;

    cipher
        .decrypt(
            nonce,
            Payload {
                msg: &record[ciphertext_start..],
                aad: &aad,
            },
        )
        .map_err(|_| StorageCryptoError::AuthenticationFailed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_key() -> StorageKey {
        StorageKey::from_bytes([0x42; KEY_LEN])
    }

    #[test]
    fn round_trips_storage_value() {
        let plaintext = b"serialized OpenMLS group state";
        let record = seal_record(&test_key(), b"group/alpha/epoch/4", plaintext).unwrap();

        assert!(record.starts_with(MAGIC));
        assert_ne!(&record[MAGIC.len() + NONCE_LEN..], plaintext);
        assert_eq!(
            open_record(&test_key(), b"group/alpha/epoch/4", &record).unwrap(),
            plaintext
        );
    }

    #[test]
    fn each_encryption_uses_a_fresh_nonce() {
        let first = seal_record(&test_key(), b"storage/item", b"same value").unwrap();
        let second = seal_record(&test_key(), b"storage/item", b"same value").unwrap();
        assert_ne!(&first[MAGIC.len()..MAGIC.len() + NONCE_LEN],
                   &second[MAGIC.len()..MAGIC.len() + NONCE_LEN]);
        assert_ne!(first, second);
    }

    #[test]
    fn rejects_wrong_key_and_tampering() {
        let record = seal_record(&test_key(), b"storage/item", b"secret").unwrap();
        assert_eq!(
            open_record(&StorageKey::from_bytes([0x24; KEY_LEN]), b"storage/item", &record),
            Err(StorageCryptoError::AuthenticationFailed)
        );

        let mut tampered = record.clone();
        *tampered.last_mut().unwrap() ^= 0x01;
        assert_eq!(
            open_record(&test_key(), b"storage/item", &tampered),
            Err(StorageCryptoError::AuthenticationFailed)
        );
    }

    #[test]
    fn binds_ciphertext_to_its_storage_slot() {
        let record = seal_record(&test_key(), b"group/alpha/state", b"state").unwrap();
        assert_eq!(
            open_record(&test_key(), b"group/beta/state", &record),
            Err(StorageCryptoError::AuthenticationFailed)
        );
    }

    #[test]
    fn rejects_malformed_records_and_keys() {
        assert_eq!(
            seal_record(&StorageKey::from_bytes([1; KEY_LEN]), b"key", b"value"),
            Err(StorageCryptoError::InvalidRecord)
        );
        assert_eq!(
            open_record(&test_key(), b"key", b"short"),
            Err(StorageCryptoError::InvalidRecord)
        );
        assert_eq!(
            open_record(&StorageKey::from_bytes([1; KEY_LEN]), b"key", &[0; 64]),
            Err(StorageCryptoError::InvalidKey)
        );
    }
}
