import Foundation
import Darwin

/// The App Group this build is actually provisioned with.
/// It must match `worse_query.entitlements` — changing this string alone
/// (without creating and provisioning a new App Group in Xcode) breaks
/// the sandbox escape, so it stays as the original worse_query group.
let workGestaltAppGroup = "group.cc.forcequit.worse-query"

// MARK: - App Group resolution

/// worse_query returns -1 ("failed to access group") when the app has no
/// accessible container for the group identifier it is given. Which groups
/// the running app can access is decided by the entitlements it was
/// *signed* with — sideload signers routinely rewrite bundle ids (e.g.
/// appending the team id) and rewrite or strip app groups entirely.
///
/// So the resolver does not guess blindly. It reads the groups in this
/// order:
///   1. The RUNNING process's own signed entitlements (csops,
///      via TaskEntitlements.c) — the authoritative source.
///      This is the only source that exists when there is no
///      provisioning profile at all, e.g. under LiveContainer, where
///      the guest app runs inside the host process with the host's
///      entitlements.
///   2. The app's embedded provisioning profile, whose Entitlements
///      section lists the application-groups the signed app has.
///   3. The configured value, signer-style derivations from the
///      (rewritten) bundle id, and the well-known defaults.
///
/// The escape itself does not care which group it uses — any group
/// whose container the kernel will grant an extension for works as
/// the vehicle — so every worse_query call tries the candidates in
/// order until one returns a handle (multi-group fallback), instead
/// of betting everything on a single group.
enum AppGroupResolver {
    private static let defaultsKey = "worktweaks.appGroupID"

