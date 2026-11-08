# Scrole E2EE native engine

This crate is the Rust boundary for Scrole's MLS implementation.

## Current scope

- Pins OpenMLS 0.9.2 and the stable Flutter Rust Bridge 2.13.0.
- Declares the RFC 9420 mandatory-to-implement X25519/AES-128-GCM/SHA-256/Ed25519 ciphersuite.
- Exposes metadata only, explicitly reporting that message encryption is not ready.

## Security gate — do not bypass

No MLS identity, KeyPackage, group state, or message operation may be exposed to Dart until all of the following are implemented and tested:

1. A persistent OpenMLS storage provider with authenticated encryption at rest.
2. A random storage-wrapping key protected by Android Keystore / iOS Keychain.
3. Atomic persistence of group state and outgoing MLS messages (to prevent nonce/epoch rollback).
4. Device registration and one-time KeyPackage publication/consumption.
5. Mobile CI and real-device tests for Android and iOS.
6. Independent security review of the storage and state-transition design.

Do not use OpenMLS' in-memory provider as the production store. Do not log plaintext,
serialized private state, KeyPackages' private bundles, or cryptographic secrets.

## Flutter bridge generation

From the repository root, after installing Rust and the FRB code generator:

```bash
cargo install flutter_rust_bridge_codegen --version 2.13.0
flutter_rust_bridge_codegen integrate --rust-root rust --rust-input rust/src/api.rs --dart-output lib/core/e2ee/bridge
flutter_rust_bridge_codegen generate --rust-root rust --rust-input rust/src/api.rs --dart-output lib/core/e2ee/bridge
```

Review generated output before committing. Native linking/build-hook integration must be completed for
the supported Flutter SDK and Android/iOS targets; do not assume desktop success proves mobile support.

## Validation

```bash
cd rust
cargo test --locked
cargo check --locked
```

A committed Cargo.lock is required before shipping; it is intentionally not fabricated by this
repository-only integration step.
