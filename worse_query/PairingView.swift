import SwiftUI
import UniformTypeIdentifiers
import Darwin

// MARK: - Get Pairing File + VPN Status (v6.1)
//
// Lives in Sandbox → Utilities, below Cache Data Cleaner.
// The pairing file + Local Dev VPN tunnel are the transport
// Airlift needs to reach the device.
//
// Status is a dot: green = ready, gray = not ready.
//   Get Pairing File — green when a pairing file is saved in
//     the app. Two ways to get one: on-device (iOS 27) via
//     Pair This iPhone, which shows a 6-digit PIN approved in
//     Settings › Privacy & Security › Developer Mode › Pair
//     with WorkTweaks; or Import Pairing File, a manual .plist
//     import from the computer. Gray when none.
//   VPN Tunnel — green when the Local Dev VPN tunnel is up
//     (a utun interface on 10.7.x.x). Gray when not connected.
//
// The photo backup/restore does NOT need either of these —
// it is local only.

/// Where the pairing file lives (Documents, both canonical copies).
/// The canonical name is worktweaks_pairing.plist; the old
/// aircard_pairing.plist is still recognised once and migrated to the
/// new name so an existing pairing is never lost by the rename.
enum PairingStore {
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    static var primaryURL: URL {
        documentsURL.appendingPathComponent("worktweaks_pairing.plist")
    }

    static var secondaryURL: URL {
        documentsURL.appendingPathComponent("airlift_pairing.plist")
    }

    static var legacyURL: URL {
        documentsURL.appendingPathComponent("aircard_pairing.plist")
    }

    /// Moves a legacy aircard_pairing.plist to the WorkTweaks name once.
    static func migrateLegacyPairingFile() {
        guard !FileManager.default.fileExists(atPath: primaryURL.path),
              FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        if let data = try? Data(contentsOf: legacyURL), !data.isEmpty {
            try? data.write(to: primaryURL, options: .atomic)
            try? data.write(to: secondaryURL, options: .atomic)
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    /// True when a pairing file is saved in the app.
    static var hasPairingFile: Bool {
        migrateLegacyPairingFile()
        return FileManager.default.fileExists(atPath: primaryURL.path)
            || FileManager.default.fileExists(atPath: secondaryURL.path)
    }

    /// The saved pairing file's name, if any.
    static var savedFileName: String? {
        migrateLegacyPairingFile()
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
        try? FileManager.default.removeItem(at: legacyURL)
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
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var pairing = PairingController.shared
    @State private var statusMessage: String?
    @State private var showPairingImporter = false
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
        .navigationTitle(wtLang.tr("Get Pairing File + VPN Status"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .fileImporter(
            isPresented: $showPairingImporter,
            allowedContentTypes: [.propertyList],
            allowsMultipleSelection: false
        ) { result in
            importPairingFile(result: result)
        }
    }

    /// Starts the on-device pairing (iOS 27): shows a 6-digit PIN
    /// to approve in Settings › Developer Mode › Pair with WorkTweaks.
    private func startPairing() {
        SoundEffects.playTap()
        statusMessage = nil
        Task {
            do {
                _ = try await pairing.startAndWait()
                statusMessage = wtLang.tr("Pairing file saved to the app.")
            } catch is CancellationError {
                statusMessage = wtLang.tr("Pairing cancelled.")
            } catch {
                statusMessage = error.localizedDescription
            }
            refresh()
        }
    }

    private func refresh() {
        hasPairing = PairingStore.hasPairingFile
        tunnelUp = VPNTunnelStatus.isTunnelUp
        tunnelAddresses = VPNTunnelStatus.tunnelAddresses
    }

    /// Imports a pairing file (.plist) picked by the user:
    /// validates that it parses as a plist dictionary, then
    /// saves it via PairingStore (both canonical copies).
    private func importPairingFile(result: Result<[URL], Error>) {
        SoundEffects.playTap()
        statusMessage = nil
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                statusMessage = error.localizedDescription
            }
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            statusMessage = wtLang.tr("Could not access that file.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            statusMessage = wtLang.tr("Could not read that file.")
            return
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard plist is [String: Any] else {
            statusMessage = wtLang.tr("That file is not a pairing file.")
            return
        }
        if PairingStore.savePairingFile(from: url) {
            statusMessage = wtLang.tr("Pairing file imported.")
        } else {
            statusMessage = wtLang.tr("Could not save that pairing file.")
        }
        refresh()
    }

    // MARK: Intro

    private var introCard: some View {
        WTSectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(wtLang.tr("Get Pairing File + VPN Status"))
                    .font(.headline)
                Text(wtLang.tr("The pairing file + Local Dev VPN tunnel are the transport Airlift uses to reach the device. Green = ready, gray = not ready."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Get Pairing File (on-device, iOS 27)

    private var pairingCard: some View {
        WTSectionCard(header: wtLang.tr("Get Pairing File")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    statusDot(isReady: hasPairing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wtLang.tr("Pairing file"))
                            .font(.subheadline.weight(.semibold))
                        Text(hasPairing
                             ? wtLang.tr("Saved: %@", PairingStore.savedFileName ?? "pairing file")
                             : wtLang.tr("No pairing file saved yet."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if pairing.running {
                    Text(pairing.pairingStatus)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pin = pairing.pairingPIN {
                        Text(pin)
                            .font(.system(.largeTitle, design: .monospaced).bold())
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 4)
                        Text(wtLang.tr("Enter this PIN in Settings › Privacy & Security › Developer Mode › Pair with WorkTweaks."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(wtLang.tr("Cancel Pairing")) {
                        SoundEffects.playTap()
                        pairing.softCancel()
                        refresh()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(wtLang.tr("Pair This iPhone")) {
                        startPairing()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pairing.running)
                    Button(wtLang.tr("Import Pairing File")) {
                        SoundEffects.playTap()
                        showPairingImporter = true
                    }
                    .buttonStyle(.bordered)
                    if hasPairing {
                        Button(wtLang.tr("Remove Pairing File"), role: .destructive) {
                            SoundEffects.playTap()
                            PairingStore.removePairingFile()
                            PairingController.deleteStoredPairingCredentials()
                            statusMessage = wtLang.tr("Pairing file removed.")
                            refresh()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Text(wtLang.tr("Two ways to get a pairing file: Pair This iPhone (iOS 27 only) shows a 6-digit PIN — approve it in Settings › Privacy & Security › Developer Mode › Pair with WorkTweaks. Or import a pairing file (.plist) from your computer manually. The pairing file is saved in the app."))
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
        WTSectionCard(header: wtLang.tr("VPN Tunnel")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    statusDot(isReady: tunnelUp)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wtLang.tr("Local Dev VPN"))
                            .font(.subheadline.weight(.semibold))
                        Text(tunnelUp
                             ? wtLang.tr("Connected%@", tunnelAddresses.isEmpty ? "" : ": \(tunnelAddresses.joined(separator: ", "))")
                             : wtLang.tr("Not connected."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(wtLang.tr("Refresh Status")) {
                    SoundEffects.playTap()
                    refresh()
                }
                .buttonStyle(.bordered)
                Text(wtLang.tr("Open the Local Dev VPN app and connect. The tunnel shows as a utun interface on 10.7.x.x (gateway 10.7.0.1)."))
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
