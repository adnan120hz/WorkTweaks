import SwiftUI

// MARK: - Tutorials
//
// Two step-by-step installation guides: the desktop route (iLoader)
// and the on-device route (App Group By Adnan.120hz, the companion
// signer app). Reachable from the Welcome screen, the unsupported
// screen, and the Tweaks tab toolbar.

struct TutorialsView: View {
    var body: some View {
        List {
            Section {
                Text("WorkTweaks only works when its App Group is part of the signing profile. Both guides below make sure that happens — pick the one that fits you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                step(1, "Download the latest WorkTweaks IPA from the GitHub Releases page.")
                step(2, "On a computer, download iLoader from iloader.app — the official site only — and open it.")
                step(3, "Connect your iPhone by USB, then sign in with your Apple ID in iLoader.")
                step(4, "Choose the WorkTweaks IPA and install it.")
                step(5, "If iOS asks, enable Developer Mode (Settings → Privacy & Security → Developer Mode) and trust the developer profile.")
                step(6, "Open WorkTweaks and you're done.")
            } header: {
                Text("Guide A — Install with iLoader (Desktop)")
            } footer: {
                Text("Free Apple ID installs expire after about 7 days — reinstall with iLoader to renew.")
            }

            Section {
                step(1, "Download the WorkTweaks IPA from GitHub.")
                step(2, "Open App Group By Adnan.120hz and sign in with your Apple ID.")
                step(3, "Certificates tab: create your certificate if needed. A free team can hold only one active development certificate — if creation fails with error 7460, revoke an old unused certificate there first.")
                step(4, "Install tab → Provisioning: fill in the fields below, tap Provision, and wait for \"profile OK\". Your Team ID is shown in the app's Certificates tab.") {
                    monoLine("Bundle ID: cc.forcequit.worse-query.<Your Team ID>")
                    monoLine("App name: WorkTweaks")
                    monoLine("App Group ID: group.cc.forcequit.worse-query.<Your Team ID>")
                }
                step(5, "Pick the WorkTweaks IPA, set the Signing Bundle ID field to the same identifier, then tap Sign IPA.")
                step(6, "Export the signed IPA and install it with ESign (or any IPA installer).")
                step(7, "Open WorkTweaks and you're done.")
            } header: {
                Text("Guide B — Sign with App Group By Adnan.120hz (Mobile)")
            }

            Section {
                note("The original identifiers are already registered to another developer account, which is why the Team ID suffix is required.")
                note("Never share your certificate .p12 file with anyone — it contains your private signing key.")
                note("A signed IPA only works on the device registered in its profile.")
            } header: {
                Text("Good to Know")
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
        .padding(.vertical, 3)
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
        .padding(.vertical, 2)
    }
}
