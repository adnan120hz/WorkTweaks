# litehook — NOT vendored (blocked, needs user approval)

## What it is

`litehook` is LiveContainer's hooking library (MIT, per
LiveContainer's README). It is a git submodule of the LC repo
(`.gitmodules`: `https://github.com/LiveContainer/litehook`,
path `litehook/`). The LC core cannot compile without it:

- `LiveContainer/LCBootstrap.m` — `#include
  "../litehook/src/litehook.h"` (`litehook_rebind_symbol`)
- `LiveContainer/LCMachOUtils.m` — `#include
  "../litehook/src/litehook.h"`
- `LiveContainer/dyld_bypass_validation.m` — `#include
  "litehook.h"` (`litehook_hook_function`)
- `LiveContainer/Tweaks/Dyld.m` — `#include
  "../../litehook/src/litehook.h"` (`litehook_find_symbol`,
  `litehook_find_dsc_symbol`, `litehook_rebind_symbol`)
- `LiveContainer/Tweaks/NSFileManager+GuestHooks.m`,
  `NSUserDefaults.m`, `SecItem.m` — also reference litehook

Without it, none of the vendored ObjC core links, so Phase 1
ships the core as source-only and the Swift installer does
install without patching (`LCPatchRevision = -1`).

## Why it is not here

During this build, fetching the submodule tripped an
execution-risk check (the clone output listed `.git/hooks`
sample files). The fetch was stopped, the partial clone was
deleted, and no litehook file was copied into this repo.
Processing that content needs an explicit go-ahead.

## To unblock (Phase 2)

Once approved, fetch it exactly as LC does:

```
cd <livecontainer checkout>
git submodule update --init litehook
```

Then copy the submodule tree to
`LiveContainerCore/litehook/` so the layout matches LC's
includes (`litehook/src/litehook.h` relative to
`LiveContainer/`). After that the core should compile:
`dyld_cache_format.h` resolves from the Xcode SDK (see
README.md) and OpenSSL comes from LC's
prepare_dependencies.sh pattern (krzyzanowskim/OpenSSL
3.6.5000, to be mirrored in our CI when the core links).
