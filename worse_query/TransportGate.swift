import SwiftUI

/// The pairing + VPN transport the Airlift features need. Both
/// must be ready or the menu is blocked: a pairing file
/// (Sandbox → Utilities → Get Pairing File) AND the Local Dev VPN
/// tunnel up (utun 10.7.x.x).
enum TransportGate {
    struct Status {
        let hasPairing: Bool
        let vpnUp: Bool
        var isReady: Bool { hasPairing && vpnUp }
    }

    static func check() -> Status {
        Status(hasPairing: PairingStore.hasPairingFile, vpnUp: VPNTunnelStatus.isTunnelUp)
    }
}

/// A blocking card shown at the top of a gated menu while the
/// transport is not ready. Lists exactly what is missing and where
/// to fix it. The menu's Apply / flash actions stay disabled until
/// `status.isReady` is true.
struct TransportGateCard: View {
    let status: TransportGate.Status
    let onRefresh: () -> Void

    var body: some View {
        WTSectionCard(header: "Blocked — transport not ready") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.red)
                    Text("This menu needs the pairing file and the VPN tunnel before it can run.")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    gateRow(ready: status.hasPairing, label: "Pairing file", detail: status.hasPairing ? "Saved" : "Not found — pair this iPhone first")
                    gateRow(ready: status.vpnUp, label: "VPN tunnel", detail: status.vpnUp ? "Connected" : "Not on — open the Local Dev VPN app and connect")
                }
                Text("Go to Sandbox → Utilities → Get Pairing File + VPN Status to fix both, then come back and tap Refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    SoundEffects.playTap()
                    onRefresh()
                } label: {
                    Text("Refresh Status")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func gateRow(ready: Bool, label: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ready ? .green : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
