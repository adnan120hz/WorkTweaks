//! WorkTweaks JIT transport: a staticlib shim over idevice's C FFI.
//!
//! The crate itself adds no Rust code of its own: linking `idevice_ffi`
//! re-exports its `#[no_mangle]` symbols into this static library, and
//! Swift calls them through the `WTIDevice` module (see
//! `include/wtidevice.h`, the minimal hand-written header declaring only
//! the functions the JIT session uses).
//!
//! Mirrors SideInstaller `rust-core/src/lib.rs` (`extern crate idevice_ffi
//! as _;`). The `idevice-ffi` crate is vendored under `vendor/idevice-ffi`
//! (jkcoxson/idevice @ 7bd551c16c6dd2e058740d85a2d9399a51a776e9) with
//! SideInstaller's local changes; `vendor/idevice` carries the matching
//! `idevice` crate (see both READMEs).

// Link idevice's C FFI crate so its `#[no_mangle]` symbols are exported to
// Swift. Aliased to `_` because only the exports are used.
extern crate idevice_ffi as _;
