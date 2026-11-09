import SwiftUI

// MARK: - Intro (first-launch welcome)
//
// Shown exactly once: the first time the app is opened after install.
// Tapping "Get Started" records that the intro has been seen
// (UserDefaults, see RootView) and it never appears again — unless the
// app is deleted and reinstalled. Content: app identity with the real
// app icon, the developer, a credits summary, compatibility, and a
// link into the full License & Credits page.

struct IntroView: View {
    /// Called when the user taps "Get Started" — the parent marks the
    /// intro as seen and dismisses this cover for good.
    var onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showLicense = false

    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "WorkTweaks v\(v)"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Soft blue glow washing down from the top of the screen.
                LinearGradient(
                    colors: [Color.blue.opacity(0.20), Color.blue.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 360)
                .ignoresSafeArea(edges: .top)

                ScrollView {
                    VStack(spacing: 22) {
                        header
                            .padding(.top, 36)

                        developerCard
                        creditsCard
                        compatibilityCard

                        Button {
                            showLicense = true
                        } label: {
                            Label("View Full License & Credits", systemImage: "doc.text")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, 2)

                        Text(versionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 10)
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button {
                    onStart()
                    dismiss()
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
                .shadow(color: .blue.opacity(0.30), radius: 10, y: 4)
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
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
                .shadow(color: .blue.opacity(0.30), radius: 16, y: 8)
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
                chip(icon: "checkmark.shield", text: "iOS 26.7 – 27.3 Beta")
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
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: Cards

    private var developerCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.15, green: 0.45, blue: 1.0), Color(red: 0.0, green: 0.25, blue: 0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
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
        }
        .introCard()
    }

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Credits & License", systemImage: "scroll")
                .font(.headline)
                .padding(.bottom, 6)

            creditRow(icon: "terminal", name: "ForceQuit OS", role: "worse_query — the core system (sandbox escape)")
            Divider()
            creditRow(icon: "slider.horizontal.3", name: "mond — rooootdev", role: "the tweak engine & MobileGestalt apply system")
            Divider()
            creditRow(icon: "cube", name: "Nugget — leminlimez", role: "the file-based CacheData method (iPadOS Mode) & custom resolution")
            Divider()
            creditRow(icon: "arrow.counterclockwise", name: "@neonmodder123 & @skadz108", role: "the respring technique (jailbreak.party)")

            Text("This app is free software under the GNU GPL v3 license, following the licenses of the projects above.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
        .introCard()
    }

    private var compatibilityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Compatibility", systemImage: "checkmark.shield")
                .font(.headline)
            Text("iOS 26.7 (23H24) — iOS 27.3 Beta 1 (24C5037i)")
                .font(.subheadline.weight(.semibold))
            Text("Includes every iOS 27.0 and 27.2 developer beta and RC, iOS 27.0.1, iOS 27.1 on iPhone Duo, and iOS 27.3 Beta 1. The full version & build list lives in License & Credits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .introCard()
    }

    private func creditRow(icon: String, name: String, role: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .padding(.vertical, 9)
    }
}

// MARK: - Shared card style

private extension View {
    /// One consistent card surface for every Intro section: same
    /// padding, corner radius, fill, and hairline border.
    func introCard() -> some View {
        self
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}
