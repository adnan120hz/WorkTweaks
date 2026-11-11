import Foundation
import Combine
import Compression

// MARK: - Deploy (targeted file replacement packages)
//
// A Deploy package replaces files inside exactly ONE app,
// addressed the way the user's spec defines it:
//
//   - Bundle ID — which app may be touched (for AppGroup
//     scope, the App Group identifier instead).
//   - Scope — "Application", "AppGroup" or "InternalDaemon":
//     which container family the identifier is resolved in.
//   - Relative paths — where each payload file goes inside
//     the resolved container. Never absolute, never with a
//     ".." component, so a package cannot escape its target
//     container or touch another app.
//
// Resolution reuses the App Data machinery: the Application
// scope matches the pathleak scan's containers by their xattr
// bundle id; the AppGroup and InternalDaemon scopes enumerate
// their container roots with the fork's pathleak helper
// (wtPathleakChildren) and match by xattr identifier or
// directory name.
//
// Execution holds ONE grant on the resolved container. Every
// replaced file is first copied into the app's backup store
// (DeployBackups/<timestamp>-<bundleID>/ in our App Group
// container, mirroring relative paths) together with a
// receipt.json, so Deploy History can restore it. Existing
// files are written in place (truncate + write, the same
// lesson as every other writer in this app); new files are
// created directly. Every step logs with a [Deploy] prefix.

// MARK: Package model

struct DeployError: Error {
    let message: String
}

struct LoadedDeployFile {
    /// Canonical relative path inside the target container.
    let relativePath: String
    /// Where the payload lived inside the package.
    let source: String
    let data: Data
}

struct LoadedDeployPackage {
    let bundleID: String
    /// "Application" | "AppGroup" | "InternalDaemon"
    let scope: String
    let name: String?
    let files: [LoadedDeployFile]
}

// MARK: Receipts

struct DeployReceiptFile: Codable {
    var path: String
    var existedBefore: Bool
    var size: Int
    var status: String
}

struct DeployReceipt: Codable {
    var name: String?
    var bundleID: String
    var scope: String
    var containerPath: String
    var timestamp: String
    var files: [DeployReceiptFile]
}

struct DeployHistoryEntry: Identifiable {
    let folderName: String
    let folderURL: URL
    let receipt: DeployReceipt
    var id: String { folderName }
}

// MARK: Run results

struct DeployRunLine: Identifiable {
    let id = UUID()
    let path: String
    let ok: Bool
    let message: String
}

struct DeployRunResult {
    let lines: [DeployRunLine]
    let receiptFolderName: String?
    var succeeded: Int { lines.filter(\.ok).count }
    var failed: Int { lines.count - succeeded }
}

// MARK: - Manager

final class DeployManager: ObservableObject {
    static let scopes = ["Application", "AppGroup", "InternalDaemon"]

    @Published var isResolving = false
    @Published var resolvedContainerPath: String?
    @Published var resolveError: String?

    @Published var isDeploying = false
    @Published var lastResult: DeployRunResult?

    @Published var isRestoring = false
    @Published var restoreResult: DeployRunResult?

    // MARK: Package loading

