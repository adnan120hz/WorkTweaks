import SwiftUI

// MARK: - News (version updates)
//
// The version changelog, newest first — what changed in each
// release. The current version carries a blue LATEST pill.
// SileoNewsContent is the list itself (no NavigationStack), so
// it can be pushed inside the settings sheet; SileoNewsView
// wraps it in its own stack with a Done button, for the sheet
// the release banners open.

struct SileoNewsContent: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let version: String
        let date: String
        let notes: String
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private let entries: [Entry] = [
        Entry(version: "v6.0.4", date: "16 Nov 2026", notes: "Back to the NEW build — native TabView (automatic Liquid Glass, no manual glassEffect, no old pill). Backup moved out of the tab bar to the top left only (opens as a sheet) and the search circle sits level with the tab bar."),
        Entry(version: "v6.0.3", date: "16 Nov 2026", notes: "The bottom bar is a floating pill with four tabs (Backup moved to the top left only) and the search circle beside it, level like real Sileo. Only the WorkTweaks version banner remains."),
        Entry(version: "v6.0.2", date: "15 Nov 2026", notes: "Back to the v6.0 native TabView — no self-coded pill. The search circle now sits level with the tab bar instead of floating above it."),
        Entry(version: "v6.0.1", date: "15 Nov 2026", notes: "The floating pill tab bar is back — the search circle sits beside it at the same height, like real Sileo, instead of floating above the native tab bar."),
        Entry(version: "v6.0", date: "15 Nov 2026", notes: "Tweak icons now run in blocks of four down the page (four blue, four gray, four cyan, four dark), the Fix Issue menu sits at the top left with the Apple Intelligence and status bar guides, and opa334 is credited for the Sileo UI in the license."),
        Entry(version: "v5.9.3", date: "15 Nov 2026", notes: "The search circle is back at the bottom right, floating above the tab bar like before, and Backup sits at the top left of the Featured page, on the same row as the profile avatar. The native tab bar stays."),
        Entry(version: "v5.9.2", date: "15 Nov 2026", notes: "The custom pill is gone — the Sileo UI now uses the native TabView, whose tab bar is the system's own Liquid Glass (the same automatic glass v1.0 had). Search moved to a magnifier in the nav bar. CI now picks the newest Xcode 26 or newer instead of pinning one version."),
        Entry(version: "v5.9.1", date: "15 Nov 2026", notes: "The pill is plain Liquid Glass again — the white tint from v5.9 turned it into frosted gray, so it is gone — and CI now pins Xcode 26.6, the exact toolchain v1.0 was built with."),
        Entry(version: "v5.9", date: "15 Nov 2026", notes: "The Sileo UI uses the system's own Liquid Glass now — native toggles on every tweak, native glass buttons, a milky pill with a highlight that glides between tabs, Backup as the fifth pill tab, centered banners, and a fixed Welcome screen (Get Started presses again)."),
        Entry(version: "v5.8", date: "15 Nov 2026", notes: "Liquid Glass everywhere — every tweak has a glass toggle switch instead of ON/OFF, the search field and close button are glass, the banners are colorful info cards (version, iOS support, iPhone lineup, 24 tweaks), the icons are tinted glass tiles, and the app follows Light Mode too."),
        Entry(version: "v5.7", date: "15 Nov 2026", notes: "Liquid Glass pill and search circle, the pill tabs are now Featured / App Data / PosterBoard / Cache Cleaner, bigger tweak icons, and the Tweaks UI choice is back on the Featured page."),
        Entry(version: "v5.6", date: "15 Nov 2026", notes: "Sileo UI, faithful replica — Featured, News, Sources and Packages, release banners, tweak packages."),
        Entry(version: "v5.5", date: "15 Nov 2026", notes: "Sileo UI restyles the whole app — the floating pill tab bar and every menu in the Sileo style."),
        Entry(version: "v5.4", date: "15 Nov 2026", notes: "Third Tweaks UI: Sileo UI, styled after the Sileo Featured page, blue accent, WorkTweaks icon."),
        Entry(version: "v5.3.2", date: "15 Nov 2026", notes: "The IPA is now ad-hoc signed with the App Group entitlements embedded, so SideStore and AltStore detect the group when re-signing."),
        Entry(version: "v5.3.1", date: "15 Nov 2026", notes: "Siri AI Cache Patch now scans every byte offset, and the Log records the pattern diagnostics when it finds nothing."),
        Entry(version: "v5.3", date: "15 Nov 2026", notes: "Custom Region Model — type the sales-region suffix, e.g. PA/A, shown in Settings > General > About."),
        Entry(version: "v5.2.1", date: "14 Nov 2026", notes: "\"Fix Apple Intelligence Here!\" guide on the Apple Intelligence card."),
        Entry(version: "v5.2", date: "14 Nov 2026", notes: "iPhone 17 Pro and 17 Pro Max subtypes, plus iPhone Duo spoofing (iPhone19,4)."),
        Entry(version: "v5.1.1", date: "14 Nov 2026", notes: "Calmer tab-switch sound, and a tap sound on every toggle."),
        Entry(version: "v5.1", date: "14 Nov 2026", notes: "\"Fix Status Bar!\" guide, iPhone 18 Pro and Duo subtypes, UI sounds, landscape mode."),
        Entry(version: "v5.0", date: "14 Nov 2026", notes: "Deploy and the Package Builder rebuilt as one zip — import a zip, no location picking, then Apply."),
        Entry(version: "v4.3.1", date: "14 Nov 2026", notes: "Siri AI anchor fix, Siri AI Method credit for Toto, PosterBoard fallback for iOS 27.3."),
        Entry(version: "v4.3", date: "14 Nov 2026", notes: "Siri AI Cache Patch — the Filza line-104 edit, in-app — plus Guide C, Turn On New Siri AI."),
        Entry(version: "v4.2", date: "12 Nov 2026", notes: "Tweaks UI choice (New UI / Old UI) and the PosterBoard wallpaper maker."),
        Entry(version: "v4.1", date: "12 Nov 2026", notes: "PosterBoard wallpaper maker — build a wallpaper descriptor from a photo or video, on-device."),
        Entry(version: "v4.0", date: "12 Nov 2026", notes: "Install without manual signing: the App Group is read from the signed app at runtime (csops), with a multi-group fallback."),
        Entry(version: "v3.13", date: "11 Nov 2026", notes: "Cache Data Cleaner — empty Library/Caches and tmp, with sizes before and after."),
    ]

    var body: some View {
        SileoPage(bottomPadding: 24) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("WorkTweaks \(entry.version)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Sileo.primary)
                        if entry.version == "v\(appVersion)" {
                            Text("LATEST")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Sileo.accent, in: Capsule())
                        }
                        Spacer()
                        Text(entry.date)
                            .font(.system(size: 13))
                            .foregroundStyle(Sileo.secondary)
                    }
                    Text(entry.notes)
                        .font(.system(size: 14))
                        .foregroundStyle(Sileo.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Sileo.separator).frame(height: 1)
                }
            }
        }
    }
}

struct SileoNewsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SileoNewsContent()
                .navigationTitle("News")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.blue, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
        }
    }
}
