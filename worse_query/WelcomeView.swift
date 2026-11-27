import SwiftUI

// MARK: - Welcome (v7.0 four-page Introducing, redesigned)
//
// Shown exactly once per install: the first time WorkTweaks is
// opened. Four swipeable pages with a smooth slide per page:
// 1. the developer (Adnan, GitHub, TikTok), 2. Terms &
// Conditions (English only, with the sign-in notice for the
// official web page), 3. every feature in v7.0, 4. license &
// credits. "Next" advances, and on the
// last page it becomes "Get Started" — that is the only way
// out. There is NO Skip anywhere: the user asked for the Skip
// menu to be gone entirely, so the welcome must be walked
// through page by page. Either button records that the
// welcome has been seen (UserDefaults key wt.welcomeV2Seen,
// see RootView) and it never appears again — unless the app
// is deleted and reinstalled. The gating is unchanged from
// v2.0.
//
// DESIGN (redesigned 2026-11-24, replacing the f2395fcb
// layout): there is NO bottom bar and NO background panel
// behind the buttons at all — the old .ultraThinMaterial
// bar covered the bottom of the developer card, which is
// what the user objected to. Instead a single floating pill
// button (Next / Get Started) plus a row of three page dots
// hovers over the content with transparent surroundings —
// just the pill, with a soft shadow so it reads over any
// content scrolling underneath. Every page's ScrollView
// carries bottom padding taller than the floating control,
// so the last card is never hidden behind it. Pages are
// leading-aligned and content-first: a hero block (icon +
// title + subtitle) then glass section cards. No big emoji
// headers, no centered avatar card.
//
// Every string goes through wtLang.tr, so the pages follow the
// app language (English default). The feature rows use custom
// blue icons (a solid blue tile + white SF Symbol, made for
// this app) — NO stock Unicode emoji anywhere in the welcome,
// by the user's order; the rest of the app stays emoji-free.
// Dynamic Type: scalable TextStyle
// fonts only, no fixed heights, rows wrap instead of
// truncating.

struct WelcomeView: View {
    @EnvironmentObject private var wtLang: WTLangStore

    /// Called when the user taps "Get Started" — the parent
    /// marks the welcome as seen and moves on to the support
    /// check.
    var onStart: () -> Void

    @State private var page = 0
    @State private var showLicense = false

    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "7.0"
        return "WorkTweaks v\(v)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                DeveloperPage(versionText: versionText)
                    .tag(0)
                TermsPage()
                    .tag(1)
                FeaturesPage()
                    .tag(2)
                CreditsPage(onShowFullLicense: { showLicense = true })
                    .tag(3)
            }
            // The system page dots are off: the floating
            // control below draws its own four dots, so the
            // dots and the pill move as one unit with no bar.
            .tabViewStyle(.page(indexDisplayMode: .never))
            // The slide between pages is the animation the user
            // asked for: one smooth ease per page, swipe or tap.
            .animation(.easeInOut(duration: 0.35), value: page)
            // Room at the top for the corner mascots below:
            // without it the top pair would sit on the hero
            // icon and the page titles.
            .padding(.top, 40)

            // Four small Tweaky mascots, one in each corner of
            // the onboarding pages — decoration only, never
            // intercepting taps. The top pair sits in the band
            // the TabView's top padding leaves open; the
            // bottom pair floats just above the floating pill
            // and dots.
            VStack {
                HStack {
                    TweakyMascot(size: 30)
                    Spacer()
                    TweakyMascot(size: 30)
                }
                Spacer()
                HStack {
                    TweakyMascot(size: 30)
                    Spacer()
                    TweakyMascot(size: 30)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 118)
            .allowsHitTesting(false)

            floatingControls
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

    // MARK: Floating controls — no bar, no background

    /// The only navigation: four dots plus one pill button,
    /// floating over the page content with transparent
    /// surroundings. No material, no solid color, no panel —
    /// nothing behind the button can cover content, because
    /// there is nothing behind it at all.
    private var floatingControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .animation(.easeInOut(duration: 0.25), value: page)
                        .accessibilityHidden(true)
                }
            }

            if page < 3 {
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
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
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
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }
}

// MARK: - Page 1: Developer
//
// Leading-aligned hero (icon, title, subtitle) then one
// glass card: the developer's name and role, one intro line,
// and two full-width tappable link rows showing the actual
// handles (@adnan.120hz, adnan120hz) with an external-link
// chevron — instead of the old centered avatar card with two
// side-by-side buttons.

private struct DeveloperPage: View {
    @EnvironmentObject private var wtLang: WTLangStore

