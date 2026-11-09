import SwiftUI

// MARK: - Intro (perkenalan saat aplikasi dibuka)
//
// Shown as a full-screen cover every time the app process starts:
// app identity, the developer, and a short credits summary, with a
// link into the full License & Credits page. One tap on "Mulai"
// dismisses it for the rest of the session.

struct IntroView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showLicense = false

    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "WorkTweaks v\(v)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    badge
                        .padding(.top, 28)

                    VStack(spacing: 8) {
                        Text("Welcome to WorkTweaks")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("A MobileGestalt tweak tool for iOS 26 & 27 — unlock your device's hidden features without a jailbreak, powered by the worse_query sandbox escape.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    developerCard
                    creditsCard
                    compatibilityCard

                    Button {
                        showLicense = true
                    } label: {
                        Label("View Full License & Credits", systemImage: "doc.text")
                            .font(.subheadline.weight(.medium))
                    }

                    Text(versionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.top, 8)
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

    // MARK: Pieces

    private var badge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.15, green: 0.45, blue: 1.0), Color(red: 0.0, green: 0.25, blue: 0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 104, height: 104)
                .shadow(color: .blue.opacity(0.35), radius: 14, y: 6)
            Text("Wt")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("WorkTweaks")
    }

    private var developerCard: some View {
        VStack(spacing: 10) {
            Label("Developer", systemImage: "person.crop.circle")
                .font(.headline)
            Text("Adnan")
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                Link(destination: URL(string: "https://www.tiktok.com/@adnan.120hz")!) {
                    Label("TikTok @adnan.120hz", systemImage: "music.note")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Link(destination: URL(string: "https://github.com/adnan120hz")!) {
                    Label("GitHub adnan120hz", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Credits & License", systemImage: "scroll")
                .font(.headline)
            creditLine(name: "ForceQuit OS", role: "worse_query — the core system (sandbox escape)")
            creditLine(name: "mond — rooootdev", role: "the tweak engine & MobileGestalt apply system")
            creditLine(name: "Nugget — leminlimez", role: "the file-based CacheData method (iPadOS Mode) & custom resolution")
            creditLine(name: "@neonmodder123 & @skadz108", role: "the respring technique (jailbreak.party)")
            Text("This app is free software under the GNU GPL v3 license, following the licenses of the projects above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var compatibilityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Compatibility", systemImage: "checkmark.shield")
                .font(.headline)
            Text("iOS 26.7 (23H24) · iOS 27.0 — 27.2 (24A437 — 24B119)")
                .font(.subheadline.weight(.semibold))
            Text("Includes every iOS 27.0 and 27.2 developer beta and RC, iOS 27.0.1, and iOS 27.1 on iPhone Duo. The full version & build list lives in License & Credits.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func creditLine(name: String, role: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.subheadline.weight(.semibold))
            Text(role)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
