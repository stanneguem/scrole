//! Scrole's native MLS engine boundary.
//!
//! Security invariant: this crate must never expose private key material or
//! plaintext message content to Supabase-facing code. The first integration
//! slice intentionally exposes capability metadata only. Stateful MLS
//! operations must not be enabled until encrypted persistent storage and
//! platform-backed key wrapping have passed the mobile test matrix.

pub mod api;
mod storage_crypto;
