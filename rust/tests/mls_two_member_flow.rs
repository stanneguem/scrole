//! Protocol-level integration test using OpenMLS' in-memory Rust provider.
//!
//! This validates MLS cryptographic flows only. It is deliberately not the
//! production persistence provider and must never be used to enable messaging.

use openmls::prelude::*;
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::signatures::Signer;
use tls_codec::Serialize;

const SUITE: Ciphersuite =
    Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

fn credential(
    provider: &OpenMlsRustCrypto,
    identity: &[u8],
) -> (CredentialWithKey, SignatureKeyPair) {
    let credential = BasicCredential::new(identity.to_vec());
    let signature_keys = SignatureKeyPair::new(SUITE.signature_algorithm())
        .expect("create Ed25519 signature key");
    signature_keys
        .store(provider.storage())
        .expect("persist test signature key in memory");

    (
        CredentialWithKey {
            credential: credential.into(),
            signature_key: signature_keys.to_public_vec().into(),
        },
        signature_keys,
    )
}

fn key_package(
    provider: &OpenMlsRustCrypto,
    credential: CredentialWithKey,
    signer: &impl Signer,
) -> KeyPackageBundle {
    KeyPackage::builder()
        .build(SUITE, provider, signer, credential)
        .expect("build MLS KeyPackage")
}

#[test]
fn two_members_exchange_ciphertext_and_removed_member_is_excluded() {
    let alice_provider = OpenMlsRustCrypto::default();
    let bob_provider = OpenMlsRustCrypto::default();

    let (alice_credential, alice_signer) = credential(&alice_provider, b"scrole:alice");
    let (bob_credential, bob_signer) = credential(&bob_provider, b"scrole:bob");

    let create_config = MlsGroupCreateConfig::builder()
        .ciphersuite(SUITE)
        .use_ratchet_tree_extension(true)
        .build();

    let mut alice_group = MlsGroup::new(
        &alice_provider,
        &alice_signer,
        &create_config,
        alice_credential,
    )
    .expect("create Alice MLS group");

    let bob_key_package = key_package(&bob_provider, bob_credential, &bob_signer);

    // Alice adds Bob and commits the new epoch locally.
    let (add_commit, welcome, _) = alice_group
        .add_members(
            &alice_provider,
            &alice_signer,
            std::slice::from_ref(bob_key_package.key_package()),
        )
        .expect("add Bob");
    let _add_commit_wire = add_commit
        .tls_serialize_detached()
        .expect("serialize add commit");
    alice_group
        .merge_pending_commit(&alice_provider)
        .expect("merge Alice add-member commit");

    // Bob joins only from the Welcome and the public ratchet tree extension.
    let welcome = match MlsMessageIn::from(welcome).extract() {
        MlsMessageBodyIn::Welcome(welcome) => welcome,
        other => panic!("expected Welcome message, got {other:?}"),
    };
    let mut bob_group = StagedWelcome::new_from_welcome(
        &bob_provider,
        create_config.join_config(),
        welcome,
        None,
    )
    .expect("stage Bob Welcome")
    .into_group(&bob_provider)
    .expect("join Bob group");

    assert_eq!(alice_group.members().count(), 2);
    assert_eq!(bob_group.members().count(), 2);
    assert_eq!(alice_group.epoch_authenticator(), bob_group.epoch_authenticator());

    // The wire payload is an MLS ciphertext, not the application plaintext.
    let plaintext = b"Scrole E2EE integration test";
    let outbound = alice_group
        .create_message(&alice_provider, &alice_signer, plaintext)
        .expect("encrypt application message");
    let ciphertext = outbound
        .tls_serialize_detached()
        .expect("serialize encrypted MLS message");
    assert!(!ciphertext.windows(plaintext.len()).any(|w| w == plaintext));

    let inbound = MlsMessageIn::tls_deserialize_exact(ciphertext.as_slice())
        .expect("deserialize MLS ciphertext")
        .try_into_protocol_message()
        .expect("application protocol message");
    let processed = bob_group
        .process_message(&bob_provider, inbound)
        .expect("Bob decrypts and authenticates message");

    match processed.into_content() {
        ProcessedMessageContent::ApplicationMessage(message) => {
            assert_eq!(message.into_bytes(), plaintext);
        }
        other => panic!("expected application message, got {other:?}"),
    }

    // Alice removes Bob. The removal commit advances the group epoch.
    let (remove_commit, _, _) = alice_group
        .remove_members(
            &alice_provider,
            &alice_signer,
            &[bob_group.own_leaf_index()],
        )
        .expect("remove Bob");
    alice_group
        .merge_pending_commit(&alice_provider)
        .expect("merge Alice removal commit");

    let inbound_remove = MlsMessageIn::from(remove_commit)
        .try_into_protocol_message()
        .expect("removal protocol message");
    let processed_remove = bob_group
        .process_message(&bob_provider, inbound_remove)
        .expect("Bob processes removal commit");
    match processed_remove.into_content() {
        ProcessedMessageContent::StagedCommitMessage(staged) => {
            bob_group
                .merge_staged_commit(&bob_provider, *staged)
                .expect("Bob merges removal commit");
        }
        other => panic!("expected removal commit, got {other:?}"),
    }

    assert!(!bob_group.is_active());
    assert_eq!(alice_group.members().count(), 1);
    assert!(bob_group
        .create_message(&bob_provider, &bob_signer, b"must not send")
        .is_err());
}
