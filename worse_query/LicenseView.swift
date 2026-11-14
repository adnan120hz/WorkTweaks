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
    var body: some View {
        WTGlassPage {
            WTSectionCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WorkTweaks")
                        .font(.title3.weight(.bold))
                    Text("A MobileGestalt tweak app for iOS 26/27, built on the open-source projects credited below. Use at your own risk — tweaks modify system files.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            WTSectionCard(header: "Compatibility — Supported iOS Versions & Builds", footer: "WorkTweaks v3.0 only opens on the builds listed above: the app checks your device's build at launch, and any other build gets the \"not supported\" screen instead of the app. Developed and tested on iOS 27.0.1 (24A446).") {
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

            WTSectionCard(header: "Developer") {
                VStack(alignment: .leading, spacing: 0) {
                    creditRow(
                        title: "Adnan.120hz on TikTok",
                        detail: "Follow for updates, demos and new tweaks.",
                        url: "https://www.tiktok.com/@adnan.120hz?_r=1&_t=ZS-9BFSZLWsbbw"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "adnan120hz on GitHub",
                        detail: "The developer's GitHub profile.",
                        url: "https://github.com/adnan120hz"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "WorkTweaks source code",
                        detail: "This app's own repository — issues and contributions welcome.",
                        url: "https://github.com/adnan120hz/WorkTweaks"
                    )
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: "Core System & Tweak Engine") {
                VStack(alignment: .leading, spacing: 0) {
                    creditRow(
                        title: "ForceQuit OS — worse_query",
                        detail: "The core system: the sandbox escape and MobileGestalt access this whole app is built on.",
                        url: "https://github.com/forcequitOS/worse_query"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "mond — by rooootdev",
                        detail: "The CacheExtra key knowledge — the tweak-key research the WorkTweaks tweak catalog is built on.",
                        url: "https://github.com/rooootdev/mond"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "Nugget — by leminlimez",
                        detail: "The file-based CacheData pattern method used by Enable iPadOS Mode (MobileGestaltCacheDataTweak).",
                        url: "https://github.com/leminlimez/Nugget"
                    )
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: "Reference") {
                VStack(alignment: .leading, spacing: 0) {
                    creditRow(
                        title: "3105 — YangJiii",
                        detail: "Reference — app-data browsing and portable patches",
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
                        Text("Reference — cache data cleaner")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "Pocket Poster — leminlimez",
                        detail: "Reference — video-to-wallpaper (CAML) builder used by the PosterBoard wallpaper maker.",
                        url: "https://github.com/leminlimez/Pocket-Poster"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "CAPlayground",
                        detail: "Reference — PosterBoard wallpaper format the maker was verified against.",
                        url: "https://github.com/CAPlayground/CAPlayground"
                    )
                    Divider()
                        .padding(.leading, 14)
                    // Toto is credited without a link: the
                    // user named the person only, no URL was given.
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Siri AI Method — Toto")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Reference — turn on new Siri AI (CacheData line edit + device spoof)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: "Respring", footer: "Credit as written in mond's source: \"Web approach developed by @neonmodder123, implemented in Swift here by @skadz108.\" — jailbreak.party") {
                VStack(alignment: .leading, spacing: 0) {
                    creditRow(
                        title: "@neonmodder123",
                        detail: "Developer of the web-based respring approach used by this app (via mond).",
                        url: "https://jailbreak.party"
                    )
                    Divider()
                        .padding(.leading, 14)
                    creditRow(
                        title: "@skadz108",
                        detail: "Swift implementation of the respring web view (via mond / jailbreak.party).",
                        url: "https://jailbreak.party"
                    )
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: "License", footer: "WorkTweaks is free software under the GNU Affero General Public License v3.0. The core (worse_query) is GPL-3.0, but the CacheExtra key knowledge from mond and the CacheData method from Nugget are AGPL-3.0 — GPLv3 code may be combined into an AGPLv3 work, and the AGPL terms then cover the combined work as a whole.") {
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
                }
            }

            WTSectionCard {
                Text("All upstream projects remain under their respective licenses. WorkTweaks only repackages and extends them; full credit belongs to the original authors above.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .navigationTitle("License & Credits")
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
