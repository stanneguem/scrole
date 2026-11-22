//! Functions exposed to Dart through flutter_rust_bridge.

/// Public capability report. This is deliberately metadata-only: it does not
/// imply that a device has registered an MLS identity or that E2EE is active.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct E2eeEngineInfo {
    pub protocol: String,
    pub engine: String,
    pub engine_version: String,
    pub ciphersuite: String,
    pub ready_for_messages: bool,
    pub readiness_reason: String,
}

/// Returns the native engine build information without exposing key material.
pub fn e2ee_engine_info() -> E2eeEngineInfo {
    E2eeEngineInfo {
        protocol: "MLS (RFC 9420)".to_owned(),
        engine: "OpenMLS".to_owned(),
        engine_version: "0.9.2".to_owned(),
        ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519".to_owned(),
        ready_for_messages: false,
        readiness_reason: "Encrypted persistent storage and Android Keystore/iOS Keychain key wrapping are not integrated yet.".to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_is_explicitly_not_ready_until_secure_storage_exists() {
        let info = e2ee_engine_info();
        assert_eq!(info.protocol, "MLS (RFC 9420)");
        assert_eq!(info.engine, "OpenMLS");
        assert!(!info.ready_for_messages);
        assert!(!info.readiness_reason.is_empty());
    }

    #[test]
    fn no_secret_material_is_part_of_the_capability_report() {
        let info = e2ee_engine_info();
        let serialized = format!("{info:?}");
        assert!(!serialized.contains("private_key"));
        assert!(!serialized.contains("secret"));
    }
}
