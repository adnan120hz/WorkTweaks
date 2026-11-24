import SwiftUI

// MARK: - Welcome (v7.0 three-page Introducing)
//
// Shown exactly once per install: the first time WorkTweaks is
// opened. Three swipeable pages with a smooth slide per page:
// 1. the developer (Adnan, GitHub, TikTok), 2. every feature
// in v7.0, 3. license & credits. "Skip" dismisses from any
// page; "Next" advances, and on the last page it becomes
// "Get Started". Either one records that the welcome has been
// seen (UserDefaults key wt.welcomeV2Seen, see RootView) and
// it never appears again — unless the app is deleted and
// reinstalled. The gating is unchanged from v2.0.
//
// Every string goes through wtLang.tr, so the pages follow the
// app language (English default). Emojis are decorative here
// by the user's order — the rest of the app stays emoji-free.
// Dynamic Type: scalable TextStyle fonts only, no fixed
// heights, rows wrap instead of truncating.

struct WelcomeView: View {
    @EnvironmentObject private var wtLang: WTLangStore

    /// Called when the user taps "Get Started" or "Skip" — the
    /// parent marks the welcome as seen and moves on to the
    /// support check.
    var onStart: () -> Void

    @State private var page = 0
    @State private var showLicense = false

    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "7.0"
        return "WorkTweaks v\(v)"
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                DeveloperPage()
                    .tag(0)
                FeaturesPage()
                    .tag(1)
                CreditsPage(onShowFullLicense: { showLicense = true })
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            // The slide between pages is the animation the user
            // asked for: one smooth ease per page, swipe or tap.
            .animation(.easeInOut(duration: 0.35), value: page)

