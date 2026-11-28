<p align="center">
  <img src="icon-rounded.png" width="160" alt="WorkTweaks icon">
</p>

<h1 align="center">WorkTweaks</h1>

<p align="center">
  A MobileGestalt tweak app for iOS 18, 26 &amp; 27 — unlock your device's hidden features without a jailbreak, powered by the <strong>worse_query</strong> sandbox escape.
</p>

<p align="center">
  WorkTweaks is an original app by Adnan. This repository also documents its companion signer, <strong>Signed Apps</strong> — the two apps are separate projects with separate credits and separate licenses, listed below.
</p>

---

## Features

- **Installation** — install the unsigned IPA with iLoader, SideInstaller, Feather, or LiveContainer (see Install below). WorkTweaks reads its App Group dynamically from the entitlements of the running process and tries every App Group in the signature until one works (multi-group fallback), so it does not depend on a manually signed provisioning profile.
- **Tweaks** — WorkTweaks' own catalog of 24 tweaks: Dynamic Island, Always-On Display, Apple Intelligence, Siri AI Cache Patch *(new in v4.3; pattern fix in v4.3.1)*, Stage Manager, Charge Limit, Action Button, Camera Control, iPadOS Mode, device spoofing, and more — applied with WorkTweaks' own in-place MobileGestalt write system, so tweaks persist across resprings and reboots. The catalog is organized into sections (All, Dynamic Island, Tweaks, Apple Intelligence, Add feature, Apply/Revert) with a search page. The Tweaks tab offers a **New UI / Old UI** choice *(new in v4.2)* — the current two-column layout or the v1 list layout, picked in Sandbox under Start Tweaks Feature; it applies to the Tweaks tab only. **(new in v5.1)** The Dynamic Island card has a **Fix Status Bar!** guide, the subtype picker gains **iPhone 18 Pro** (iOS 27.0.1+), **iPhone 18 Pro Max** (iOS 27.0.1+) and **iPhone Duo** (iOS 27.3+), menus and features play soft sound effects (toggle in Sandbox), section switches animate smoothly, and the app rotates to landscape when orientation lock is off. *(v5.1.1 refines the transition sound to a calmer one, and every toggle now plays a tap sound.)* *(v5.2 adds iPhone 17 Pro / 17 Pro Max subtypes and an iPhone Duo spoofing device.)* *(v5.2.1 adds a "Fix Apple Intelligence Here!" guide next to the Apple Intelligence toggle.)* *(v6.1 restores Custom Region Model from v5.3 — type the sales-region suffix, e.g. PA/A, under Custom Device Name; the Siri AI Cache Patch pattern scan now checks every byte offset, so it finds the slot on all iOS versions; and the subtype picker gains iPhone X Gestures and iPhone SE.)*
- **Siri AI manual path** *(new in v7.0)* — the MobileGestalt.plist viewer and text editor provide a manual path for the Siri AI Cache Patch: Jump to Siri line locates the exact line for the device, and the whole line is replaced with the replacement string. A pristine backup is created before the first save, and Restore is available in the viewer.
- **iPadOS Mode** *(updated in v7.0)* — Enable iPadOS Mode now uses the file-based Nugget locator, which validates the target before writing anything.
- **Save Vault and largest-file scanner** *(new in v7.0)* — Save Vault stages app data into a ZIP vault for backup, and the largest-file scanner lists the largest files in a container.
- **Battery & Thermal and Jetsam & Crash** *(new in v7.0)* — Battery & Thermal reads the system powerlog database (battery level, health, cycle count, cell temperature, thermal history); Jetsam & Crash lists the crash and jetsam reports iOS writes when it terminates an app.
- **Wi-Fi File Sharing, Voice Memos & AI Cache, SQLite/plist editor, profile viewer** *(new in v7.0)* — Sandbox → Utilities: share files with a computer over Wi-Fi; export Voice Memos and inspect the AI cache; view installed configuration profiles. App Data gains in-place SQLite database and property-list editing.
- **Adnan.120hz Repository** *(new in v7.0)* — 25 Deploy packages converted from 3105 patch files (PUBG variants, Mod Skin, app and game patches), installable through Deploy. *(Dialer themes and pass themes removed in v8.0.)*
- **Nine UI languages** *(new in v7.0)* — English (US, default), Indonesian, Vietnamese, Russian, Chinese, Arabic, Brazilian Portuguese, Spanish, and French, each with its own theme colours and app icon. The CacheExtra editor remains in English.
- **Onboarding** *(new in v7.0)* — the first-install welcome flow is redesigned as three pages: developer introduction, feature overview, and license & credits.
- **Airlift & pairing** *(new in v6.1)* — Sandbox → Utilities: **Get Pairing File** obtains the pairing file on-device (iOS 27: Pair This iPhone shows a 6-digit PIN to approve in Settings) or imports one manually (.plist), and **Airlift** flashes Passcode Themes and Wallet Cards over the pairing + Local Dev VPN transport. **All data changed** keeps a history of everything ever applied.
- **App Data** — browse the data containers of the apps on your device, open and edit text files in place, edit binary files byte by byte with the hex editor (a pristine backup is taken before the first byte edit), and add files and folders.
- **Cache Data Cleaner** *(new in v3.13)* — Sandbox → Utilities: pick an app, see how much cache it keeps in `Library/Caches` and `tmp`, and empty those two folders after a confirmation. Only the contents of those two cache folders are deleted — Documents and the rest of Library are never touched — and the freed space is measured, not estimated.
- **PosterBoard** — import `.tendies` wallpaper packages into PosterBoard's data store and remove the wallpapers you imported, tracked by receipts. The built-in **wallpaper maker** *(new in v4.1)* creates PosterBoard wallpapers on-device from a photo or a video (first 12 seconds, loop on/off) and installs them through the same verified path. On iOS 27.3 the container search falls back to a direct enumeration of the Application containers root when the shared scan misses it *(new in v4.3.1)*.
- **Deploy** — install file packages into app containers, App Groups, and internal daemon containers, with per-file backups and a restore history. **(new in v5.0)** The built-in **Package Builder** now produces ONE `.zip` file (manifest + payloads; Add File unpacks `.zip` archives and accepts `.plist` files) — save it in Files, then Deploy imports the zip, resolves the target itself, and applies it with no location picking.
- **Lock Screen Footnote** — set the footnote text shown on the Lock Screen, as a card in Tweaks → Add feature.
- **Extra** — a free-form CacheExtra editor: add, edit, or delete any MobileGestalt key directly, with a Reset that restores exactly the keys you edited.
- **Backup** — an original backup is saved on first read, an automatic **After Apply Tweaks** snapshot is taken at every Apply, and manual snapshots can be created at any time. Every snapshot can be restored as a whole, per tweak, or per key.
- **Sandbox & Log** — the original worse_query escape / path tools and the live console output.
- **First-launch welcome & tutorials** — install and signing guides, plus a step-by-step Siri AI guide *(new in v4.3)*, shown once per install.
- Liquid Glass cards throughout (except the Log, which stays solid). Light, dark, and tinted app icons.

