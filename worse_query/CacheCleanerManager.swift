import Foundation
import Combine

// MARK: - Cache Data Cleaner (manager)
//
// Deletes the cache an app leaves inside its data container,
// in exactly the two places that are safe to empty:
//
//  - Library/Caches  (downloaded images, network responses,
//    temporary databases, processed files)
//  - tmp             (temporary files the system is supposed
//    to clear by itself, but often doesn't)
//
// Nothing else is ever touched: the folders themselves stay in
// place, and Documents and the rest of Library are never
// deleted — emptying those would break the app.
//
// Access uses the same proven machinery as App Data: the
// container list is the shared App Data scan (pathleak), and
// each measure / clean operation runs under ONE short
// consumeExtension grant on the container directory
// (grant → work → release), the fork's own pattern. Sizes are
// measured by walking the folder; cleaning removes the
// folder's top-level contents one by one and counts what
// could not be removed instead of hiding it.
//
// Every step logs with a [CacheCleaner] prefix so a device
// test explains itself in the Log tab.

/// The two cache locations inside a container, in display
/// order. The relative paths are fixed — they are the whole
/// safety contract of this feature.
enum CacheLocation: String, CaseIterable, Identifiable {
    case libraryCaches
    case tmp

    var id: String { rawValue }

    /// Path relative to the container root.
    var relativePath: String {
        switch self {
        case .libraryCaches: return "Library/Caches"
        case .tmp: return "tmp"
        }
    }

    var displayName: String {
        switch self {
        case .libraryCaches: return "Library/Caches"
        case .tmp: return "tmp"
        }
    }
}

struct CacheFolderStat {
    /// The folder exists inside the container.
    var exists: Bool = false
    /// Total size of regular files below the folder.
    var size: Int64 = 0
    /// Number of regular files below the folder.
    var fileCount: Int = 0
}

struct CacheCleanResult {
    /// Bytes freed across the cleaned folders (measured
    /// before vs. after, so it never overstates).
    var freedBytes: Int64 = 0
    /// Top-level entries removed.
    var removedCount: Int = 0
    /// Top-level entries that could not be removed (in use,
    /// protected, or owned by the system).
    var failedCount: Int = 0
}

final class CacheCleanerManager: ObservableObject {
    @Published var stats: [CacheLocation: CacheFolderStat] = [:]
    @Published var isMeasuring = false
    @Published var isCleaning = false
    @Published var didMeasure = false
    @Published var statusMessage: String?
    @Published var lastResult: CacheCleanResult?

    private var measuredContainerPath: String?

    /// The full path of one cache location inside a container.
    /// Built only from the fixed relative paths above.
    private func folderPath(container: AppContainer, location: CacheLocation) -> String {
        (container.path as NSString).appendingPathComponent(location.relativePath)
    }

    /// Defense in depth before anything is deleted: the path
    /// being emptied must sit strictly inside this container
    /// and must end with one of the two fixed relative paths.
    private func isSafeCachePath(_ path: String, container: AppContainer) -> Bool {
        let standardized = (path as NSString).standardizingPath
        guard standardized.hasPrefix(container.path + "/") else { return false }
        return CacheLocation.allCases.contains {
            standardized == folderPath(container: container, location: $0)
        }
    }

    // MARK: Measure

    func measureIfNeeded(container: AppContainer) {
        if !didMeasure || measuredContainerPath != container.path {
            measure(container: container)
        }
    }

