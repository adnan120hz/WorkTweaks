# LiveContainerCore — vendored LiveContainer sources (Phase 2)

Guest apps ("containers") in WorkTweaks run on LiveContainer's
machinery. The sources here are vendored from the user's fork
`adnan120hz/livecontainer`, HEAD `b0f53e8934df325970e9b6ff52932a43b585c424`
(2026-11-20), which is byte-identical to upstream
`LiveContainer/LiveContainer` main at that commit — zero custom
changes in the fork. Build from main, NOT from release 3.8.0.

License: AGPL-3.0 (see `LICENSE` in this folder — the verbatim
LiveContainer LICENSE). Compatible with WorkTweaks (AGPL-3.0).
Sub-component licenses, from LiveContainer's README:
- ZSign: originally by zhlynn (MIT — verified 2026-11-25:
  zhlynn/zsign LICENSE reads "MIT License, Copyright (c)
  2026 zhlynn"; the vendored files match zhlynn's src/ layout
  exactly: archo, macho, openssl, signing + common/).
  LiveContainer uses Feather's version of ZSign modified by
  khcrysalis, and Feather itself is GPL-3.0 (verified:
  claration/Feather, LICENSE; the old khcrysalis/Feather URL
  now redirects there). The vendored `ZSign/` carries no
  license file of its own, so LicenseView credits both:
  "ZSign — zhlynn" MIT and "Feather — khcrysalis" GPL-3.0.
  Either way it is compatible with WorkTweaks (AGPL-3.0).
- litehook: MIT (see `litehook/` — vendored since Phase 2,
  source LiveContainer/litehook, commit `a7e9f59`).
  LicenseView credits it as "litehook — LiveContainer" MIT.
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
  SecItem, IDFV, Dead10ccFix, mach_excServer), and
  `LivePlugInSupport/` (guest-extension support:
  `NSExtension+GuestHooks.m` defines `NSExtensionGuestHooksInit`,
  called by `LCBootstrap` at guest launch, plus `LivePlugInServer.m`,
  the XPC server for guest extensions). This directory was MISSED
  by the Phase 1 vendoring and added with the link fix: without it
  the link failed (`_NSExtensionGuestHooksInit`, referenced from
  `_invokeAppMain` in `LCBootstrap.o`). Both files have no
  constructor/`+load` — everything is explicit-init, so compiling
  them into the host is safe. One-line deviation from upstream in
  `NSExtension+GuestHooks.m`: `#import "Tweaks.h"` became
  `#import "../Tweaks/Tweaks.h"` (upstream relies on Xcode header
  maps for that include).
- `TweakLoader/` — the dylib injected into the guest process
  (`TweakLoader.m` + `UIKit+GuestHooks.m`, `BackgroundTasks.m`,
  `DocumentPicker.m`, `Notification.m`). At runtime LC symlinks
  it to `<group>/LiveContainer/Tweaks/TweakLoader.dylib` and the
  patched guest loads it from `@loader_path/../../Tweaks/`.
  These 5 files carry `__attribute__((constructor))` and are
  EXCLUDED from the app target (pbxproj exception set on the
  `worse_query` synchronized root group) — their hooks must run
  inside the guest, never inside WorkTweaks itself. CI builds
  them as a separate `TweakLoader.dylib` and copies it into the
  .app `Frameworks/` before packaging.
- `ZSign/` — Feather's ZSign (signing engine). It needs OpenSSL
  headers at compile time (`openssl.cpp` includes
  `<openssl/...>`); CI downloads OpenSSL.xcframework
  (krzyzanowskim/OpenSSL 3.6.5000) into `Dependencies/` before
  the build, matching LC's prepare_dependencies.sh.
