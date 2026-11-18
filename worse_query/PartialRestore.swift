import Foundation
import CryptoKit

// MARK: - Partial Restore engine (v6.1, iOS 26 path)
//
// Applies the SpringBoard / Status Bar tweaks by the iOS 26
// partial restore: a synthetic backup is built from nothing
// (legacy MBDB manifest + the tweak payloads as flat files),
// then restored with the backup service. No protective backup
// is pulled — that is the iOS 26 path.
//
// This engine builds the payloads and the synthetic backup.
// The restore itself talks to the device's backup service over
// the pairing-file + LocalDevVPN connection (the transport the
// app sets up in the Pairing flow); without a live connection
// the backup is prepared and saved for inspection instead of
// being silently pretended to have applied.

final class PartialRestoreEngine {
    static let shared = PartialRestoreEngine()
    private init() {}

    /// The risk note shown before any apply. In English, as ordered.
    static let riskText = """
    Use at your own risk. Not all iPhones can be unlocked this way. Do not use on an MDM-managed device or a bypassed device.

    A partial restore can affect your photos and videos, and can log you out of iCloud. Back up your photos and videos first (Backup Your Photos & Videos Here!) — optional, you can skip it.
    """

    // MARK: - Apply entry points

    /// Apply the Status Bar overrides.
    func applyStatusBar(
        overrides: StatusBarOverrides,
        suppressedIdentifiers: Set<String>,
        console: Console
    ) async -> String {
        do {
            let archive = try StatusBarArchiveBuilder.build(overrides)
            let payloads = [RestorePayload(
                domain: StatusBarArchiveBuilder.domain,
                relativePath: StatusBarArchiveBuilder.relativePath,
                contents: archive
            )]
            return await runRestore(payloads: payloads, label: "Status Bar", console: console)
        } catch {
            return "Status Bar apply failed: \(error.localizedDescription)"
        }
    }

    /// Apply the SpringBoard options.
    func applySpringBoard(
        showBatteryPercentage: Bool,
        suppressDynamicIsland: Bool,
        console: Console
    ) async -> String {
        var payloads: [RestorePayload] = []
        if showBatteryPercentage {
            payloads.append(RestorePayload(
                domain: SpringBoardOverrides.springboardDomain,
                relativePath: SpringBoardOverrides.springboardPlistPath,
                contents: SpringBoardOverrides.batteryPercentagePlist(show: true)
            ))
        }
        if suppressDynamicIsland {
            payloads.append(RestorePayload(
                domain: SpringBoardOverrides.managedDomain,
                relativePath: SpringBoardOverrides.managedSpringboardPath,
                contents: SpringBoardOverrides.suppressDynamicIslandPlist(suppress: true)
            ))
        }
        return await runRestore(payloads: payloads, label: "SpringBoard", console: console)
    }

    // MARK: - Restore

    private func runRestore(payloads: [RestorePayload], label: String, console: Console) async -> String {
        guard !payloads.isEmpty else {
            return "Nothing to apply — turn on at least one option first."
        }
        // iOS 26 path only: this build targets iOS 27, and the
        // iOS 26 branch is forced (no protective backup).
        guard isIOS27OrNewer else {
            return "Partial restore needs iOS 27. This device is not on iOS 27."
        }
        let backupRoot = prepareBackup(payloads: payloads)
        console.output += "\n(partial-restore) \(label): backup prepared at \(backupRoot.path)\n"
        // The restore transport (pairing file + LocalDevVPN tunnel
        // to the device's backup service) is not connected in this
        // build. The backup is prepared and saved; the restore
        // step runs once the transport is set up.
        return """
        \(label) backup prepared (\(payloads.count) file(s)) and saved to the app's Documents/PartialRestore folder.

        The restore step needs the device connection (pairing file + LocalDevVPN). Set those up in the Pairing flow, then Apply again to restore this backup.
        """
    }

    private var isIOS27OrNewer: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    // MARK: - Synthetic iOS 26 backup (MBDB)

