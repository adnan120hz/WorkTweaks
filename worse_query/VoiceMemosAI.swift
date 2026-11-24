import Foundation
import Combine
import SQLite3
import Darwin

// MARK: - Voice Memos export + AI cache (engine)
//
// Two read-mostly tools on one page, following the
// Erosion-CN mechanisms in VoiceMemosAIView.swift (see
// License & Credits):
//
//  - Voice Memos: find the com.apple.VoiceMemos container
//    (and its group.com.apple.VoiceMemos.shared group), read
//    CloudRecordings.db from a clonefile snapshot — never
//    opened in place, never written — and export selected
//    recordings as .m4a files with their original titles,
//    as a batch ZIP in this app's Documents.
//  - AI cache: read-only size probes (depth <= 4) of the
//    translationd + mediaanalysisd system groups and the
//    Translate / VoiceMemos / Shortcuts containers. "Delete
//    cache" removes ONLY files under Library/Caches inside
//    those targets — Caches is regenerable cache by iOS
//    convention, and the models live elsewhere and are never
//    touched. Erosion-CN never implemented the delete; the
//    cache-vs-model line here is that Caches boundary.
//
// Every step logs with a [VoiceMemos] / [AICache] prefix.

struct VoiceMemoRecording: Identifiable {
    let id = UUID()
    let title: String
    let duration: Double?
    let fileName: String
    /// Full path of the audio file.
    let filePath: String
    /// Container/group root the file lives under (for the
    /// export grant).
    let containerRoot: String
    let size: Int64
    var isSelected = false
}

struct AICacheTarget: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isSystemGroup: Bool
    var fileCount = 0
    var bytes: Int64 = 0
    var probed = false
    /// Files/bytes under Library/Caches (the deletable part).
    var cachesFiles = 0
    var cachesBytes: Int64 = 0
}

