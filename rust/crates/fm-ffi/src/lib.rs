//! The single FFI boundary between Rust and Flutter.
//!
//! Everything exported here is intentionally typed: the UI never
//! sees backend internals, and bridge files are generated from this crate alone.

#![allow(unexpected_cfgs)]
#![cfg_attr(not(test), deny(clippy::unwrap_used))]

pub mod api;
pub mod registry;
#[allow(clippy::unwrap_used)]
mod frb_generated;

#[cfg(target_os = "android")]
mod saf_jni;
