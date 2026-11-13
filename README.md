<p align="center">
  <img src="icon-rounded.png" width="160" alt="WorkTweaks icon">
</p>

<h1 align="center">WorkTweaks</h1>

<p align="center">
  A MobileGestalt tweak app for iOS 26 &amp; 27 — unlock your device's hidden features without a jailbreak, powered by the <strong>worse_query</strong> sandbox escape.
</p>

<p align="center">
  WorkTweaks is an original app by Adnan. This repository also documents its companion signer, <strong>Signed Apps</strong> — the two apps are separate projects with separate credits and separate licenses, listed below.
</p>

---

## Features

- **Install without manual signing** *(new in v4.0)* — WorkTweaks reads its App Group dynamically from the entitlements of the running process and tries every App Group in the signature until one works (multi-group fallback), so it no longer depends on a manually-signed provisioning profile. Install the unsigned IPA with SideStore, AltStore, or LiveContainer and the tweaks work — device-verified in LiveContainer.
- **Tweaks** — WorkTweaks' own catalog of 24 tweaks: Dynamic Island, Always-On Display, Apple Intelligence, Siri AI Cache Patch *(new in v4.3)*, Stage Manager, Charge Limit, Action Button, Camera Control, iPadOS Mode, device spoofing, and more — applied with WorkTweaks' own in-place MobileGestalt write system, so tweaks persist across resprings and reboots. The catalog is organized into sections (All, Dynamic Island, Tweaks, Apple Intelligence, Add feature, Apply/Revert) with a search page. The Tweaks tab offers a **New UI / Old UI** choice *(new in v4.2)* — the current two-column layout or the v1 list layout, picked in Sandbox under Start Tweaks Feature; it applies to the Tweaks tab only.
- **App Data** — browse the data containers of the apps on your device, open and edit text files in place, edit binary files byte by byte with the hex editor (a pristine backup is taken before the first byte edit), and add files and folders.
- **Cache Data Cleaner** *(new in v3.13)* — Sandbox → Utilities: pick an app, see how much cache it keeps in `Library/Caches` and `tmp`, and empty those two folders after a confirmation. Only the contents of those two cache folders are deleted — Documents and the rest of Library are never touched — and the freed space is measured, not estimated.
- **PosterBoard** — import `.tendies` wallpaper packages into PosterBoard's data store and remove the wallpapers you imported, tracked by receipts. The built-in **wallpaper maker** *(new in v4.1)* creates PosterBoard wallpapers on-device from a photo or a video (first 12 seconds, loop on/off) and installs them through the same verified path.
- **Deploy** — install file packages (`.deploy` / folders / `.zip` with a `manifest.json`) into app containers, App Groups, and internal daemon containers, with per-file backups and a restore history. The built-in **Package Builder** lets you create and edit packages on-device.
- **Lock Screen Footnote** — set the footnote text shown on the Lock Screen, as a card in Tweaks → Add feature.
- **Extra** — a free-form CacheExtra editor: add, edit, or delete any MobileGestalt key directly, with a Reset that restores exactly the keys you edited.
- **Backup** — an original backup is saved on first read, an automatic **After Apply Tweaks** snapshot is taken at every Apply, and manual snapshots can be created at any time. Every snapshot can be restored as a whole, per tweak, or per key.
- **Sandbox & Log** — the original worse_query escape / path tools and the live console output.
- **First-launch welcome & tutorials** — install and signing guides (iLoader on desktop, or the Signed Apps companion), plus a step-by-step Siri AI guide *(new in v4.3)*, shown once per install.
- Liquid Glass cards throughout (except the Log, which stays solid). Light, dark, and tinted app icons.

## Supported iOS versions

WorkTweaks checks your exact iOS version and build at launch — only the builds below are supported, and unsupported devices stop at an "unsupported" screen instead of running with unknown keys:

| Version | Build |
| --- | --- |
| iOS 26.7.2 | 23H128 |
| iOS 27.0 | 24A437 |
| iOS 27.0.1 | 24A446 |
| iOS 27.2 Beta 1 | 24B5084k |
| iOS 27.2 Beta 2 | 24B5089g |
| iOS 27.2 Beta 3 | 24B5099f |
| iOS 27.2 Beta 4 | 24B5110a |
| iOS 27.2 RC | 24B115 |
| iOS 27.2 | 24B119 |
| iOS 27.3 Beta 1 | 24C5037i |

