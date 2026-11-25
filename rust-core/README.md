# rust-core — WorkTweaks JIT transport (idevice FFI)

Builds `libwt_idevice_ffi.a` (device slice, `aarch64-apple-ios`) and packs
it as `worse_query/WTIDevice.xcframework` in CI (see
`.github/workflows/build-ipa.yml`, step "Build WTIDevice (Rust FFI)").
Swift imports it as `WTIDevice` and calls the FFI through the minimal
header `include/wtidevice.h`.

## What it is

A staticlib shim re-exporting idevice's C FFI — the same surface
SideInstaller v2.2.0 ships (StikDebug's tunnel + debugserver stack), ported
for the Install IPA on Container JIT session. The crate adds no Rust code
of its own: `src/lib.rs` is one `extern crate idevice_ffi as _;` line, and
the `#[no_mangle]` symbols land in the staticlib.

Upstream: [jkcoxson/idevice](https://github.com/jkcoxson/idevice) @
`7bd551c16c6dd2e058740d85a2d9399a51a776e9` (MIT), the revision
SideInstaller pins. License/credit rows live in the app's License &
Credits (added by the parallel workstream): "idevice — Jackson Coxson
(jkcoxson)" MIT, plus the SideInstaller attribution row covering the
derived Swift.

## Vendoring

`vendor/idevice` and `vendor/idevice-ffi` are byte-identical copies of
SideInstaller `rust-core/vendor/` at the same revision (174 files,
2.6 MB). They carry SideInstaller's local fixes — see
`vendor/idevice/README.md` (OPACK back-references, AFC packet, remote
pairing TLS) and `vendor/idevice-ffi/README.md` (rlib crate-type,
`[patch]` redirect, `tunnel_create_rppairing_multihost` with a
classified failure kind). Do not "update" them to a newer idevice rev
without re-checking every FFI signature in `include/wtidevice.h`.

`[patch."https://github.com/jkcoxson/idevice.git"]` in `Cargo.toml`
redirects idevice-ffi's git dependency to `vendor/idevice`, so cargo
builds exactly one `idevice` instance.

## Feature set (minimal, JIT-only)

Enabled on `idevice-ffi` (each maps to the same-named `idevice` feature,
plus `aws-lc` for TLS):

| feature | used by |
|---|---|
| `amfi` | Developer Mode reveal/enable (`amfi_*`) |
| `core_device`, `core_device_proxy` | `AdapterHandle` type; CoreDeviceProxy route (declared for later, not dialled in v1) |
| `debug_proxy` | debugserver (`debug_proxy_*`, `debugserver_command_*`) |
| `dvt` | declared for later (DVT process control is NOT used in v1 — see below) |
| `heartbeat` | RSD heartbeat while the debugger stays attached |
| `mobile_image_mounter` | developer disk image mount (`image_mounter_*`) |
| `remote_pairing` | RPPairing file + tunnel (`rp_pairing_file_*`, `tunnel_create_rppairing_multihost`) |
| `rsd`, `xpc` | RSD handshake (`RsdHandshakeHandle`, `*_connect_rsd`) |
| `tunnel_tcp_stack` | the in-process TCP stack the tunnel runs on (`tunnel_provider`) |
| `aws-lc` | TLS (rustls/aws-lc-rs), matching SideInstaller |

`lockdown` / `provider` / `pairing_file` modules in idevice-ffi are
ungated, so `lockdownd_connect_rsd` / `lockdownd_get_value` need no extra
feature. `full` is deliberately NOT enabled.

## What v1 deliberately does NOT build or call

- **DVT process control** (`remote_server_*`, `process_control_*`): not
  declared in `wtidevice.h`, and the `dvt` feature is enabled only so the
  option stays open. A LiveContainer guest runs INSIDE WorkTweaks, so
  there is no installed app to launch suspended via
  `process_control_launch_app`; the session attaches to WorkTweaks' own
  pid with `vAttach` over the debug proxy instead. If a later version
  needs DVT kill, the declarations + `openDebugSession` must grow a
  remote-server leg — the device test must first prove debug-proxy-only
  attach works.
- **CoreDeviceProxy / lockdown route** (`tunnel_create_usb`,
  `idevice_tcp_provider_new`, `lockdownd_new`, `lockdownd_pair`): v1 is
  RPPairing-only. From iOS 26.4 on, lockdownd hangs up on loopback
  connections anyway, so the lockdown route would not help on this
  user's iOS 27.0.1.
- **si_probe_pairing_port / si_find_pairing_port** (SideInstaller's own
  Rust helpers in `rust-core/src/pairing_port.rs`): not vendored. v1
  dials RSD port 49152 first, then the port this iPhone advertises over
  Bonjour (`_remotepairing._tcp`). Port-knocking (49152–65535) is the
  known gap — see `WTDeviceConnection.swift`.

## Build notes

- `IPHONEOS_DEPLOYMENT_TARGET` is 26.0 in CI, matching the app target
  (the target's `IPHONEOS_DEPLOYMENT_TARGET` is 26.0; the project-level
  27.0 is not used for the Rust objects). SideInstaller's own script
  uses 17.4 — do NOT copy that value here.
- `cargo build` runs idevice-ffi's `build.rs`, which regenerates
  `vendor/idevice-ffi/idevice.h` in place via cbindgen (feature-gated
  subset) and needs `plist.h` present in that crate dir (it is,
  vendored). That regenerated file is a build artifact and is NOT
  shipped: the xcframework headers are `include/wtidevice.h` +
  `include/plist.h` + `include/module.modulemap` only.
- The build needs network for crates.io (tokio, rustls, cbindgen, …).
  Only `idevice`/`idevice-ffi` themselves are vendored; the rest
  resolves from crates.io at the versions in the generated `Cargo.lock`.
- Device slice only (`aarch64-apple-ios`). There is no simulator slice:
  the tunnel talks to a real iPhone over the Local Dev VPN.