final class VoiceMemosAI: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case ready
        case blocked(String)
    }

    static let voiceMemosBundleID = "com.apple.VoiceMemos"
    static let voiceMemosGroupID = "group.com.apple.VoiceMemos.shared"
    static let mediaRecordingsPath = "/private/var/mobile/Media/Recordings"
    static let systemGroupIDs = [
        "systemgroup.com.apple.translationd",
        "systemgroup.com.apple.mediaanalysisd",
    ]
    static let aiAppBundleIDs = [
        "com.apple.Translate",
        "com.apple.VoiceMemos",
        "com.apple.shortcuts",
    ]
    static let audioExtensions: Set<String> = ["m4a", "qta", "wav", "caf"]

    @Published var recordingsState: LoadState = .idle
    @Published var recordings: [VoiceMemoRecording] = []
    @Published var aiTargets: [AICacheTarget] = []
    @Published var isProbingAI = false
    @Published var isExporting = false
    @Published var exportURL: URL?
    @Published var exportMessage: String?
    @Published var isDeletingCache = false
    @Published var cacheMessage: String?

    private var snapshotDir: URL?

    deinit {
        if let dir = snapshotDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: Voice Memos

    func loadRecordings() {
        guard case .idle = recordingsState else { return }
        recordingsState = .loading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.performLoadRecordings()
        }
    }

    /// Retry after a blocked load (e.g. the App Data scan
    /// had not finished yet when the page first opened).
    func retryLoadRecordings() {
        recordingsState = .idle
        loadRecordings()
    }

    private func performLoadRecordings() {
        print("[VoiceMemos] searching for CloudRecordings.db")
        // 1. App container via the shared App Data scan.
        DispatchQueue.main.sync { AppDataManager.shared.scanIfNeeded() }
        let appContainer = AppDataManager.shared.containers.first { $0.bundleID == Self.voiceMemosBundleID }
        var roots: [String] = []
        if let appContainer {
            roots.append(appContainer.path)
            print("[VoiceMemos] app container: \(appContainer.path)")
        }
        // 2. The shared group container (pathleak scan +
        // identifier match — slow, background only).
        if let group = findGroupContainer() {
            roots.append(group)
            print("[VoiceMemos] group container: \(group)")
        }
        guard !roots.isEmpty else {
            finishRecordingsBlocked("Voice Memos (com.apple.VoiceMemos) was not found — its container scan came back empty. The App Data scan may still be running; come back to this page after it finishes.")
            return
        }

        // 3. Find the database under any root.
        var dbPath: String?
        var dbRoot: String?
        for root in roots {
            let handle = consumeExtension(root)
            guard handle > 0 else { continue }
            defer { releaseExtension(handle) }
            if let found = findFile(named: "CloudRecordings.db", under: root, maxDepth: 5) {
                dbPath = found
                dbRoot = root
                break
            }
        }
        guard let dbPath, let dbRoot else {
            finishRecordingsBlocked("CloudRecordings.db was not found under the Voice Memos containers. Nothing was read or written.")
            return
        }
        print("[VoiceMemos] database at \(dbPath)")

        // 4. Clone snapshot, open read-only.
        guard let clone = snapshotDatabase(dbPath: dbPath) else {
            finishRecordingsBlocked("The recordings database could not be cloned for read-only inspection. Nothing was read or written.")
            return
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = clone.path.withCString { sqlite3_open_v2($0, &handle, flags, nil) }
        guard rc == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            finishRecordingsBlocked("The cloned recordings database could not be opened. Nothing was read or written.")
            return
        }
        sqlite3_busy_timeout(handle, 1500)
        defer { sqlite3_close(handle) }
        guard probe(handle) else {
            finishRecordingsBlocked("The cloned recordings database failed its probe. Nothing was read or written.")
            return
        }

        // 5. Find the recordings table + columns.
        let tables = tableNames(handle)
        guard let table = tables.first(where: { $0.contains("CLOUDRECORDING") || $0.contains("ZRECORDING") }) else {
            finishRecordingsBlocked("No recordings table (CLOUDRECORDING / ZRECORDING) was found in the database. Nothing was read or written.")
            return
        }
        let cols = columns(of: table, db: handle)
        let pathCol = pickColumn(["ZPATH", "ZFILENAME"], from: cols)
        let labelCol = pickColumn(["ZCUSTOMLABELFORSORTING", "ZCUSTOMLABEL"], from: cols)
        let durationCol = pickColumn(["ZDURATION"], from: cols)
        guard let pathCol else {
            finishRecordingsBlocked("The recordings table has no ZPATH/ZFILENAME column. Nothing was read or written.")
            return
        }

        // 6. Read the rows, resolve each audio file. The
        // direct joins need grants on the roots held for the
        // whole loop — fileExists returns false without one.
        let searchRoots = roots + [Self.mediaRecordingsPath]
        var rootHandles: [Int64] = []
        for root in searchRoots {
            let handle = consumeExtension(root)
            if handle > 0 { rootHandles.append(handle) }
        }
        defer {
            for handle in rootHandles { releaseExtension(handle) }
        }
        var found: [VoiceMemoRecording] = []
        var select = "\"\(pathCol)\""
        if let labelCol { select += ", \"\(labelCol)\"" }
        if let durationCol { select += ", \"\(durationCol)\"" }
        let sql = "SELECT \(select) FROM \"\(table)\" ORDER BY rowid"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let rawPath = columnText(stmt, 0), !rawPath.isEmpty else { continue }
                var label: String?
                var duration: Double?
                var idx: Int32 = 1
                if labelCol != nil {
                    label = columnText(stmt, idx)
                    idx += 1
                }
                if durationCol != nil, sqlite3_column_type(stmt, idx) != SQLITE_NULL {
                    duration = sqlite3_column_double(stmt, idx)
                }
                let fileName = (rawPath as NSString).lastPathComponent
                guard Self.audioExtensions.contains((fileName as NSString).pathExtension.lowercased()) else { continue }
                guard let resolved = resolveAudioFile(rawPath: rawPath, roots: roots) else {
                    print("[VoiceMemos] audio file not found for \(rawPath)")
                    continue
                }
                let title = displayTitle(label: label, fileName: fileName)
                let size = fileSize(resolved.path)
                found.append(VoiceMemoRecording(
                    title: title,
                    duration: duration,
                    fileName: fileName,
                    filePath: resolved.path,
                    containerRoot: resolved.root,
                    size: size
                ))
            }
        }
        print("[VoiceMemos] \(found.count) recording(s) resolved")
        DispatchQueue.main.async {
            self.recordings = found
            self.recordingsState = .ready
        }
    }

    private func finishRecordingsBlocked(_ message: String) {
        print("[VoiceMemos] blocked: \(message)")
        DispatchQueue.main.async { self.recordingsState = .blocked(message) }
    }

    /// ISO-date labels ("2024-01-15 …") become
    /// "Recording <date>"; anything else keeps its label.
    private func displayTitle(label: String?, fileName: String) -> String {
        guard let label, !label.isEmpty else {
            return (fileName as NSString).deletingPathExtension
        }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        let dashParts = trimmed.split(separator: "-")
        if dashParts.count >= 3,
           dashParts[0].count == 4, dashParts[0].allSatisfy(\.isNumber),
           dashParts[1].count == 2, dashParts[1].allSatisfy(\.isNumber),
           dashParts[2].prefix(2).count == 2, dashParts[2].prefix(2).allSatisfy(\.isNumber) {
            return "Recording \(trimmed)"
        }
        return trimmed
    }

    /// Resolve one recording's audio file: direct joins
    /// first, then a bounded filename search under each root.
    private func resolveAudioFile(rawPath: String, roots: [String]) -> (path: String, root: String)? {
        if (rawPath as NSString).isAbsolutePath, FileManager.default.fileExists(atPath: rawPath) {
            return (rawPath, Self.containerRoot(ofFilePath: rawPath) ?? rawPath)
        }
        let searchRoots = roots + [Self.mediaRecordingsPath]
        for root in searchRoots {
            for base in ["", "Library", "Library/Application Support", "Media/Recordings"] {
                let candidate = base.isEmpty
                    ? (root as NSString).appendingPathComponent(rawPath)
                    : ((root as NSString).appendingPathComponent(base) as NSString).appendingPathComponent(rawPath)
                if FileManager.default.fileExists(atPath: candidate) {
                    return (candidate, root)
                }
            }
        }
        let fileName = (rawPath as NSString).lastPathComponent
        for root in searchRoots {
            let handle = consumeExtension(root)
            guard handle > 0 else { continue }
            defer { releaseExtension(handle) }
            if let found = findFile(named: fileName, under: root, maxDepth: 5) {
                return (found, root)
            }
        }
        return nil
    }

    /// The container/group root a path lives under, for the
    /// export grant. Nil for paths outside containers.
    private static func containerRoot(ofFilePath path: String) -> String? {
        for marker in ["/Containers/Data/Application/", "/Containers/Shared/AppGroup/"] {
            if let range = path.range(of: marker) {
                let after = path[range.upperBound...]
                if let slash = after.firstIndex(of: "/") {
                    return String(path[path.startIndex..<slash])
                }
            }
        }
        if path.hasPrefix(Self.mediaRecordingsPath) { return Self.mediaRecordingsPath }
        return nil
    }

    /// Find the shared group container by pathleak scan +
    /// identifier match (the fork's pattern). Slow — call
    /// off the main thread. Nil when not found.
    private func findGroupContainer() -> String? {
        let root = "/var/mobile/Containers/Shared/AppGroup"
        guard let children = wtPathleakChildren(root) else { return nil }
        for path in children {
            if wtContainerIdentifier(atPath: path) == Self.voiceMemosGroupID {
                return path
            }
        }
        return nil
    }

    /// Bounded filename search (depth-first, symlinked dirs
    /// never descended into). Nil when not found.
    private func findFile(named name: String, under root: String, maxDepth: Int) -> String? {
        findFileRecursive(named: name, dir: root, depth: 1, maxDepth: maxDepth)
    }

    private func findFileRecursive(named name: String, dir: String, depth: Int, maxDepth: Int) -> String? {
        guard depth <= maxDepth else { return nil }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        for entry in names {
            let full = (dir as NSString).appendingPathComponent(entry)
            var st = stat()
            guard lstat(full, &st) == 0 else { continue }
            let mode = st.st_mode & S_IFMT
            if mode == S_IFLNK { continue }
            if mode == S_IFREG, entry == name { return full }
            if mode == S_IFDIR,
               let found = findFileRecursive(named: name, dir: full, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }

    private func snapshotDatabase(dbPath: String) -> URL? {
        let fm = FileManager.default
        if let old = snapshotDir {
            try? fm.removeItem(at: old)
            snapshotDir = nil
        }
        let dir = fm.temporaryDirectory.appendingPathComponent("sql_snap_\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[VoiceMemos] snapshot dir failed: \(error)")
            return nil
        }
        let dest = dir.appendingPathComponent((dbPath as NSString).lastPathComponent)
        var anyCopied = false
        for suffix in ["", "-wal", "-shm"] {
            let src = dbPath + suffix
            guard fm.fileExists(atPath: src) else { continue }
            let dst = dest.path + suffix
            let ok = SaveVaultManager.cloneFile(src: src, dst: dst) || (try? fm.copyItem(atPath: src, toPath: dst)) != nil
            if ok { anyCopied = true }
        }
        guard anyCopied, fm.fileExists(atPath: dest.path) else {
            try? fm.removeItem(at: dir)
            return nil
        }
        _ = try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
        snapshotDir = dir
        return dest
    }

    private func fileSize(_ path: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: Export

    /// Copy the selected recordings into staging (one grant
    /// per container root) and zip them to this app's
    /// Documents/VoiceMemosExports/<date>.zip. The database
    /// is never written.
    func exportSelected() {
        let selected = recordings.filter { $0.isSelected }
        guard !selected.isEmpty, !isExporting else { return }
        isExporting = true
        exportMessage = nil
        exportURL = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.performExport(selected: selected)
            DispatchQueue.main.async {
                self.isExporting = false
                switch result {
                case .success(let url):
                    self.exportURL = url
                    self.exportMessage = "Exported \(selected.count) recording(s) to \(url.lastPathComponent)."
                    print("[VoiceMemos] export done: \(url.path)")
                case .failure(let error):
                    self.exportMessage = error.message
                    print("[VoiceMemos] export failed: \(error.message)")
                }
            }
        }
    }

    private func performExport(selected: [VoiceMemoRecording]) -> Result<URL, VaultError> {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("voicememos-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return .failure(VaultError(message: "Could not create export staging: \(error.localizedDescription)"))
        }
        // One grant per distinct container root.
        let roots = Array(Set(selected.map { $0.containerRoot }))
        var handles: [Int64] = []
        for root in roots {
            let handle = consumeExtension(root)
            print("[VoiceMemos] grant for export -> \(handle) (\(root))")
            if handle > 0 { handles.append(handle) }
        }
        defer {
            for handle in handles { releaseExtension(handle) }
        }
        var staged = 0
        for recording in selected {
            let safeTitle = recording.title.replacingOccurrences(of: "/", with: "-")
            let ext = (recording.fileName as NSString).pathExtension
            var destName = ext.isEmpty ? safeTitle : "\(safeTitle).\(ext)"
            var dest = staging.appendingPathComponent(destName)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                destName = ext.isEmpty ? "\(safeTitle) \(n)" : "\(safeTitle) \(n).\(ext)"
                dest = staging.appendingPathComponent(destName)
                n += 1
            }
            do {
                try fm.copyItem(atPath: recording.filePath, toPath: dest.path)
                staged += 1
            } catch {
                print("[VoiceMemos] copy failed for \(recording.fileName): \(error)")
            }
        }
        guard staged > 0 else {
            return .failure(VaultError(message: "None of the selected recordings could be copied — the details are in the Log."))
        }
        guard let outRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("VoiceMemosExports", isDirectory: true) else {
            return .failure(VaultError(message: "Could not create the exports folder."))
        }
        do {
            try fm.createDirectory(at: outRoot, withIntermediateDirectories: true)
        } catch {
            return .failure(VaultError(message: "Could not create the exports folder: \(error.localizedDescription)"))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let zipURL = outRoot.appendingPathComponent("VoiceMemos-\(formatter.string(from: Date())).zip")
        let writer = WTStoredZipWriter(url: zipURL)
        guard writer.open() else {
            return .failure(VaultError(message: "Could not create \(zipURL.lastPathComponent)."))
        }
        var zipOK = true
        let names = (try? fm.contentsOfDirectory(atPath: staging.path)) ?? []
        for name in names.sorted() {
            let full = (staging.path as NSString).appendingPathComponent(name)
            if !writer.addFile(name: name, path: full) { zipOK = false; break }
        }
        writer.close(success: zipOK)
        guard zipOK else {
            try? fm.removeItem(at: zipURL)
            return .failure(VaultError(message: "Writing the ZIP failed partway — the partial file was deleted."))
        }
        return .success(zipURL)
    }

    // MARK: AI cache

    func probeAICache() {
        guard !isProbingAI else { return }
        isProbingAI = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.performProbeAICache()
            DispatchQueue.main.async { self.isProbingAI = false }
        }
    }

    private func performProbeAICache() {
        print("[AICache] probing sizes (depth <= 4)")
        var targets: [AICacheTarget] = []
        // System groups.
        for groupID in Self.systemGroupIDs {
            let path = "/private/var/containers/Shared/SystemGroup/\(groupID)"
            targets.append(AICacheTarget(name: groupID, path: path, isSystemGroup: true))
        }
        // App containers.
        DispatchQueue.main.sync { AppDataManager.shared.scanIfNeeded() }
        for bundleID in Self.aiAppBundleIDs {
            if let container = AppDataManager.shared.containers.first(where: { $0.bundleID == bundleID }) {
                targets.append(AICacheTarget(name: bundleID, path: container.path, isSystemGroup: false))
            }
        }
        for index in targets.indices {
            let target = targets[index]
            let handle = consumeExtension(target.path)
            guard handle > 0 else {
                print("[AICache] grant refused for \(target.name) (\(handle)) — size unknown")
                continue
            }
            defer { releaseExtension(handle) }
            let stats = probeTree(path: target.path, maxDepth: 4)
            let caches = probeTree(path: (target.path as NSString).appendingPathComponent("Library/Caches"), maxDepth: -1)
            targets[index].fileCount = stats.files
            targets[index].bytes = stats.bytes
            targets[index].cachesFiles = caches.files
            targets[index].cachesBytes = caches.bytes
            targets[index].probed = true
            print("[AICache] \(target.name): \(stats.files) files, \(stats.bytes) bytes; Caches: \(caches.files) files, \(caches.bytes) bytes")
        }
        DispatchQueue.main.async {
            self.aiTargets = targets
        }
    }

    /// Delete ONLY files under Library/Caches inside the
    /// probed targets. Models live outside Library/Caches
    /// and are never touched. Reports the freed bytes.
    func deleteAICaches() {
        guard !isDeletingCache, aiTargets.contains(where: { $0.cachesBytes > 0 }) else { return }
        isDeletingCache = true
        cacheMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.performDeleteAICaches()
            DispatchQueue.main.async {
                self.isDeletingCache = false
                self.cacheMessage = result
                print("[AICache] \(result)")
            }
        }
    }

    private func performDeleteAICaches() -> String {
        var freed: Int64 = 0
        var deleted = 0
        for target in aiTargets where target.cachesBytes > 0 {
            let handle = consumeExtension(target.path)
            guard handle > 0 else {
                print("[AICache] grant refused for delete on \(target.name) (\(handle)) — skipped")
                continue
            }
            defer { releaseExtension(handle) }
            let cachesPath = (target.path as NSString).appendingPathComponent("Library/Caches")
            let (count, bytes) = deleteFilesOnly(under: cachesPath)
            deleted += count
            freed += bytes
            print("[AICache] \(target.name): deleted \(count) cache file(s), \(bytes) bytes")
        }
        // Re-probe so the sizes shown are current.
        performProbeAICache()
        if deleted == 0 {
            return "Nothing was deleted — the cache folders were already empty or their grants were refused."
        }
        return "Deleted \(deleted) cache file(s), freeing \(wtFormatSize(freed)). Models were not touched — only files under Library/Caches were deleted."
    }

    /// Delete regular files under a directory (recursively,
    /// symlinked dirs never descended into, directories
    /// kept). Returns (deleted count, freed bytes).
    private func deleteFilesOnly(under dir: String) -> (Int, Int64) {
        var count = 0
        var freed: Int64 = 0
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return (0, 0) }
        for name in names {
            let full = (dir as NSString).appendingPathComponent(name)
            var st = stat()
            guard lstat(full, &st) == 0 else { continue }
            let mode = st.st_mode & S_IFMT
            if mode == S_IFLNK { continue }
            if mode == S_IFDIR {
                let (c, b) = deleteFilesOnly(under: full)
                count += c
                freed += b
            } else if mode == S_IFREG {
                let size = Int64(st.st_size)
                if (try? FileManager.default.removeItem(atPath: full)) != nil {
                    count += 1
                    freed += size
                }
            }
        }
        return (count, freed)
    }

    // MARK: Size probe

    private struct TreeStats {
        var files = 0
        var bytes: Int64 = 0
    }

    /// File count + bytes under a path. maxDepth < 0 means
    /// unlimited. Symlinked directories are never descended
    /// into.
    private func probeTree(path: String, maxDepth: Int) -> TreeStats {
        var stats = TreeStats()
        probeTreeRecursive(dir: path, depth: 1, maxDepth: maxDepth, stats: &stats)
        return stats
    }

    private func probeTreeRecursive(dir: String, depth: Int, maxDepth: Int, stats: inout TreeStats) {
        guard maxDepth < 0 || depth <= maxDepth else { return }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for name in names {
            let full = (dir as NSString).appendingPathComponent(name)
            var st = stat()
            guard lstat(full, &st) == 0 else { continue }
            let mode = st.st_mode & S_IFMT
            if mode == S_IFLNK { continue }
            if mode == S_IFDIR {
                probeTreeRecursive(dir: full, depth: depth + 1, maxDepth: maxDepth, stats: &stats)
            } else if mode == S_IFREG {
                stats.files += 1
                stats.bytes += Int64(st.st_size)
            }
        }
    }

    // MARK: SQLite helpers (same snapshot rules as Battery)

    private func probe(_ db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master LIMIT 1", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func tableNames(_ db: OpaquePointer) -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table'", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return out
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = columnText(stmt, 0) { out.append(text) }
        }
        return out
    }

    private func columns(of table: String, db: OpaquePointer) -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\"\(table)\")"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return out
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = columnText(stmt, 1) { out.append(text) }
        }
        return out
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let raw = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: UnsafeRawPointer(raw).assumingMemoryBound(to: CChar.self))
    }

    private func pickColumn(_ candidates: [String], from available: [String]) -> String? {
        let lowered = available.map { $0.lowercased() }
        for candidate in candidates {
            if let idx = lowered.firstIndex(of: candidate.lowercased()) {
                return available[idx]
            }
        }
        return nil
    }
}
