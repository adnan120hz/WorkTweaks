import Foundation
import Combine

// MARK: - PosterBoard (wallpaper data store)
//
// PosterBoard (com.apple.PosterBoard) is the system app that
// manages wallpapers and the Lock Screen. Its data lives in a
// NORMAL Application data container, so everything here is
// built on the app's proven App Data machinery — the shared
// container scan (AppDataManager.shared), the fork's
// pathleak / xattr primitives (ContainerSupport.swift), and
// one sandbox extension on the container per operation (the
// fork's consumeExtension pattern, exactly like App Data
// browsing). The container root is never granted for
// enumeration; it is found in the scan results.
//
// Inside the container the layout is:
//   Library/Application Support/PRBPosterExtensionDataStore/
//     <version>/                        (e.g. 61 — the EXISTING
//                                        highest-numbered one)
//       Extensions/
//         com.apple.WallpaperKit.CollectionsPoster/descriptors/
//           <UUID>/versions/1/contents/… (one folder per
//                                        wallpaper)
//
// The apply flow follows mond's PosterBoard implementation
// (helpers/posterboard/poster.swift):
//   - the container identifier is com.apple.PosterBoard;
//     mond searches the Application root first, then
//     Data/InternalDaemon and Data/PluginKitPlugin, reading
//     the container metadata plist when the xattr is absent —
//     the same order is used here;
//   - a .tendies package is a ZIP; descriptors inside it are
//     found by the same layout rules mond uses (a "container"
//     mirror layout, loose descriptor(s) folders, or a deep
//     search for folders holding a descriptor identifier
//     file);
//   - each descriptor's internal identifier is randomized
//     (the identifier file, the userInfo plist, Wallpaper.plist)
//     exactly like mond's randomize_id;
//   - the descriptor folder itself is copied into the
//     descriptors folder under a FRESH UUID, so it can never
//     clash with an existing wallpaper;
//   - the SQLite store (PBFPosterExtensionDataStoreSQLite
//     Database.sqlite3) is deliberately NOT touched — mond
//     doesn't touch it either; SpringBoard rebuilds its view
//     of the store on respring, which is why importing or
//     deleting always ends with the respring prompt.
// Deviations from mond, by design: mond identifies containers
// only via the metadata plist (we lead with the App Data
// scan's xattr identifier, the metadata plist is the
// fallback); mond's reset deletes EVERY descriptor (we only
// ever delete descriptors this app imported, tracked by
// receipts in our App Group container); mond grants with
// create:true helpers (we hold ONE grant on the container,
// the App Data pattern); found descriptor folders are
// de-duplicated before copying (mond's deep search can meet
// the same folder twice — once through its container folder,
// once directly).
//
// Fail-safe throughout: a refused grant, an unreadable
// package, or a failed copy produces an honest state with
// the real code/message, a partially copied descriptor is
// removed again, and nothing claims success that did not
// verify. Every step logs with a [PosterBoard] prefix.

struct PosterBoardReceipt: Codable, Identifiable {
    /// The fresh-UUID folder name created for this descriptor.
    let descriptorUUID: String
    /// The poster extension the descriptor belongs to.
    let ext: String
    /// The descriptor folder's path relative to the container
    /// root (captured at import time, store version included).
    let storeRelativePath: String
    /// The .tendies file the descriptor came from.
    let sourcePackage: String
    /// ISO 8601 import timestamp.
    let importedAt: String

    var id: String { descriptorUUID }
}

final class PosterBoardManager: ObservableObject {
    static let posterBoardBundleID = "com.apple.PosterBoard"
    static let collectionsExtension = "com.apple.WallpaperKit.CollectionsPoster"
    static let photosExtension = "com.apple.PhotosUIPrivate.PhotosPosterProvider"
    static let dataStoreRelativePath = "Library/Application Support/PRBPosterExtensionDataStore"
    /// mond's container search order: Application first (via
    /// the App Data scan), then these two roots.
    static let fallbackRoots = [
        "/var/mobile/Containers/Data/InternalDaemon",
        "/var/mobile/Containers/Data/PluginKitPlugin",
    ]