    /// Load and fully validate a package picked by the user:
    /// a folder, or a `.zip` / `.deploy` archive. On any
    /// validation failure the whole package is rejected and
    /// nothing is ever written.
    static func loadPackage(from url: URL) -> Result<LoadedDeployPackage, DeployError> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failure(DeployError(message: "The picked item could not be found."))
        }

        let entries: [String: Data]
        if isDirectory.boolValue {
            switch readFolder(url) {
            case .failure(let error): return .failure(error)
            case .success(let dict): entries = dict
            }
        } else {
            guard let data = try? Data(contentsOf: url) else {
                return .failure(DeployError(message: "The picked file could not be read."))
            }
            switch zipEntries(from: data) {
            case .failure(let error): return .failure(error)
            case .success(let dict): entries = dict
            }
        }
        return buildPackage(entries: entries)
    }

    private static func readFolder(_ root: URL) -> Result<[String: Data], DeployError> {
        let base = root.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .failure(DeployError(message: "The picked folder could not be opened."))
        }
        var entries: [String: Data] = [:]
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let path = fileURL.standardizedFileURL.path
            guard path.hasPrefix(base.path + "/") else { continue }
            let relative = String(path.dropFirst(base.path.count + 1))
            guard let data = try? Data(contentsOf: fileURL) else {
                return .failure(DeployError(message: "A file in the folder could not be read: \(relative)"))
            }
            entries[normalizePackagePath(relative)] = data
        }
        return .success(entries)
    }

    private static func buildPackage(entries rawEntries: [String: Data]) -> Result<LoadedDeployPackage, DeployError> {
        // Drop archive noise (Finder metadata) before lookup.
        var entries: [String: Data] = [:]
        for (key, value) in rawEntries {
            if key.hasPrefix("__MACOSX/") { continue }
            if (key as NSString).lastPathComponent == ".DS_Store" { continue }
            entries[key] = value
        }

        guard let manifestData = entries["manifest.json"] else {
            return .failure(DeployError(message: "manifest.json is missing at the top level of the package."))
        }
        let parsed = try? JSONSerialization.jsonObject(with: manifestData)
        guard let manifest = parsed as? [String: Any] else {
            return .failure(DeployError(message: "manifest.json is not a valid JSON object."))
        }

        let bundleID = (manifest["bundleID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else {
            return .failure(DeployError(message: "The manifest's bundleID is empty — a Deploy package must name exactly one target app."))
        }
        guard !bundleID.contains("/") && !bundleID.contains("..") else {
            return .failure(DeployError(message: "The manifest's bundleID is not a valid identifier: \(bundleID)"))
        }

        let scope = (manifest["scope"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard scopes.contains(scope) else {
            return .failure(DeployError(message: "The manifest's scope is unknown: \"\(scope)\" — it must be Application, AppGroup or InternalDaemon."))
        }

        // File list: the "files" array, or the single-file
        // shorthand ("relativePath" + "file").
        var specs: [(path: String, source: String)] = []
        if let files = manifest["files"] as? [[String: Any]] {
            for entry in files {
                guard let path = entry["path"] as? String, let source = entry["source"] as? String else {
                    return .failure(DeployError(message: "Every entry in the manifest's files list needs both a \"path\" and a \"source\"."))
                }
                specs.append((path, source))
            }
        } else if let relativePath = manifest["relativePath"] as? String,
                  let file = manifest["file"] as? String {
            specs.append((relativePath, file))
        }
        guard !specs.isEmpty else {
            return .failure(DeployError(message: "The manifest lists no files — nothing to deploy."))
        }

        var files: [LoadedDeployFile] = []
        for spec in specs {
            guard let relativePath = cleanRelativePath(spec.path) else {
                return .failure(DeployError(message: "Invalid target path in the manifest: \"\(spec.path)\" — target paths must be relative, non-empty and contain no \"..\" component."))
            }
            let sourceKey = normalizePackagePath(spec.source)
            guard let data = entries[sourceKey] else {
                return .failure(DeployError(message: "The payload file \"\(spec.source)\" is missing from the package."))
            }
            files.append(LoadedDeployFile(relativePath: relativePath, source: spec.source, data: data))
        }

        let name = (manifest["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        print("[Deploy] package loaded: \(name ?? bundleID) — \(bundleID), scope \(scope), \(files.count) file(s)")
        return .success(LoadedDeployPackage(bundleID: bundleID, scope: scope, name: name, files: files))
    }

    /// Package-side path normalization: forward slashes, no
    /// leading "./" or "/", so manifest sources match the
    /// entry keys from both zip archives and folders.
    private static func normalizePackagePath(_ path: String) -> String {
        var result = path.replacingOccurrences(of: "\\", with: "/")
        while result.hasPrefix("./") { result = String(result.dropFirst(2)) }
        while result.hasPrefix("/") { result = String(result.dropFirst()) }
        return result
    }

    /// Validate + canonicalize a manifest target path. Nil
    /// when the path is absolute, empty, or contains a ".."
    /// component — such a package is rejected as a whole.
    private static func cleanRelativePath(_ path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else { return nil }
        var components: [String] = []
        for component in normalized.split(separator: "/", omittingEmptySubsequences: true) {
            if component == ".." { return nil }
            if component == "." { continue }
            components.append(String(component))
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    // MARK: Minimal ZIP reader (read-only)

    /// Stored + deflate entries only. Encryption, ZIP64 and
    /// other compression methods are honest errors naming the
    /// limitation — they are never silently mishandled.
    private static func zipEntries(from data: Data) -> Result<[String: Data], DeployError> {
        let bytes = [UInt8](data)
        func u16(_ offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) | (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24)
        }
        guard bytes.count >= 22 else {
            return .failure(DeployError(message: "The file is too small to be a ZIP archive."))
        }

        // End of central directory: search the tail window
        // (the record is 22 bytes plus an optional comment).
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
            return .failure(DeployError(message: "No ZIP end-of-central-directory record was found — this is not a ZIP archive."))
        }
        let entryCount = u16(eocd + 10)
        let cdSize = u32(eocd + 12)
        let cdOffset = u32(eocd + 16)
        if entryCount == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            return .failure(DeployError(message: "ZIP64 archives are not supported."))
        }

        var result: [String: Data] = [:]
        var p = cdOffset
        for _ in 0..<entryCount {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else {
                return .failure(DeployError(message: "The archive's central directory is damaged."))
            }
            let flags = u16(p + 8)
            let method = u16(p + 10)
            let compSize = u32(p + 20)
            let uncompSize = u32(p + 24)
            let nameLength = u16(p + 28)
            let extraLength = u16(p + 30)
            let commentLength = u16(p + 32)
            let localOffset = u32(p + 42)
            guard p + 46 + nameLength <= bytes.count else {
                return .failure(DeployError(message: "The archive's central directory is damaged."))
            }
            let name = String(bytes: bytes[(p + 46)..<(p + 46 + nameLength)], encoding: .utf8) ?? ""
            p += 46 + nameLength + extraLength + commentLength

            if name.hasSuffix("/") { continue } // directory entry
            if flags & 0x1 != 0 {
                return .failure(DeployError(message: "Encrypted archives are not supported (entry \"\(name)\")."))
            }
            if compSize == 0xFFFF_FFFF || uncompSize == 0xFFFF_FFFF {
                return .failure(DeployError(message: "ZIP64 archives are not supported (entry \"\(name)\")."))
            }
            guard uncompSize <= 268_435_456 else {
                return .failure(DeployError(message: "The entry \"\(name)\" is too large (\(uncompSize) bytes)."))
            }
            guard localOffset + 30 <= bytes.count, u32(localOffset) == 0x0403_4B50 else {
                return .failure(DeployError(message: "The archive's local header for \"\(name)\" is damaged."))
            }
            let localNameLength = u16(localOffset + 26)
            let localExtraLength = u16(localOffset + 28)
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compSize <= bytes.count else {
                return .failure(DeployError(message: "The archive's data for \"\(name)\" is truncated."))
            }
            let compressed = Data(bytes[dataStart..<(dataStart + compSize)])
            switch method {
            case 0:
                guard compressed.count == uncompSize else {
                    return .failure(DeployError(message: "The stored entry \"\(name)\" has a size mismatch."))
                }
                result[normalizePackagePath(name)] = compressed
            case 8:
                guard let inflated = inflate(compressed, expectedSize: uncompSize) else {
                    return .failure(DeployError(message: "The deflated entry \"\(name)\" could not be decompressed."))
                }
                result[normalizePackagePath(name)] = inflated
            default:
                return .failure(DeployError(message: "Unsupported compression method \(method) for \"\(name)\" — only stored and deflated entries are supported."))
            }
        }
        return .success(result)
    }

    /// ZIP deflate is a raw deflate stream, which is what the
    /// Compression framework's COMPRESSION_ZLIB decoder reads.
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

    // MARK: Backup store

    /// The Deploy backup store: DeployBackups/ inside our own
    /// App Group container. Nil when the group container does
    /// not resolve — deploys then honestly refuse to run,
    /// because replacing files without a backup is not offered.
    static func storeRootURL() -> URL? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupResolver.resolvedGroup) else {
            print("[Deploy] App Group container unavailable — no backup store.")
            return nil
        }
        return groupURL.appendingPathComponent("DeployBackups", isDirectory: true)
    }

    private static func timestampStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: Resolution

    /// Resolve the manifest's identifier to a live container.
    /// Application scope matches the App Data scan results;
    /// AppGroup / InternalDaemon enumerate their roots with
    /// the fork's pathleak helper and match by identifier.
    func resolveTarget(package: LoadedDeployPackage, containers: [AppContainer]) {
        resolvedContainerPath = nil
        resolveError = nil

        if package.scope == "Application" {
            if let match = containers.first(where: { $0.bundleID == package.bundleID }) {
                resolvedContainerPath = match.path
                print("[Deploy] resolved \(package.bundleID) -> \(match.path)")
            } else {
                resolveError = "Target container not found for \(package.bundleID)"
                print("[Deploy] no Application container matches \(package.bundleID) among \(containers.count) scanned container(s)")
            }
            return
        }

        let root = package.scope == "AppGroup"
            ? "/var/mobile/Containers/Shared/AppGroup"
            : "/var/mobile/Containers/Data/System"
        isResolving = true
        print("[Deploy] resolving \(package.bundleID) under \(root) (pathleak)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Self.findContainer(root: root, identifier: package.bundleID)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isResolving = false
                if let found {
                    self.resolvedContainerPath = found
                    print("[Deploy] resolved \(package.bundleID) -> \(found)")
                } else {
                    self.resolveError = "Target container not found for \(package.bundleID)"
                    print("[Deploy] no container under \(root) matches \(package.bundleID)")
                }
            }
        }
    }

    /// Match a container under `root` by directory name or by
    /// the fork's xattr identifier read. Shared by resolution
    /// and by restore re-resolution. Off-main-thread only —
    /// the pathleak scan reads inodes one by one.
    static func findContainer(root: String, identifier: String) -> String? {
        let children = wtPathleakChildren(root) ?? []
        for child in children {
            if (child as NSString).lastPathComponent == identifier {
                return child
            }
            if wtContainerIdentifier(atPath: child) == identifier {
                return child
            }
        }
        return nil
    }

    // MARK: Execution

    func deploy(package: LoadedDeployPackage) {
        guard let containerPath = resolvedContainerPath, !isDeploying else { return }
        isDeploying = true
        lastResult = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.performDeploy(package: package, containerPath: containerPath)
            DispatchQueue.main.async {
                self?.isDeploying = false
                self?.lastResult = result
            }
        }
    }

    private static func performDeploy(package: LoadedDeployPackage, containerPath: String) -> DeployRunResult {
        guard let storeRoot = storeRootURL() else {
            return DeployRunResult(
                lines: [DeployRunLine(path: "", ok: false, message: "The App Group container is unavailable, so there is no backup store — nothing was deployed.")],
                receiptFolderName: nil
            )
        }
        let folderName = "\(timestampStamp())-\(package.bundleID.replacingOccurrences(of: "/", with: "_"))"
        let backupDir = storeRoot.appendingPathComponent(folderName, isDirectory: true)

        let handle = consumeExtension(containerPath)
        print("[Deploy] grant for \(containerPath) -> \(handle)")
        guard handle > 0 else {
            return DeployRunResult(
                lines: [DeployRunLine(path: "", ok: false, message: "The sandbox extension for the target container was refused (code \(handle)) — nothing was deployed.")],
                receiptFolderName: nil
            )
        }
        defer { releaseExtension(handle) }

        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        } catch {
            print("[Deploy] could not create the backup folder \(backupDir.path): \(error)")
            return DeployRunResult(
                lines: [DeployRunLine(path: "", ok: false, message: "The backup folder could not be created — nothing was deployed.")],
                receiptFolderName: nil
            )
        }

        var lines: [DeployRunLine] = []
        var receiptFiles: [DeployReceiptFile] = []
        for file in package.files {
            let destPath = (containerPath as NSString).appendingPathComponent(file.relativePath)
            let existed = FileManager.default.fileExists(atPath: destPath)
            var ok = true
            var message = ""

            let parent = (destPath as NSString).deletingLastPathComponent
            do {
                try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            } catch {
                ok = false
                message = "Could not create the folder: \(error.localizedDescription)"
            }

            if ok && existed {
                let backupPath = backupDir.appendingPathComponent(file.relativePath).path
                do {
                    try FileManager.default.createDirectory(atPath: (backupPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(atPath: destPath, toPath: backupPath)
                    print("[Deploy] backed up \(file.relativePath)")
                } catch {
                    ok = false
                    message = "Backup failed: \(error.localizedDescription)"
                }
            }

            if ok {
                if writeDataInPlace(path: destPath, data: file.data) {
                    let size = (try? FileManager.default.attributesOfItem(atPath: destPath))?[.size] as? NSNumber
                    if size?.int64Value == Int64(file.data.count) {
                        message = existed
                            ? "Replaced (\(wtFormatSize(Int64(file.data.count))))"
                            : "Created (\(wtFormatSize(Int64(file.data.count))))"
                    } else {
                        ok = false
                        message = "Size check failed after writing"
                    }
                } else {
                    ok = false
                    message = "Write failed"
                }
            }

            lines.append(DeployRunLine(path: file.relativePath, ok: ok, message: message))
            receiptFiles.append(DeployReceiptFile(
                path: file.relativePath,
                existedBefore: existed,
                size: file.data.count,
                status: ok ? "ok" : "failed"
            ))
            print("[Deploy] \(file.relativePath): \(ok ? "ok" : "FAILED") — \(message)")
        }

        let receipt = DeployReceipt(
            name: package.name,
            bundleID: package.bundleID,
            scope: package.scope,
            containerPath: containerPath,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            files: receiptFiles
        )
        let receiptURL = backupDir.appendingPathComponent("receipt.json")
        if let receiptData = try? JSONEncoder().encode(receipt) {
            try? receiptData.write(to: receiptURL)
            print("[Deploy] receipt written to \(receiptURL.path)")
        } else {
            print("[Deploy] WARNING: the receipt could not be written — this deploy will not appear in Deploy History.")
        }

        return DeployRunResult(lines: lines, receiptFolderName: folderName)
    }

    /// Write data to a file: in place (truncate + write +
    /// synchronize) when the file exists, created directly
    /// when it does not.
    static func writeDataInPlace(path: String, data: Data) -> Bool {
        let files = FileManager.default
        if !files.fileExists(atPath: path) {
            return files.createFile(atPath: path, contents: data)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return false }
        do {
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            return true
        } catch {
            try? handle.close()
            return false
        }
    }

    // MARK: History & restore

    static func loadHistory() -> [DeployHistoryEntry] {
        guard let storeRoot = storeRootURL(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: storeRoot.path) else {
            return []
        }
        var entries: [DeployHistoryEntry] = []
        for name in names {
            let folder = storeRoot.appendingPathComponent(name, isDirectory: true)
            let receiptURL = folder.appendingPathComponent("receipt.json")
            guard let data = try? Data(contentsOf: receiptURL),
                  let receipt = try? JSONDecoder().decode(DeployReceipt.self, from: data) else {
                continue
            }
            entries.append(DeployHistoryEntry(folderName: name, folderURL: folder, receipt: receipt))
        }
        // Folder names start with a sortable timestamp, so a
        // descending name sort is newest first.
        return entries.sorted { $0.folderName > $1.folderName }
    }

    func restore(entry: DeployHistoryEntry, containers: [AppContainer]) {
        guard !isRestoring else { return }
        isRestoring = true
        restoreResult = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.performRestore(entry: entry, containers: containers)
            DispatchQueue.main.async {
                self?.isRestoring = false
                self?.restoreResult = result
            }
        }
    }

    private static func performRestore(entry: DeployHistoryEntry, containers: [AppContainer]) -> DeployRunResult {
        let receipt = entry.receipt
        print("[Deploy] restore of \(entry.folderName) started (\(receipt.bundleID), scope \(receipt.scope))")

        // The recorded container path is used while it still
        // exists; otherwise the target is re-resolved by
        // bundle ID, exactly like a fresh deploy.
        var containerPath = receipt.containerPath
        var isDirectory: ObjCBool = false
        let recordedExists = FileManager.default.fileExists(atPath: containerPath, isDirectory: &isDirectory) && isDirectory.boolValue
        if !recordedExists {
            print("[Deploy] recorded container \(containerPath) no longer exists — re-resolving by bundle ID")
            let resolved: String?
            switch receipt.scope {
            case "Application":
                resolved = containers.first(where: { $0.bundleID == receipt.bundleID })?.path
            case "AppGroup":
                resolved = findContainer(root: "/var/mobile/Containers/Shared/AppGroup", identifier: receipt.bundleID)
            default:
                resolved = findContainer(root: "/var/mobile/Containers/Data/System", identifier: receipt.bundleID)
            }
            guard let resolved else {
                return DeployRunResult(
                    lines: [DeployRunLine(path: "", ok: false, message: "Target container not found for \(receipt.bundleID) — the recorded container is gone and re-resolution found nothing. For Application scope, open App Data and let the container scan finish, then restore again.")],
                    receiptFolderName: nil
                )
            }
            containerPath = resolved
            print("[Deploy] re-resolved \(receipt.bundleID) -> \(containerPath)")
        }

        let handle = consumeExtension(containerPath)
        print("[Deploy] grant for restore on \(containerPath) -> \(handle)")
        guard handle > 0 else {
            return DeployRunResult(
                lines: [DeployRunLine(path: "", ok: false, message: "The sandbox extension for the target container was refused (code \(handle)) — nothing was restored.")],
                receiptFolderName: nil
            )
        }
        defer { releaseExtension(handle) }

        var lines: [DeployRunLine] = []
        for file in receipt.files {
            let destPath = (containerPath as NSString).appendingPathComponent(file.path)
            var ok = true
            var message = ""
            if file.existedBefore {
                let backupPath = entry.folderURL.appendingPathComponent(file.path).path
                if let data = try? Data(contentsOf: URL(fileURLWithPath: backupPath)) {
                    do {
                        try FileManager.default.createDirectory(atPath: (destPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    } catch {
                        ok = false
                        message = "Could not create the folder: \(error.localizedDescription)"
                    }
                    if ok {
                        if writeDataInPlace(path: destPath, data: data) {
                            message = "Restored (\(wtFormatSize(Int64(data.count))))"
                        } else {
                            ok = false
                            message = "Write failed"
                        }
                    }
                } else {
                    ok = false
                    message = "The backup copy is missing"
                }
            } else {
                // The deploy created this file; restoring
                // removes it again.
                if FileManager.default.fileExists(atPath: destPath) {
                    do {
                        try FileManager.default.removeItem(atPath: destPath)
                        message = "Removed (created by the deploy)"
                    } catch {
                        ok = false
                        message = "Could not remove the file: \(error.localizedDescription)"
                    }
                } else {
                    message = "Already absent (created by the deploy)"
                }
            }
            lines.append(DeployRunLine(path: file.path, ok: ok, message: message))
            print("[Deploy] restore \(file.path): \(ok ? "ok" : "FAILED") — \(message)")
        }
        return DeployRunResult(lines: lines, receiptFolderName: nil)
    }
}