- `litehook/` — LiveContainer's MIT hooking library (the dyld /
  NSFileManager / NSUserDefaults / keychain hooks the core calls
  via `litehook.h`). Source: LiveContainer/litehook, commit
  `a7e9f59` (checked out 2026-11-25, copied verbatim; the
  `Tests/` harness was NOT copied — it is a test program, not
  app code). The user approved this copy explicitly on
  2026-11-25 ("selama litehook ga ganggu fitur lain ya udah ga
  apa apa boleh") — see README.LITEHOOK.md. It compiles only
  inside this LiveContainer integration; the diff touches
  nothing else.
- `LCContainerPatch.h` / `LCContainerPatch.m` — WorkTweaks' own
  ObjC wrapper (NOT LC code): patch / sign / launch / certificate
  entry points the Swift side calls. The patch sequence
  reimplements LCAppInfo.m's patch step (currentPatchRev 7) and
  patchGuestExtensions; signing calls `ZSigner` directly
  (LCUtils.signAppBundleWithZSign dlopens a ZSign.dylib that does
  not exist — ZSigner is compiled into the app binary instead).
- `LCUtils.h` / `LCUtils.m` — LC's signing/launch helpers.
  **LCUtils.m is NOT compiled** (pbxproj exception set): it
  imports `../MultitaskSupport/DecoratedAppSceneViewController.h`
  and `LiveContainerSwiftUI-Swift.h`, neither of which is vendored
  (MultitaskSupport + LiveContainerSwiftUI are LC's own UI
  targets), and nothing in the core calls its methods (verified
  by grep — only LCMachOUtils.m imports the header, and calls
  nothing from it). Its two helpers this feature needs
  (certificateData, setCertificatePassword) are reimplemented in
  `LCContainerPatch.m`.
- `entitlements-reference.xml` — LC's own entitlements file,
  for comparison with `worse_query/worse_query.entitlements`
  (the WT file must carry get-task-allow + the 128
  `com.kdt.livecontainer.shared` keychain groups at signing
  time; see the Phase 1 commit).

## What is NOT here (deliberately)

- `dyld_cache_format.h` — **CORRECTION (2026-11-25): it is NOT
  from the Xcode SDK.** It lives in litehook itself, at
  `litehook/external/include/dyld_cache_format.h` (with
  `fixup-chains.h`). The earlier note claiming it resolved from
  the SDK was wrong. The header search path for it is
  `LiveContainerCore/litehook/external/include`.
- `LCAppInfo` — the patch/sign orchestration class lives in
  LiveContainer's SwiftUI target
  (`LiveContainerSwiftUI/Models/LCAppInfo.{h,m}`), not in the
  vendored core. Its patch logic is reimplemented in
  `LCContainerPatch.m` (same steps, same revision 7); its sign
  step is replaced by a direct `ZSigner` call (see above).
- `main.c` — LC's app entry (dlopens
  `LiveContainerShared.framework` and calls `LiveContainerMain`).
  Not applicable: WorkTweaks keeps its Swift `@main`
  (`WorkTweaksApp`) and calls the bootstrap entry directly
  (`ContainerLaunch.checkSelectedGuest()`).
- `LiveContainerSwiftUI/`, `SideStoreSupport/`, `LiveProcess/`,
  `LaunchAppExtension/`, `ShareExtension/`, `TestJITLess/`,
  `Resources/`, `screenshots/`, `xcconfigs/` — LC's own UI and
  extensions. WorkTweaks writes its own Swift UI
  (`worse_query/ContainerManager.swift`,
  `worse_query/ContainerView.swift`); only the core is reused.

## Phase 2 status

The core now lives under `worse_query/` (inside the single
synchronized root group) and COMPILES into the app binary:
`LCBootstrap`, `LCMachOUtils`, `LCSharedUtils`, `utils`,
`dyld_bypass_validation`, `Tweaks/`, `ZSign/`, `litehook/` are
all in the app target; `TweakLoader/*.m` and `LCUtils.m` are
excluded by the exception set (see above). Installs are patched
(`LCPatchRevision` 7), signed when a certificate is imported,
and launchable JIT-less when signed — the JIT toggle stays
OFF/disabled until the Phase 3 JIT session exists. A decrypted
IPA is still required (encrypted guests are refused with LC's
exact message); 32-bit guests are refused (they need JIT +
classic mode, Phase 3).
