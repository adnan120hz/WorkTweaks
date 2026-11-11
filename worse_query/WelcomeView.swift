import SwiftUI

// MARK: - Welcome (v2.0 first-launch gate)
//
// Shown exactly once per install: the first time WorkTweaks v2.0
// is opened. Tapping "Get Started" records that the welcome has
// been seen (UserDefaults key wt.welcomeV2Seen, see RootView) and
// it never appears again — unless the app is deleted and
// reinstalled. Content: app identity with the real app icon, the
// install-method requirement, the developer, a credits summary,
// compatibility, and buttons into Tutorials and License & Credits.
//
// Since v3.8 the page renders as Liquid Glass cards (WTGlassPage),
// like every other page — the content and buttons are unchanged.

struct WelcomeView: View {
    /// Called when the user taps "Get Started" — the parent marks
    /// the welcome as seen and moves on to the support check.
    var onStart: () -> Void

    @State private var showTutorials = false
    @State private var showLicense = false

    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"
        return "WorkTweaks v\(v)"
    }

    var body: some View {
        WTGlassPage {
            header
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

            installSection
            developerSection
            creditsSection
            compatibilitySection

            WTSectionCard {
                Button {
                    showLicense = true
                } label: {
                    Label("View Full License & Credits", systemImage: "doc.text")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
            }

            Text(versionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    onStart()
                } label: {
                    HStack(spacing: 8) {
                        Text("Get Started")
                        Image(systemName: "arrow.right")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showTutorials = true
                } label: {
                    Label("Tutorials", systemImage: "book")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showTutorials) {
            NavigationStack {
                TutorialsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close") { showTutorials = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showLicense) {
            NavigationStack {
                LicenseView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close") { showLicense = false }
                        }
                    }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 16) {
            // The real app icon — the same artwork as the home-screen
            // icon (bundled as the AppIconDisplay image set).
            Image("AppIconDisplay")
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
                Text("Welcome to WorkTweaks")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("A MobileGestalt tweak tool for iOS 26 & 27 — unlock your device's hidden features without a jailbreak, powered by the worse_query sandbox escape.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                chip(icon: "checkmark.shield", text: "iOS 26.7.2 – 27.3 Beta")
                chip(icon: "iphone", text: "No Jailbreak")
                chip(icon: "lock.open", text: "Open Source")
            }
        }
    }

    private func chip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .wtGlassCard(cornerRadius: 999)
    }

    // MARK: Sections

    private var installSection: some View {
        WTSectionCard(header: "Installation") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Please Install It the Right Way")
                    .font(.subheadline.weight(.semibold))
                Text("WorkTweaks must be installed with iLoader, or by signing the IPA with Signed Apps, so that its App Group works correctly.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Installed any other way, the signed profile leaves the App Group out — and without it, the tweaks can't run. Tap Tutorials below for both step-by-step guides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var developerSection: some View {
        WTSectionCard(header: "Developer") {
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
                        Text("Developer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
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
    }

    private var creditsSection: some View {
        WTSectionCard(header: "Credits & License", footer: "This app is free software under the GNU AGPL v3 license, following the licenses of the projects above.") {
            VStack(alignment: .leading, spacing: 0) {
                creditRow(icon: "terminal", name: "ForceQuit OS", role: "worse_query — the core system (sandbox escape)")
                Divider().padding(.leading, 14)
                creditRow(icon: "slider.horizontal.3", name: "mond — rooootdev", role: "the CacheExtra key knowledge behind the tweak catalog")
                Divider().padding(.leading, 14)
                creditRow(icon: "cube", name: "Nugget — leminlimez", role: "the file-based CacheData method (iPadOS Mode)")
                Divider().padding(.leading, 14)
                creditRow(icon: "arrow.counterclockwise", name: "@neonmodder123 & @skadz108", role: "the respring technique (jailbreak.party)")
            }
            .padding(.vertical, 4)
        }
    }

    private var compatibilitySection: some View {
        WTSectionCard(header: "Compatibility") {
            VStack(alignment: .leading, spacing: 8) {
                Text("iOS 26.7.2 (23H128) — iOS 27.3 Beta 1 (24C5037i)")
                    .font(.subheadline.weight(.semibold))
                Text("v3.0 checks your device's build at launch and only opens on the supported builds. The full version & build list lives in License & Credits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func creditRow(icon: String, name: String, role: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(systemImage: icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text(role)
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
