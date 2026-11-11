import SwiftUI

// MARK: - License & Credits
//
// WorkTweaks is built on open-source work. This page credits every
// upstream project and person whose code or technique ships in the app.

struct LicenseView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WorkTweaks")
                        .font(.title3.weight(.bold))
                    Text("A MobileGestalt tweak app for iOS 26/27, built on the open-source projects credited below. Use at your own risk — tweaks modify system files.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(SupportInfo.supportedReleases) { release in
                    SupportedReleaseRow(release: release)
                }
            } header: {
                Text("Compatibility — Supported iOS Versions & Builds")
            } footer: {
                Text("WorkTweaks v3.0 only opens on the builds listed above: the app checks your device's build at launch, and any other build gets the \"not supported\" screen instead of the app. Developed and tested on iOS 27.0.1 (24A446).")
            }

            Section {
                creditRow(
                    title: "Adnan.120hz on TikTok",
                    detail: "Follow for updates, demos and new tweaks.",
                    url: "https://www.tiktok.com/@adnan.120hz?_r=1&_t=ZS-9BFSZLWsbbw"
                )
                creditRow(
                    title: "adnan120hz on GitHub",
                    detail: "The developer's GitHub profile.",
                    url: "https://github.com/adnan120hz"
                )
                creditRow(
                    title: "WorkTweaks source code",
                    detail: "This app's own repository — issues and contributions welcome.",
                    url: "https://github.com/adnan120hz/WorkTweaks"
                )
            } header: {
                Text("Developer")
            }

            Section {
                creditRow(
                    title: "ForceQuit OS — worse_query",
                    detail: "The core system: the sandbox escape and MobileGestalt access this whole app is built on.",
                    url: "https://github.com/forcequitOS/worse_query"
                )
                creditRow(
                    title: "mond — by rooootdev",
                    detail: "The CacheExtra key knowledge — the tweak-key research the WorkTweaks tweak catalog is built on.",
                    url: "https://github.com/rooootdev/mond"
                )
                creditRow(
                    title: "Nugget — by leminlimez",
                    detail: "The file-based CacheData pattern method used by Enable iPadOS Mode (MobileGestaltCacheDataTweak), and the daemon catalog knowledge — the launchd label research the Daemons page is built on.",
                    url: "https://github.com/leminlimez/Nugget"
                )
            } header: {
                Text("Core System & Tweak Engine")
            }

            Section {
                creditRow(
                    title: "@neonmodder123",
                    detail: "Developer of the web-based respring approach used by this app (via mond).",
                    url: "https://jailbreak.party"
                )
                creditRow(
                    title: "@skadz108",
                    detail: "Swift implementation of the respring web view (via mond / jailbreak.party).",
                    url: "https://jailbreak.party"
                )
            } header: {
                Text("Respring")
            } footer: {
                Text("Credit as written in mond's source: \"Web approach developed by @neonmodder123, implemented in Swift here by @skadz108.\" — jailbreak.party")
            }

            Section {
                LabeledContent("WorkTweaks", value: "AGPL-3.0")
                LabeledContent("worse_query — ForceQuit OS", value: "GPL-3.0")
                LabeledContent("mond — rooootdev", value: "AGPL-3.0")
                LabeledContent("Nugget — leminlimez", value: "AGPL-3.0")
            } header: {
                Text("License")
            } footer: {
                Text("WorkTweaks is free software under the GNU Affero General Public License v3.0. The core (worse_query) is GPL-3.0, but the CacheExtra key knowledge from mond and the CacheData method and daemon catalog knowledge from Nugget are AGPL-3.0 — GPLv3 code may be combined into an AGPLv3 work, and the AGPL terms then cover the combined work as a whole.")
            }

            Section {
                Text("All upstream projects remain under their respective licenses. WorkTweaks only repackages and extends them; full credit belongs to the original authors above.")
                    .font(.caption).foregroundStyle(.secondary)
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
                        .font(.caption2).foregroundStyle(Color.accentColor)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
        }
    }
}
