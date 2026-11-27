import SwiftUI

// MARK: - Terms & Conditions (English only)
//
// The terms live in the onboarding as page 2, and here as a
// standalone page users can re-read later (linked from the
// Tweaks tab footer, next to License & Credits). Both use the
// same TermsContent, so the wording never drifts.
//
// English ONLY, by the user's order: no wtLang.tr calls here
// and no keys added to WTLang — the terms are a legal text
// that reads the same in every language.
//
// This is NOT a login gate. The sign-in notice below says the
// tutorials and complete guides on the official web page need
// a Gmail sign-in; the app itself never signs anyone in, never
// asks for a Google account, and stays fully open.

struct TermsView: View {
    var body: some View {
        WTGlassPage {
            TermsContent()
        }
        .navigationTitle("Terms & Conditions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The shared terms content: the intro line, the sign-in
/// notice (with the tappable web link and the "Go to Website"
/// button), and the eight numbered clauses. The clauses are
/// drafted from the app's own LicenseView/README content —
/// what the app is, the 7-day free-certificate limit, the
/// Backup tab snapshots, the honestly-blocked features — not
/// generic filler.
struct TermsContent: View {
    @Environment(\.openURL) private var openURL

    private static let webURL = URL(string: "https://worktweaks-group.vercel.app")!

    private var clauses: [(title: String, body: String)] {
        [
            (
                "What WorkTweaks is",
                "WorkTweaks is a MobileGestalt tweak app for iOS 26 and 27, built by Adnan. It unlocks hidden device features — Dynamic Island tweaks, iPadOS Mode, custom region, and more — without a jailbreak, using the worse_query sandbox escape by ForceQuit OS."
            ),
            (
                "Sign-in requirement",
                "Access to the tutorials and the complete guides on the official web page requires signing in with a Gmail account at worktweaks-group.vercel.app. The sign-in happens on the web. The app itself does not sign you in and never asks for your Google account."
            ),
            (
                "Your device, your responsibility",
                "Tweaks run on your own iPhone. You are responsible for your device, your Apple ID, and the data on it. WorkTweaks is installed with a free Apple ID certificate, which Apple limits to about 7 days — re-sign the app when it expires."
            ),
            (
                "Use at your own risk",
                "Tweaks modify system files (MobileGestalt, CacheExtra, and app data). A wrong value can stop a feature from working until you restore it. Every Apply saves a snapshot first, and you can restore it from the Backup tab."
            ),
            (
                "No warranty",
                "WorkTweaks is provided “as is”, without warranty of any kind. The developer is not liable for data loss, a broken setup, or an app that stops opening after an iOS update. Some features are honestly blocked on your iOS version — Battery & Jetsam diagnostics cannot read their folders on iOS 27.0.1, and worse_query is patched in iOS 27.3 beta 2 and later."
            ),
            (
                "Acceptable use",
                "Use WorkTweaks on your own device only. Do not use it to bypass paid features, to change other people's devices without permission, or to distribute tweaked apps that break the law. Respect the licenses of the projects credited in License & Credits."
            ),
            (
                "License",
                "WorkTweaks is free software under the GNU Affero General Public License v3.0. The core (worse_query) is GPL-3.0; the CacheExtra key knowledge from mond and the CacheData method from Nugget are AGPL-3.0. You may use, study, and share the app under those terms — see License & Credits for the full list."
            ),
            (
                "Changes to these terms",
                "These terms may change with new versions of WorkTweaks. The version shown in the app is the one that applies. If you keep using the app after a change, you accept the new terms."
            ),
        ]
    }

    var body: some View {
        Text("Please read these terms before using WorkTweaks. By using the app, you agree to them.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        WTSectionCard(header: "Sign-in required") {
            VStack(alignment: .leading, spacing: 0) {
                Text("To get the tutorials and complete guides, you must log in with your Gmail account on the official WorkTweaks web page. The sign-in happens on the web, not in the app — the app never asks for your Google password.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider()
                    .padding(.leading, 14)

                Link(destination: Self.webURL) {
                    HStack(spacing: 12) {
                        RowIcon(systemImage: "globe")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Official web page")
                                .font(.subheadline.weight(.semibold))
                            Text("worktweaks-group.vercel.app")
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
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 14)

                Button {
                    openURL(Self.webURL)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text("Go to Website")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }

        WTSectionCard(header: "Terms & Conditions") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(clauses.enumerated()), id: \.offset) { index, clause in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 14)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1).")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(clause.title)
                                .font(.subheadline.weight(.semibold))
                            Text(clause.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
