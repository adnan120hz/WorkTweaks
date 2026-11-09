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
                creditRow(
                    title: "ForceQuit OS — worse_query",
                    detail: "The core system: the sandbox escape and MobileGestalt access this whole app is built on.",
                    url: "https://github.com/forcequitOS/worse_query"
                )
                creditRow(
                    title: "mond — by rooootdev",
                    detail: "The tweak engine: the tweak catalog and commands, and the load / apply / write system (mg.swift), ported from mond.",
                    url: "https://github.com/rooootdev/mond"
                )
                creditRow(
                    title: "Nugget — by leminlimez",
                    detail: "The file-based CacheData pattern method used by Enable iPadOS Mode (MobileGestaltCacheDataTweak), and the IOMobileGraphicsFamily resolution file used by resolution tweaks.",
                    url: "https://github.com/leminlimez/Nugget"
                )
            } header: {
                Label("Core System & Tweak Engine", systemImage: "cpu")
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
                Label("Respring", systemImage: "restart.circle")
            } footer: {
                Text("Credit as written in mond's source: \"Web approach developed by @neonmodder123, implemented in Swift here by @skadz108.\" — jailbreak.party")
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
                Label("Developer", systemImage: "person.crop.circle")
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
