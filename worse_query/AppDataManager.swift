import Foundation
import Combine

// MARK: - App Data (container browser / editor)
//
// Browse and edit the files inside app data containers under
// /var/mobile/Containers/Data/Application, using ONLY the
// Gestalt-Tweak fork's machinery, as restored in
// ContainerSupport.swift:
//
//  - The container list comes from the fork's pathleak scan
//    (wtPathleakChildren). A grant on the container root itself
//    is refused by the kernel with -6, so — exactly like the
//    fork — this file never attempts one to enumerate.
//  - A container's app is identified the fork's way
//    (wtContainerIdentifier): grant the container directory,
//    read the com.apple.containermanager.identifier xattr,
//    release.
//  - Browsing holds ONE grant on the opened container (the
//    fork's consumeExtension argument pattern, via
//    SandboxBridge) and works under it with FileManager; the
//    grant is released when the container is left.
//  - Edits are written in place (truncate + write through a
//    FileHandle) — never atomic replacement, the same lesson
//    the MobileGestalt writer learned.
//
// Every step logs with an [AppData] prefix so a device test
// explains itself in the Log tab.

struct AppContainer: Identifiable {
    /// Full path of the container directory (unique).
    let path: String
    /// Bundle id from the container xattr; falls back to the
    /// directory (UUID) name when the xattr can't be read.
    let bundleID: String
    /// The container directory's own name (a UUID).
    let directoryName: String
    /// Top-level item count, when it could be read.
    var itemCount: Int?

    var id: String { path }
}

struct AppDataEntry: Identifiable {
    let name: String
    /// Full path of the entry.
    let path: String
    let isDirectory: Bool
    /// File size in bytes (0 for directories).
    let size: Int64

    var id: String { path }
}

final class AppDataManager: ObservableObject {
    static let rootPath = "/var/mobile/Containers/Data/Application"

    @Published var containers: [AppContainer] = []
    @Published var isScanning = false
    @Published var didScan = false
    @Published var scanPhase = ""
    @Published var scanSummary: String?

    // MARK: Scan

    func scanIfNeeded() {
        if !didScan && !isScanning {
            rescan()
        }
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        didScan = false
        scanSummary = nil
        scanPhase = "Scanning containers (pathleak)…"
        print("[AppData] scan started for \(Self.rootPath)")

        let started = Date()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let found = wtPathleakChildren(Self.rootPath) ?? []
            let scanElapsed = Date().timeIntervalSince(started)
            print(String(format: "[AppData] pathleak returned %d path(s) in %.1fs", found.count, scanElapsed))

            var seen = Set<String>()
            var unique: [String] = []
            for path in found where seen.insert(path).inserted {
                unique.append(path)
            }

            DispatchQueue.main.async {
                self.scanPhase = "Identifying containers…"
            }

            var result: [AppContainer] = []
            for (index, path) in unique.enumerated() {
                let directoryName = (path as NSString).lastPathComponent
                let bundleID = wtContainerIdentifier(atPath: path)
                let count = Self.topLevelCount(atPath: path)
                print("[AppData] container \(directoryName): \(bundleID ?? "no identifier")\(count.map { ", \($0) item(s)" } ?? "")")
                result.append(AppContainer(
                    path: path,
                    bundleID: bundleID ?? directoryName,
                    directoryName: directoryName,
                    itemCount: count
                ))
                if index % 4 == 0 || index == unique.count - 1 {
                    let phase = "Identifying containers… \(index + 1) of \(unique.count)"
                    DispatchQueue.main.async {
                        self.scanPhase = phase
                    }
                }
            }
            result.sort {
                $0.bundleID.localizedCaseInsensitiveCompare($1.bundleID) == .orderedAscending
            }

            let totalElapsed = Date().timeIntervalSince(started)
            DispatchQueue.main.async {
                self.containers = result
                self.isScanning = false
                self.didScan = true
                self.scanSummary = String(format: "%d container(s) found in %.1fs.", result.count, totalElapsed)
                print(String(format: "[AppData] scan finished: %d container(s) in %.1fs", result.count, totalElapsed))
            }
        }
    }

    /// Top-level entry count under one short grant, the fork's
    /// leakPaths pattern (grant → use → release). Nil when the
    /// grant is refused or the listing fails.
    private static func topLevelCount(atPath path: String) -> Int? {
        let handle = consumeExtension(path)
        guard handle > 0 else { return nil }
        defer { releaseExtension(handle) }
        return try? FileManager.default.contentsOfDirectory(atPath: path).count
    }

    // MARK: Container grant session

    private var activeHandle: Int64 = -1
    private(set) var activeContainerPath: String?

    /// Acquire (or keep) the browsing grant for a container.
    /// Idempotent for the container already being browsed.
    @discardableResult
    func enterContainer(_ container: AppContainer) -> Bool {
        if activeHandle > 0 && activeContainerPath == container.path {
            return true
        }
        leaveContainer()
        let handle = consumeExtension(container.path)
        print("[AppData] grant for \(container.path) -> \(handle)")
        guard handle > 0 else { return false }
        activeHandle = handle
        activeContainerPath = container.path
        return true
    }

    /// Release the browsing grant, if one is held.
    func leaveContainer() {
        if activeHandle > 0 {
            releaseExtension(activeHandle)
            print("[AppData] released grant for \(activeContainerPath ?? "?")")
        }
        activeHandle = -1
        activeContainerPath = nil
    }

    // MARK: File operations (all under the browsing grant)

    /// Directory listing: folders first, then files, each
    /// sorted by name. Hidden files are included — app data
    /// containers keep real content in dotfiles.
    func listDirectory(_ path: String) -> [AppDataEntry] {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: path) else {
            print("[AppData] listing failed: \(path)")
            return []
        }
        var entries: [AppDataEntry] = []
        for name in names {
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard files.fileExists(atPath: fullPath, isDirectory: &isDirectory) else { continue }
            var size: Int64 = 0
            if !isDirectory.boolValue,
               let attributes = try? files.attributesOfItem(atPath: fullPath),
               let fileSize = attributes[.size] as? NSNumber {
                size = fileSize.int64Value
            }
            entries.append(AppDataEntry(
                name: name,
                path: fullPath,
                isDirectory: isDirectory.boolValue,
                size: size
            ))
        }
        entries.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        print("[AppData] listed \(path): \(entries.count) item(s)")
        return entries
    }

    func readFileData(_ path: String) -> Data? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("[AppData] read failed: \(path)")
            return nil
        }
        print("[AppData] read \(path) (\(data.count) bytes)")
        return data
    }

    /// Save text to a file, writing in place (truncate + write
    /// through a FileHandle, no atomic replacement). With
    /// `isNew` the file is created first — creation happens
    /// under the same browsing grant.
    func saveText(path: String, text: String, isNew: Bool) -> Bool {
        let data = Data(text.utf8)
        if isNew {
            guard FileManager.default.createFile(atPath: path, contents: nil) else {
                print("[AppData] create failed: \(path)")
                return false
            }
            print("[AppData] created file: \(path)")
        }
        guard let handle = FileHandle(forWritingAtPath: path) else {
            print("[AppData] open for writing failed: \(path)")
            return false
        }
        do {
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            print("[AppData] saved \(path) (\(data.count) bytes)")
            return true
        } catch {
            print("[AppData] write failed for \(path): \(error)")
            try? handle.close()
            return false
        }
    }

    /// Create a subdirectory in the browsed directory.
    func createFolder(path: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
            print("[AppData] created folder: \(path)")
            return true
        } catch {
            print("[AppData] create folder failed for \(path): \(error)")
            return false
        }
    }
}
