import Foundation
import UIKit

// MARK: - Save Vault
//
// Two ways to keep an app's user data across a sideload
// reinstall (the 7-day free certificate), built on the
// APFS-vault idea from yangokok886/WCMigrate (see License &
// Credits) and the ZIP backup shape Erosion-CN uses —
// original Swift code written for WorkTweaks, following the
// user's written spec where it differs from Erosion (notably
// the ZIP scope: Documents + Preferences + Application
// Support, not Documents + Preferences only).
//
// 1. APFS staging vault (zero-space swap): the target's
//    Documents, Library/Application Support and
//    Library/Preferences (never Caches) are cloned with
//    clonefile() into this app's own Documents/APFSStagingVault.
//    The source is never moved or deleted ("Copy-Never-Move").
//    After reinstall, the target container is found again by
//    bundle id (never the old container UUID), and the restore
//    swaps atomically with a .bak rollback.
// 2. ZIP save backup: the same three subdirectories are copied
//    into staging and zipped to <bundleID>__<date>.zip. Restore
//    merges in place (no rollback, unlike the APFS path).
//
// The staging vault lives in this app's Documents and does NOT
// survive uninstalling WorkTweaks. The screen is kept awake
// during stage/restore. Every step logs with a [Vault] prefix.
//
// Guards (Erosion's five layers, adapted): (1) cert gate — the
// target's embedded.mobileprovision ExpirationDate, warn if
// < 24 h or expired; (2) WAL-lock scan — *-wal files modified
// within 10 s block staging/restore ("close the target app
// first"); (3) WeChat detection — 32-hex MD5 account dirs in
// Documents; (4) manifest.json — a stage is only "verified"
// if cloned item + file counts match the source exactly, else
// the partial snapshot is deleted; (5) atomic restore with
// .bak rollback (see performRestore).

@_silgen_name("clonefile")
func wt_clonefile(_ src: UnsafePointer<CChar>, _ dst: UnsafePointer<CChar>, _ flags: UInt32) -> Int32

/// One staged snapshot's record. Written as manifest.json
/// inside the snapshot folder; a snapshot is only trusted
/// when the vault on disk matches these counts exactly.
struct SaveVaultManifest: Codable {
    let version: Int
    let sourceBundleID: String
    let sourceContainerUUID: String
    let stagedAt: String
    let subdirectories: [String]
    let itemCount: Int
    let fileCount: Int
    let logicalBytes: Int64
    let weChatAccountCount: Int
    /// ISO 8601 expiry of the target's cert, when it could
    /// be read at stage time.
    let certExpiresAt: String?
}

struct SaveVaultCounts {
    var items = 0
    var files = 0
    var bytes: Int64 = 0
}

enum SaveVaultCertState {
    case ok(expires: Date)
    case expiringSoon(expires: Date)
    case expired(expires: Date)
    case unknown
}

/// Failure payload for the vault's Result completions
/// (Swift's Result requires Failure: Error, and a bare
/// String does not conform).
struct VaultError: Error {
    let message: String
}

final class SaveVaultManager {
    static let targetSubdirectories = [
        "Documents",
        "Library/Application Support",
        "Library/Preferences",
    ]

    /// Bundle ids the ZIP restore refuses outright: Apple
    /// system apps and this app itself.
    static let protectedRestoreBundleIDs: Set<String> = [
        "cc.forcequit.worse-query",
        "com.apple.PosterBoard",
        "com.apple.springboard",
        "com.apple.Preferences",
        "com.apple.mobilephone",
    ]

    // MARK: Paths

