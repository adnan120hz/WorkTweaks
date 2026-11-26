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
/// test explains itself. The root is canonicalized with
/// canonicalScanPath before scanning: pathleak's literal
/// prefix match needs the canonical /private spelling that
/// fsgetpath returns (a /var/... root can never match), and
/// the children come back in that same /private form.
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

    let scanRoot = canonicalScanPath(root)
    if scanRoot != root {
        print("(containers) canonicalized scan root: \(root) -> \(scanRoot)")
    }

    print("(containers) pathleak scan of \(scanRoot) up to inode \(baselineInode) — this can take a while…")
    let started = Date()
    let found = pathleak(scanRoot, baselineInode) ?? []
    let elapsed = Date().timeIntervalSince(started)
    print(String(format: "(containers) pathleak found %d container(s) under %@ in %.1fs.", found.count, scanRoot, elapsed))
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

// MARK: - Persistent JIT diagnostics (WTJITDiag)
//
// A bounded file that survives a SIGKILL / force-close, for
// the JIT relaunch / attach path. The in-app Log is an
// in-memory string (Console.swift, capped at 60,000 chars)
// and ObjC NSLog goes to stderr, which the Log never
// captures — after a crash both are gone, so the two JIT
// hypotheses (H1: the self-open fails, the app dies in the
// kill without relaunching; H2: the relaunch succeeds but
// the new process dies during startup self-attach) were
// indistinguishable. Every risky step now appends one
// timestamped line to this file, from BOTH Swift (the C
// helper below) and ObjC (LCSharedUtils' self-open handler,
// which writes its success line BEFORE raise(SIGKILL) —
// no Swift write can ever happen after a successful open).
//
// Location: <AppGroup>/LiveContainer/jit-diagnostics.log —
// the same root guests live in (ContainerManager.
// liveContainerRoot), so no sandbox grant is needed to
// write it: App Group containers are directly accessible.
// Cap 64 KB, oldest lines dropped first (see the C
// implementation in LCContainerPatch.m). Never logs
// passwords, tokens, or cert material — step names, bundle
// IDs, booleans, error descriptions, and timings only.
// Logging only: no gate, attach timing, serve loop,
// getReady, or launch logic is touched by this file.

enum WTJITDiag {
    static let fileName = "jit-diagnostics.log"
    static let maxBytes = 64 * 1024

    static func fileURL() -> URL? {
        ContainerManager.liveContainerRoot()?.appendingPathComponent(fileName)
    }

    /// Hand the resolved path to the C helper so the ObjC
    /// self-open handler writes to the same file. Idempotent;
    /// called early (WorkTweaksApp.init) and again before any
    /// launch. Until it runs, the C side falls back to
    /// resolving the App Group the LC way.
    static func setPathIfNeeded() {
        guard let path = fileURL()?.path else { return }
        path.withCString { WTJITDiagSetPath($0) }
    }

    /// One timestamped line ("HH:MM:SS [JIT] <step>:
    /// <detail>"). Synchronous — safe to call right before a
    /// relaunch that kills the process.
    static func append(step: String, detail: String) {
        step.withCString { cStep in
            detail.withCString { cDetail in
                WTJITDiagAppend(cStep, cDetail)
            }
        }
    }

    /// Whole file as text, or nil when there is nothing yet
    /// (missing file, or empty).
    static func readText() -> String? {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Truncate the log (delete the file; it is recreated on
    /// the next append).
    static func clear() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Copy into tmp so the share sheet can export the full
    /// file (same pattern as CrashDiagnostics.shareURL).
    static func shareURL() -> URL? {
        guard let url = fileURL(), FileManager.default.fileExists(atPath: url.path) else { return nil }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return nil }
        return dest
    }
}
