import SwiftUI

/// Airlift tab — the aircard features ported into WorkTweaks:
/// custom Passcode Themes (.passthm) and custom Apple Wallet card art.
/// Both write through the AirliftFFI exploit, so both need a pairing
/// file (Sandbox → Utilities → Get Pairing File) and a loopback VPN
/// is strongly recommended while they run.
struct AirliftView: View {
    @State private var transport = TransportGate.check()

    var body: some View {
        WTGlassPage {
            if !transport.isReady {
                TransportGateCard(status: transport) {
                    transport = TransportGate.check()
                }
            }
            WTSectionCard(header: "Airlift — from Aircard") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Custom passcode keypad themes and Apple Wallet card art, flashed on-device through the Airlift exploit (iOS 18.0 – 27.2 beta 2).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    Divider().padding(.leading, 14)
                    Text("Both need a pairing file first: Sandbox → Utilities → Get Pairing File. A loopback VPN (Local Dev VPN) is strongly recommended while flashing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            WTSectionCard(header: "Menus") {
                VStack(alignment: .leading, spacing: 0) {
                    menuRow("Passcode Themes", systemImage: "lock.circle.fill") {
                        AirliftPasscodeView()
                    }
                    .disabled(!transport.isReady)
                    .opacity(transport.isReady ? 1 : 0.5)
                    Divider().padding(.leading, 14)
                    menuRow("Wallet Cards", systemImage: "creditcard.fill") {
                        AirliftWalletView()
                    }
                    .disabled(!transport.isReady)
                    .opacity(transport.isReady ? 1 : 0.5)
                }
            }
        }
        .navigationTitle("Airlift")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { transport = TransportGate.check() }
    }

    /// One Airlift menu row: label on the left, chevron on the right,
    /// the whole row tappable (same shape as the Sandbox utility rows).
    private func menuRow<Destination: View>(_ title: String, systemImage: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
    }
}