    static var vaultRoot: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("APFSStagingVault", isDirectory: true)
    }

    static var zipBackupsRoot: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SaveVaultBackups", isDirectory: true)
    }

    static func snapshotDir(bundleID: String) -> URL? {
        vaultRoot?.appendingPathComponent(bundleID, isDirectory: true)
    }

    static func manifestURL(bundleID: String) -> URL? {
        snapshotDir(bundleID: bundleID)?.appendingPathComponent("manifest.json")
    }

    // MARK: POSIX helpers

    /// lstat mode bits, or nil when the path cannot be
    /// stat'ed. Never follows symlinks.
    static func posixMode(atPath path: String) -> mode_t? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return st.st_mode
    }

    static func isSymlink(_ path: String) -> Bool {
        guard let mode = posixMode(atPath: path) else { return false }
        return (mode & S_IFMT) == S_IFLNK
    }

    static func isRegularFile(_ path: String) -> Bool {
        guard let mode = posixMode(atPath: path) else { return false }
        return (mode & S_IFMT) == S_IFREG
    }

    static func isDirectory(_ path: String) -> Bool {
        guard let mode = posixMode(atPath: path) else { return false }
        return (mode & S_IFMT) == S_IFDIR
    }

    static func errnoString() -> String {
        String(cString: strerror(errno))
    }

    /// Count a tree: items = every entry (files, dirs,
    /// symlinks), files = regular files only, bytes = sum of
    /// regular-file sizes. Symlinked directories are never
    /// descended into.
    static func countTree(atPath path: String) -> SaveVaultCounts {
        var counts = SaveVaultCounts()
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return counts }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            if values.isSymbolicLink == true {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                counts.items += 1
                continue
            }
            counts.items += 1
            if values.isDirectory == false {
                var st = stat()
                if lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG {
                    counts.files += 1
                    counts.bytes += Int64(st.st_size)
                }
            }
        }
        return counts
    }

    /// Count one of the target subdirectories (Documents etc.)
    /// under a container root. Missing subdir = zero counts.
    static func countSubdirectory(containerPath: String, subdir: String) -> SaveVaultCounts {
        let full = (containerPath as NSString).appendingPathComponent(subdir)
        guard isDirectory(full) else { return SaveVaultCounts() }
        var counts = SaveVaultCounts()
        counts.items += 1 // the subdir itself
        let inner = countTree(atPath: full)
        counts.items += inner.items
        counts.files += inner.files
        counts.bytes += inner.bytes
        return counts
    }

    // MARK: WAL-lock scan

    /// True when a *-wal / *.sqlite-wal / *.db-wal file under
    /// Documents or Library (depth <= 4) was modified within
    /// the last 10 seconds — the target app is still writing
    /// and its database would stage torn. Hard block.
    static func activeWALFiles(containerPath: String) -> [String] {
        var found: [String] = []
        let now = Date().timeIntervalSince1970
        for root in ["Documents", "Library"] {
            let rootPath = (containerPath as NSString).appendingPathComponent(root)
            guard isDirectory(rootPath) else { continue }
            scanWAL(dir: rootPath, depth: 1, now: now, found: &found)
        }
        return found
    }

    private static func scanWAL(dir: String, depth: Int, now: TimeInterval, found: inout [String]) {
        guard depth <= 4 else { return }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for name in names {
            let full = (dir as NSString).appendingPathComponent(name)
            var st = stat()
            guard lstat(full, &st) == 0 else { continue }
            let mode = st.st_mode & S_IFMT
            if mode == S_IFLNK { continue }
            if mode == S_IFDIR {
                scanWAL(dir: full, depth: depth + 1, now: now, found: &found)
            } else if mode == S_IFREG {
                let lower = name.lowercased()
                if lower.hasSuffix("-wal") || lower.hasSuffix(".sqlite-wal") || lower.hasSuffix(".db-wal") {
                    let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
                    if now - mtime <= 10 {
                        found.append(full)
                    }
                }
            }
        }
    }

    // MARK: Cert gate

    /// The target app's bundle container, found by bundle id
    /// via a pathleak scan of the Bundle root. Cached for the
    /// session — the scan is slow and the bundle list barely
    /// changes. Nil when it cannot be resolved.
    private static var bundleScanCache: [String: String]?
    private static var bundleScanRunning = false

    static func bundlePath(forBundleID bundleID: String) -> String? {
        if let cache = bundleScanCache { return cache[bundleID] }
        guard !bundleScanRunning else { return nil }
        bundleScanRunning = true
        defer { bundleScanRunning = false }
        let root = "/var/mobile/Containers/Bundle/Application"
        let found = wtPathleakChildren(root) ?? []
        var map: [String: String] = [:]
        for path in found {
            if let id = wtContainerIdentifier(atPath: path) {
                map[id] = path
            }
        }
        bundleScanCache = map
        print("[Vault] bundle scan: \(map.count) app(s) mapped")
        return map[bundleID]
    }

    /// ExpirationDate from an app bundle's
    /// embedded.mobileprovision (CMS blob with an XML plist
    /// inside, same extraction as the signed-entitlements
    /// reader). Nil when it cannot be read.
    static func certExpiration(bundlePath: String) -> Date? {
        let url = URL(fileURLWithPath: bundlePath)
            .appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: url),
              let xmlStart = data.range(of: Data("<?xml".utf8)),
              let plistEnd = data.range(of: Data("</plist>".utf8), options: .backwards) else {
            return nil
        }
        let plistData = data[xmlStart.lowerBound..<plistEnd.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let expires = plist["ExpirationDate"] as? Date else {
            return nil
        }
        return expires
    }

    static func certState(forBundleID bundleID: String) -> SaveVaultCertState {
        guard let bundle = bundlePath(forBundleID: bundleID),
              let expires = certExpiration(bundlePath: bundle) else {
            return .unknown
        }
        let now = Date()
        if expires <= now { return .expired(expires: expires) }
        if expires.timeIntervalSince(now) < 24 * 3600 { return .expiringSoon(expires: expires) }
        return .ok(expires: expires)
    }

    // MARK: WeChat detection

    /// WeChat keeps one 32-hex MD5 directory per account
    /// under Documents. A count > 0 means the target is
    /// WeChat (or a WeChat-like layout) — shown to the user,
    /// never used to block.
    static func weChatAccountCount(containerPath: String) -> Int {
        let docs = (containerPath as NSString).appendingPathComponent("Documents")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: docs) else { return 0 }
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return names.filter { name in
            name.count == 32 && name.unicodeScalars.allSatisfy { hex.contains($0) }
        }.count
    }

    // MARK: Clone (APFS CoW)

    /// Clone one file with clonefile(). Returns false when
    /// the filesystem refuses (e.g. not APFS) — the caller
    /// falls back to a plain copy.
    @discardableResult
    static func cloneFile(src: String, dst: String) -> Bool {
        src.withCString { s in
            dst.withCString { d in
                wt_clonefile(s, d, 0) == 0
            }
        }
    }

    /// Clone one tree: whole-tree clonefile() first; on
    /// failure, per-entry fallback (dir recursion, per-file
    /// clonefile, symlink via CLONE_NOFOLLOW or
    /// readlink+symlink); final fallback FileManager.copyItem.
    /// Dirs are created writable first so 0555 sources still
    /// clone; the source mode is restored on the clone after.
    /// Returns false only when an entry could not be copied
    /// by any method.
    @discardableResult
    static func cloneTree(src: String, dst: String) -> Bool {
        let fm = FileManager.default
        if cloneFile(src: src, dst: dst) {
            // Whole-tree clone: restore source modes on the
            // clone so a 0555 source does not leave a 0555
            // vault behind.
            restoreModes(src: src, dst: dst)
            return true
        }
        var ok = true
        var st = stat()
        guard lstat(src, &st) == 0 else { return false }
        let mode = st.st_mode & S_IFMT
        if mode == S_IFLNK {
            var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
            let len = readlink(src, &buf, buf.count - 1)
            guard len >= 0 else { return false }
            buf[len] = 0
            let target = String(cString: buf)
            do {
                try fm.createSymbolicLink(atPath: dst, withDestinationPath: target)
            } catch {
                print("[Vault] symlink clone failed: \(src) — \(error)")
                return false
            }
            return true
        }
        if mode == S_IFDIR {
            do {
                try fm.createDirectory(atPath: dst, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            } catch {
                print("[Vault] mkdir failed: \(dst) — \(error)")
                return false
            }
            guard let names = try? fm.contentsOfDirectory(atPath: src) else { return false }
            for name in names {
                let s = (src as NSString).appendingPathComponent(name)
                let d = (dst as NSString).appendingPathComponent(name)
                if !cloneTree(src: s, dst: d) {
                    ok = false
                    print("[Vault] per-entry clone failed: \(s)")
                }
            }
            restoreMode(src: src, dst: dst)
            return ok
        }
        if mode == S_IFREG {
            if cloneFile(src: src, dst: dst) {
                restoreMode(src: src, dst: dst)
                return true
            }
            do {
                try fm.copyItem(atPath: src, toPath: dst)
                restoreMode(src: src, dst: dst)
                return true
            } catch {
                print("[Vault] file copy failed: \(src) — \(error)")
                return false
            }
        }
        print("[Vault] skipping non-regular entry: \(src)")
        return true
    }

    /// Copy the source mode bits (permissions only) onto the
    /// clone, one path at a time. Best effort — a failure is
    /// logged, never fatal.
    private static func restoreMode(src: String, dst: String) {
        var st = stat()
        guard lstat(src, &st) == 0 else { return }
        let perms = mode_t(st.st_mode & 0o7777)
        if Darwin.chmod(dst, perms) != 0 {
            print("[Vault] chmod restore failed for \(dst): \(errnoString())")
        }
    }

    private static func restoreModes(src: String, dst: String) {
        restoreMode(src: src, dst: dst)
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: src),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let rel = url.path.dropFirst(src.count)
            let clonePath = dst + rel
            restoreMode(src: url.path, dst: clonePath)
        }
    }
}

