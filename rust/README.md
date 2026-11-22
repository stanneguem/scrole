# Scrole E2EE native engine

This crate is the Rust boundary for Scrole's MLS implementation.

## Current scope

- Flutter declares `flutter_rust_bridge: ^2.13.0`, `flutter_rust_bridge_hooks: ^2.13.0` and `flutter_secure_storage: ^11.2.0`.
- `hook/build.dart` invokes `FlutterRustBridgeNativeAssetsBuilder` for the `rust/` crate so Flutter build hooks can compile and bundle the native library for supported targets.
- `lib/core/e2ee/secure_mls_storage_key.dart` creates a per-user/per-installation 256-bit database wrapping key using `Random.secure()` and stores it through the platform secure-storage plugin (Android encrypted storage backed by Keystore; iOS Keychain).

- Pins OpenMLS 0.9.2, Rust 1.91.1 (OpenMLS' minimum supported compiler) and Flutter Rust Bridge 2.13.0.
- `rust/rust-toolchain.toml` declares Android ARM64, iOS ARM64 and Linux host targets required by the native build hook.
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

The checked-in `flutter_rust_bridge.yaml` pins the source/output layout.
Use the exact generator version matching the Rust runtime:

```bash
cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen
flutter pub get
flutter_rust_bridge_codegen generate
```

Review and commit the generated `lib/core/e2ee/bridge/` Dart bindings and
`rust/src/frb_generated.rs`. The GitHub Actions workflow also generates these
files and publishes them as a review artifact. This generation step does not
yet integrate native library packaging into Android/iOS app builds; native
assets/build-hook integration and platform smoke tests remain separate gates.

## Validation

```bash
cd rust
cargo test
cargo check
```

A committed Cargo.lock is required before shipping. Generate it in a Rust-enabled environment, review the resolved dependency tree and licenses, then commit it. The repository-only GitHub editing environment cannot run Cargo or generate a trustworthy lockfile.


## Current limitation

The Flutter key manager is not yet called by application startup and no `MlsEngine` is instantiated. The Rust API intentionally reports `ready_for_messages = false`. The next implementation slice must add durable device identity, invoke the secure key manager, initialize the native engine, and test its storage lifecycle before any messaging repository can use it.


## Current limitation

The Flutter key manager is not called by application startup and no persistent
OpenMLS provider is instantiated. The Rust API intentionally reports
`ready_for_messages = false`. The wrapping key currently crosses into Dart
as a byte array; it must not be passed into production MLS operations until
the native integration can keep key material in Rust-owned memory and apply
explicit zeroization. A SQLCipher database/provider, authenticated storage
format, rollback-safe commits and device recovery are still required.

No direct or community message repository has been switched to this engine.


## Android cross-compilation CI

The Android Rust check installs the NDK and exports both the Cargo linker and
the target-specific C compiler variables required by C dependencies such as
`dart-sys`. The check is considered valid only when the full Cargo build
completes for `aarch64-linux-android`; installing the NDK alone is not a
successful compile check.


## Native build prerequisites

The build hook validates `rust/rust-toolchain.toml` before invoking Cargo.
Keep the Rust version pinned to a concrete release (not the floating
`stable` channel) and list every target used by Flutter builds. The workflow
runs Flutter tests with Rust installed because Flutter executes package build
hooks during `flutter test` as well as app builds.

Android's NDK compiler variables are passed with `env` because target triples
contain hyphens and cannot be written as ordinary shell variable names.


## Authenticated storage-record codec (experimental, not wired to OpenMLS)

- `rust/src/storage_crypto.rs` implements a versioned `SCM1` record envelope
  using XChaCha20-Poly1305 with a fresh 192-bit nonce per write.
- The OpenMLS storage slot identifier is authenticated as associated data,
  preventing ciphertext records from being moved between storage keys.
- The wrapping key is represented by a native-only `StorageKey` backed by
  `Zeroizing<[u8; 32]>`; it is not exposed in FRB/Dart APIs.
- Unit tests cover round-trip, nonce uniqueness, wrong-key rejection,
  tampering, malformed records and storage-slot substitution.
- This codec is not yet an OpenMLS `StorageProvider`: the SQLx provider,
  transaction boundary, native Keystore/Keychain key loading and deletion of
  obsolete epoch material still need integration and mobile verification.
