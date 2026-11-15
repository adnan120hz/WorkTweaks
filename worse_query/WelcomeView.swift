import SwiftUI

// MARK: - Welcome (v2.0 first-launch gate)
//
// Shown exactly once per install: the first time WorkTweaks
// is opened. Tapping "Get Started" records that the welcome
// has been seen (UserDefaults key wt.welcomeV2Seen, see
// RootView) and it never appears again — unless the app is
// deleted and reinstalled. Content: app identity with the
// real app icon, the install-method requirement, the
// developer, a credits summary, compatibility, and buttons
// into Tutorials and License & Credits.
//
// Since v5.8 the page is rebuilt in full Liquid Glass, in the
// Sileo UI's language: a flat page that follows the system
// appearance (Light or Dark Mode), glass cards with tinted
// glass icon tiles, glass pill chips, and glass capsule
// buttons — no grouped list, no solid buttons. The content
// and the behavior are unchanged.

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
        ZStack {
            Sileo.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                    installCard
                    developerCard
                    creditsCard
                    compatibilityCard

                    Button {
                        showLicense = true
                    } label: {
                        HStack {
                            SileoIcon(systemImage: "doc.text", color: .blue, size: 44)
                            Text("View Full License & Credits")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Sileo.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Sileo.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Text(versionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
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
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .glassEffect(.regular.tint(.blue), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    showTutorials = true
                } label: {
                    Label("Tutorials", systemImage: "book")
                        .font(.headline)
                        .foregroundStyle(Sileo.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .glassEffect(.regular, in: Rectangle())
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

    // MARK: One glass card

    /// A section as a Liquid Glass card: a tinted glass icon
    /// tile + the section title on top, the content below.
    private func glassCard<Content: View>(icon: String, tint: Color, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SileoIcon(systemImage: icon, color: tint, size: 44)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Sileo.primary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    .foregroundStyle(Sileo.primary)
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
            .foregroundStyle(Sileo.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
    }

    // MARK: Sections

    private var installCard: some View {
        glassCard(icon: "arrow.down.circle", tint: .blue, title: "Installation") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Please Install It the Right Way")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Sileo.primary)
                Text("WorkTweaks must be installed with iLoader, or by signing the IPA with Signed Apps, so that its App Group works correctly.")
                    .font(.subheadline)
                    .foregroundStyle(Sileo.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Installed any other way, the signed profile leaves the App Group out — and without it, the tweaks can't run. Tap Tutorials below for both step-by-step guides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var developerCard: some View {
        glassCard(icon: "person.fill", tint: .cyan, title: "Developer") {
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
                            .foregroundStyle(Sileo.primary)
                        Text("Developer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 12)

                HStack(spacing: 10) {
                    Link(destination: URL(string: "https://www.tiktok.com/@adnan.120hz")!) {
                        Label("TikTok", systemImage: "music.note")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Sileo.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Link(destination: URL(string: "https://github.com/adnan120hz")!) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Sileo.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var creditsCard: some View {
        glassCard(icon: "heart.fill", tint: .cyan, title: "Credits & License") {
            VStack(alignment: .leading, spacing: 0) {
                creditRow(icon: "terminal", tint: .blue, name: "ForceQuit OS", role: "worse_query — the core system (sandbox escape)")
                Divider().padding(.vertical, 4)
                creditRow(icon: "slider.horizontal.3", tint: .blue, name: "mond — rooootdev", role: "the CacheExtra key knowledge behind the tweak catalog")
                Divider().padding(.vertical, 4)
                creditRow(icon: "cube", tint: .cyan, name: "Nugget — leminlimez", role: "the file-based CacheData method (iPadOS Mode)")
                Divider().padding(.vertical, 4)
                creditRow(icon: "arrow.counterclockwise", tint: .cyan, name: "@neonmodder123 & @skadz108", role: "the respring technique (jailbreak.party)")
            }
            Text("This app is free software under the GNU AGPL v3 license, following the licenses of the projects above.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private var compatibilityCard: some View {
        glassCard(icon: "checkmark.shield", tint: .cyan, title: "Compatibility") {
            VStack(alignment: .leading, spacing: 8) {
                Text("iOS 26.7.2 (23H128) — iOS 27.3 Beta 1 (24C5037i)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Sileo.primary)
                Text("WorkTweaks checks your device's build at launch and only opens on the supported builds. The full version & build list lives in License & Credits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func creditRow(icon: String, tint: Color, name: String, role: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SileoIcon(systemImage: icon, color: tint, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Sileo.primary)
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