    static var configuredGroup: String {
        get {
            let saved = UserDefaults.standard.string(forKey: defaultsKey)
            return (saved?.isEmpty == false) ? saved! : workGestaltAppGroup
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    // MARK: Live task entitlements

    /// The application-groups the RUNNING process is actually entitled
    /// to, read from the kernel (csops, see TaskEntitlements.c).
    /// Unlike the profile below, this needs no
    /// embedded.mobileprovision — it is what the kernel really
    /// granted this process, whatever signer or host (SideStore,
    /// AltStore, LiveContainer) put it there.
    static func taskAppGroups() -> [String] {
        guard let data = wtTaskEntitlements() else {
            print("[AppGroup] csops: no entitlements blob (errno \(wtTaskEntitlementsErrno()))")
            return []
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            print("[AppGroup] csops: blob \(data.count) bytes, plist parse failed")
            return []
        }
        return plist["com.apple.security.application-groups"] as? [String] ?? []
    }

    // MARK: Signed profile

    /// Entitlements parsed out of the app's embedded.mobileprovision.
    static func signedEntitlements() -> [String: Any]? {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let xmlStart = data.range(of: Data("<?xml".utf8)),
              let plistEnd = data.range(of: Data("</plist>".utf8), options: .backwards) else {
            return nil
        }
        let plistData = data[xmlStart.lowerBound..<plistEnd.upperBound]
        guard let profile = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return profile["Entitlements"] as? [String: Any]
    }

    /// The application-groups the signed app is actually entitled to.
    static var signedAppGroups: [String] {
        signedEntitlements()?["com.apple.security.application-groups"] as? [String] ?? []
    }

    // MARK: Candidates

    /// Group names signers commonly derive when they uniquify an app with
    /// a free team id: the bundle id gains a suffix (seen in the wild:
    /// cc.forcequit.worse-query.NGTRRNDQDU) and groups are rewritten the
    /// same way. Generate those shapes so they get probed too.
    static func derivedCandidates() -> [String] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        var out: [String] = ["group." + bundleID]
        let parts = bundleID.split(separator: ".")
        if parts.count >= 4, let suffix = parts.last {
            out.append("\(workGestaltAppGroup).\(suffix)")
            out.append("group.\(suffix).cc.forcequit.worse-query")
            out.append("\(configuredGroup).\(suffix)")
        }
        return out
    }

    static var candidates: [String] {
        var list = taskAppGroups()
        list.append(contentsOf: signedAppGroups)
        list.append(configuredGroup)
        list.append(contentsOf: derivedCandidates())
        list.append("group.cc.forcequit.worse-query")
        list.append("group.cc.forcequit.workgestalt")
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    static func probe() -> [(group: String, url: URL?)] {
        candidates.map { group in
            (group, FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group))
        }
    }

    /// First candidate whose container actually resolves; falls back to the
    /// configured value so the caller still surfaces the -1 error.
    static var resolvedGroup: String {
        for entry in probe() where entry.url != nil {
            return entry.group
        }
        return configuredGroup
    }

    /// Full diagnostics, once per launch — so the Log always shows
    /// what the kernel really granted this process, without having
    /// to open Sandbox → App Group first.
    private static var diagnosticsLogged = false
    static func logDiagnosticsOnce() {
        guard !diagnosticsLogged else { return }
        diagnosticsLogged = true
        logDiagnostics()
    }

    static func logDiagnostics() {
        let entitlements = signedEntitlements()
        print("[AppGroup] bundle id: \(Bundle.main.bundleIdentifier ?? "?")")
        print("[AppGroup] application-identifier: \(entitlements?["application-identifier"] as? String ?? "?")")
        let taskGroups = taskAppGroups()
        if taskGroups.isEmpty {
            print("[AppGroup] task groups: NONE (csops — the running process reports no application-groups entitlement)")
        } else {
            for group in taskGroups {
                print("[AppGroup] task group: \(group)")
            }
        }
        let groups = signedAppGroups
        if groups.isEmpty {
            print("[AppGroup] signed groups: NONE - the provisioning profile in this install contains no application-groups entitlement.")
            print("[AppGroup] VERDICT: no group name typed into this app can create a container it is not entitled to. The IPA must be re-signed with a profile that includes an App Group (e.g. Xcode with the App Groups capability for your team, or a signing service/profile that keeps application-groups).")
        } else {
            for group in groups {
                print("[AppGroup] signed group: \(group)")
            }
        }
        print("[AppGroup] configured: \(configuredGroup)")
        for entry in probe() {
            if let url = entry.url {
                print("[AppGroup] OK   \(entry.group) -> \(url.path)")
            } else {
                print("[AppGroup] FAIL \(entry.group) (no container)")
            }
        }
        print("[AppGroup] using: \(resolvedGroup)")
    }
}

/// Multi-group fallback: try each candidate App Group in turn until
/// one returns a handle. A failed attempt returns a negative code and
/// consumes nothing, so retrying with the next group is safe — the
/// only handle ever returned (and ever released) is a positive one.
func consumeExtension(_ path: String, create: Bool = false) -> Int64 {
    let useAltFlags = path.contains("/var/mobile/Containers/Shared/AppGroup") &&
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26

    var lastFailure: Int64 = -1
    for group in AppGroupResolver.candidates {
        let handle = worse_query(path, group, useAltFlags, create)
        if handle > 0 {
            print("[AppGroup] grant via \(group): handle \(handle)")
            return handle
        }
        print("[AppGroup] grant via \(group) failed: \(handle)")
        lastFailure = handle
    }

    // No candidate worked — report the last failure code the same way
    // a single attempt used to be reported.
    switch lastFailure {
    case -1: print("failed to access group!")
    case -2: print("failed to resolve functions!")
    case -3: print("failed to create query!")
    case -4: print("failed to create symlink!")
    case -5: print("query rejected!")
    case -6: print("kernel refused extension issue!")
    case -255: print("target doesn't exist!")
    default: print("handle: \(lastFailure)")
    }

    return lastFailure
}

/// The gestalt-directory grant (mond's grant_mg), with the same
/// multi-group fallback. The alt_flags value matches the original
/// mond port: true on iOS 26, false otherwise.
func consumeGestaltExtension() -> Int64 {
    let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    var lastFailure: Int64 = -1
    for group in AppGroupResolver.candidates {
        let handle = worse_query(MGPaths.gestaltDir, group, major == 26, false)
        if handle > 0 {
            print("[AppGroup] mg grant via \(group): handle \(handle)")
            return handle
        }
        print("[AppGroup] mg grant via \(group) failed: \(handle)")
        lastFailure = handle
    }
    return lastFailure
}

func releaseExtension(_ handle: Int64) {
    guard handle > 0 else {
        print("sandbox extension hasn't been consumed!")
        return
    }
    worse_query_release(handle)
    print("released sandbox extension!")
}

// MARK: - Path Leak

/// Canonical spelling of a pathleak scan target.
///
/// pathleak (pathleak.m, fork code) matches fsgetpath results
/// against the handed path by literal prefix, and fsgetpath
/// returns canonical paths: on iOS the data volume mounts at
/// /private/var and /var is a symlink to it, so fsgetpath never
/// returns a path starting with /var/. A scan target spelled
/// /var/... therefore matches nothing (the App Data container
/// scan ran the full inode range and found 0 containers this
/// way). Resolve the target at our call boundary instead —
/// realpath() first, the /var -> /private spelling rewrite as
/// the fallback for targets that cannot be resolved.
func canonicalScanPath(_ path: String) -> String {
    var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
    if realpath(path, &buf) != nil {
        return String(cString: buf)
    }
    if path.hasPrefix("/var/") {
        return "/private" + path
    }
    return path
}

func leakPaths(_ filter: String) {
    let scanFilter = canonicalScanPath(filter)
    if scanFilter != filter {
        print("canonicalized scan path: \(filter) -> \(scanFilter)")
    }
    let files = FileManager.default
    let baselineURL = files.temporaryDirectory.appendingPathComponent(".baseline_\(UUID().uuidString)")
    var baselineInode: UInt64 = 0

    do {
        try "helloworld".write(to: baselineURL, atomically: true, encoding: .utf8)
        var baselineInfo = stat()
        if stat(baselineURL.path, &baselineInfo) == 0 {
            baselineInode = baselineInfo.st_ino
            print("baseline: \(baselineInode)")
        } else {
            print("Failed to get baseline inode!")
        }
        try files.removeItem(at: baselineURL)
    } catch {
        print("Failed to get baseline inode: \(error)")
        return
    }

    print("This is gonna take a while...")

    // Run the enumeration on a background queue so the UI stays responsive.
    // The baseline inode is passed in full on purpose: pathleak scans inode
    // numbers up to that baseline (values in the tens of millions are normal — a
    // temp file inode on a real device was 14,911,791), so capping it to a
    // small number would make the scan find almost nothing.
    let baseline = baselineInode
    DispatchQueue.global(qos: .userInitiated).async {
        let paths = pathleak(scanFilter, baseline) ?? []
        print("pathleak found \(paths.count) path(s).")

        for path in paths {
            let handle = consumeExtension(path)
            if handle > 0 {
                var buf = [CChar](repeating: 0, count: 512)
                let len = getxattr(path, "com.apple.containermanager.identifier", &buf, 511, 0, 0)
                if len > 0 {
                    let bundleID = String(cString: buf)
                    print("\n\(bundleID): \(path)\n")
                }
                releaseExtension(handle)
            }
        }
        print("Done!")
    }
}

func listPaths(_ path: String) {
    let handle = consumeExtension(path)
    guard handle > 0 else {
        print("Failed to get parent directory extension!")
        return
    }

    let files = FileManager.default
    let root = URL(filePath: path)
    var collected: [String] = []

    do {
        let enumerated = try files.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for fileURL in enumerated {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                collected.append(fileURL.path)
            }
        }
    } catch {
        print("Failed to load enumerate directories!")
    }

    for path in collected {
        print(path)
        var buf = [CChar](repeating: 0, count: 512)
        let len = getxattr(path, "com.apple.containermanager.identifier", &buf, 511, 0, 0)
        if len > 0 {
            let bundleID = String(cString: buf)
            print("\n\(bundleID): \(path)\n")
        }
    }

    releaseExtension(handle)
}