// MARK: - SaveVaultManager: stage / restore / release

extension SaveVaultManager {
    // MARK: Manifest

    func loadManifest(bundleID: String) -> SaveVaultManifest? {
        guard let url = Self.manifestURL(bundleID: bundleID),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(SaveVaultManifest.self, from: data) else {
            return nil
        }
        return manifest
    }

    /// The staged snapshots currently in the vault, newest
    /// first. A snapshot only lists when its manifest reads.
    func stagedSnapshots() -> [SaveVaultManifest] {
        guard let root = Self.vaultRoot,
              let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        var out: [SaveVaultManifest] = []
        for name in names {
            if let manifest = loadManifest(bundleID: name) {
                out.append(manifest)
            }
        }
        return out.sorted { $0.stagedAt > $1.stagedAt }
    }

    // MARK: Stage (APFS)

    /// Stage one app's user data into the vault. Runs on a
    /// background queue; the completion reports the manifest
    /// on success, or an honest error message. A failed stage
    /// deletes its partial snapshot.
    func stage(container: AppContainer, completion: @escaping (Result<SaveVaultManifest, VaultError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.sync { UIApplication.shared.isIdleTimerDisabled = true }
            defer { DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false } }
            let result = self.performStage(container: container)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func performStage(container: AppContainer) -> Result<SaveVaultManifest, VaultError> {
        let fm = FileManager.default
        let bundleID = container.bundleID
        print("[Vault] staging \(bundleID) from \(container.path)")

        // Guard 2: WAL-lock scan on the source.
        let wal = Self.activeWALFiles(containerPath: container.path)
        if !wal.isEmpty {
            print("[Vault] stage blocked — active WAL: \(wal.joined(separator: ", "))")
            return .failure(VaultError(message: "The app is still writing its database (\(wal.count) active WAL file(s)). Close \(bundleID) first, wait a few seconds, then stage again. Nothing was staged."))
        }

        guard let root = Self.vaultRoot, let snapDir = Self.snapshotDir(bundleID: bundleID) else {
            return .failure(VaultError(message: "The vault folder inside this app's Documents could not be created."))
        }
        // Guard 1: cert gate (informational at stage time —
        // the expiry is recorded in the manifest). Runs before
        // the grant — the bundle scan is slow and needs no
        // grant on the target container.
        let certExpires: String?
        switch Self.certState(forBundleID: bundleID) {
        case .ok(let date), .expiringSoon(let date), .expired(let date):
            certExpires = ISO8601DateFormatter().string(from: date)
            print("[Vault] target cert expires \(certExpires ?? "?")")
        case .unknown:
            certExpires = nil
            print("[Vault] target cert could not be read")
        }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            return .failure(VaultError(message: "Could not create the vault folder: \(error.localizedDescription)"))
        }
        // A previous snapshot for this app is replaced.
        try? fm.removeItem(at: snapDir)
        do {
            try fm.createDirectory(at: snapDir, withIntermediateDirectories: true)
        } catch {
            return .failure(VaultError(message: "Could not create the snapshot folder: \(error.localizedDescription)"))
        }

        let handle = consumeExtension(container.path)
        print("[Vault] grant for stage -> \(handle)")
        guard handle > 0 else {
            try? fm.removeItem(at: snapDir)
            return .failure(VaultError(message: "The sandbox extension for \(bundleID) was refused (code \(handle)). Nothing was staged."))
        }
        defer { releaseExtension(handle) }

        var total = SaveVaultCounts()
        var stagedSubdirs: [String] = []
        var cloneOK = true
        for subdir in Self.targetSubdirectories {
            let src = (container.path as NSString).appendingPathComponent(subdir)
            guard Self.isDirectory(src) else { continue }
            let dst = (snapDir.path as NSString).appendingPathComponent(subdir)
            // Create the parent (Library) writable first.
            try? fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if !Self.cloneTree(src: src, dst: dst) {
                cloneOK = false
                print("[Vault] clone failed for \(subdir)")
                break
            }
            stagedSubdirs.append(subdir)
            let counts = Self.countSubdirectory(containerPath: container.path, subdir: subdir)
            total.items += counts.items
            total.files += counts.files
            total.bytes += counts.bytes
        }
        guard cloneOK else {
            try? fm.removeItem(at: snapDir)
            return .failure(VaultError(message: "Cloning \(bundleID) failed partway — the partial snapshot was deleted. The details are in the Log."))
        }

        // Guard 4: verify the clone matches the source
        // exactly, else delete the partial snapshot.
        var verify = SaveVaultCounts()
        for subdir in stagedSubdirs {
            let dst = (snapDir.path as NSString).appendingPathComponent(subdir)
            let counts = Self.countTree(atPath: dst)
            verify.items += counts.items + 1 // the subdir itself
            verify.files += counts.files
            verify.bytes += counts.bytes
        }
        guard verify.items == total.items, verify.files == total.files else {
            try? fm.removeItem(at: snapDir)
            print("[Vault] stage verify failed: source \(total.items) items / \(total.files) files, clone \(verify.items) / \(verify.files)")
            return .failure(VaultError(message: "The staged copy did not match the source (\(verify.files) of \(total.files) files) — the partial snapshot was deleted. Nothing was staged."))
        }

        let manifest = SaveVaultManifest(
            version: 1,
            sourceBundleID: bundleID,
            sourceContainerUUID: container.directoryName,
            stagedAt: ISO8601DateFormatter().string(from: Date()),
            subdirectories: stagedSubdirs,
            itemCount: total.items,
            fileCount: total.files,
            logicalBytes: total.bytes,
            weChatAccountCount: Self.weChatAccountCount(containerPath: container.path),
            certExpiresAt: certExpires
        )
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: snapDir.appendingPathComponent("manifest.json"))
        } catch {
            try? fm.removeItem(at: snapDir)
            return .failure(VaultError(message: "Could not write the snapshot manifest: \(error.localizedDescription)"))
        }
        print("[Vault] staged \(bundleID): \(total.items) items, \(total.files) files, \(total.bytes) bytes")
        DispatchQueue.main.async { AppDataManager.shared.invalidateScanCache() }
        return .success(manifest)
    }

    // MARK: Restore (APFS)

    /// Restore a staged snapshot into the app's current
    /// container (found by bundle id). Atomic swap with .bak
    /// rollback; the vault copy is kept. Runs on a background
    /// queue.
    func restore(manifest: SaveVaultManifest, targetBundleID: String? = nil, completion: @escaping (Result<String, VaultError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.sync { UIApplication.shared.isIdleTimerDisabled = true }
            defer { DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false } }
            let result = self.performRestore(manifest: manifest, targetBundleID: targetBundleID ?? manifest.sourceBundleID)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func performRestore(manifest: SaveVaultManifest, targetBundleID: String) -> Result<String, VaultError> {
        let fm = FileManager.default
        let bundleID = manifest.sourceBundleID
        print("[Vault] restoring \(bundleID) into \(targetBundleID)")

        guard let snapDir = Self.snapshotDir(bundleID: bundleID),
              fm.fileExists(atPath: snapDir.path) else {
            return .failure(VaultError(message: "The staged snapshot for \(bundleID) is gone from the vault."))
        }
        // Guard 4 (read side): vault must still match its
        // manifest before anything is touched.
        var vaultCounts = SaveVaultCounts()
        for subdir in manifest.subdirectories {
            let dst = (snapDir.path as NSString).appendingPathComponent(subdir)
            let counts = Self.countTree(atPath: dst)
            vaultCounts.items += counts.items + 1
            vaultCounts.files += counts.files
            vaultCounts.bytes += counts.bytes
        }
        guard vaultCounts.items == manifest.itemCount, vaultCounts.files == manifest.fileCount else {
            print("[Vault] restore refused — vault mismatch: manifest \(manifest.itemCount)/\(manifest.fileCount), disk \(vaultCounts.items)/\(vaultCounts.files)")
            return .failure(VaultError(message: "The vault copy no longer matches its manifest (\(vaultCounts.files) of \(manifest.fileCount) files) — restore refused so a partial restore cannot happen."))
        }

        // Target resolution by bundle id, never the old UUID.
        // The caller may pass a different target bundle id
        // (e.g. com.tencent.wx for a com.tencent.xin stage) —
        // the cross-bundle adapt below renames the Preferences
        // plist to match.
        DispatchQueue.main.sync { AppDataManager.shared.scanIfNeeded() }
        guard let target = AppDataManager.shared.containers.first(where: { $0.bundleID == targetBundleID }) else {
            return .failure(VaultError(message: "\(targetBundleID) is not installed (or has not been opened once since reinstall). Install it, open it once, close it, then restore."))
        }
        let targetPath = target.path

        // A leftover .bak without a live Documents means a
        // previous restore was interrupted — abort, do not
        // guess which side is good.
        let docsBak = (targetPath as NSString).appendingPathComponent("Documents.worktweaks_pre_restore_bak")
        let docsLive = (targetPath as NSString).appendingPathComponent("Documents")
        if fm.fileExists(atPath: docsBak) && !fm.fileExists(atPath: docsLive) {
            return .failure(VaultError(message: "A previous restore was interrupted (a .bak folder is left without a live Documents). Restore aborted — check the target's container before trying again."))
        }

        // Guard 2: WAL-lock scan on the target.
        let wal = Self.activeWALFiles(containerPath: targetPath)
        if !wal.isEmpty {
            return .failure(VaultError(message: "The target app is still writing its database (\(wal.count) active WAL file(s)). Close \(targetBundleID) first, wait a few seconds, then restore again. Nothing was changed."))
        }

        let handle = consumeExtension(targetPath)
        print("[Vault] grant for restore -> \(handle)")
        guard handle > 0 else {
            return .failure(VaultError(message: "The sandbox extension for \(targetBundleID) was refused (code \(handle)). Nothing was changed."))
        }
        defer { releaseExtension(handle) }

        // Atomic swap: move live subdirs aside, clone from
        // the vault, verify, then drop the .bak.
        var movedAside: [(live: String, bak: String)] = []
        var restoreError: String?
        for subdir in manifest.subdirectories {
            let live = (targetPath as NSString).appendingPathComponent(subdir)
            guard fm.fileExists(atPath: live) else { continue }
            let bak = live + ".worktweaks_pre_restore_bak"
            try? fm.removeItem(atPath: bak)
            do {
                try fm.moveItem(atPath: live, toPath: bak)
                movedAside.append((live: live, bak: bak))
            } catch {
                restoreError = "Could not move \(subdir) aside: \(error.localizedDescription)"
                break
            }
        }
        if restoreError == nil {
            for subdir in manifest.subdirectories {
                let src = (snapDir.path as NSString).appendingPathComponent(subdir)
                let dst = (targetPath as NSString).appendingPathComponent(subdir)
                try? fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                if !Self.cloneTree(src: src, dst: dst) {
                    restoreError = "Cloning \(subdir) into the target failed."
                    break
                }
            }
        }
        if restoreError == nil {
            var restored = SaveVaultCounts()
            for subdir in manifest.subdirectories {
                let dst = (targetPath as NSString).appendingPathComponent(subdir)
                let counts = Self.countTree(atPath: dst)
                restored.items += counts.items + 1
                restored.files += counts.files
                restored.bytes += counts.bytes
            }
            if restored.items != manifest.itemCount || restored.files != manifest.fileCount {
                restoreError = "Restored counts do not match the manifest (\(restored.files) of \(manifest.fileCount) files)."
                print("[Vault] restore verify failed: \(restored.items)/\(restored.files) vs manifest \(manifest.itemCount)/\(manifest.fileCount)")
            }
        }

        if let error = restoreError {
            // Roll back from .bak: drop partial restores,
            // move the .bak folders back.
            for subdir in manifest.subdirectories {
                let live = (targetPath as NSString).appendingPathComponent(subdir)
                try? fm.removeItem(atPath: live)
            }
            for pair in movedAside {
                try? fm.moveItem(atPath: pair.bak, toPath: pair.live)
            }
            print("[Vault] restore failed, rolled back from .bak: \(error)")
            return .failure(VaultError(message: "Restore failed and was rolled back from the backup: \(error) The target is back to its pre-restore state."))
        }

        // Cross-bundle-ID adapt: WeChat-style renames
        // (com.tencent.xin -> com.tencent.wx) keep the user's
        // settings under the installed app's id.
        if manifest.sourceBundleID != target.bundleID {
            let prefsDir = (targetPath as NSString).appendingPathComponent("Library/Preferences")
            let sourcePlist = (prefsDir as NSString).appendingPathComponent(manifest.sourceBundleID + ".plist")
            let targetPlist = (prefsDir as NSString).appendingPathComponent(target.bundleID + ".plist")
            if fm.fileExists(atPath: sourcePlist) {
                try? fm.removeItem(atPath: targetPlist)
                do {
                    try fm.copyItem(atPath: sourcePlist, toPath: targetPlist)
                    print("[Vault] cross-bundle adapt: \(manifest.sourceBundleID).plist -> \(target.bundleID).plist")
                } catch {
                    print("[Vault] cross-bundle adapt failed: \(error)")
                }
            }
        }

        for pair in movedAside {
            try? fm.removeItem(atPath: pair.bak)
        }
        print("[Vault] restored \(bundleID) into \(targetBundleID): \(manifest.fileCount) files")
        DispatchQueue.main.async { AppDataManager.shared.invalidateScanCache() }
        return .success("Restored \(manifest.fileCount) file(s) into \(targetBundleID). Open the app to check, then release the staging vault from this page.")
    }

    // MARK: Release

    /// Delete one staged snapshot. The vault is only ever
    /// freed manually, after the user verifies the restore.
    func releaseSnapshot(bundleID: String) -> Bool {
        guard let dir = Self.snapshotDir(bundleID: bundleID) else { return false }
        do {
            try FileManager.default.removeItem(at: dir)
            print("[Vault] released snapshot for \(bundleID)")
            return true
        } catch {
            print("[Vault] release failed for \(bundleID): \(error)")
            return false
        }
    }
}

