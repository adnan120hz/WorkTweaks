<p align="center">
  <img src="icon-rounded.png" width="160" alt="WorkTweaks icon">
</p>

<h1 align="center">WorkTweaks</h1>

<p align="center">
  A MobileGestalt tweak app for iOS 26 &amp; 27 — unlock your device's hidden features without a jailbreak, powered by the <strong>worse_query</strong> sandbox escape.
</p>

---

## Features

- **Tweaks** — the tweak catalog ported from [mond](https://github.com/rooootdev/mond): Dynamic Island, Always-On Display, Apple Intelligence, Stage Manager, Charge Limit, Action Button, iPadOS Mode, device spoofing, and more — applied with mond's in-place MobileGestalt write system, so tweaks persist across resprings and reboots.
- **Extra** — a free-form CacheExtra editor: add, edit, or delete any MobileGestalt key directly.
- **Backup** — an original backup is saved on first read, an automatic **After Apply Tweaks** snapshot is taken at every Apply, and manual snapshots can be created at any time. Every snapshot shows which tweaks were on and the value of every tweak key, and can be restored as a whole, per tweak, or per key.
- **Sandbox & Log** — the original worse_query escape / path tools and the live console output.
- **First-launch intro** — developer and credits welcome screen, shown once per install.
- Light, dark, and tinted app icons.

## Supported iOS versions

WorkTweaks is built for **iOS 26 and 27** — the worse_query core targets both major versions — and installs on iOS 26.0 or later. Later iOS 27.x releases are covered by the same major-version support. Developed and tested on **iOS 27.0.1 (24A446)**.

| Version | Build |
| --- | --- |
| iOS 26.7 | 23H24 |
| iOS 27.0 Developer Beta 1 | 24A5355q |
| iOS 27.0 Developer Beta 2 | 24A5370h |
| iOS 27.0 Developer Beta 3 | 24A5380h |
| iOS 27.0 Developer Beta 4 | 24A5390f |
| iOS 27.0 Developer Beta 5 | 24A5408d |
| iOS 27.0 Developer Beta 6 | 24A5418b |
| iOS 27.0 Developer Beta 7 | 24A5424a |
| iOS 27.0 Developer Beta 8 | 24A5430a |
| iOS 27.0 RC | 24A437 |
| iOS 27.0 | 24A437 |
| iOS 27.0.1 | 24A446 |
| iOS 27.1 | iPhone Duo only |
| iOS 27.2 Beta 1 | 24B5084k |
| iOS 27.2 Beta 2 | 24B5089g |
| iOS 27.2 Beta 3 | 24B5099f |
| iOS 27.2 Beta 4 | 24B5110a |
| iOS 27.2 RC | 24B115 |
| iOS 27.2 | 24B119 |
| iOS 27.3 Beta 1 | 24C5037i |

## Credits

WorkTweaks is built on open-source work:

| Project | Author | What it provides | License |
| --- | --- | --- | --- |
| [worse_query](https://github.com/forcequitOS/worse_query) | ForceQuit OS | The core system: the sandbox escape and MobileGestalt access this whole app is built on | GPL-3.0 |
| [mond](https://github.com/rooootdev/mond) | rooootdev | The tweak engine: the tweak catalog and the load / apply / write system | AGPL-3.0 |
| [Nugget](https://github.com/leminlimez/Nugget) | leminlimez | The file-based CacheData pattern method used by Enable iPadOS Mode | AGPL-3.0 |
| Respring technique | @neonmodder123 & @skadz108 | The web-based respring approach and its Swift implementation (via jailbreak.party) | — |

**Developer:** Adnan — [TikTok @adnan.120hz](https://www.tiktok.com/@adnan.120hz) · [GitHub @adnan120hz](https://github.com/adnan120hz)

## License

WorkTweaks is free software, licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)** — see [LICENSE](LICENSE) for the full text.

Why AGPL and not plain GPL: the core system (worse_query) is GPL-3.0, but the tweak engine ported from mond and the CacheData method taken from Nugget are both AGPL-3.0. GPLv3 code may be combined into an AGPLv3 work (GPLv3 §13), and the AGPL terms then apply to the combined work as a whole — so WorkTweaks is distributed under AGPL-3.0.

## Install

WorkTweaks is distributed as an unsigned IPA and must be installed with **[iLoader](https://iloader.app)** — the free, open-source sideloading tool for Windows, macOS, and Linux (download it only from the official site, iloader.app). Open iLoader, sign in with your Apple ID, connect your device by USB, choose **Install IPA**, and select the WorkTweaks `.ipa`. With a free Apple ID, sideloaded apps expire after about 7 days and must be refreshed.

## Building & signing notes

- Every push to `main` builds an unsigned IPA in GitHub Actions (artifact `WorkTweaks-unsigned-ipa`).
- The Xcode target is intentionally still named `worse_query` — only the display name is WorkTweaks.
- The app must keep an App Group entitlement when signed. WorkTweaks reads its own provisioning profile at runtime and uses the group it was actually signed with, so signer-rewritten bundle ids and team-suffixed groups work automatically.
- Use at your own risk — tweaks modify system files. Keep your original backup.