Developed and tested on **iOS 27.0.1 (24A446)**.

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
| [Nugget](https://github.com/leminlimez/Nugget) | leminlimez | The file-based CacheData pattern method used by Enable iPadOS Mode | AGPL-3.0 |
| [3105](https://github.com/YangJiiii/3105) | YangJiii | Reference — app-data browsing and portable patches | — |
| Xo File | — | Reference — cache data cleaner | — |
| [Pocket Poster](https://github.com/leminlimez/Pocket-Poster) | leminlimez | Reference — video-to-wallpaper (CAML) builder used by the PosterBoard wallpaper maker | GPL-3.0 |
| [CAPlayground](https://github.com/CAPlayground/CAPlayground) | CAPlayground | Reference — PosterBoard wallpaper format the maker was verified against | — |
| Respring technique | neonmodder123 & skadz108 | The web-based respring approach and its Swift implementation (via jailbreak.party) | — |

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

WorkTweaks is distributed as an unsigned IPA. Whichever route you take, the IPA must end up signed with a provisioning profile that includes **WorkTweaks' App Group registered under your own team** — that requirement is what decides which tools work and which do not. With a free Apple ID, sideloaded apps expire after about 7 days and must be refreshed.

**Option 1 — iLoader (desktop).** Install with **[iLoader](https://iloader.app)** — the free sideloading tool for Windows, macOS, and Linux (download it only from the official site, iloader.app). Open iLoader, sign in with your Apple ID, connect your device by USB, choose **Install IPA**, and select the WorkTweaks `.ipa`. iLoader registers the App Group under your team as part of signing.

**Option 2 — Signed Apps (on-device, no iLoader, no computer).** You can also sign and install WorkTweaks without iLoader, using an on-device signer that provisions with your own Apple ID — **Signed Apps** (the companion app above) does exactly this, and signers built the same way, such as SideInstaller, work on the same principle:

1. Open **Signed Apps** and sign in with your Apple ID (**Sign In** tab).
2. **Certificates** tab: create a certificate. If creation fails with **error 7460**, a certificate already holds your team's single slot — revoke the old certificate there first, then create a new one. (Revoking kills apps signed with the old certificate until they are re-signed.)
3. **Install** tab → **Choose IPA…** and pick the WorkTweaks `.ipa`.
4. **Provisioning** section: Bundle ID `cc.forcequit.worse-query.<your Team ID>`, App name `WorkTweaks`, App Group ID `group.cc.forcequit.worse-query.<your Team ID>` → tap **Provision** and wait until the profile is ready.
5. **Signing** section: set the Bundle ID to the same `cc.forcequit.worse-query.<your Team ID>` — check this field *after* choosing the IPA, because picking an IPA resets it to the IPA's original ID — then tap **Sign IPA**.
6. **Export** the signed IPA and install it. The signed IPA already carries your own profile, so a plain installer is enough for this last step.

**Option 3 — SideStore / AltStore / LiveContainer (no manual signing, v4.0+).** Install the unsigned IPA directly with SideStore, AltStore, or LiveContainer — no certificate, provisioning, or computer signing needed. WorkTweaks finds its App Group from the running process and works as installed.

**What does NOT work:** signing WorkTweaks directly with **KSign**, or with **ESign's shared/free certificates** (the same applies to Sideloadly). Those signers cannot register the App Group under your team, so the signed result has no working App Group entitlement — WorkTweaks then cannot apply its tweaks. ESign is fine as the *installer* in step 6 for an IPA that Signed Apps has already signed; it just cannot do the provisioning itself.

## Building & signing notes

- Every push to `main` builds an unsigned IPA in GitHub Actions (artifact `WorkTweaks-unsigned-ipa`).
- The Xcode target is intentionally still named `worse_query` — only the display name is WorkTweaks.
- The app must keep an App Group entitlement when signed. WorkTweaks reads its App Group dynamically from the entitlements of the running process at runtime (with multi-group fallback), so signer-rewritten bundle ids, team-suffixed groups, and installs via SideStore/AltStore/LiveContainer work automatically.
- Use at your own risk — tweaks modify system files. Keep your original backup.
