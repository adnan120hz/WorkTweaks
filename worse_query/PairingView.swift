import SwiftUI
import UniformTypeIdentifiers
import Darwin

// MARK: - Get Pairing File + VPN Status (v6.1)
//
// Lives in Sandbox → Utilities, below Cache Data Cleaner.
// The pairing file + Local Dev VPN tunnel are the transport
// the iOS 26 partial restore (SpringBoard / Status Bar) needs
// to reach the device's backup service.
//
// Status is a dot: green = ready, gray = not ready.
//   Get Pairing File — green when a pairing file is saved in
//     the app (imported from SideStore / LiveContainer / iLoader
//     / AltStore / Jitterbug / a computer). Gray when none.
//   VPN Tunnel — green when the Local Dev VPN tunnel is up
//     (a utun interface on 10.7.x.x). Gray when not connected.
//
// The photo backup/restore does NOT need either of these —
// it is local only.

/// Where the pairing file lives (Documents, both canonical
/// copies, matching the aircard convention).
enum PairingStore {
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    static var primaryURL: URL {
        documentsURL.appendingPathComponent("aircard_pairing.plist")
    }

    static var secondaryURL: URL {
        documentsURL.appendingPathComponent("airlift_pairing.plist")
    }

    /// True when a pairing file is saved in the app.
    static var hasPairingFile: Bool {
        FileManager.default.fileExists(atPath: primaryURL.path)
            || FileManager.default.fileExists(atPath: secondaryURL.path)
    }

    /// The saved pairing file's name, if any.
    static var savedFileName: String? {
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            return primaryURL.lastPathComponent
        }
        if FileManager.default.fileExists(atPath: secondaryURL.path) {
            return secondaryURL.lastPathComponent
        }
        return nil
    }

    /// Saves an imported pairing file as both canonical copies.
    /// Returns true on success.
    static func savePairingFile(from url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            try data.write(to: primaryURL, options: .atomic)
            try data.write(to: secondaryURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Removes the saved pairing file(s).
    static func removePairingFile() {
        try? FileManager.default.removeItem(at: primaryURL)
        try? FileManager.default.removeItem(at: secondaryURL)
    }
}

/// Local Dev VPN tunnel detection via the network interfaces.
/// The tunnel is a utun interface on 10.7.x.x (gateway 10.7.0.1).
enum VPNTunnelStatus {
    /// The utun interface addresses (e.g. 10.7.0.x), if any.
    static var tunnelAddresses: [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & Int32(IFF_UP)) != 0
            let name = String(cString: current.pointee.ifa_name)
            if isUp, name.hasPrefix("utun"), let addr = current.pointee.ifa_addr {
                if addr.pointee.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if ip.hasPrefix("10.7.") { addresses.append(ip) }
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return addresses
    }

    /// True when the Local Dev VPN tunnel is up.
    static var isTunnelUp: Bool { !tunnelAddresses.isEmpty }
}

// MARK: - The page

struct PairingView: View {
    @State private var showImporter = false
    @State private var statusMessage: String?
    @State private var hasPairing = PairingStore.hasPairingFile
    @State private var tunnelUp = VPNTunnelStatus.isTunnelUp
    @State private var tunnelAddresses: [String] = VPNTunnelStatus.tunnelAddresses

    var body: some View {
        WTGlassPage {
            introCard
            pairingCard
            vpnCard
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            }
            Color.clear.frame(height: 60)
        }
        .navigationTitle("Get Pairing File + VPN Status")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.propertyList, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if PairingStore.savePairingFile(from: url) {
                    statusMessage = "Pairing file saved to the app."
                } else {
                    statusMessage = "Could not save that pairing file."
                }
                refresh()
            case .failure:
                statusMessage = "Pairing file import cancelled."
            }
        }
    }

    private func refresh() {
        hasPairing = PairingStore.hasPairingFile
        tunnelUp = VPNTunnelStatus.isTunnelUp
        tunnelAddresses = VPNTunnelStatus.tunnelAddresses
    }

    // MARK: Intro

    private var introCard: some View {
        WTSectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Get Pairing File + VPN Status")
                    .font(.headline)
                Text("The pairing file + Local Dev VPN tunnel are the transport the iOS 26 partial restore (SpringBoard / Status Bar) uses to reach the device. Green = ready, gray = not ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Get Pairing File

    private var pairingCard: some View {
        WTSectionCard(header: "Get Pairing File") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    statusDot(isReady: hasPairing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pairing file")
                            .font(.subheadline.weight(.semibold))
                        Text(hasPairing
                             ? "Saved: \(PairingStore.savedFileName ?? "pairing file")"
                             : "No pairing file saved yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Import Pairing File") {
                    SoundEffects.playTap()
                    showImporter = true
                }
                .buttonStyle(.borderedProminent)
                if hasPairing {
                    Button("Remove Pairing File", role: .destructive) {
                        SoundEffects.playTap()
                        PairingStore.removePairingFile()
                        statusMessage = "Pairing file removed."
                        refresh()
                    }
                    .buttonStyle(.bordered)
                }
                Text("Import a .mobiledevicepairing / .plist pairing file from SideStore, LiveContainer, iLoader, AltStore, Jitterbug, or a computer. It is saved in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: VPN Tunnel

    private var vpnCard: some View {
        WTSectionCard(header: "VPN Tunnel") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    statusDot(isReady: tunnelUp)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local Dev VPN")
                            .font(.subheadline.weight(.semibold))
                        Text(tunnelUp
                             ? "Connected\(tunnelAddresses.isEmpty ? "" : ": \(tunnelAddresses.joined(separator: ", "))")"
                             : "Not connected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Refresh Status") {
                    SoundEffects.playTap()
                    refresh()
                }
                .buttonStyle(.bordered)
                Text("Open the Local Dev VPN app and connect. The tunnel shows as a utun interface on 10.7.x.x (gateway 10.7.0.1).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    /// Green dot = ready, gray dot = not ready.
    private func statusDot(isReady: Bool) -> some View {
        Circle()
            .fill(isReady ? Color.green : Color.gray.opacity(0.5))
            .frame(width: 12, height: 12)
    }
}
