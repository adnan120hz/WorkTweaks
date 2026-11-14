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
    /// Internal (not private) so the package builder can
    /// validate destination paths with these exact rules
    /// while the user types.
    static func cleanRelativePath(_ path: String) -> String? {
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
    static func zipEntries(from data: Data) -> Result<[String: Data], DeployError> {
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
            // Exact scan match first.
            if let match = containers.first(where: { $0.bundleID == package.bundleID }) {
                resolvedContainerPath = match.path
                print("[Deploy] resolved \(package.bundleID) -> \(match.path)")
                return
            }
            // A typed plain bundle ID also matches the one
            // container whose scanned identifier is that ID
            // plus a team suffix (the WorkTweaks container
            // itself: cc.forcequit.worse-query.<TEAMID>).
            // Only when exactly one container matches.
            let prefixed = containers.filter { $0.bundleID.hasPrefix(package.bundleID + ".") }
            if prefixed.count == 1, let match = prefixed.first {
                resolvedContainerPath = match.path
                print("[Deploy] resolved \(package.bundleID) -> \(match.path) (team-suffixed identifier)")
                return
            }
            // No scan match — enumerate the Application root
            // directly. The scan can be empty or stale (the
            // same gap PosterBoard's searchRoot closed in
            // v4.3.1), and without this fallback Deploy can
            // never resolve. Slow, on a background queue.
            let target = package.bundleID
            isResolving = true
            print("[Deploy] no scan match for \(target) — enumerating the Application containers root directly…")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let found = Self.findContainer(root: AppDataManager.rootPath, identifier: target)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isResolving = false
                    if let found {
                        self.resolvedContainerPath = found
                        print("[Deploy] resolved \(target) -> \(found) (direct enumeration)")
                    } else {
                        self.resolveError = "Target container not found for \(target)"
                        print("[Deploy] no Application container matches \(target) — not in the scan and not in a direct enumeration")
                    }
                }
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
                // Container contents changed: the cached App
                // Data scan is stale, so the next App Data
                // visit rescans.
                if result.succeeded > 0 {
                    AppDataManager.shared.invalidateScanCache()
                }
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
                // Container contents changed: the cached App
                // Data scan is stale, so the next App Data
                // visit rescans.
                if result.succeeded > 0 {
                    AppDataManager.shared.invalidateScanCache()
                }
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

// MARK: - Package store & builder support
//
// Packages authored in the app live as folders in the App
// Group container: DeployPackages/<id>/ holding a
// manifest.json plus its payload files — the exact folder
// layout loadPackage(from:) already accepts. Everything in
// this section only ever reads or writes inside those
// package folders. Validation is the loader's own
// (buildPackage): a draft is saved only when the loader
// would accept it, and deploying a stored package goes
// through the same loadPackage -> resolve -> deploy path as
// an externally picked one. Nothing here touches deployed
// files or Deploy History receipts.

struct StoredDeployPackageFile: Identifiable {
    let id = UUID()
    /// File name inside the package folder (the manifest's
    /// "source"); payloads sit next to manifest.json.
    var payloadName: String
    /// Where the file goes inside the target container (the
    /// manifest's "path"); editable in the builder.
    var destinationPath: String
    /// Payload size in bytes, for display.
    var size: Int
}

struct StoredDeployPackage: Identifiable {
    /// The folder name inside DeployPackages/.
    let id: String
    let folderURL: URL
    var name: String?
    var bundleID: String
    /// "Application" | "AppGroup" | "InternalDaemon"
    var scope: String
    var files: [StoredDeployPackageFile]

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return bundleID.isEmpty ? "Untitled package" : bundleID
    }
}

extension DeployManager {

    // MARK: Store location