// MARK: - SaveVaultManager: ZIP backup / restore

extension SaveVaultManager {
    // MARK: ZIP backup

    /// ZIP backup (user spec: Documents + Preferences +
    /// Application Support — wider than Erosion's Documents +
    /// Preferences only). Copies the three subdirectories
    /// into staging first (transient double space — for very
    /// large apps the APFS vault is the better path), then
    /// streams a stored (uncompressed) ZIP to this app's
    /// Documents/SaveVaultBackups/<bundleID>__<date>.zip with
    /// a BackupManifest.plist at the zip root.
    func zipBackup(container: AppContainer, completion: @escaping (Result<URL, VaultError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.performZipBackup(container: container)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func performZipBackup(container: AppContainer) -> Result<URL, VaultError> {
        let fm = FileManager.default
        let bundleID = container.bundleID
        print("[Vault] ZIP backup for \(bundleID)")

        let wal = Self.activeWALFiles(containerPath: container.path)
        if !wal.isEmpty {
            return .failure(VaultError(message: "The app is still writing its database (\(wal.count) active WAL file(s)). Close \(bundleID) first, wait a few seconds, then back up again."))
        }

        let handle = consumeExtension(container.path)
        print("[Vault] grant for ZIP backup -> \(handle)")
        guard handle > 0 else {
            return .failure(VaultError(message: "The sandbox extension for \(bundleID) was refused (code \(handle)). Nothing was backed up."))
        }
        defer { releaseExtension(handle) }

        let staging = fm.temporaryDirectory.appendingPathComponent("vault-zip-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return .failure(VaultError(message: "Could not create ZIP staging: \(error.localizedDescription)"))
        }
        var stagedSubdirs: [String] = []
        var total = SaveVaultCounts()
        for subdir in Self.targetSubdirectories {
            let src = (container.path as NSString).appendingPathComponent(subdir)
            guard Self.isDirectory(src) else { continue }
            let dst = (staging.path as NSString).appendingPathComponent(subdir)
            try? fm.createDirectory(atPath: (dst as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            do {
                try fm.copyItem(atPath: src, toPath: dst)
            } catch {
                return .failure(VaultError(message: "Copying \(subdir) into ZIP staging failed: \(error.localizedDescription)"))
            }
            stagedSubdirs.append(subdir)
            let counts = Self.countSubdirectory(containerPath: container.path, subdir: subdir)
            total.items += counts.items
            total.files += counts.files
            total.bytes += counts.bytes
        }
        guard !stagedSubdirs.isEmpty else {
            return .failure(VaultError(message: "\(bundleID) has no Documents, Preferences or Application Support to back up."))
        }

        // BackupManifest.plist at the zip root: the bundle id
        // the restore matches against.
        let manifestPlist: [String: Any] = [
            "bundleID": bundleID,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "subdirectories": stagedSubdirs,
            "fileCount": total.files,
            "logicalBytes": total.bytes,
        ]
        guard let manifestData = try? PropertyListSerialization.data(fromPropertyList: manifestPlist, format: .xml, options: 0) else {
            return .failure(VaultError(message: "Could not build the backup manifest."))
        }
        do {
            try manifestData.write(to: staging.appendingPathComponent("BackupManifest.plist"))
        } catch {
            return .failure(VaultError(message: "Could not write the backup manifest: \(error.localizedDescription)"))
        }

        guard let outRoot = Self.zipBackupsRoot else {
            return .failure(VaultError(message: "Could not create the backups folder."))
        }
        do {
            try fm.createDirectory(at: outRoot, withIntermediateDirectories: true)
        } catch {
            return .failure(VaultError(message: "Could not create the backups folder: \(error.localizedDescription)"))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let zipName = "\(bundleID)__\(formatter.string(from: Date())).zip"
        let zipURL = outRoot.appendingPathComponent(zipName)

        // Collect the entry list (files + empty dirs), then
        // stream the zip — nothing larger than one file's
        // 64 KB chunk is ever held in memory.
        var entries: [String] = []
        collectZipEntries(dir: staging.path, base: staging.path, into: &entries)
        let writer = VaultZipWriter(url: zipURL)
        guard writer.open() else {
            return .failure(VaultError(message: "Could not create \(zipName)."))
        }
        var zipOK = true
        for name in entries {
            let full = (staging.path as NSString).appendingPathComponent(name)
            if Self.isDirectory(full) {
                if !writer.addDirectory(name: name) { zipOK = false; break }
            } else if Self.isRegularFile(full) {
                if !writer.addFile(name: name, path: full) { zipOK = false; break }
            } else if Self.isSymlink(full) {
                // Symlinks are not followed or stored — a
                // restore must never recreate a link blindly.
                print("[Vault] ZIP skipped symlink: \(name)")
            }
        }
        writer.close(success: zipOK)
        guard zipOK else {
            try? fm.removeItem(at: zipURL)
            return .failure(VaultError(message: "Writing the ZIP failed partway — the partial file was deleted."))
        }
        let zipSize = (try? fm.attributesOfItem(atPath: zipURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        print("[Vault] ZIP backup done: \(zipName) (\(total.files) files, \(zipSize) bytes)")
        DispatchQueue.main.async { AppDataManager.shared.invalidateScanCache() }
        return .success(zipURL)
    }

    private func collectZipEntries(dir: String, base: String, into out: inout [String]) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for name in names.sorted() {
            let full = (dir as NSString).appendingPathComponent(name)
            let rel = String(full.dropFirst(base.count + 1))
            if Self.isSymlink(full) {
                out.append(rel)
                continue
            }
            if Self.isDirectory(full) {
                out.append(rel + "/")
                collectZipEntries(dir: full, base: base, into: &out)
            } else if Self.isRegularFile(full) {
                out.append(rel)
            }
        }
    }

    // MARK: ZIP restore

    /// Restore a ZIP backup picked with the file importer.
    /// Zip-Slip guards: absolute paths, "..", and resolved
    /// paths escaping the target are rejected whole. Merge in
    /// place — files written atomically, never overwriting a
    /// symlink in the destination. No rollback (unlike the
    /// APFS path). Protected bundle ids are blocked.
    func zipRestore(zipURL: URL, completion: @escaping (Result<String, VaultError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.performZipRestore(zipURL: zipURL)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func performZipRestore(zipURL: URL) -> Result<String, VaultError> {
        let fm = FileManager.default
        guard let zipSize = (try? fm.attributesOfItem(atPath: zipURL.path)[.size] as? NSNumber)?.int64Value,
              zipSize <= 1_073_741_824 else {
            return .failure(VaultError(message: "That ZIP is larger than 1 GB — restore refuses it rather than risk running out of memory."))
        }
        guard let data = try? Data(contentsOf: zipURL) else {
            return .failure(VaultError(message: "Could not read \(zipURL.lastPathComponent)."))
        }
        let entries: [String: Data]
        switch DeployManager.zipEntries(from: data) {
        case .success(let dict):
            entries = dict
        case .failure(let error):
            print("[Vault] ZIP read failed: \(error.message)")
            return .failure(VaultError(message: error.message))
        }
        guard let manifestData = entries["BackupManifest.plist"],
              let plist = try? PropertyListSerialization.propertyList(from: manifestData, options: [], format: nil) as? [String: Any],
              let bundleID = plist["bundleID"] as? String, !bundleID.isEmpty else {
            return .failure(VaultError(message: "That ZIP has no BackupManifest.plist — it is not a Save Vault backup."))
        }
        if bundleID.hasPrefix("com.apple.") || SaveVaultManager.protectedRestoreBundleIDs.contains(bundleID) {
            return .failure(VaultError(message: "Restore into \(bundleID) is blocked — system bundle ids are never restore targets."))
        }
        DispatchQueue.main.sync { AppDataManager.shared.scanIfNeeded() }
        guard let target = AppDataManager.shared.containers.first(where: { $0.bundleID == bundleID }) else {
            return .failure(VaultError(message: "\(bundleID) is not installed (or has not been opened once since reinstall). Install it, open it once, close it, then restore."))
        }
        let targetPath = target.path
        let wal = Self.activeWALFiles(containerPath: targetPath)
        if !wal.isEmpty {
            return .failure(VaultError(message: "The target app is still writing its database (\(wal.count) active WAL file(s)). Close \(bundleID) first, wait a few seconds, then restore again. Nothing was changed."))
        }

        // Zip-Slip validation up front: every entry must
        // resolve inside the target container.
        var planned: [(name: String, data: Data)] = []
        for (name, entryData) in entries {
            if name == "BackupManifest.plist" { continue }
            if name.hasPrefix("/") || name.contains("..") {
                return .failure(VaultError(message: "The ZIP contains an unsafe path (\(name)) — rejected whole, nothing was written."))
            }
            let dest = (targetPath as NSString).appendingPathComponent(name)
            let resolved = (dest as NSString).standardizingPath
            guard resolved == targetPath || resolved.hasPrefix(targetPath + "/") else {
                return .failure(VaultError(message: "The ZIP contains a path escaping the container (\(name)) — rejected whole, nothing was written."))
            }
            planned.append((name: name, data: entryData))
        }

        let handle = consumeExtension(targetPath)
        print("[Vault] grant for ZIP restore -> \(handle)")
        guard handle > 0 else {
            return .failure(VaultError(message: "The sandbox extension for \(bundleID) was refused (code \(handle)). Nothing was changed."))
        }
        defer { releaseExtension(handle) }

        var written = 0
        var skipped = 0
        for entry in planned {
            let dest = (targetPath as NSString).appendingPathComponent(entry.name)
            if entry.name.hasSuffix("/") {
                try? fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
                continue
            }
            // Never overwrite a symlink in the destination.
            if Self.isSymlink(dest) {
                skipped += 1
                print("[Vault] ZIP restore skipped symlink target: \(entry.name)")
                continue
            }
            do {
                try fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try entry.data.write(to: URL(fileURLWithPath: dest), options: .atomic)
                written += 1
            } catch {
                print("[Vault] ZIP restore write failed for \(entry.name): \(error)")
            }
        }
        print("[Vault] ZIP restore into \(bundleID): \(written) written, \(skipped) skipped")
        DispatchQueue.main.async { AppDataManager.shared.invalidateScanCache() }
        var message = "Restored \(written) file(s) into \(bundleID) from \(zipURL.lastPathComponent)."
        if skipped > 0 {
            message += " \(skipped) symlink target(s) were skipped."
        }
        message += " Respring so the system reloads the restored Preferences."
        return .success(message)
    }
}

// MARK: - Streaming stored ZIP writer
//
// Minimal ZIP writer: STORE (no compression), data
// descriptors (flag bit 3) so file data streams in 64 KB
// chunks without a pre-pass for CRC/sizes, central directory
// at the end. One file at a time is ever in memory. Files
// >= 4 GB are refused (ZIP32 limit).

private final class VaultZipWriter {
    private let url: URL
    private var handle: FileHandle?
    private var offset: UInt64 = 0
    private var central = Data()

    init(url: URL) {
        self.url = url
    }

    func open() -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let h = FileHandle(forWritingAtPath: url.path) else { return false }
        handle = h
        return true
    }

    func close(success: Bool) {
        guard let h = handle else { return }
        if success {
            let cdOffset = UInt32(offset)
            h.write(central)
            offset += UInt64(central.count)
            var eocd = Data()
            eocd += le32(0x0605_4B50)
            eocd += le16(0)
            eocd += le16(0)
            eocd += le16(UInt16(centralEntryCount))
            eocd += le16(UInt16(centralEntryCount))
            eocd += le32(UInt32(central.count))
            eocd += le32(cdOffset)
            eocd += le16(0)
            h.write(eocd)
        }
        try? h.close()
        handle = nil
    }

    private var centralEntryCount = 0

    private func dosDateTime() -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: Date()
        )
        let time = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        let date = UInt16((((c.year ?? 1980) - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        return (time, date)
    }

    private func le16(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 2)
    }

    private func le32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }

    func addDirectory(name: String) -> Bool {
        guard let h = handle else { return false }
        let (time, date) = dosDateTime()
        let nameBytes = [UInt8](name.utf8)
        let localOffset = UInt32(offset)
        var header = Data()
        header += le32(0x0403_4B50)
        header += le16(20)
        header += le16(0x0800)
        header += le16(0)
        header += le16(time)
        header += le16(date)
        header += le32(0)
        header += le32(0)
        header += le32(0)
        header += le16(UInt16(nameBytes.count))
        header += le16(0)
        header += Data(nameBytes)
        h.write(header)
        offset += UInt64(header.count)
        var cd = Data()
        cd += le32(0x0201_4B50)
        cd += le16(20)
        cd += le16(20)
        cd += le16(0x0800)
        cd += le16(0)
        cd += le16(time)
        cd += le16(date)
        cd += le32(0)
        cd += le32(0)
        cd += le32(0)
        cd += le16(UInt16(nameBytes.count))
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le32(0x10) // directory external attribute
        cd += le32(localOffset)
        cd += Data(nameBytes)
        central += cd
        centralEntryCount += 1
        return true
    }

    func addFile(name: String, path: String) -> Bool {
        guard let h = handle else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              size < 4_294_967_295 else {
            print("[Vault] ZIP refused file >= 4 GB: \(name)")
            return false
        }
        guard let input = FileHandle(forReadingAtPath: path) else {
            print("[Vault] ZIP could not open \(name)")
            return false
        }
        defer { try? input.close() }
        let (time, date) = dosDateTime()
        let nameBytes = [UInt8](name.utf8)
        let localOffset = UInt32(offset)
        var header = Data()
        header += le32(0x0403_4B50)
        header += le16(20)
        header += le16(0x0808) // UTF-8 + data descriptor
        header += le16(0)      // method: stored
        header += le16(time)
        header += le16(date)
        header += le32(0)      // crc (in descriptor)
        header += le32(0)      // compressed size (in descriptor)
        header += le32(0)      // uncompressed size (in descriptor)
        header += le16(UInt16(nameBytes.count))
        header += le16(0)
        header += Data(nameBytes)
        h.write(header)
        offset += UInt64(header.count)

        var crc: UInt32 = 0
        var written: UInt64 = 0
        var readOK = true
        while true {
            let chunk: Data
            do {
                guard let data = try input.read(upToCount: 65_536), !data.isEmpty else { break }
                chunk = data
            } catch {
                print("[Vault] ZIP read failed for \(name): \(error)")
                readOK = false
                break
            }
            crc = VaultCRC32.update(crc, chunk)
            h.write(chunk)
            written += UInt64(chunk.count)
            if chunk.count < 65_536 { break }
        }
        guard readOK else { return false }
        var descriptor = Data()
        descriptor += le32(0x0807_4B50)
        descriptor += le32(crc)
        descriptor += le32(UInt32(written))
        descriptor += le32(UInt32(written))
        h.write(descriptor)
        offset += written + UInt64(descriptor.count)

        var cd = Data()
        cd += le32(0x0201_4B50)
        cd += le16(20)
        cd += le16(20)
        cd += le16(0x0800)
        cd += le16(0)
        cd += le16(time)
        cd += le16(date)
        cd += le32(crc)
        cd += le32(UInt32(written))
        cd += le32(UInt32(written))
        cd += le16(UInt16(nameBytes.count))
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le32(0)
        cd += le32(localOffset)
        cd += Data(nameBytes)
        central += cd
        centralEntryCount += 1
        return true
    }
}

/// CRC-32 (IEEE) with a lazily built table. Same
/// polynomial as the ZIP format requires.
private enum VaultCRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func update(_ crc: UInt32, _ data: Data) -> UInt32 {
        var c = crc ^ 0xFFFF_FFFF
        for byte in data {
            c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }
}
