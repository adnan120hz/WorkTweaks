import Combine
import Foundation
import Compression

// MARK: - Install IPA on Container (Phase 1 host skeleton)
//
// Guest apps ("containers") live in the WorkTweaks App Group,
// mirroring LiveContainer's layout
// (LiveContainerSwiftUI/Utilities/Shared.swift: LCPath):
//   <group>/LiveContainer/Applications/<bundle-id>.app  (guest bundle)
//   <group>/LiveContainer/Data/Application/<uuid>/      (guest data container)
//   <group>/LiveContainer/Tweaks/                      (TweakLoader symlink target)
// The only difference from stock LiveContainer is the group
// itself: LC resolves SideStore/AltStore groups first, WorkTweaks
// resolves its own group via AppGroupResolver.
//
// Phase 1 CAN: list guests, import an .ipa (unzip, validate,
// encryption check, store the bundle, write LCAppInfo.plist,
// create the data container skeleton).
// Phase 1 CANNOT: patch the executable (needs LCMachOUtils —
// blocked on the litehook submodule, see
// LiveContainerCore/README.LITEHOOK.md), sign the guest
// (Phase 2), or launch it (needs signing or a JIT session,
// Phases 2–3). Installs therefore land with
// LCPatchRevision = -1 ("not patched yet") and the UI says so
// plainly instead of pretending the guest is ready to run.

/// One installed guest app.
struct ContainerGuest: Identifiable {
    /// LC's current patch revision (LCAppInfo.m): a guest is
    /// patched when its stored revision reaches this.
    static let currentPatchRevision = 7

    let bundleID: String
    let displayName: String
    let version: String
    let executableName: String
    /// Folder name inside Applications/, "<bundle-id>.app".
    let folderName: String
    let bundlePath: String
    let dataUUID: String
    /// -1 = installed by Phase 1, never patched.
    let patchRevision: Int
    let installedAt: Date?

    var id: String { bundleID }
    var isPatched: Bool { patchRevision >= Self.currentPatchRevision }
}

enum ContainerError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

final class ContainerManager: ObservableObject {
    static let shared = ContainerManager()

    @Published private(set) var guests: [ContainerGuest] = []
    @Published private(set) var isBusy = false
    @Published private(set) var lastResult: String?

    private let fm = FileManager.default

    // MARK: Paths

