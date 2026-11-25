# LiveContainerCore — vendored LiveContainer sources (Phase 1)

Guest apps ("containers") in WorkTweaks run on LiveContainer's
machinery. The sources here are vendored from the user's fork
`adnan120hz/livecontainer`, HEAD `b0f53e8934df325970e9b6ff52932a43b585c424`
(2026-11-20), which is byte-identical to upstream
`LiveContainer/LiveContainer` main at that commit — zero custom
changes in the fork. Build from main, NOT from release 3.8.0.

License: AGPL-3.0 (see `LICENSE` in this folder — the verbatim
LiveContainer LICENSE). Compatible with WorkTweaks (AGPL-3.0).
Sub-component licenses, from LiveContainer's README:
- ZSign: originally by zhlynn; LiveContainer uses Feather's
  version of ZSign modified by khcrysalis. Feather is GPL-3.0,
  so the vendored ZSign is treated as GPL-3.0 (compatible with
  AGPL-3.0 via GPLv3 §13). There is no license file inside LC's
  `ZSign/` itself — this is recorded, not assumed away.
- litehook: MIT (see README.LITEHOOK.md — **not vendored yet**).
- CFastFind (used by `utils.m`, Linus Henze): MIT.

## Layout (mirrors the fork)

- `LiveContainer/` — the host core: `LCBootstrap.m` (guest launch:
  `LiveContainerMain` / `invokeAppMain`), `LCSharedUtils`
  (app-group / team / certificate-password helpers),
  `LCMachOUtils` (Mach-O parse + patch: `LCPatchExecSlice`,
  `LCIsMachOEncrypted`, `LCPatchAppBundleFixupARM64eSlice`),
  `utils.m` (aarch64 emulation helpers, CFastFind),
  `dyld_bypass_validation.m` (JIT-mode library-validation bypass),
  `Localization.m`, private headers (`FoundationPrivate.h`,
  `UIKitPrivate.h`, `XPCPrivate.h`), and `Tweaks/` (the guest
  hooks: Dyld, NSFileManager+GuestHooks, NSUserDefaults,
  SecItem, IDFV, Dead10ccFix, mach_excServer).
- `TweakLoader/` — the dylib injected into the guest process
  (`TweakLoader.m` + `UIKit+GuestHooks.m`, `BackgroundTasks.m`,
  `DocumentPicker.m`, `Notification.m`). At runtime LC symlinks
  it to `<group>/LiveContainer/Tweaks/TweakLoader.dylib` and the
  patched guest loads it from `@loader_path/../../Tweaks/`.
- `ZSign/` — Feather's ZSign (signing engine), source-only for
  now. It needs OpenSSL headers at compile time
  (`openssl.cpp` includes `<openssl/...>`); LC's CI downloads
  OpenSSL.xcframework via `.github/prepare_dependencies.sh`
  (krzyzanowskim/OpenSSL 3.6.5000). Phase 2 wires this up with
  the signing flow.
- `LCUtils.h` / `LCUtils.m` — LC's signing/launch helpers
  (ZSign wrapper, `signAppBundleWithZSign`), source-only,
  Phase 2.
- `entitlements-reference.xml` — LC's own entitlements file,
  for comparison with `worse_query/worse_query.entitlements`
  (the WT file must carry get-task-allow + the 128
  `com.kdt.livecontainer.shared` keychain groups at signing
  time; see the Phase 1 commit).

## What is NOT here (deliberately)

- `litehook/` — **BLOCKED, see README.LITEHOOK.md.** The LC
  core cannot compile without it.
- `dyld_cache_format.h` — `LCMachOUtils.m` includes it, but the
  file is NOT in the LC repo (it is a dyld private header).
  Phase 2 must supply it (e.g. from Apple's open-source dyld)
  before the core can compile.
- `main.c` — LC's app entry (dlopens
  `LiveContainerShared.framework` and calls `LiveContainerMain`).
  Not applicable: WorkTweaks keeps its Swift `@main`
  (`WorkTweaksApp`) and will call the bootstrap entry directly
  once the core links.
- `LiveContainerSwiftUI/`, `SideStoreSupport/`, `LiveProcess/`,
  `LaunchAppExtension/`, `ShareExtension/`, `TestJITLess/`,
  `Resources/`, `screenshots/`, `xcconfigs/` — LC's own UI and
  extensions. WorkTweaks writes its own Swift UI
  (`worse_query/ContainerManager.swift`,
  `worse_query/ContainerView.swift`); only the core is reused.

## Phase 1 status

These sources are **vendored but not compiled**: they live
outside the `worse_query/` synchronized group on purpose, so
the Xcode project does not try to build them yet. The Phase 1
Swift installer (`ContainerManager.swift`) implements install
(unzip, validate, encryption check, store, `LCAppInfo.plist`)
without the ObjC core, and installs land with
`LCPatchRevision = -1` ("not patched yet"). Patching, signing
and launch land in Phases 2–3 once the core links.