    /// DeployPackages/ inside our own App Group container.
    /// Nil when the group container does not resolve — the
    /// builder then honestly reports the store as unavailable.
    static func packageStoreRootURL() -> URL? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupResolver.resolvedGroup) else {
            print("[Deploy] App Group container unavailable — no package store.")
            return nil
        }
        return groupURL.appendingPathComponent("DeployPackages", isDirectory: true)
    }

    // MARK: Listing

    static func loadStoredPackages() -> [StoredDeployPackage] {
        guard let root = packageStoreRootURL(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        var packages: [StoredDeployPackage] = []
        for name in names {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let stored = loadStoredPackage(folderURL: folder) else {
                continue
            }
            packages.append(stored)
        }
        return packages.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Load one stored package folder through the regular
    /// package loader, so a stored package is by construction
    /// one the importer would accept. Nil when the folder
    /// does not hold a valid package (yet — e.g. a new draft
    /// whose manifest has never been saved).
    static func loadStoredPackage(folderURL: URL) -> StoredDeployPackage? {
        switch loadPackage(from: folderURL) {
        case .failure:
            return nil
        case .success(let loaded):
            let files = loaded.files.map {
                StoredDeployPackageFile(
                    payloadName: normalizePackagePath($0.source),
                    destinationPath: $0.relativePath,
                    size: $0.data.count
                )
            }
            return StoredDeployPackage(
                id: folderURL.lastPathComponent,
                folderURL: folderURL,
                name: loaded.name,
                bundleID: loaded.bundleID,
                scope: loaded.scope,
                files: files
            )
        }
    }

    // MARK: Drafts & payloads

    /// Create the folder for a brand-new package and return
    /// its empty draft. Payloads are copied in as they are
    /// added in the builder; the manifest is written on the
    /// first save.
    static func makeNewStoredPackage() -> StoredDeployPackage? {
        guard let root = packageStoreRootURL() else { return nil }
        let id = UUID().uuidString
        let folder = root.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            print("[Deploy] could not create the package folder \(folder.path): \(error)")
            return nil
        }
        print("[Deploy] new package draft created: \(id)")
        return StoredDeployPackage(
            id: id, folderURL: folder,
            name: nil, bundleID: "", scope: "Application", files: []
        )
    }

    /// Copy a picked file into a package folder under a
    /// unique flat name (name, name-2, name-3, … before the
    /// extension). Returns the payload name and size, or nil
    /// when the copy fails.
    static func addPayload(to folderURL: URL, from sourceURL: URL, takenNames: Set<String>) -> (name: String, size: Int)? {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: sourceURL) else {
            print("[Deploy] payload pick could not be read: \(sourceURL.path)")
            return nil
        }
        let candidate = uniquePayloadName(for: sourceURL.lastPathComponent, takenNames: takenNames, folderURL: folderURL)
        let destination = folderURL.appendingPathComponent(candidate)
        do {
            try data.write(to: destination)
        } catch {
            print("[Deploy] payload copy failed for \(candidate): \(error)")
            return nil
        }
        print("[Deploy] payload added to package \(folderURL.lastPathComponent): \(candidate) (\(data.count) bytes)")
        return (candidate, data.count)
    }

    /// Add the contents of a picked .zip as payloads: every
    /// entry becomes one payload file, stored flat under a
    /// unique name, with its destination defaulting to the
    /// entry's own path inside the archive — the zip knows
    /// where its files go. manifest.json, __MACOSX noise
    /// and .DS_Store entries are skipped: a builder zip is
    /// imported whole through Import Package, not added
    /// file by file. Returns the added rows, or an error
    /// when the archive cannot be read or holds nothing
    /// usable. Files already written are removed again on
    /// failure, so a failed add leaves nothing behind.
    static func addZipPayloads(to folderURL: URL, from sourceURL: URL, takenNames: Set<String>) -> Result<[(name: String, destination: String, size: Int)], DeployError> {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: sourceURL) else {
            return .failure(DeployError(message: "The picked ZIP file could not be read."))
        }
        let entries: [String: Data]
        switch zipEntries(from: data) {
        case .failure(let error): return .failure(error)
        case .success(let dict): entries = dict
        }
        var rows: [(name: String, destination: String, size: Int)] = []
        var written: [URL] = []
        var taken = takenNames
        for (entryPath, entryData) in entries.sorted(by: { $0.key < $1.key }) {
            if entryPath == "manifest.json" { continue }
            if entryPath.hasPrefix("__MACOSX/") { continue }
            if (entryPath as NSString).lastPathComponent == ".DS_Store" { continue }
            guard let destination = cleanRelativePath(entryPath) else { continue }
            let payloadName = uniquePayloadName(for: (entryPath as NSString).lastPathComponent, takenNames: taken, folderURL: folderURL)
            taken.insert(payloadName)
            let destURL = folderURL.appendingPathComponent(payloadName)
            do {
                try entryData.write(to: destURL)
            } catch {
                for url in written { try? FileManager.default.removeItem(at: url) }
                return .failure(DeployError(message: "A file from the ZIP could not be copied into the package: \(error.localizedDescription)"))
            }
            written.append(destURL)
            rows.append((payloadName, destination, entryData.count))
            print("[Deploy] ZIP payload added: \(entryPath) -> \(payloadName) (dest \(destination))")
        }
        guard !rows.isEmpty else {
            return .failure(DeployError(message: "The ZIP holds no files that can be added as payloads."))
        }
        return .success(rows)
    }

    /// Remove a payload file from a package folder (used
    /// when its entry is removed in the builder). Only ever
    /// touches the package's own folder.
    static func removePayload(from folderURL: URL, payloadName: String) {
        let url = folderURL.appendingPathComponent(payloadName)
        do {
            try FileManager.default.removeItem(at: url)
            print("[Deploy] payload removed from package \(folderURL.lastPathComponent): \(payloadName)")
        } catch {
            print("[Deploy] payload remove failed for \(payloadName): \(error)")
        }
    }

    /// A payload name that collides with nothing: not with
    /// the names already used by the draft and not with a
    /// file already sitting in the package folder.
    private static func uniquePayloadName(for original: String, takenNames: Set<String>, folderURL: URL?) -> String {
        let ns = original as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var candidate = original
        var counter = 2
        while takenNames.contains(candidate)
                || (folderURL.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(candidate).path) } ?? false) {
            candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    // MARK: Saving

    /// Validate the draft exactly like the loader validates
    /// an imported package and, only when it passes, write
    /// manifest.json into the package folder. A rejected
    /// draft leaves the manifest on disk untouched; nothing
    /// outside the package folder is ever written. The
    /// returned package is reloaded from disk, so the
    /// builder afterwards shows the canonical stored form.
    static func saveStoredPackage(_ package: StoredDeployPackage) -> Result<StoredDeployPackage, DeployError> {
        do {
            try FileManager.default.createDirectory(at: package.folderURL, withIntermediateDirectories: true)
        } catch {
            return .failure(DeployError(message: "The package folder could not be created: \(error.localizedDescription)"))
        }

        var manifest: [String: Any] = [
            "bundleID": package.bundleID.trimmingCharacters(in: .whitespacesAndNewlines),
            "scope": package.scope,
            "files": package.files.map { ["path": $0.destinationPath, "source": $0.payloadName] },
        ]
        if let name = package.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            manifest["name"] = name
        }
        guard let manifestData = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else {
            return .failure(DeployError(message: "The manifest could not be encoded."))
        }

        var entries: [String: Data] = ["manifest.json": manifestData]
        for file in package.files {
            let payloadURL = package.folderURL.appendingPathComponent(file.payloadName)
            guard let data = try? Data(contentsOf: payloadURL) else {
                return .failure(DeployError(message: "The payload file \"\(file.payloadName)\" could not be read from the package folder."))
            }
            entries[normalizePackagePath(file.payloadName)] = data
        }

        // The loader's own validation is the gate.
        switch buildPackage(entries: entries) {
        case .failure(let error):
            print("[Deploy] package save rejected: \(error.message)")
            return .failure(error)
        case .success:
            break
        }

        do {
            try manifestData.write(to: package.folderURL.appendingPathComponent("manifest.json"))
        } catch {
            return .failure(DeployError(message: "The manifest could not be written: \(error.localizedDescription)"))
        }
        print("[Deploy] package saved: \(package.displayName) — \(package.bundleID), scope \(package.scope), \(package.files.count) file(s)")
        guard let stored = loadStoredPackage(folderURL: package.folderURL) else {
            return .failure(DeployError(message: "The package was written but could not be reloaded."))
        }
        return .success(stored)
    }

    // MARK: Import & delete

    /// Copy an externally picked package into the store and
    /// return it ready for the builder. The package is
    /// loaded and validated by the regular loader first;
    /// payloads are flattened to sit flat next to the new
    /// manifest.json. A failed import leaves no folder
    /// behind.
    static func importIntoStore(from url: URL) -> Result<StoredDeployPackage, DeployError> {
        let loaded: LoadedDeployPackage
        switch loadPackage(from: url) {
        case .failure(let error):
            return .failure(error)
        case .success(let package):
            loaded = package
        }
        guard let draft = makeNewStoredPackage() else {
            return .failure(DeployError(message: "The package store is unavailable (the App Group container did not resolve)."))
        }
        var taken = Set<String>()
        var files: [StoredDeployPackageFile] = []
        for file in loaded.files {
            let original = (normalizePackagePath(file.source) as NSString).lastPathComponent
            let candidate = uniquePayloadName(for: original, takenNames: taken, folderURL: nil)
            taken.insert(candidate)
            do {
                try file.data.write(to: draft.folderURL.appendingPathComponent(candidate))
            } catch {
                deleteStoredPackage(draft)
                return .failure(DeployError(message: "A payload file could not be copied into the store: \(error.localizedDescription)"))
            }
            files.append(StoredDeployPackageFile(payloadName: candidate, destinationPath: file.relativePath, size: file.data.count))
        }
        var stored = draft
        stored.name = loaded.name
        stored.bundleID = loaded.bundleID
        stored.scope = loaded.scope
        stored.files = files
        switch saveStoredPackage(stored) {
        case .failure(let error):
            deleteStoredPackage(draft)
            return .failure(error)
        case .success(let saved):
            print("[Deploy] package imported into the store: \(saved.displayName) (\(saved.id))")
            return .success(saved)
        }
    }

    /// Delete a stored package folder. Only folders directly
    /// inside DeployPackages/ can be removed; files the
    /// package already deployed and Deploy History receipts
    /// live elsewhere and are not touched.
    @discardableResult
    static func deleteStoredPackage(_ package: StoredDeployPackage) -> Bool {
        guard let root = packageStoreRootURL() else { return false }
        let folder = package.folderURL.standardizedFileURL
        guard folder.deletingLastPathComponent().path == root.standardizedFileURL.path else {
            print("[Deploy] delete refused — \(folder.path) is not inside the package store")
            return false
        }
        do {
            try FileManager.default.removeItem(at: folder)
            print("[Deploy] package deleted: \(package.displayName) (\(package.id))")
            return true
        } catch {
            print("[Deploy] package delete failed for \(folder.path): \(error)")
            return false
        }
    }

    // MARK: Export

    /// Zip a stored package (manifest.json plus exactly the
    /// payloads its manifest names) into ONE .zip file in
    /// the temporary directory and return its URL for
    /// sharing — the v5 artifact the user saves (in Files)
    /// and Deploy imports. Entries are stored, not
    /// compressed — the subset the app's own ZIP reader
    /// accepts.
    static func exportZipURL(for package: StoredDeployPackage) -> URL? {
        var entries: [(name: String, data: Data)] = []
        let manifestURL = package.folderURL.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            print("[Deploy] export refused — \(package.folderURL.path) has no readable manifest.json")
            return nil
        }
        entries.append(("manifest.json", manifestData))
        for file in package.files {
            let payloadURL = package.folderURL.appendingPathComponent(file.payloadName)
            guard let data = try? Data(contentsOf: payloadURL) else {
                print("[Deploy] export refused — payload \(file.payloadName) could not be read")
                return nil
            }
            entries.append((file.payloadName, data))
        }

        let base = String(package.displayName.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-" || scalar == "_" || scalar == "." {
                return Character(scalar)
            }
            return "-"
        }).trimmingCharacters(in: .whitespaces)
        let fileName = (base.isEmpty ? "DeployPackage" : base) + ".zip"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try makeStoredZip(entries: entries).write(to: url)
        } catch {
            print("[Deploy] export write failed: \(error)")
            return nil
        }
        print("[Deploy] package exported: \(url.path) (\(entries.count) entries)")
        return url
    }

    // MARK: Minimal ZIP writer (stored entries)

    /// Build a ZIP archive with stored (uncompressed)
    /// entries, UTF-8 names — all the bundled reader and
    /// standard tools need.
    static func makeStoredZip(entries: [(name: String, data: Data)]) -> Data {
        func le16(_ value: UInt16) -> Data {
            var v = value.littleEndian
            return Data(bytes: &v, count: 2)
        }
        func le32(_ value: UInt32) -> Data {
            var v = value.littleEndian
            return Data(bytes: &v, count: 4)
        }
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: Date()
        )
        let dosTime = UInt16(((components.hour ?? 0) << 11) | ((components.minute ?? 0) << 5) | ((components.second ?? 0) / 2))
        let dosDate = UInt16((((components.year ?? 1980) - 1980) << 9) | ((components.month ?? 1) << 5) | (components.day ?? 1))

        var out = Data()
        var central = Data()
        for entry in entries {
            let nameBytes = [UInt8](entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let localOffset = UInt32(out.count)

            out += le32(0x0403_4B50)              // local file header
            out += le16(20)                       // version needed
            out += le16(0x0800)                   // flag: UTF-8 names
            out += le16(0)                        // method: stored
            out += le16(dosTime)
            out += le16(dosDate)
            out += le32(crc)
            out += le32(size)                     // compressed size
            out += le32(size)                     // uncompressed size
            out += le16(UInt16(nameBytes.count))
            out += le16(0)                        // extra length
            out += Data(nameBytes)
            out += entry.data

            central += le32(0x0201_4B50)          // central directory
            central += le16(20)                   // version made by
            central += le16(20)                   // version needed
            central += le16(0x0800)
            central += le16(0)
            central += le16(dosTime)
            central += le16(dosDate)
            central += le32(crc)
            central += le32(size)
            central += le32(size)
            central += le16(UInt16(nameBytes.count))
            central += le16(0)                    // extra length
            central += le16(0)                    // comment length
            central += le16(0)                    // disk number
            central += le16(0)                    // internal attributes
            central += le32(0)                    // external attributes
            central += le32(localOffset)
            central += Data(nameBytes)
        }
        let cdOffset = UInt32(out.count)
        out += central
        out += le32(0x0605_4B50)                  // end of central directory
        out += le16(0)                            // disk number
        out += le16(0)                            // CD start disk
        out += le16(UInt16(entries.count))        // entries on this disk
        out += le16(UInt16(entries.count))        // total entries
        out += le32(UInt32(central.count))
        out += le32(cdOffset)
        out += le16(0)                            // comment length
        return out
    }

    /// CRC-32 (the ZIP polynomial), for the stored entries
    /// written by makeStoredZip. The table is rebuilt per
    /// call — exports are small and infrequent.
    private static func crc32(_ data: Data) -> UInt32 {
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFF_FFFF
    }
}
