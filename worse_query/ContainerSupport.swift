import Foundation
import Darwin

// MARK: - Container support (Gestalt-Tweak fork primitives)
//
// Everything in this file is the Gestalt-Tweak fork's own
// machinery, the same code the worse_query PoC ships:
//
//  - Grants go through `consumeExtension` / `releaseExtension`
//    (SandboxBridge.swift), the direct port of the fork's
//    ContentView.consumeExtension: worse_query(path, group,
//    alt_flags, create_dir) with alt_flags = true ONLY for
//    AppGroup paths on iOS 26 and create_dir = false — the only
//    argument pattern the fork ever uses.
//  - Container enumeration is the fork's pathleak (pathleak.m):
//    a fresh temp file's inode is the scan cap, and fsgetpath
//    brute-forces inodes 1...cap, returning the filter path's
//    direct children. The fork's ContentView calls this its
//    "reliable, but insanely slow" method; for container roots
//    it is the ONLY method the fork offers on iOS 27 (its
//    parentdir grant works, in the fork's own words, "only on
//    directories that can get a parent directory extension
//    (AppGroup and System on 27.x)" — a grant on
//    /var/mobile/Containers/Data/Application is refused by the
//    kernel with -6, so this file never attempts one).
//  - A container's identifier is read the fork's way
//    (ContentView.leakPaths): consume an extension on the
//    container directory itself, then getxattr(
//    "com.apple.containermanager.identifier"), then release.

/// Fork leakPaths enumeration: the direct children of `root`
/// found by pathleak, or nil when the baseline inode could not
/// be established. Slow by design (one fsgetpath per inode up
/// to the baseline) — call off the main thread. Logs the method,
/// the cap, the elapsed time, and the hit count so a device
/// test explains itself.
func wtPathleakChildren(_ root: String) -> [String]? {
    let files = FileManager.default
    let baselineURL = files.temporaryDirectory.appendingPathComponent(".baseline_\(UUID().uuidString)")
    var baselineInode: UInt64 = 0
    do {
        try "helloworld".write(to: baselineURL, atomically: true, encoding: .utf8)
        var baselineInfo = stat()
        if stat(baselineURL.path, &baselineInfo) == 0 {
            baselineInode = baselineInfo.st_ino
            print("(containers) baseline: \(baselineInode)")
        }
        try files.removeItem(at: baselineURL)
    } catch {
        print("(containers) failed to get baseline inode: \(error)")
    }
    guard baselineInode > 0 else { return nil }

    print("(containers) pathleak scan of \(root) up to inode \(baselineInode) — this can take a while…")
    let started = Date()
    let found = pathleak(root, baselineInode) ?? []
    let elapsed = Date().timeIntervalSince(started)
    print(String(format: "(containers) pathleak found %d container(s) under %@ in %.1fs.", found.count, root, elapsed))
    return found.sorted()
}

/// Fork identifier read: grant the container directory itself
/// (consumeExtension, the fork's argument pattern), read the
/// "com.apple.containermanager.identifier" xattr, release.
/// Returns nil when the grant is refused or the xattr is absent.
func wtContainerIdentifier(atPath path: String) -> String? {
    let handle = consumeExtension(path)
    guard handle > 0 else { return nil }
    defer { releaseExtension(handle) }

    var buf = [CChar](repeating: 0, count: 512)
    let len = getxattr(path, "com.apple.containermanager.identifier", &buf, 511, 0, 0)
    guard len > 0 else { return nil }
    return String(cString: buf)
}

/// Human-friendly byte size for container/file rows.
func wtFormatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