    /// <group>/LiveContainer — nil when the App Group container
    /// does not resolve, in which case every operation refuses
    /// honestly instead of writing somewhere wrong.
    static func liveContainerRoot() -> URL? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupResolver.resolvedGroup) else {
            print("[Container] App Group container unavailable — no LiveContainer root.")
            return nil
        }
        return groupURL.appendingPathComponent("LiveContainer", isDirectory: true)
    }

    private func applicationsDir() -> URL? {
        ContainerManager.liveContainerRoot()?.appendingPathComponent("Applications", isDirectory: true)
    }

    private func dataDir() -> URL? {
        ContainerManager.liveContainerRoot()?.appendingPathComponent("Data/Application", isDirectory: true)
    }

    private func ensureRoots() throws -> (apps: URL, data: URL) {
        guard let root = ContainerManager.liveContainerRoot(),
              let apps = applicationsDir(), let data = dataDir() else {
            throw ContainerError.message("The App Group container could not be opened, so no guest can be stored.")
        }
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Tweaks", isDirectory: true), withIntermediateDirectories: true)
        return (apps, data)
    }

    // MARK: List

    /// Re-read the installed guests from disk.
    func refresh() {
        guard let apps = applicationsDir() else {
            guests = []
            return
        }
        var found: [ContainerGuest] = []
        for folder in (try? fm.contentsOfDirectory(atPath: apps.path)) ?? [] {
            guard folder.hasSuffix(".app") else { continue }
            let bundlePath = apps.appendingPathComponent(folder).path
            guard let plist = NSDictionary(contentsOfFile: (bundlePath as NSString).appendingPathComponent("Info.plist")) as? [String: Any],
                  let bundleID = plist["CFBundleIdentifier"] as? String,
                  let executable = plist["CFBundleExecutable"] as? String else {
                print("[Container] skipping \(folder) — no readable Info.plist.")
                continue
            }
            let info = NSDictionary(contentsOfFile: (bundlePath as NSString).appendingPathComponent("LCAppInfo.plist")) as? [String: Any]
            let displayName = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? executable
            found.append(ContainerGuest(
                bundleID: bundleID,
                displayName: displayName,
                version: (plist["CFBundleShortVersionString"] as? String) ?? "—",
                executableName: executable,
                folderName: folder,
                bundlePath: bundlePath,
                dataUUID: (info?["LCDataUUID"] as? String) ?? "",
                patchRevision: (info?["LCPatchRevision"] as? Int) ?? -1,
                installedAt: info?["installationDate"] as? Date
            ))
        }
        guests = found.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        print("[Container] listed \(guests.count) guest(s).")
    }

    // MARK: Install

    /// Install one .ipa: unzip, validate, encryption check,
    /// store the bundle, write LCAppInfo.plist, create the data
    /// container. Runs on the calling task; the view wraps it in
    /// a Task and shows isBusy. Throws ContainerError with a
    /// user-facing message on every failure; nothing is left
    /// half-installed (the staging folder and any partial
    /// destination are removed again).
    func installIPA(from url: URL) async throws -> ContainerGuest {
        await MainActor.run { isBusy = true; lastResult = nil }
        defer { Task { @MainActor in self.isBusy = false } }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ContainerError.message("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
        }
        print("[Container] installing \(url.lastPathComponent) (\(data.count) bytes).")

        let staging = fm.temporaryDirectory.appendingPathComponent("container-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        // Set once the bundle has been moved: any later failure
        // removes it again, so a failed install never leaves a
        // broken guest behind.
        var installedDestination: URL?
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try ContainerZip.extract(data: data, to: staging)

            // Payload/*.app — the first .app in Payload, like LC.
            let payload = staging.appendingPathComponent("Payload", isDirectory: true)
            let payloadContents = try fm.contentsOfDirectory(atPath: payload.path)
            guard let appFolderName = payloadContents.first(where: { $0.hasSuffix(".app") }) else {
                throw ContainerError.message("No .app bundle found in the IPA (Payload/*.app is missing).")
            }
            let stagedApp = payload.appendingPathComponent(appFolderName)

            guard let plist = NSDictionary(contentsOfFile: stagedApp.appendingPathComponent("Info.plist").path) as? [String: Any],
                  let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty,
                  let executable = plist["CFBundleExecutable"] as? String, !executable.isEmpty else {
                throw ContainerError.message("The .app bundle has no readable Info.plist (CFBundleIdentifier / CFBundleExecutable missing).")
            }
            let displayName = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? executable
            let version = (plist["CFBundleShortVersionString"] as? String) ?? "—"

            // Encryption check on the executable (LCAppInfo.m:
            // encrypted guests are rejected with exactly this
            // message). A missing arm64 slice is also refused:
            // 32-bit guests need JIT + classic mode (Phase 3).
            let executableURL = stagedApp.appendingPathComponent(executable)
            let machO: ContainerMachO.SliceInfo
            do {
                machO = try ContainerMachO.inspect(executableURL: executableURL)
            } catch {
                throw ContainerError.message("Could not read the app executable: \(error.localizedDescription)")
            }
            guard machO.hasARM64 else {
                throw ContainerError.message("This app has no arm64 slice (32-bit only). 32-bit guests need JIT + classic mode, which lands in Phase 3.")
            }
            if machO.isEncrypted {
                throw ContainerError.message("The app you tried to install is encrypted. Please provide a decrypted app.")
            }

            let (appsDir, dataRoot) = try ensureRoots()
            let folderName = ContainerManager.sanitizedFolderName(bundleID: bundleID)
            let destination = appsDir.appendingPathComponent(folderName)
            guard !fm.fileExists(atPath: destination.path) else {
                throw ContainerError.message("Already installed — \(bundleID) is already in Containers. Delete it first to reinstall.")
            }

            try fm.moveItem(at: stagedApp, to: destination)
            installedDestination = destination

            // LCAppInfo.plist — the metadata invokeAppMain reads.
            // LCPatchRevision -1 means "installed, never patched":
            // patching lands once the LC core links (Phase 2).
            let dataUUID = UUID().uuidString
            let lcInfo: [String: Any] = [
                "LCPatchRevision": -1,
                "LCDataUUID": dataUUID,
                "LCOrignalBundleIdentifier": bundleID,
                "installationDate": Date(),
            ]
            let lcInfoData = try PropertyListSerialization.data(fromPropertyList: lcInfo, format: .xml, options: 0)
            try lcInfoData.write(to: destination.appendingPathComponent("LCAppInfo.plist"))

            // Data container skeleton (LC creates the container
            // lazily on first run; the skeleton is created here so
            // the guest's LCDataUUID already points somewhere).
            let containerDir = dataRoot.appendingPathComponent(dataUUID, isDirectory: true)
            for sub in ["Documents", "Library", "Library/Caches", "Library/Preferences", "tmp"] {
                try fm.createDirectory(at: containerDir.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
            }

            let guest = ContainerGuest(
                bundleID: bundleID,
                displayName: displayName,
                version: version,
                executableName: executable,
                folderName: folderName,
                bundlePath: destination.path,
                dataUUID: dataUUID,
                patchRevision: -1,
                installedAt: Date()
            )
            print("[Container] installed \(bundleID) (\(displayName) \(version)) — stored, NOT patched yet (patching lands in Phase 2).")
            await MainActor.run {
                self.lastResult = "Install complete — the guest is stored but not patched yet."
                self.refresh()
            }
            return guest
        } catch let error as ContainerError {
            if let installedDestination {
                try? fm.removeItem(at: installedDestination)
            }
            print("[Container] install failed: \(error.localizedDescription)")
            throw error
        } catch {
            if let installedDestination {
                try? fm.removeItem(at: installedDestination)
            }
            print("[Container] install failed: \(error.localizedDescription)")
            throw ContainerError.message("Installing \(url.lastPathComponent) failed: \(error.localizedDescription)")
        }
    }

    /// Folder name for a guest: "<bundle-id>.app", sanitized to
    /// ASCII letters, digits, "." and "-" (LC sanitizes
    /// non-ASCII the same way).
    static func sanitizedFolderName(bundleID: String) -> String {
        let kept = bundleID.unicodeScalars.filter {
            $0.isASCII && ($0.properties.isAlphanumeric || $0 == "." || $0 == "-")
        }
        let base = String(String.UnicodeScalarView(kept))
        return (base.isEmpty ? "unknown" : base) + ".app"
    }

    // MARK: Delete

    /// Delete a guest: its bundle folder and its data container
    /// go together, like LC's delete (the receipts for Deploy
    /// are unrelated — guests are not Deploy packages).
    func delete(_ guest: ContainerGuest) {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: guest.bundlePath) {
                try fm.removeItem(atPath: guest.bundlePath)
            }
            if !guest.dataUUID.isEmpty,
               let dataRoot = dataDir() {
                let containerDir = dataRoot.appendingPathComponent(guest.dataUUID)
                if fm.fileExists(atPath: containerDir.path) {
                    try fm.removeItem(at: containerDir)
                }
            }
            print("[Container] deleted \(guest.bundleID).")
            refresh()
        } catch {
            // Failure is Log-only: the message is composed with
            // the guest name, so it has no translation key.
            print("[Container] deleting \(guest.bundleID) failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Launch-path decision (Phase 1 stub)
//
// LC relaunches the host with a guest selected: it stores the
// guest's bundle id under the "selected" key in the standard
// defaults and re-opens itself (LCSharedUtils
// launchToGuestAppWithURL). WorkTweaksApp calls this from
// init(): in Phase 1 the bootstrap itself is not linked yet
// (litehook pending), so a selected guest is logged honestly
// and the host UI opens normally. Phase 2 replaces the body
// with the real bootstrap call.
enum ContainerLaunch {
    static func checkSelectedGuest() {
        guard let selected = UserDefaults.standard.string(forKey: "selected"), !selected.isEmpty else { return }
        print("[Container] guest selected at launch: \(selected) — launch unavailable: LC core not linked yet (litehook pending, Phase 2). Staying in WorkTweaks.")
    }
}

// MARK: - Mach-O inspection (encryption + arm64 slice)
//
// LC's LCIsMachOEncrypted (LCMachOUtils.m) walks the load
// commands for LC_ENCRYPTION_INFO(_64) with cryptid != 0.
// Reimplemented here in Swift because the ObjC core is not
// linked yet — same rule, same outcome.

enum ContainerMachO {
    struct SliceInfo {
        let hasARM64: Bool
        let isEncrypted: Bool
    }

    private static let cpuTypeARM64: UInt32 = 0x0100_000C
    private static let mhMagic64: UInt32 = 0xFEED_FACF
    private static let fatMagic: UInt32 = 0xCAFE_BABE
    private static let fatMagicSwapped: UInt32 = 0xBEBA_FECA
    private static let lcEncryptionInfo: UInt32 = 0x21
    private static let lcEncryptionInfo64: UInt32 = 0x2C

    static func inspect(executableURL url: URL) throws -> SliceInfo {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ContainerError.message("The app executable could not be opened.")
        }
        defer { try? handle.close() }

        func read(at offset: UInt64, count: Int) throws -> Data {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw ContainerError.message("The app executable is truncated.")
            }
            return data
        }
        func u32LE(_ data: Data, _ offset: Int) -> UInt32 {
            UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
        }
        func u32BE(_ data: Data, _ offset: Int) -> UInt32 {
            (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16)
                | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
        }

        let magicData = try read(at: 0, count: 4)
        let magicBE = u32BE(magicData, 0)

        // Fat binary: walk the arch entries, inspect arm64 slices.
        if magicBE == fatMagic || magicBE == fatMagicSwapped {
            let header = try read(at: 0, count: 8)
            let narch = Int(u32BE(header, 4))
            var hasARM64 = false
            var encrypted = false
            for i in 0..<narch {
                let entry = try read(at: 8 + UInt64(i * 20), count: 20)
                let cputype = u32BE(entry, 0)
                guard cputype == cpuTypeARM64 else { continue }
                let sliceOffset = UInt64(u32BE(entry, 8))
                let slice = try inspectSlice(at: sliceOffset, read: read, u32LE: u32LE)
                hasARM64 = true
                encrypted = encrypted || slice
            }
            return SliceInfo(hasARM64: hasARM64, isEncrypted: encrypted)
        }

        // Thin 64-bit Mach-O.
        let magicLE = u32LE(magicData, 0)
        guard magicLE == mhMagic64 else {
            throw ContainerError.message("The app executable is not a 64-bit Mach-O binary.")
        }
        let encrypted = try inspectSlice(at: 0, read: read, u32LE: u32LE)
        return SliceInfo(hasARM64: true, isEncrypted: encrypted)
    }

    private static func inspectSlice(
        at base: UInt64,
        read: (UInt64, Int) throws -> Data,
        u32LE: (Data, Int) -> UInt32
    ) throws -> Bool {
        let header = try read(base, 32)
        let ncmds = Int(u32LE(header, 16))
        let sizeofcmds = Int(u32LE(header, 20))
        guard sizeofcmds >= 0 else { return false }
        let commands = try read(base + 32, sizeofcmds)
        var offset = 0
        for _ in 0..<ncmds {
            guard offset + 8 <= commands.count else { break }
            let cmd = u32LE(commands, offset)
            let cmdsize = Int(u32LE(commands, offset + 4))
            guard cmdsize >= 8, offset + cmdsize <= commands.count else { break }
            if cmd == lcEncryptionInfo || cmd == lcEncryptionInfo64 {
                // struct encryption_info_command: cmd, cmdsize,
                // cryptoff, cryptsize, cryptid — cryptid at +16.
                guard offset + 20 <= commands.count else { break }
                if u32LE(commands, offset + 16) != 0 { return true }
            }
            offset += cmdsize
        }
        return false
    }
}