    enum LoadState {
        case idle
        case resolving
        case ready
        case blocked(String)
    }

    @Published var state: LoadState = .idle
    @Published var resolvePhase = ""
    @Published var containerPath: String?
    @Published var storeVersion: String?
    @Published var descriptorCount = 0
    @Published var receipts: [PosterBoardReceipt] = []
    @Published var isBusy = false
    @Published var lastResult: String?

    private var resolveInFlight = false

    // MARK: Receipts (our App Group container)

    private static func receiptsDirectory() -> URL? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupResolver.resolvedGroup) else {
            return nil
        }
        return groupURL.appendingPathComponent("PosterBoardImports", isDirectory: true)
    }

    func loadReceipts() {
        guard let dir = Self.receiptsDirectory() else {
            receipts = []
            print("[PosterBoard] import records unavailable — the App Group container could not be opened")
            return
        }
        let file = dir.appendingPathComponent("imports.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([PosterBoardReceipt].self, from: data) else {
            receipts = []
            return
        }
        receipts = decoded.sorted { $0.importedAt > $1.importedAt }
        print("[PosterBoard] loaded \(receipts.count) import record(s)")
    }

    private func saveReceipts() {
        guard let dir = Self.receiptsDirectory() else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let sorted = receipts.sorted { $0.importedAt > $1.importedAt }
            let data = try JSONEncoder().encode(sorted)
            try data.write(to: dir.appendingPathComponent("imports.json"))
        } catch {
            print("[PosterBoard] saving import records failed: \(error)")
        }
    }

    // MARK: Resolution

    /// The view calls this while the shared App Data scan is
    /// still running, so the page can show scan progress.
    func noteWaitingForScan() {
        if case .ready = state { return }
        guard !resolveInFlight else { return }
        state = .resolving
        resolvePhase = "Scanning containers (pathleak)…"
    }

    /// Resolve the PosterBoard container from the shared scan
    /// (plus mond's fallback roots), then read the data-store
    /// status under one grant.
    func resolve() {
        guard !resolveInFlight else { return }
        if case .ready = state { return }
        resolveInFlight = true
        state = .resolving
        resolvePhase = "Resolving the PosterBoard container…"
        print("[PosterBoard] resolving the container for \(Self.posterBoardBundleID)…")
        let scanned = AppDataManager.shared.containers
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let found = self.findContainer(in: scanned)
            DispatchQueue.main.async {
                self.resolveInFlight = false
                guard let found else {
                    print("[PosterBoard] container not found")
                    self.state = .blocked("No container with the identifier \(Self.posterBoardBundleID) was found — not in the App Data scan and not in the daemon / plug-in container roots. Nothing was written.")
                    return
                }
                self.containerPath = found
                self.refreshStatus()
            }
        }
    }

    private func setPhase(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.resolvePhase = text
        }
    }

    /// mond's search: the Application scan first (xattr
    /// identifier, then the metadata plist for candidates
    /// whose xattr could not be read), then pathleak
    /// enumeration of the InternalDaemon and PluginKitPlugin
    /// roots with the same two identification methods.
    private func findContainer(in scanned: [AppContainer]) -> String? {
        if let hit = scanned.first(where: { $0.bundleID == Self.posterBoardBundleID }) {
            print("[PosterBoard] container found in the App Data scan: \(hit.path)")
            return hit.path
        }
        for candidate in scanned where candidate.bundleID == candidate.directoryName {
            if Self.metadataIdentifier(atPath: candidate.path) == Self.posterBoardBundleID {
                print("[PosterBoard] container found via its metadata plist: \(candidate.path)")
                return candidate.path
            }
        }
        for root in Self.fallbackRoots {
            setPhase("Searching \(root)…")
            print("[PosterBoard] searching \(root)…")
            guard let children = wtPathleakChildren(root) else { continue }
            for child in children {
                let identifier = wtContainerIdentifier(atPath: child)
                if identifier == Self.posterBoardBundleID {
                    print("[PosterBoard] container found under \(root): \(child)")
                    return child
                }
                if identifier == nil,
                   Self.metadataIdentifier(atPath: child) == Self.posterBoardBundleID {
                    print("[PosterBoard] container found under \(root) via its metadata plist: \(child)")
                    return child
                }
            }
        }
        return nil
    }

    /// mond's identification fallback: the container's
    /// metadata plist (hidden name first, then the plain one),
    /// key MCMMetadataIdentifier, read under one grant.
    static func metadataIdentifier(atPath path: String) -> String? {
        let handle = consumeExtension(path)
        guard handle > 0 else { return nil }
        defer { releaseExtension(handle) }

        for name in [".com.apple.mobile_container_manager.metadata.plist",
                     "com.apple.mobile_container_manager.metadata.plist"] {
            let url = URL(fileURLWithPath: (path as NSString).appendingPathComponent(name))
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                continue
            }
            if let identifier = plist["MCMMetadataIdentifier"] as? String {
                return identifier
            }
        }
        return nil
    }

    /// Read the data-store status (version folder + descriptor
    /// count) under one grant on the container. Also used to
    /// refresh after an import or delete.
    private func refreshStatus() {
        guard let containerPath else { return }
        let handle = consumeExtension(containerPath)
        print("[PosterBoard] grant for \(containerPath) -> \(handle)")
        guard handle > 0 else {
            state = .blocked("The sandbox extension for the PosterBoard container was refused (code \(handle)). Nothing was read or written.")
            return
        }
        defer { releaseExtension(handle) }

        let storePath = (containerPath as NSString).appendingPathComponent(Self.dataStoreRelativePath)
        guard let version = Self.highestVersionFolder(in: storePath) else {
            print("[PosterBoard] data store not found at \(storePath)")
            state = .blocked("PosterBoard's data store was not found — \(storePath) is missing or has no numbered version folder. Nothing was written.")
            return
        }
        storeVersion = version
        descriptorCount = Self.descriptorCount(container: containerPath, version: version)
        state = .ready
        print("[PosterBoard] ready — store version \(version), \(descriptorCount) descriptor(s)")
    }

    /// The existing highest-numbered version folder inside the
    /// data store — never an invented one.
    private static func highestVersionFolder(in storePath: String) -> String? {
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: storePath) else {
            return nil
        }
        let numeric = children.filter { !$0.isEmpty && $0.allSatisfy { $0.isNumber } }
        return numeric.max { (Int($0) ?? 0) < (Int($1) ?? 0) }
    }

    private static func descriptorsPath(container: String, version: String, ext: String) -> String {
        ((container as NSString).appendingPathComponent(dataStoreRelativePath) as NSString)
            .appendingPathComponent(version) + "/Extensions/\(ext)/descriptors"
    }

    private static func descriptorCount(container: String, version: String) -> Int {
        var total = 0
        for ext in [collectionsExtension, photosExtension] {
            let path = descriptorsPath(container: container, version: version, ext: ext)
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: path) else { continue }
            for child in children {
                var isDirectory: ObjCBool = false
                let full = (path as NSString).appendingPathComponent(child)
                if FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory), isDirectory.boolValue {
                    total += 1
                }
            }
        }
        return total
    }

    // MARK: Import

    /// Import one .tendies package. The completion reports
    /// whether at least one descriptor was written and
    /// verified (the view then offers the respring prompt).
    func importPackage(url: URL, completion: @escaping (Bool) -> Void) {
        guard let containerPath, let version = storeVersion,
              case .ready = state, !isBusy else {
            completion(false)
            return
        }
        isBusy = true
        lastResult = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let outcome = self.performImport(url: url, containerPath: containerPath, version: version)
            DispatchQueue.main.async {
                self.isBusy = false
                self.lastResult = outcome.message
                if outcome.written > 0 {
                    self.receipts.append(contentsOf: outcome.newReceipts)
                    self.saveReceipts()
                    AppDataManager.shared.invalidateScanCache()
                    self.refreshStatus()
                }
                completion(outcome.written > 0)
            }
        }
    }

    // MARK: Install a wallpaper built here

    /// Installs a descriptor folder built by PosterBoardMaker:
    /// same grant / copy / verify / receipt path as a .tendies
    /// import, so a made wallpaper is listed and deletable
    /// exactly like an imported one. The builder already gave
    /// the descriptor a fresh random ID, so — unlike imports —
    /// the ID is NOT re-randomized here: the folder and file
    /// names match the IDs inside the plists.
    func installBuiltDescriptor(folder: URL, name: String, completion: @escaping (Bool) -> Void) {
        guard let containerPath, let version = storeVersion,
              case .ready = state, !isBusy else {
            completion(false)
            return
        }
        isBusy = true
        lastResult = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var message = ""
            var written = false
            var newReceipt: PosterBoardReceipt?
            let handle = consumeExtension(containerPath)
            print("[PosterBoard] grant for maker install -> \(handle)")
            if handle > 0 {
                defer { releaseExtension(handle) }
                let destDir = Self.descriptorsPath(container: containerPath, version: version, ext: Self.collectionsExtension)
                do {
                    try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
                    let destName = UUID().uuidString
                    let dest = (destDir as NSString).appendingPathComponent(destName)
                    try FileManager.default.copyItem(atPath: folder.path, toPath: dest)
                    let sourceCount = Self.recursiveFileCount(folder)
                    let destCount = Self.recursiveFileCount(URL(fileURLWithPath: dest))
                    if destCount == sourceCount {
                        written = true
                        newReceipt = PosterBoardReceipt(
                            descriptorUUID: destName,
                            ext: Self.collectionsExtension,
                            storeRelativePath: "\(Self.dataStoreRelativePath)/\(version)/Extensions/\(Self.collectionsExtension)/descriptors/\(destName)",
                            sourcePackage: "Wallpaper Maker — \(name)",
                            importedAt: ISO8601DateFormatter().string(from: Date())
                        )
                        message = "Created “\(name)” (\(destCount) file(s)). Respring to see it in the wallpaper gallery."
                        print("[PosterBoard] installed maker wallpaper \(destName) (\(destCount) file(s))")
                    } else {
                        try? FileManager.default.removeItem(atPath: dest)
                        message = "Verification failed for “\(name)” (\(destCount) of \(sourceCount) files) — partial copy removed, nothing was installed."
                        print("[PosterBoard] maker verify failed for \(destName) — partial copy removed")
                    }
                } catch {
                    message = "Installing “\(name)” failed: \(error.localizedDescription)"
                    print("[PosterBoard] maker install failed: \(error)")
                }
            } else {
                message = "The sandbox extension for the PosterBoard container was refused (code \(handle)). Nothing was written."
            }
            DispatchQueue.main.async {
                self.isBusy = false
                self.lastResult = message
                if written, let receipt = newReceipt {
                    self.receipts.append(receipt)
                    self.saveReceipts()
                    AppDataManager.shared.invalidateScanCache()
                    self.refreshStatus()
                }
                completion(written)
            }
        }
    }

    private struct ImportOutcome {
        var written = 0
        var failed = 0
        var newReceipts: [PosterBoardReceipt] = []
        var message = ""
    }

    private func performImport(url: URL, containerPath: String, version: String) -> ImportOutcome {
        let fm = FileManager.default
        let packageName = url.lastPathComponent
        var outcome = ImportOutcome()

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            print("[PosterBoard] could not read \(packageName)")
            outcome.message = "Could not read \(packageName)."
            return outcome
        }
        // mond's not-a-zip check: a ZIP starts with "PK".
        guard data.count >= 4, data[0] == 0x50, data[1] == 0x4B else {
            print("[PosterBoard] \(packageName) is not a zip archive")
            outcome.message = "\(packageName) is not a valid .tendies/zip archive."
            return outcome
        }
        let entries: [String: Data]
        switch DeployManager.zipEntries(from: data) {
        case .success(let dict):
            entries = dict
        case .failure(let error):
            print("[PosterBoard] zip read failed for \(packageName): \(error.message)")
            outcome.message = error.message
            return outcome
        }

        // Imports are recorded so they can be listed and
        // deleted again — without the records store there is
        // no import (the same stance Deploy takes).
        guard Self.receiptsDirectory() != nil else {
            print("[PosterBoard] import aborted — the App Group container is unavailable")
            outcome.message = "The app's group container is unavailable, so the import could not be recorded. Nothing was written."
            return outcome
        }

        // Extract to a staging folder in our own temporary
        // directory (no grant needed there).
        let staging = fm.temporaryDirectory.appendingPathComponent("posterboard-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for (name, bytes) in entries {
                if name.hasSuffix("/") { continue }
                let components = name.split(separator: "/").map(String.init)
                if components.isEmpty || components.contains("__MACOSX") { continue }
                if components.contains("..") {
                    print("[PosterBoard] package contains an unsafe path: \(name)")
                    outcome.message = "The package contains an unsafe path (\(name)) — rejected whole, nothing was written."
                    return outcome
                }
                let dest = components.reduce(staging) { $0.appendingPathComponent($1) }
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: dest)
            }
        } catch {
            print("[PosterBoard] extraction failed for \(packageName): \(error)")
            outcome.message = "Extracting \(packageName) failed: \(error.localizedDescription)"
            return outcome
        }

        let found = Self.findDescriptors(in: staging)
        let total = found.values.reduce(0) { $0 + $1.count }
        guard total > 0 else {
            print("[PosterBoard] no descriptors found in \(packageName)")
            outcome.message = "No descriptors found in \(packageName)."
            return outcome
        }
        print("[PosterBoard] \(packageName): \(total) descriptor(s) found")

        // One grant on the container for the whole import.
        let handle = consumeExtension(containerPath)
        print("[PosterBoard] grant for import -> \(handle)")
        guard handle > 0 else {
            outcome.message = "The sandbox extension for the PosterBoard container was refused (code \(handle)). Nothing was written."
            return outcome
        }
        defer { releaseExtension(handle) }

        for (ext, folders) in found {
            let destDir = Self.descriptorsPath(container: containerPath, version: version, ext: ext)
            do {
                try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            } catch {
                outcome.failed += folders.count
                print("[PosterBoard] could not create \(destDir): \(error)")
                continue
            }
            for folder in folders {
                Self.randomizeIdentifier(in: folder)
                let destName = UUID().uuidString
                let dest = (destDir as NSString).appendingPathComponent(destName)
                do {
                    try fm.copyItem(atPath: folder.path, toPath: dest)
                } catch {
                    outcome.failed += 1
                    print("[PosterBoard] copying \(folder.lastPathComponent) failed: \(error)")
                    continue
                }
                let sourceCount = Self.recursiveFileCount(folder)
                let destCount = Self.recursiveFileCount(URL(fileURLWithPath: dest))
                guard destCount == sourceCount else {
                    try? fm.removeItem(atPath: dest)
                    outcome.failed += 1
                    print("[PosterBoard] verify failed for \(destName) (\(destCount) of \(sourceCount) files) — partial copy removed")
                    continue
                }
                outcome.written += 1
                outcome.newReceipts.append(PosterBoardReceipt(
                    descriptorUUID: destName,
                    ext: ext,
                    storeRelativePath: "\(Self.dataStoreRelativePath)/\(version)/Extensions/\(ext)/descriptors/\(destName)",
                    sourcePackage: packageName,
                    importedAt: ISO8601DateFormatter().string(from: Date())
                ))
                print("[PosterBoard] imported \(destName) (\(ext), \(destCount) file(s))")
            }
        }

        if outcome.written > 0, outcome.failed == 0 {
            outcome.message = "Imported \(outcome.written) wallpaper(s) from \(packageName)."
        } else if outcome.written > 0 {
            outcome.message = "Imported \(outcome.written) wallpaper(s) from \(packageName) — \(outcome.failed) could not be written (details in the Log)."
        } else {
            outcome.message = "Import failed — none of the \(total) descriptor(s) in \(packageName) could be written. Nothing was imported."
        }
        return outcome
    }

    // MARK: Delete

    /// Delete one wallpaper this app imported: its descriptor
    /// folder is removed under a fresh grant and its record
    /// is dropped. Descriptors the app did not import are
    /// never offered here and never touched.
    func delete(receipt: PosterBoardReceipt, completion: @escaping (Bool) -> Void) {
        guard let containerPath, !isBusy else {
            completion(false)
            return
        }
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            var ok = false
            var message = ""
            let handle = consumeExtension(containerPath)
            print("[PosterBoard] grant for delete -> \(handle)")
            if handle <= 0 {
                message = "The sandbox extension for the PosterBoard container was refused (code \(handle)). Nothing was deleted."
            } else {
                let target = (containerPath as NSString).appendingPathComponent(receipt.storeRelativePath)
                if fm.fileExists(atPath: target) {
                    do {
                        try fm.removeItem(atPath: target)
                        ok = !fm.fileExists(atPath: target)
                        message = ok
                            ? "Deleted the wallpaper from \(receipt.sourcePackage)."
                            : "Deleting \(receipt.descriptorUUID) could not be verified."
                        print("[PosterBoard] delete \(target) -> \(ok ? "ok" : "unverified")")
                    } catch {
                        message = "Deleting \(receipt.descriptorUUID) failed: \(error.localizedDescription)"
                        print("[PosterBoard] delete failed for \(target): \(error)")
                    }
                } else {
                    ok = true
                    message = "That wallpaper was already gone — its import record was removed."
                    print("[PosterBoard] delete target already gone: \(target)")
                }
                releaseExtension(handle)
            }
            DispatchQueue.main.async {
                self.isBusy = false
                self.lastResult = message
                if ok {
                    self.receipts.removeAll { $0.id == receipt.id }
                    self.saveReceipts()
                    AppDataManager.shared.invalidateScanCache()
                    self.refreshStatus()
                }
                completion(ok)
            }
        }
    }

    // MARK: Package layout (mond's find_descriptors)

    /// Find descriptor folders inside an extracted package.
    /// Returns extension id → descriptor folder URLs, using
    /// mond's layout rules: a "container" mirror layout, loose
    /// descriptor(s) / video-descriptor(s) folders, or a deep
    /// search for descriptor containers and for folders that
    /// hold a descriptor identifier file.
    private static func findDescriptors(in root: URL) -> [String: [URL]] {
        let fm = FileManager.default
        var result: [String: [URL]] = [:]
        guard let top = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else {
            return result
        }

        // Container layout: <root>/container/Library/…/PRBPoster
        // ExtensionDataStore/<version>/Extensions/<ext>/descriptors
        if let containerDir = top.first(where: { $0.lastPathComponent.lowercased() == "container" }) {
            let storeDir = containerDir
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("PRBPosterExtensionDataStore")
            if let versions = try? fm.contentsOfDirectory(at: storeDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                for versionDir in versions where isNumericName(versionDir.lastPathComponent) {
                    let extRoot = versionDir.appendingPathComponent("Extensions")
                    guard let exts = try? fm.contentsOfDirectory(at: extRoot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
                    for extDir in exts {
                        let descriptors = extDir.appendingPathComponent("descriptors")
                        if fm.fileExists(atPath: descriptors.path) {
                            result[extDir.lastPathComponent, default: []].append(contentsOf: descriptorFolders(in: descriptors))
                        }
                    }
                }
            }
            if !result.isEmpty { return result }
        }

        for dir in top {
            switch dir.lastPathComponent.lowercased() {
            case "video-descriptor", "video-descriptors":
                result[photosExtension, default: []].append(contentsOf: descriptorFolders(in: dir))
            case "descriptor", "descriptors", "ordered-descriptor", "ordered-descriptors":
                result[collectionsExtension, default: []].append(contentsOf: descriptorFolders(in: dir))
            default:
                continue
            }
        }
        if !result.isEmpty { return result }

        // The package root itself can be one bare descriptor.
        if isDescriptor(root) {
            result[collectionsExtension, default: []].append(root)
            return result
        }

        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let dir as URL in enumerator {
                guard dir.lastPathComponent != "__MACOSX",
                      (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if isDescriptorContainer(dir) {
                    let ext = dir.lastPathComponent.lowercased().hasPrefix("video") ? photosExtension : collectionsExtension
                    result[ext, default: []].append(contentsOf: descriptorFolders(in: dir))
                } else if isDescriptor(dir) {
                    let ext = dir.lastPathComponent.lowercased().hasPrefix("video") ? photosExtension : collectionsExtension
                    result[ext, default: []].append(dir)
                }
            }
        }

        // De-duplicate: the deep search can meet the same
        // folder twice (once through its container folder,
        // once directly), and importing it twice would create
        // two copies of one wallpaper.
        var seen = Set<String>()
        for ext in Array(result.keys) {
            result[ext] = result[ext]?.filter { seen.insert($0.standardizedFileURL.path).inserted }
        }
        return result
    }

    private static func descriptorFolders(in dir: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else {
            return []
        }
        return children.filter { child in
            child.lastPathComponent != "__MACOSX"
                && (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func isDescriptorContainer(_ dir: URL) -> Bool {
        switch dir.lastPathComponent.lowercased() {
        case "descriptor", "descriptors", "ordered-descriptor", "ordered-descriptors",
             "video-descriptor", "video-descriptors":
            return true
        default:
            return false
        }
    }

    private static func isDescriptor(_ dir: URL) -> Bool {
        guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return false
        }
        return children.contains { $0.lastPathComponent == "com.apple.posterkit.provider.descriptor.identifier" }
    }

    private static func isNumericName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isNumber }
    }

    // MARK: Identifier randomization (mond's randomize_id)

    /// Give the descriptor a fresh internal identifier so it
    /// cannot clash with an existing wallpaper: the identifier
    /// file gets the new number as text, and the two plists
    /// that carry the identifier get the same value.
    private static func randomizeIdentifier(in folder: URL) {
        let newID = Int.random(in: 9999...99999)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
        for case let file as URL in enumerator {
            switch file.lastPathComponent.lowercased() {
            case "com.apple.posterkit.provider.descriptor.identifier":
                try? String(newID).data(using: .utf8)?.write(to: file)
            case "com.apple.posterkit.provider.contents.userinfo":
                setPlistValue(key: "wallpaperRepresentingIdentifier", value: newID, at: file)
            case "wallpaper.plist":
                setPlistValue(key: "identifier", value: newID, at: file)
            default:
                break
            }
        }
        print("[PosterBoard] randomized the identifier of \(folder.lastPathComponent) to \(newID)")
    }

    private static func setPlistValue(key: String, value: Any, at file: URL) {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: file.path),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return }
        plist[key] = value
        guard let updated = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? updated.write(to: file)
    }

    /// Recursive regular-file count, used to verify a copied
    /// descriptor arrived complete.
    private static func recursiveFileCount(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: []) else {
            return 0
        }
        var count = 0
        for case let file as URL in enumerator {
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
        return count
    }
}
