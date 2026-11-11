import SwiftUI

// MARK: - Tutorials
//
// Two step-by-step installation guides: the desktop route (iLoader)
// and the on-device route (Signed Apps, the companion
// signer app). Reachable from the Welcome screen, the unsupported
// screen, and the Tweaks tab toolbar.
//
// Since v3.8 the page renders as Liquid Glass cards (WTGlassPage),
// like every other page — the guides' text is unchanged.

struct TutorialsView: View {
    var body: some View {
        WTGlassPage {
            WTSectionCard {
                Text("WorkTweaks only works when its App Group is part of the signing profile. Both guides below make sure that happens — pick the one that fits you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            WTSectionCard(header: "Guide A — Install with iLoader (Desktop)", footer: "Free Apple ID installs expire after about 7 days — reinstall with iLoader to renew.") {
                VStack(alignment: .leading, spacing: 0) {
                    step(1, "Download the latest WorkTweaks IPA from the GitHub Releases page.")
                    Divider().padding(.leading, 14)
                    step(2, "On a computer, download iLoader from iloader.app — the official site only — and open it.")
                    Divider().padding(.leading, 14)
                    step(3, "Connect your iPhone by USB, then sign in with your Apple ID in iLoader.")
                    Divider().padding(.leading, 14)
                    step(4, "Choose the WorkTweaks IPA and install it.")
                    Divider().padding(.leading, 14)
                    step(5, "If iOS asks, enable Developer Mode (Settings → Privacy & Security → Developer Mode) and trust the developer profile.")
                    Divider().padding(.leading, 14)
                    step(6, "Open WorkTweaks and you're done.")
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: "Guide B — Sign with Signed Apps (Mobile)") {
                VStack(alignment: .leading, spacing: 0) {
                    step(1, "Download the WorkTweaks IPA from GitHub.")
                    Divider().padding(.leading, 14)
                    step(2, "Open Signed Apps and sign in with your Apple ID.")
                    Divider().padding(.leading, 14)
                    step(3, "Certificates tab: create your certificate if needed. A free team can hold only one active development certificate — if creation fails with error 7460, revoke an old unused certificate there first.")
                    Divider().padding(.leading, 14)
                    step(4, "Install tab → Provisioning: fill in the fields below, tap Provision, and wait for \"profile OK\". Your Team ID is shown in the app's Certificates tab.") {
                        monoLine("Bundle ID: cc.forcequit.worse-query.<Your Team ID>")
                        monoLine("App name: WorkTweaks")
                        monoLine("App Group ID: group.cc.forcequit.worse-query.<Your Team ID>")
                    }
                    Divider().padding(.leading, 14)
                    step(5, "Pick the WorkTweaks IPA, set the Signing Bundle ID field to the same identifier, then tap Sign IPA.")
                    Divider().padding(.leading, 14)
                    step(6, "Export the signed IPA and install it with ESign (or any IPA installer).")
                    Divider().padding(.leading, 14)
                    step(7, "Open WorkTweaks and you're done.")
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: "Good to Know") {
                VStack(alignment: .leading, spacing: 0) {
                    note("The original identifiers are already registered to another developer account, which is why the Team ID suffix is required.")
                    Divider().padding(.leading, 14)
                    note("Never share your certificate .p12 file with anyone — it contains your private signing key.")
                    Divider().padding(.leading, 14)
                    note("A signed IPA only works on the device registered in its profile.")
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Tutorials")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Rows

    private func step(_ number: Int, _ text: String) -> some View {
        step(number, text) { EmptyView() }
    }

    private func step<Extra: View>(_ number: Int, _ text: String, @ViewBuilder extra: () -> Extra) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 26, height: 26)
                Text("\(number)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func monoLine(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.subheadline)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