// MARK: - ZIP extraction (with symlink support)
//
// Same central-directory parser shape as
// DeployManager.zipEntries (stored/deflate only, no ZIP64, no
// encrypted entries, 256 MB per-entry cap) — but it writes to
// disk instead of returning Data, and it recreates symlinks:
// an entry whose external attributes carry Unix mode 0120000
// is a symlink whose content is the link target. Deploy's
// reader drops that bit, and .app bundles rely on symlinks
// (Frameworks, Versions/Current), so installing through it
// would silently produce a broken bundle.

enum ContainerZip {
    static func extract(data: Data, to destination: URL) throws {
        // Index the Data directly — copying a whole IPA into a
        // [UInt8] would double its memory footprint.
        let bytes = data
        func u16(_ offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
                | (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24)
        }
        guard bytes.count >= 22 else {
            throw ContainerError.message("The file is too small to be a ZIP archive.")
        }
        var eocd = -1
        var i = bytes.count - 22
        let windowStart = max(0, bytes.count - 65_558)
        while i >= windowStart {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else {
            throw ContainerError.message("No ZIP end-of-central-directory record was found — this is not a ZIP archive.")
        }
        let entryCount = u16(eocd + 10)
        let cdSize = u32(eocd + 12)
        let cdOffset = u32(eocd + 16)
        if entryCount == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            throw ContainerError.message("ZIP64 archives are not supported.")
        }

        let fm = FileManager.default
        var p = cdOffset
        for _ in 0..<entryCount {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else {
                throw ContainerError.message("The archive's central directory is damaged.")
            }
            let flags = u16(p + 8)
            let method = u16(p + 10)
            let compSize = u32(p + 20)
            let uncompSize = u32(p + 24)
            let nameLength = u16(p + 28)
            let extraLength = u16(p + 30)
            let commentLength = u16(p + 32)
            let externalAttrs = u32(p + 38)
            let localOffset = u32(p + 42)
            guard p + 46 + nameLength <= bytes.count else {
                throw ContainerError.message("The archive's central directory is damaged.")
            }
            let name = String(data: bytes.subdata(in: (p + 46)..<(p + 46 + nameLength)), encoding: .utf8) ?? ""
            p += 46 + nameLength + extraLength + commentLength

            // Path safety: no absolute paths, no ".." components.
            let components = name.split(separator: "/").map(String.init)
            guard !name.hasPrefix("/"), !components.contains("..") else {
                throw ContainerError.message("The archive contains an unsafe path (\(name)) — rejected whole, nothing was installed.")
            }
            if components.isEmpty || name.hasSuffix("/") {
                if !components.isEmpty {
                    let dir = components.reduce(destination) { $0.appendingPathComponent($1) }
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                continue
            }
            if flags & 0x1 != 0 {
                throw ContainerError.message("Encrypted archives are not supported (entry \"\(name)\").")
            }
            if compSize == 0xFFFF_FFFF || uncompSize == 0xFFFF_FFFF {
                throw ContainerError.message("ZIP64 archives are not supported (entry \"\(name)\").")
            }
            guard uncompSize <= 268_435_456 else {
                throw ContainerError.message("The entry \"\(name)\" is too large (\(uncompSize) bytes).")
            }
            guard localOffset + 30 <= bytes.count, u32(localOffset) == 0x0403_4B50 else {
                throw ContainerError.message("The archive's local header for \"\(name)\" is damaged.")
            }
            let localNameLength = u16(localOffset + 26)
            let localExtraLength = u16(localOffset + 28)
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compSize <= bytes.count else {
                throw ContainerError.message("The archive's data for \"\(name)\" is truncated.")
            }
            let compressed = bytes.subdata(in: dataStart..<(dataStart + compSize))
            let content: Data
            switch method {
            case 0:
                guard compressed.count == uncompSize else {
                    throw ContainerError.message("The stored entry \"\(name)\" has a size mismatch.")
                }
                content = compressed
            case 8:
                guard let inflated = inflate(compressed, expectedSize: uncompSize) else {
                    throw ContainerError.message("The deflated entry \"\(name)\" could not be decompressed.")
                }
                content = inflated
            default:
                throw ContainerError.message("Unsupported compression method \(method) for \"\(name)\" — only stored and deflated entries are supported.")
            }

            let dest = components.reduce(destination) { $0.appendingPathComponent($1) }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let unixMode = externalAttrs >> 16
            if unixMode & 0o170000 == 0o120000 {
                // Symlink: the content is the link target.
                let target = String(data: content, encoding: .utf8) ?? ""
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: target)
            } else {
                try content.write(to: dest)
            }
        }
    }

    /// ZIP deflate is a raw deflate stream, which is what the
    /// Compression framework's COMPRESSION_ZLIB decoder reads
    /// (same as DeployManager.inflate).
    private static func inflate(_ compressed: Data, expectedSize: Int) -> Data? {
        if expectedSize == 0 { return Data() }
        guard !compressed.isEmpty else { return nil }
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { dst.deallocate() }
        let written = compressed.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return compression_decode_buffer(
                dst, expectedSize,
                base.assumingMemoryBound(to: UInt8.self), compressed.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written == expectedSize else { return nil }
        return Data(bytes: dst, count: written)
    }
}
