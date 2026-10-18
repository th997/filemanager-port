//! The single FFI boundary between Rust and Flutter.
//!
//! Everything exported here is intentionally typed: the UI never
//! sees backend internals, and bridge files are generated from this crate alone.

#![allow(unexpected_cfgs)]

pub mod api;
mod frb_generated;
