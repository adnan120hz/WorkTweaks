import SwiftUI

// MARK: - License & Credits
//
// WorkTweaks is built on open-source work. This page credits every
// upstream project and person whose code or technique ships in the app.
//
// Since v3.8 the page renders as Liquid Glass cards (WTGlassPage),
// like every other page — presentation only; the credits and
// license texts are unchanged, apart from the 3105 reference the
// user asked to add below.

struct LicenseView: View {
    @EnvironmentObject private var wtLang: WTLangStore

    var body: some View {
        WTGlassPage {
            WTSectionCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WorkTweaks")
                        .font(.title3.weight(.bold))
                    Text(wtLang.tr("A MobileGestalt tweak app for iOS 26/27, built on the open-source projects credited below. Use at your own risk — tweaks modify system files."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            WTSectionCard(header: wtLang.tr("Compatibility — Supported iOS Versions & Builds"), footer: wtLang.tr("WorkTweaks v3.0 only opens on the builds listed above: the app checks your device's build at launch, and any other build gets the \"not supported\" screen instead of the app. On iOS 18 and iOS 26, only App Data and Airlift are supported (partial support). Developed and tested on iOS 27.0.1 (24A446).")) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(SupportInfo.supportedReleases.enumerated()), id: \.element.id) { index, release in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 14)
                        }
                        SupportedReleaseRow(release: release)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: wtLang.tr("Developer")) {
                VStack(alignment: .leading, spacing: 0) {
                    creditRow(
                        title: "Adnan.120hz on TikTok",
                        detail: wtLang.tr("Follow for updates, demos and new tweaks."),
                        url: "https://www.tiktok.com/@adnan.120hz?_r=1&_t=ZS-9BFSZLWsbbw"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "adnan120hz on GitHub",
                        detail: wtLang.tr("The developer's GitHub profile."),
                        url: "https://github.com/adnan120hz"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "WorkTweaks source code",
                        detail: wtLang.tr("This app's own repository — issues and contributions welcome."),
                        url: "https://github.com/adnan120hz/WorkTweaks"
                    )
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: wtLang.tr("Core System & Tweak Engine")) {
                VStack(alignment: .leading, spacing: 0) {
                    creditRow(
                        title: "ForceQuit OS — worse_query",
                        detail: wtLang.tr("The core system: the sandbox escape and MobileGestalt access this whole app is built on."),
                        url: "https://github.com/forcequitOS/worse_query"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "mond — by rooootdev",
                        detail: wtLang.tr("The CacheExtra key knowledge — the tweak-key research the WorkTweaks tweak catalog is built on."),
                        url: "https://github.com/rooootdev/mond"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "Nugget — by leminlimez",
                        detail: wtLang.tr("The file-based CacheData pattern method used by Enable iPadOS Mode (MobileGestaltCacheDataTweak)."),
                        url: "https://github.com/leminlimez/Nugget"
                    )
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: wtLang.tr("Reference")) {
                VStack(alignment: .leading, spacing: 0) {
                    creditRow(
                        title: "3105 — YangJiii",
                        detail: wtLang.tr("Reference & Patch Files"),
                        url: "https://github.com/YangJiiii/3105"
                    )
                    Divider()
                        .padding(.leading, 14)
                    // Xo File is credited without a link: the
                    // user named the app only, no URL was given.
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Xo File")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(wtLang.tr("Reference — cache data cleaner"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "Pocket Poster — leminlimez",
                        detail: wtLang.tr("Reference — video-to-wallpaper (CAML) builder used by the PosterBoard wallpaper maker."),
                        url: "https://github.com/leminlimez/Pocket-Poster"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "CAPlayground",
                        detail: wtLang.tr("Reference — PosterBoard wallpaper format the maker was verified against."),
                        url: "https://github.com/CAPlayground/CAPlayground"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "Erosion-CN — Kianuni",
                        detail: wtLang.tr("Reference — Splash Ad Cache Lock mechanism (ad SDK cache lock, save vault, diagnostics, Wi-Fi file sharing, Voice Memos export, AI cache probes)."),
                        url: "https://github.com/Kianuni/Erosion-CN"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "WCMigrate — yangokok886",
                        detail: wtLang.tr("Reference — APFS save-vault idea (clonefile staging, atomic swap with rollback)."),
                        url: "https://github.com/yangokok886/WCMigrate"
                    )
                    Divider()
                        .padding(.leading, 14)
                    // LiveContainer core is vendored from the
                    // user's fork adnan120hz/livecontainer
                    // (byte-identical to upstream main); the
                    // upstream URL is the credit.
                    creditRow(
                        title: "LiveContainer",
                        detail: wtLang.tr("Guest apps run inside WorkTweaks — IPA install, patching and launch (LiveContainer core)."),
                        url: "https://github.com/LiveContainer/LiveContainer"
                    )
                    Divider()
                        .padding(.leading, 14)
                    // litehook — LiveContainer's MIT hooking
                    // library, vendored since Phase 2 (source
                    // LiveContainer/litehook, commit a7e9f59).
                    creditRow(
                        title: "litehook — LiveContainer",
                        detail: wtLang.tr("Hooking library the LiveContainer core uses to run guest apps (litehook)."),
                        url: "https://github.com/LiveContainer/litehook"
                    )
                    Divider()
                        .padding(.leading, 14)
                    // ZSign provenance (verified 2026-11-25):
                    // originally zhlynn/zsign (MIT); LiveContainer
                    // uses Feather's iOS adaptation, modified by
                    // khcrysalis (Feather itself is GPL-3.0).
                    // khcrysalis/Feather now redirects to
                    // claration/Feather — the current URL is used.
                    creditRow(
                        title: "Feather — khcrysalis",
                        detail: wtLang.tr("ZSign on-device signing — Feather's iOS adaptation of zhlynn's zsign, modified by khcrysalis."),
                        url: "https://github.com/claration/Feather"
                    )
                    Divider()
                        .padding(.leading, 14)
                    // SideInstaller — FrizzleM: the sign-in /
                    // provisioning system the Container's Apple ID
                    // login ports (GrandSlam auth, teams,
                    // certificates, App IDs, App Groups, profiles).
                    // Custom license: personal/non-commercial use
                    // only; §4 requires the attribution
                    // "SideInstaller by FrizzleM" + link, which
                    // this row is.
                    creditRow(
                        title: "SideInstaller by FrizzleM",
                        detail: wtLang.tr("Apple ID sign-in, provisioning and signing — and the JIT session, developer disk image download and device transport this build derives from"),
                        url: "https://github.com/FrizzleM/SideInstaller"
                    )
                    Divider()
                        .padding(.leading, 14)
                    // isideload — Nicholas Sharp (MIT): the Rust
                    // core whose GrandSlam + developer-services
                    // protocol the sign-in and provisioning flow
                    // follows (via Signed Apps).
                    creditRow(
                        title: "isideload — Nicholas Sharp",
                        detail: wtLang.tr("Apple ID auth + developer-services protocol the Container's sign-in and provisioning follow."),
                        url: "https://github.com/nab138/isideload"
                    )
                    Divider()
                        .padding(.leading, 14)
                    // idevice — Jackson Coxson (jkcoxson, MIT):
                    // the RPPairing tunnel + RSD services the JIT
                    // session's device transport uses (vendored
                    // under rust-core/vendor, idevice 7bd551c).
                    creditRow(
                        title: "idevice — Jackson Coxson (jkcoxson)",
                        detail: wtLang.tr("RPPairing tunnel + RSD services (lockdown, AMFI, debugserver, developer disk image) — the JIT transport"),
                        url: "https://github.com/jkcoxson/idevice"
                    )
                    Divider()
                        .padding(.leading, 14)
                    // Toto is credited without a link: the
                    // user named the person only, no URL was given.
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Siri AI Method — Toto")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(wtLang.tr("Reference — turn on new Siri AI (CacheData line edit + device spoof)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    Divider()
                        .padding(.leading, 14)
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: wtLang.tr("Get Pairing + VPN Tunnel")) {
                VStack(alignment: .leading, spacing: 0) {
                    creditRow(
                        title: "Aircard",
                        detail: wtLang.tr("Get Pairing File + Local Dev VPN tunnel — the on-device pairing Airlift uses to reach the device."),
                        url: "https://github.com/adnan120hz/aircard-ios"
                    )
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: wtLang.tr("Respring"), footer: wtLang.tr("Credit as written in mond's source: \"Web approach developed by @neonmodder123, implemented in Swift here by @skadz108.\" — jailbreak.party")) {
                VStack(alignment: .leading, spacing: 0) {
                    creditRow(
                        title: "@neonmodder123",
                        detail: wtLang.tr("Developer of the web-based respring approach used by this app (via mond)."),
                        url: "https://jailbreak.party"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "@skadz108",
                        detail: wtLang.tr("Swift implementation of the respring web view (via mond / jailbreak.party)."),
                        url: "https://jailbreak.party"
                    )
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: wtLang.tr("License"), footer: wtLang.tr("WorkTweaks is free software under the GNU Affero General Public License v3.0. The core (worse_query) is GPL-3.0, but the CacheExtra key knowledge from mond and the CacheData method from Nugget are AGPL-3.0 — GPLv3 code may be combined into an AGPLv3 work, and the AGPL terms then cover the combined work as a whole.")) {
                VStack(alignment: .leading, spacing: 0) {
                    LabeledContent("WorkTweaks", value: "AGPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("worse_query — ForceQuit OS", value: "GPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("mond — rooootdev", value: "AGPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("Nugget — leminlimez", value: "AGPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("Pocket Poster — leminlimez", value: "GPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("Erosion-CN — Kianuni", value: "GPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("WCMigrate — yangokok886", value: "GPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("3105 — YangJiii", value: "GPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("LiveContainer", value: "AGPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("litehook — LiveContainer", value: "MIT")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("ZSign — zhlynn", value: "MIT")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("Feather — khcrysalis", value: "GPL-3.0")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("SideInstaller by FrizzleM", value: "Custom")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("isideload — Nicholas Sharp", value: "MIT")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider()
                        .padding(.leading, 14)
                    LabeledContent("idevice — Jackson Coxson (jkcoxson)", value: "MIT")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
            }

            WTSectionCard {
                Text(wtLang.tr("All upstream projects remain under their respective licenses. WorkTweaks only repackages and extends them; full credit belongs to the original authors above."))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .navigationTitle(wtLang.tr("License & Credits"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditRow(title: String, detail: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(url)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