            bottomBar
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showLicense) {
            NavigationStack {
                LicenseView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(wtLang.tr("Close")) { showLicense = false }
                        }
                    }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if page < 2 {
                Button {
                    page += 1
                } label: {
                    HStack(spacing: 8) {
                        Text(wtLang.tr("Next"))
                        Image(systemName: "arrow.right")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    onStart()
                } label: {
                    HStack(spacing: 8) {
                        Text(wtLang.tr("Get Started"))
                        Image(systemName: "arrow.right")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button {
                onStart()
            } label: {
                Text(wtLang.tr("Skip"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text(versionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Page 1: Developer

private struct DeveloperPage: View {
    @EnvironmentObject private var wtLang: WTLangStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // The real icon artwork for the current language —
                // same PNGs as the home-screen alternate icons.
                Image(uiImage: WTHeaderIcon.image(for: wtLang.language))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityLabel("WorkTweaks")

                VStack(spacing: 8) {
                    Text("👋")
                        .font(.largeTitle)
                    Text(wtLang.tr("Welcome to WorkTweaks"))
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(wtLang.tr("A MobileGestalt tweak tool for iOS 26 & 27 — unlock your device's hidden features without a jailbreak, powered by the worse_query sandbox escape."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WTSectionCard(header: wtLang.tr("Meet the Developer")) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 46, height: 46)
                                Text("A")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Adnan")
                                    .font(.headline)
                                Text(wtLang.tr("Developer"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                        Divider()
                            .padding(.leading, 14)

                        Text(wtLang.tr("WorkTweaks is built by Adnan — find him on GitHub and TikTok."))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)

                        Divider()
                            .padding(.leading, 14)

                        HStack(spacing: 10) {
                            Link(destination: URL(string: "https://www.tiktok.com/@adnan.120hz")!) {
                                Label("TikTok", systemImage: "music.note")
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            Link(destination: URL(string: "https://github.com/adnan120hz")!) {
                                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }

                Text(wtLang.tr("Follow for updates, demos and new tweaks."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Page 2: Features

private struct FeaturesPage: View {
    @EnvironmentObject private var wtLang: WTLangStore

    /// Every v7.0 feature, one short row each. Titles reuse the
    /// app's existing translation keys where they exist; the
    /// one-line descriptions are new Introducing keys.
    private var features: [(emoji: String, title: String, desc: String)] {
        [
            ("🎛️", "Tweaks", "24 catalog tweaks — Dynamic Island, iPadOS Mode, custom region and more."),
            ("🔓", "Sandbox Escape", "Reach system folders the sandbox normally hides."),
            ("📁", "App Data", "Browse any app's container, edit files, and build portable patches."),
            ("🖼️", "PosterBoard", "Make lock-screen wallpapers from your photos and videos."),
            ("🧹", "Cache Data Cleaner", "Free space by cleaning app caches, safely."),
            ("🛡️", "Splash Ad Cache Lock", "Lock ad splash-screen caches so apps open without the splash ad."),
            ("💾", "Save Vault", "Back up an app's save data and restore it after a reinstall."),
            ("🔋", "Battery & Thermal", "Battery health, cycle count and temperature — read-only."),
            ("💥", "Jetsam & Crash", "See why apps were killed, with crash logs you can delete."),
            ("📡", "Wi-Fi File Sharing", "Share files with your PC over Wi-Fi, protected by a PIN."),
            ("🗃️", "SQLite / plist editor", "Edit app databases and preference files in place."),
            ("📋", "Configuration Profiles", "List installed profiles, read-only — no fake supervision."),
            ("🎙️", "Voice Memos & AI Cache", "Export voice memos and check Apple Intelligence cache size."),
            ("✈️", "Airlift", "Flash passcode themes and wallet card skins over the pairing tunnel."),
            ("🔑", "Get Pairing File", "Pair this iPhone on-device and unlock Airlift."),
            ("💽", "Backup", "Snapshots of your tweaks, plus All Data Backup for photos and videos."),
            ("📜", "Log", "Every action, logged — send it when something goes wrong."),
            ("🌐", "Languages", "English, Indonesian, Chinese, Vietnamese and Russian — the UI follows you."),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("✨")
                        .font(.largeTitle)
                    Text(wtLang.tr("Features"))
                        .font(.title.weight(.bold))
                    Text(wtLang.tr("Everything in WorkTweaks, at a glance."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                WTSectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            featureRow(emoji: feature.emoji, title: feature.title, desc: feature.desc)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func featureRow(emoji: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji)
                .font(.title3)
                .frame(width: 30, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(wtLang.tr(title))
                    .font(.subheadline.weight(.semibold))
                Text(wtLang.tr(desc))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Page 3: License & Credits
//
// Mirrors LicenseView.swift: the same projects, the same
// licenses, the same role wording. LicenseView stays the full
// list (it also holds Aircard, CAPlayground, respring and the
// compatibility table) — this page links out to it.

private struct CreditsPage: View {
    @EnvironmentObject private var wtLang: WTLangStore

    var onShowFullLicense: () -> Void

    /// Same rows as LicenseView's License card.
    private var licenseRows: [(name: String, license: String)] {
        [
            ("WorkTweaks", "AGPL-3.0"),
            ("worse_query — ForceQuit OS", "GPL-3.0"),
            ("mond — rooootdev", "AGPL-3.0"),
            ("Nugget — leminlimez", "AGPL-3.0"),
            ("Pocket Poster — leminlimez", "GPL-3.0"),
            ("Erosion-CN — Kianuni", "GPL-3.0"),
            ("WCMigrate — yangokok886", "GPL-3.0"),
        ]
    }

    /// Same rows as LicenseView's credit cards, same wording.
    /// mond is credited ONLY for CacheExtra key knowledge —
    /// WorkTweaks is Adnan's original app, never a port.
    private var creditRows: [(name: String, role: String)] {
        [
            ("ForceQuit OS — worse_query", "The core system: the sandbox escape and MobileGestalt access this whole app is built on."),
            ("mond — by rooootdev", "The CacheExtra key knowledge — the tweak-key research the WorkTweaks tweak catalog is built on."),
            ("Nugget — by leminlimez", "The file-based CacheData pattern method used by Enable iPadOS Mode (MobileGestaltCacheDataTweak)."),
            ("Pocket Poster — leminlimez", "Reference — video-to-wallpaper (CAML) builder used by the PosterBoard wallpaper maker."),
            ("Erosion-CN — Kianuni", "Reference — Splash Ad Cache Lock mechanism (ad SDK cache lock, save vault, diagnostics, Wi-Fi file sharing, Voice Memos export, AI cache probes)."),
            ("WCMigrate — yangokok886", "Reference — APFS save-vault idea (clonefile staging, atomic swap with rollback)."),
            ("3105 — YangJiii", "Reference — app-data browsing and portable patches"),
            ("Xo File", "Reference — cache data cleaner"),
            ("Siri AI Method — Toto", "Reference — turn on new Siri AI (CacheData line edit + device spoof)"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("📜")
                        .font(.largeTitle)
                    Text(wtLang.tr("License & Credits"))
                        .font(.title.weight(.bold))
                    Text(wtLang.tr("A MobileGestalt tweak app for iOS 26/27, built on the open-source projects credited below. Use at your own risk — tweaks modify system files."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                WTSectionCard(header: wtLang.tr("License"), footer: wtLang.tr("Free and open source — the projects below made it possible.")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(licenseRows.enumerated()), id: \.offset) { index, row in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            LabeledContent(row.name, value: row.license)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                        }
                    }
                }
                .padding(.horizontal, 16)

                WTSectionCard(header: wtLang.tr("Credits")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(creditRows.enumerated()), id: \.offset) { index, row in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            creditRow(name: row.name, role: row.role)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)

                WTSectionCard {
                    Button {
                        onShowFullLicense()
                    } label: {
                        Label(wtLang.tr("View Full License & Credits"), systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func creditRow(name: String, role: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(systemImage: "cube")
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text(wtLang.tr(role))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
