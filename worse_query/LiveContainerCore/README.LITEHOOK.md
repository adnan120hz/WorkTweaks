# litehook — vendored (unblocked 2026-11-25, user approved)

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

## Approval (2026-11-25)

Fetching the submodule first tripped an execution-risk check;
the clone was stopped, the partial clone deleted, and nothing
was copied. The user was then asked in plain words what
litehook is and said yes with one condition (his exact words):
"selama litehook ga ganggu fitur lain ya udah ga apa apa
boleh" — as long as litehook doesn't disturb other features,
it's fine, allowed. That is the informed consent for this
step. The copy below is the exact step approved: copy the
checked-out submodule tree into the repo and compile it as
part of the app — ONLY inside the LiveContainer integration.
The condition is verified by the diff (it touches only the
container integration) and by the built IPA (existing
features intact — see the Phase 2 commit report).

## What was copied

Source: the submodule checked out at
`~/workspace/upstream/livecontainer-adnan/litehook/`,
commit `a7e9f59` (status clean), copied verbatim to
`LiveContainerCore/litehook/`:

- `src/litehook.c`, `src/litehook.h`
- `external/include/dyld_cache_format.h`,
  `external/include/fixup-chains.h`
- `LICENSE`, `README.md`

NOT copied: `Tests/` (a test harness — `main.c`, Makefile,
`upload.sh` — not app code). The layout matches LC's relative
includes (`litehook/src/litehook.h` relative to
`LiveContainer/`).

CORRECTION: `dyld_cache_format.h` does NOT come from the
Xcode SDK (the earlier note was wrong) — it lives in
litehook itself, at `litehook/external/include/`. The header
search path for it is
`LiveContainerCore/litehook/external/include`.