## What's new in v8.0

- **UI revamp** — menus rearranged in a Sileo-inspired layout, built fresh on the v7.0 material. The five tabs (Sandbox, Tweaks, Extra, Backup, Log) are unchanged.
- **Deploy via Airlift** — Deploy now offers two options: **Normal** (the worse_query flow, iOS 26.0–27.3 beta 1) and **Airlift** (the same package flow through the Airlift exploit over the pairing + VPN tunnel, iOS 17/18/26/27 with iOS 27 capped at 27.2 beta 2). Airlift cannot back up files it replaces on iOS 17/18 — the exploit writes but cannot read them back — and files replaced without a backup cannot be restored from Deploy History.
- **PosterBoard flake option** — alongside Normal, PosterBoard import now offers **Flake (MercuryPoster)**, which also finds MercuryPoster descriptors anywhere in a package and keeps their original identifiers. It works on iOS 26.0–27.3 beta 1; on iOS 27.3 beta 2 and later it is blocked — the worse_query escape is patched there and no flake fix exists for those versions.
- **Repository** — 25 packages (dialer themes and pass themes removed), with a credit to [adnan120hz](https://github.com/adnan120hz) on GitHub.
- **Tweaky, sounds, and motion** — small Tweaky mascots on the corners of icons, calmer ASMR-style menu sounds, smooth animations on small menus, and an animated Tweaky success popup on Apply.
- **3105 → zip conversion** — the 3105 package conversion was verified against the Deploy package system: `manifest.json` at the top level, relative paths only, stored and deflated entries only, no encryption, no ZIP64.

## Supported iOS versions

WorkTweaks checks your exact iOS version and build at launch — only the builds below are supported, and unsupported devices stop at an "unsupported" screen instead of running with unknown keys. **iOS 18 and iOS 26 are partially supported** (App Data + Airlift only); **iOS 27 is fully supported**:

| Version | Build | Support |
| --- | --- | --- |
| iOS 18.0 Beta 1 | 22A5282m | Partial (App Data + Airlift) |
| iOS 18.0 Beta 2 | 22A5297f | Partial (App Data + Airlift) |
| iOS 18.0 Beta 3 | 22A5307f | Partial (App Data + Airlift) |
| iOS 18.0 Beta 3 Update | 22A5307i | Partial (App Data + Airlift) |
| iOS 18.0 Beta 4 | 22A5316j | Partial (App Data + Airlift) |
| iOS 18.0 Beta 4 Update | 22A5316k | Partial (App Data + Airlift) |
| iOS 18.0 Beta 5 | 22A5326f | Partial (App Data + Airlift) |
| iOS 18.0 Beta 6 | 22A5338b | Partial (App Data + Airlift) |
| iOS 18.0 Beta 7 | 22A5346a | Partial (App Data + Airlift) |
| iOS 18.0 Beta 8 | 22A5350a | Partial (App Data + Airlift) |
| iOS 18.0 | 22A3354 | Partial (App Data + Airlift) |
| iOS 26.0 | 23A341 | Partial (App Data + Airlift) |
| iOS 26.0.1 | 23A355 | Partial (App Data + Airlift) |
| iOS 26.1 | 23B85 | Partial (App Data + Airlift) |
| iOS 26.2 | 23C55 | Partial (App Data + Airlift) |
| iOS 26.2.1 | 23C71 | Partial (App Data + Airlift) |
| iOS 26.3 | 23D127 | Partial (App Data + Airlift) |
| iOS 26.3.1 | 23D8133 | Partial (App Data + Airlift) |
| iOS 26.4 | 23E246 | Partial (App Data + Airlift) |
| iOS 26.4.1 | 23E254 | Partial (App Data + Airlift) |
| iOS 26.4.2 | 23E261 | Partial (App Data + Airlift) |
| iOS 26.5 | 23F77 | Partial (App Data + Airlift) |
| iOS 26.5.2 | 23F84 | Partial (App Data + Airlift) |
| iOS 26.6 | 23G71 | Partial (App Data + Airlift) |
| iOS 26.6.1 | 23G83 | Partial (App Data + Airlift) |
| iOS 26.6.2 | 23G90 | Partial (App Data + Airlift) |
| iOS 26.7.2 | 23H128 | Partial (App Data + Airlift) |
| iOS 27.0 Beta 1 | 24A5355q | Full |
| iOS 27.0 Beta 2 | 24A5370h | Full |
| iOS 27.0 Beta 3 | 24A5380h | Full |
| iOS 27.0 Beta 4 | 24A5390f | Full |
| iOS 27.0 Beta 5 | 24A5408d | Full |
| iOS 27.0 Beta 6 | 24A5418b | Full |
| iOS 27.0 Beta 7 | 24A5424a | Full |
| iOS 27.0 Beta 8 | 24A5430a | Full |
| iOS 27.0 RC | 24A435 | Full |
| iOS 27.0 | 24A437 | Full |
| iOS 27.0.1 | 24A446 | Full |
| iOS 27.1 | 24B91034 | Full |
| iOS 27.2 Beta 1 | 24B5084k | Full |
| iOS 27.2 Beta 2 | 24B5089g | Full |
| iOS 27.2 Beta 3 | 24B5099f | Full |
| iOS 27.2 Beta 4 | 24B5110a | Full |
| iOS 27.2 RC | 24B115 | Full |
| iOS 27.2 | 24B119 | Full |
| iOS 27.2.1 | 24B156 | Full |
| iOS 27.3 Beta 1 | 24C5037i | Full |

**iOS 27.3 Beta 2 (24C5049d) and later are not supported.** The worse_query sandbox escape is patched in iOS 27.3 Beta 2; it remains available on iOS 27.0–27.2.1 and iOS 27.3 Beta 1. Features that depend on the escape, including PosterBoard, are unavailable on iOS 27.3 Beta 2 and later.

Developed and tested on **iOS 27.0.1 (24A446)**.

## Known limitations

- **Battery & Thermal and Jetsam & Crash are blocked on iOS 27.0.1** — the powerlog and DiagnosticReports paths do not exist on that version (fallback chain exhausted, -255 ENOENT).
- **Internal Features are blocked** — CacheData returns 0 on iOS 27.0.1, and no file-based method exists.
- **Disable Thermal is not shipped** — no MobileGestalt key exists for it.
- **The Siri method only makes the waitlist appear** — it does not fix Siri stuck on "Adding support…" with models already downloaded.
- **PosterBoard is blocked on iOS 27.3 Beta 2 and later** — the worse_query escape is patched there (available on iOS 27.0–27.2.1 and iOS 27.3 Beta 1).

## Companion app — Signed Apps

**Signed Apps** (by adnan.120hz) is the companion signer for WorkTweaks: an on-device app that signs IPAs with your own Apple ID — GrandSlam sign-in and anisette, provisioning (certificate, App ID, and the App Group WorkTweaks needs) under your own team, then in-app signing and export of the signed IPA.

Signed Apps is a **separate, closed-source app**. Its repository is **private** and its source code is not published here or anywhere else — see its own license section below. It is documented in this README only so WorkTweaks users know what it is and which terms apply to it.

## Credits

The two apps' credits are kept separate — they are different projects built on different work.

### WorkTweaks

| Project | Author | What it provides | License |
| --- | --- | --- | --- |
| [worse_query](https://github.com/forcequitOS/worse_query) | ForceQuit OS | The core system: the sandbox escape and MobileGestalt access this whole app is built on | GPL-3.0 |
| [mond](https://github.com/rooootdev/mond) | rooootdev | CacheExtra key knowledge — the tweak-key research the WorkTweaks tweak catalog is built on | AGPL-3.0 |
| [Nugget](https://github.com/leminlimez/Nugget) | leminlimez | The file-based CacheData pattern method used by Enable iPadOS Mode (MobileGestaltCacheDataTweak). | AGPL-3.0 |
| [3105](https://github.com/YangJiiii/3105) | YangJiii | Reference & Patch Files | GPL-3.0 |
| Xo File | — | Reference — cache data cleaner | — |
| [Pocket Poster](https://github.com/leminlimez/Pocket-Poster) | leminlimez | Reference — video-to-wallpaper (CAML) builder used by the PosterBoard wallpaper maker | GPL-3.0 |
| [Flake](https://github.com/squairdev/Flake) | Squair | Reference — MercuryPoster wallpaper import (Flake method) | GPL-3.0 |
| [CAPlayground](https://github.com/CAPlayground/CAPlayground) | CAPlayground | Reference — PosterBoard wallpaper format the maker was verified against | — |
| [Erosion-CN](https://github.com/Kianuni/Erosion-CN) | Kianuni | Reference — Splash Ad Cache Lock mechanism (ad SDK cache lock, save vault, diagnostics, Wi-Fi file sharing, Voice Memos export, AI cache probes) | GPL-3.0 |
| [WCMigrate](https://github.com/yangokok886/WCMigrate) | yangokok886 | Reference — APFS save-vault idea (clonefile staging, atomic swap with rollback) | GPL-3.0 |
| [Aircard](https://github.com/adnan120hz/aircard-ios) | Adnan | Get Pairing File + Local Dev VPN tunnel — the on-device pairing Airlift uses to reach the device | — |
| Siri AI Method | Toto | Reference — turn on new Siri AI (CacheData line edit + device spoof) | — |
| Respring technique — @neonmodder123 | @neonmodder123 | Developer of the web-based respring approach used by this app (via mond). | — |
| Respring technique — @skadz108 | @skadz108 | Swift implementation of the respring web view (via mond / jailbreak.party). | — |

### Signed Apps

| Project | Author | What it provides | License |
| --- | --- | --- | --- |
| [iLoader](https://iloader.app) | iLoader team | System — Signed Apps implements iLoader's signing system on-device: the same isideload-based flow (GrandSlam sign-in, anisette, provisioning with App Groups, and signing) | — |
| SideInstaller | FrizzleM | Implementation — the code Signed Apps was built from | Custom (see below) |
| isideload | Nicholas Sharp | Core — the Rust library for Apple ID sign-in and provisioning | MIT |

**Developer (both apps):** Adnan — [TikTok @adnan.120hz](https://www.tiktok.com/@adnan.120hz) · [GitHub @adnan120hz](https://github.com/adnan120hz)

## License

### WorkTweaks — AGPL-3.0 (open source)

WorkTweaks is free software, licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)** — see [LICENSE](LICENSE) for the full text.

Why AGPL and not plain GPL: the core system (worse_query) is GPL-3.0, but the CacheExtra key knowledge from mond and the CacheData method from Nugget are AGPL-3.0. GPLv3 code may be combined into an AGPLv3 work (GPLv3 §13), and the AGPL terms then apply to the combined work as a whole — so WorkTweaks is distributed under AGPL-3.0. The same applies to the wallpaper-maker format knowledge from Pocket Poster (GPL-3.0).

### Signed Apps — proprietary (NOT open source)

Signed Apps is **not open source**. It is closed-source software under a **custom license** (Copyright 2026 Adnan):

- Personal, non-commercial use only. Commercial use is prohibited.
- The source code is not published; the app's repository is private.
- Redistribution of the app is not permitted except as the developer authorizes.

These terms mirror the license of SideInstaller by FrizzleM, the implementation Signed Apps was built from, whose license likewise allows personal, non-commercial use and prohibits commercial use. One component inside Signed Apps is open source: its core, **isideload** by Nicholas Sharp, is MIT-licensed, and that MIT license applies to isideload itself — it does not make Signed Apps open source.

The AGPL-3.0 license above covers **WorkTweaks only**. It does not apply to Signed Apps, and Signed Apps' custom license does not apply to WorkTweaks.

## Install

WorkTweaks is distributed as an unsigned IPA. iLoader, SideInstaller, and Feather sign the IPA with a provisioning profile that must include WorkTweaks' App Group registered under your own team; LiveContainer runs the unsigned IPA as a guest app without signing. With a free Apple ID, sideloaded apps expire after about 7 days and must be refreshed.

**Option 1 — iLoader (desktop).** Install with **[iLoader](https://iloader.app)** — the free sideloading tool for Windows, macOS, and Linux (download it only from the official site, iloader.app). Open iLoader, sign in with your Apple ID, connect your device by USB, choose **Install IPA**, and select the WorkTweaks `.ipa`. iLoader registers the App Group under your team as part of signing.

**Option 2 — SideInstaller (desktop).** Install with **SideInstaller** — the free sideloading tool by FrizzleM ([github.com/FrizzleM/SideInstaller](https://github.com/FrizzleM/SideInstaller)). Open SideInstaller, sign in with your Apple ID, choose **Install IPA**, and select the WorkTweaks `.ipa`. SideInstaller registers the App Group under your team as part of signing.

**Option 3 — Feather (on-device).** Install with **Feather** — the on-device IPA signer. Import the WorkTweaks `.ipa` into Feather, sign it with your own Apple ID, and install it.

**Option 4 — LiveContainer (on-device, no signing).** Install with **LiveContainer** — import the WorkTweaks `.ipa` into the LiveContainer app and launch it from inside LiveContainer. No Apple ID sign-in or signing is required; the app runs as a guest inside LiveContainer.

**What does NOT work:** signing WorkTweaks directly with **KSign**, or with **ESign's shared/free certificates** (the same applies to Sideloadly). Those signers cannot register the App Group under your team, so the signed result has no working App Group entitlement — WorkTweaks then cannot apply its tweaks. ESign is fine as the *installer* for an IPA that has already been signed with the correct App Group; it just cannot do the provisioning itself.

## Building & signing notes

- Every push to `main` builds an unsigned IPA in GitHub Actions (artifact `WorkTweaks-unsigned-ipa`).
- The Xcode target is intentionally still named `worse_query` — only the display name is WorkTweaks.
- The app must keep an App Group entitlement when signed. WorkTweaks reads its App Group dynamically from the entitlements of the running process at runtime (with multi-group fallback), so signer-rewritten bundle ids and team-suffixed groups work automatically.
- Use at your own risk — tweaks modify system files. Keep your original backup.