    /// The folder the prepared backup is saved to.
    static var preparedBackupRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("PartialRestore", isDirectory: true)
    }

    /// Builds the synthetic iOS 26 backup: an empty root, the
    /// minimal Info/Status/Manifest plists, the MBDB manifest with
    /// one row per payload, and the payloads flat in the root
    /// named by fileID. Returns the backup root.
    private func prepareBackup(payloads: [RestorePayload]) -> URL {
        let root = Self.preparedBackupRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Clear any previous prepared backup.
        if let existing = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in existing { try? FileManager.default.removeItem(at: url) }
        }
        var rows: [MBDBRow] = []
        for payload in payloads {
            let fileID = MBDBManifest.fileID(domain: payload.domain, relativePath: payload.relativePath)
            let fileURL = root.appendingPathComponent(fileID)
            try? payload.contents.write(to: fileURL)
            rows.append(MBDBRow(
                domain: payload.domain,
                relativePath: payload.relativePath,
                fileID: fileID,
                size: UInt64(payload.contents.count),
                hash: Insecure.SHA1.hash(data: payload.contents)
            ))
        }
        // Minimal host manifests (a restore refuses a backup without them).
        writeHostManifests(to: root)
        // MBDB manifest (legacy binary, iOS 26 path).
        let mbdb = MBDBManifest.encode(rows: rows)
        try? mbdb.write(to: root.appendingPathComponent("Manifest.mbdb"))
        // Explicitly no Manifest.db in this branch.
        try? FileManager.default.removeItem(at: root.appendingPathComponent("Manifest.db"))
        return root
    }

    private func writeHostManifests(to root: URL) {
        let info: [String: Any] = [
            "Target Identifier": "WorkTweaks-PartialRestore",
            "Product Type": "iPhone",
            "Product Version": "27.0",
            "Serial Number": "WorkTweaks",
            "Unique Identifier": "WorkTweaks-PartialRestore",
            "Is Encrypted": false,
        ]
        let status: [String: Any] = ["Is Full Backup": false, "Version": "10.0"]
        let manifest: [String: Any] = ["Is Encrypted": false, "Version": "10.0"]
        for (name, dict) in [("Info.plist", info), ("Status.plist", status), ("Manifest.plist", manifest)] {
            if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
                try? data.write(to: root.appendingPathComponent(name))
            }
        }
    }
}

/// One file to inject into the backup.
struct RestorePayload {
    let domain: String
    /// Relative path inside the domain (leading slash stripped for the manifest).
    let relativePath: String
    let contents: Data

    var manifestPath: String {
        relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }
}

// MARK: - MBDB manifest (legacy binary, iOS 26 path)

/// One row in `Manifest.mbdb`.
private struct MBDBRow {
    let domain: String
    let relativePath: String
    let fileID: String
    let size: UInt64
    let hash: Data
}

private enum MBDBManifest {
    /// fileID = sha1("<domain>-<relativePath>"), hex lowercase.
    static func fileID(domain: String, relativePath: String) -> String {
        let path = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        let input = "\(domain)-\(path)"
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Encodes the MBDB file: header `mbdb` + 0x05 0x00, then one
    /// row per file (domain, path, link, hash, key, mode, inode,
    /// owner/group, mtimes, size, flags, properties).
    static func encode(rows: [MBDBRow]) -> Data {
        var data = Data()
        data.append(contentsOf: [0x6d, 0x62, 0x64, 0x62, 0x05, 0x00]) // "mbdb" + version
        for row in rows {
            appendString(row.domain, to: &data)
            appendString(row.manifestPath, to: &data)
            appendString("", to: &data) // link
            appendData(row.hash, to: &data) // sha1
            appendData(Data(count: 16), to: &data) // key (empty)
            appendUInt32(0o100644, to: &data) // mode: regular file 0644
            appendUInt64(0, to: &data) // inode
            appendUInt32(501, to: &data) // uid (mobile)
            appendUInt32(501, to: &data) // gid (mobile)
            appendUInt32(UInt32(Date().timeIntervalSince1970), to: &data) // mtime
            appendUInt32(UInt32(Date().timeIntervalSince1970), to: &data) // atime
            appendUInt32(UInt32(Date().timeIntervalSince1970), to: &data) // ctime
            appendUInt64(row.size, to: &data) // size
            data.append(4) // flags
            data.append(0) // properties count
        }
        return data
    }

    private static func appendString(_ s: String, to data: inout Data) {
        let bytes = Data(s.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(bytes)
    }

    private static func appendData(_ d: Data, to data: inout Data) {
        appendUInt16(UInt16(d.count), to: &data)
        data.append(d)
    }

    private static func appendUInt16(_ v: UInt16, to data: inout Data) {
        var be = v.bigEndian
        data.append(Data(bytes: &be, count: 2))
    }

    private static func appendUInt32(_ v: UInt32, to data: inout Data) {
        var be = v.bigEndian
        data.append(Data(bytes: &be, count: 4))
    }

    private static func appendUInt64(_ v: UInt64, to data: inout Data) {
        var be = v.bigEndian
        data.append(Data(bytes: &be, count: 8))
    }
}

private extension MBDBRow {
    var manifestPath: String {
        relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }
}