    func measure(container: AppContainer) {
        guard !isMeasuring, !isCleaning else { return }
        isMeasuring = true
        didMeasure = false
        statusMessage = nil
        print("[CacheCleaner] measuring \(container.bundleID) (\(container.path))")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let handle = consumeExtension(container.path)
            print("[CacheCleaner] grant for \(container.path) -> \(handle)")
            var measured: [CacheLocation: CacheFolderStat] = [:]
            if handle > 0 {
                for location in CacheLocation.allCases {
                    measured[location] = Self.measureFolder(
                        atPath: self.folderPath(container: container, location: location)
                    )
                }
                releaseExtension(handle)
            }
            DispatchQueue.main.async {
                self.isMeasuring = false
                if handle > 0 {
                    self.stats = measured
                    self.didMeasure = true
                    self.measuredContainerPath = container.path
                    for location in CacheLocation.allCases {
                        let stat = measured[location] ?? CacheFolderStat()
                        print("[CacheCleaner] \(container.bundleID) \(location.displayName): exists=\(stat.exists), \(stat.fileCount) file(s), \(stat.size) byte(s)")
                    }
                } else {
                    self.statusMessage = "The sandbox extension for this container was refused (grant \(handle)), so its cache could not be measured."
                }
            }
        }
    }

    /// Walk one folder and total its regular files. Runs under
    /// the caller's grant.
    private static func measureFolder(atPath path: String) -> CacheFolderStat {
        let files = FileManager.default
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return CacheFolderStat(exists: false)
        }
        var stat = CacheFolderStat(exists: true)
        guard let enumerator = files.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            return stat
        }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            stat.fileCount += 1
            stat.size += Int64(values.fileSize ?? 0)
        }
        return stat
    }

    // MARK: Clean

    /// Empty the given cache locations of one container: the
    /// folders stay, their contents go. Files that refuse
    /// removal are counted and logged, never hidden.
    func clean(container: AppContainer, locations: [CacheLocation]) {
        guard !isCleaning, !isMeasuring, !locations.isEmpty else { return }
        isCleaning = true
        lastResult = nil
        statusMessage = nil
        print("[CacheCleaner] cleaning \(container.bundleID): \(locations.map { $0.displayName }.joined(separator: ", "))")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let handle = consumeExtension(container.path)
            print("[CacheCleaner] grant for \(container.path) -> \(handle)")
            var result = CacheCleanResult()
            var after: [CacheLocation: CacheFolderStat] = [:]
            if handle > 0 {
                let files = FileManager.default
                for location in locations {
                    let path = self.folderPath(container: container, location: location)
                    guard self.isSafeCachePath(path, container: container) else {
                        print("[CacheCleaner] REFUSED unsafe path: \(path)")
                        result.failedCount += 1
                        continue
                    }
                    let before = Self.measureFolder(atPath: path)
                    guard before.exists else {
                        print("[CacheCleaner] \(location.displayName) does not exist in \(container.bundleID) — skipped")
                        after[location] = before
                        continue
                    }
                    let entries = (try? files.contentsOfDirectory(atPath: path)) ?? []
                    for entry in entries {
                        let entryPath = (path as NSString).appendingPathComponent(entry)
                        do {
                            try files.removeItem(atPath: entryPath)
                            result.removedCount += 1
                        } catch {
                            result.failedCount += 1
                            print("[CacheCleaner] could not remove \(entryPath): \(error.localizedDescription)")
                        }
                    }
                    let measuredAfter = Self.measureFolder(atPath: path)
                    after[location] = measuredAfter
                    let freed = max(Int64(0), before.size - measuredAfter.size)
                    result.freedBytes += freed
                    print("[CacheCleaner] \(container.bundleID) \(location.displayName): freed \(freed) byte(s), \(result.failedCount) failure(s) so far")
                }
                releaseExtension(handle)
            }
            DispatchQueue.main.async {
                self.isCleaning = false
                if handle > 0 {
                    self.lastResult = result
                    for (location, stat) in after {
                        self.stats[location] = stat
                    }
                    print("[CacheCleaner] done \(container.bundleID): freed \(result.freedBytes) byte(s), removed \(result.removedCount), failed \(result.failedCount)")
                } else {
                    self.statusMessage = "The sandbox extension for this container was refused (grant \(handle)), so nothing was cleaned."
                }
            }
        }
    }

    /// Total size across the measured locations.
    func totalSize(locations: [CacheLocation]) -> Int64 {
        locations.reduce(Int64(0)) { $0 + (stats[$1]?.size ?? 0) }
    }
}