    var versionText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // The real icon artwork for the current language —
                // same PNGs as the home-screen alternate icons.
                Image(uiImage: WTHeaderIcon.image(for: wtLang.language))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityLabel("WorkTweaks")
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(wtLang.tr("Welcome to WorkTweaks"))
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(wtLang.tr("A MobileGestalt tweak tool for iOS 26 & 27 — unlock your device's hidden features without a jailbreak, powered by the worse_query sandbox escape."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WTSectionCard(header: wtLang.tr("Meet the Developer")) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Adnan")
                                .font(.title3.weight(.bold))
                            Text(wtLang.tr("Developer"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider()
                            .padding(.leading, 14)

                        Text(wtLang.tr("WorkTweaks is built by Adnan — find him on GitHub and TikTok."))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)

                        Divider()
                            .padding(.leading, 14)

                        Link(destination: URL(string: "https://www.tiktok.com/@adnan.120hz")!) {
                            linkRow(
                                systemImage: "music.note",
                                title: "TikTok",
                                handle: "@adnan.120hz"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 14)

                        Link(destination: URL(string: "https://github.com/adnan120hz")!) {
                            linkRow(
                                systemImage: "chevron.left.forwardslash.chevron.right",
                                title: "GitHub",
                                handle: "adnan120hz"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(wtLang.tr("Follow for updates, demos and new tweaks."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            // Taller than the floating pill + dots, so the
            // version line at the end is never hidden behind
            // them — the old bar covered the card's bottom.
            .padding(.bottom, 120)
        }
    }

    private func linkRow(systemImage: String, title: String, handle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(handle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.forward.app")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - Page 2: Terms & Conditions
//
// English only, by the user's order — the title and the whole
// content are hardcoded in TermsContent, with no wtLang.tr
// calls and no WTLang keys. The page shares TermsContent with
// the standalone TermsView (linked from the Tweaks tab footer),
// so the wording never drifts. This is NOT a login gate: the
// sign-in notice is about the official web page, and the app
// itself never signs anyone in.

private struct TermsPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms & Conditions")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                TermsContent()
            }
            .padding(.horizontal, 20)
            // Taller than the floating pill + dots, so the
            // last clause is never hidden behind them.
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Page 3: Features
//
// The same 18 v7.0 features, now grouped into four glass
// cards instead of one flat list — Tweaks & System, Files &
// Data, Look & Feel, Setup & More. The rows themselves are
// unchanged (custom blue icon, title, one-line description), so every
// existing translation key still applies; only the four
// group headers are new keys.

private struct FeaturesPage: View {
    @EnvironmentObject private var wtLang: WTLangStore

    /// Every v7.0 feature, one short row each, grouped by
    /// what it does. Titles reuse the app's existing
    /// translation keys where they exist; the one-line
    /// descriptions are Introducing keys.
    private var groups: [(title: String, features: [(icon: String, title: String, desc: String)])] {
        [
            ("Tweaks & System", [
                ("slider.horizontal.3", "Tweaks", "24 catalog tweaks — Dynamic Island, iPadOS Mode, custom region and more."),
                ("lock.open.fill", "Sandbox Escape", "Reach system folders the sandbox normally hides."),
                ("battery.100", "Battery & Thermal", "Battery health, cycle count and temperature — read-only."),
                ("memorychip", "Jetsam & Crash", "See why apps were killed, with crash logs you can delete."),
                ("person.badge.shield.checkmark", "Configuration Profiles", "List installed profiles, read-only — no fake supervision."),
            ]),
            ("Files & Data", [
                ("folder.fill", "App Data", "Browse any app's container, edit files, and build portable patches."),
                ("archivebox.fill", "Save Vault", "Back up an app's save data and restore it after a reinstall."),
                ("wifi", "Wi-Fi File Sharing", "Share files with your PC over Wi-Fi, protected by a PIN."),
                ("tablecells.fill", "SQLite / plist editor", "Edit app databases and preference files in place."),
                ("mic.fill", "Voice Memos & AI Cache", "Export voice memos and check Apple Intelligence cache size."),
                ("trash.fill", "Cache Data Cleaner", "Free space by cleaning app caches, safely."),
            ]),
            ("Look & Feel", [
                ("photo.fill", "PosterBoard", "Make lock-screen wallpapers from your photos and videos."),
                ("shield.fill", "Splash Ad Cache Lock", "Lock ad splash-screen caches so apps open without the splash ad."),
            ]),
            ("Setup & More", [
                ("airplane", "Airlift", "Flash passcode themes and wallet card skins over the pairing tunnel."),
                ("key.fill", "Get Pairing File", "Pair this iPhone on-device and unlock Airlift."),
                ("externaldrive.fill", "Backup", "Snapshots of your tweaks, plus All Data Backup for photos and videos."),
                ("terminal.fill", "Log", "Every action, logged — send it when something goes wrong."),
                ("globe", "Languages", "English, Indonesian, Chinese, Vietnamese and Russian — the UI follows you."),
            ]),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(wtLang.tr("Features"))
                        .font(.largeTitle.weight(.bold))
                    Text(wtLang.tr("Everything in WorkTweaks, at a glance."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 16)

                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    WTSectionCard(header: wtLang.tr(group.title)) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(group.features.enumerated()), id: \.offset) { index, feature in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                                featureRow(icon: feature.icon, title: feature.title, desc: feature.desc)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            // Taller than the floating pill + dots, so the
            // last group's bottom row is never hidden behind
            // them.
            .padding(.bottom, 120)
        }
    }

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Custom blue icon (made for this app — NO stock
            // Unicode emoji): a solid blue tile with a white
            // SF Symbol. Fixed size: row icons don't scale
            // with Dynamic Type.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
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

// MARK: - Page 4: License & Credits
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
            ("3105 — YangJiii", "GPL-3.0"),
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
            ("3105 — YangJiii", "Reference & Patch Files"),
            ("Xo File", "Reference — cache data cleaner"),
            ("Siri AI Method — Toto", "Reference — turn on new Siri AI (CacheData line edit + device spoof)"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(wtLang.tr("License & Credits"))
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(wtLang.tr("A MobileGestalt tweak app for iOS 26/27, built on the open-source projects credited below. Use at your own risk — tweaks modify system files."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            }
            .padding(.horizontal, 20)
            // Taller than the floating pill + dots, so the
            // full-license row is never hidden behind them.
            .padding(.bottom, 120)
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
