import Foundation
import UIKit

// MARK: - Supported iOS releases (v2.0 enforced allowlist)
//
// WorkTweaks v2.0 only runs on the exact iOS builds listed below.
// At launch the app reads the device's build number and compares it
// against this list: a match opens the app, anything else lands on
// the "not supported" screen. The same table is shown in License &
// Credits and on the unsupported screen, so what the app says and
// what it enforces can never drift apart.

struct SupportedRelease: Identifiable {
    /// e.g. "iOS 27.0.1"
    let version: String
    /// e.g. "24A446"
    let build: String
    /// e.g. "Bug Fix Patch"
    let notes: String
    /// e.g. "September 28, 2026"
    let releaseDate: String

    var id: String { build }
}

enum SupportInfo {
    /// The allowlist — user-specified for v2.0, used verbatim.
    static let supportedReleases: [SupportedRelease] = [
        SupportedRelease(version: "iOS 26.7.2", build: "23H128", notes: "Final Release (Security)", releaseDate: "October 26, 2026"),
        SupportedRelease(version: "iOS 27.0", build: "24A437", notes: "Final Release", releaseDate: "September 14, 2026"),
        SupportedRelease(version: "iOS 27.0.1", build: "24A446", notes: "Bug Fix Patch", releaseDate: "September 28, 2026"),
        SupportedRelease(version: "iOS 27.2 Beta 1", build: "24B5084k", notes: "Developer Beta", releaseDate: "September 16, 2026"),
        SupportedRelease(version: "iOS 27.2 Beta 2", build: "24B5089g", notes: "Developer Beta", releaseDate: "September 21, 2026"),
        SupportedRelease(version: "iOS 27.2 Beta 3", build: "24B5099f", notes: "Developer Beta", releaseDate: "October 5, 2026"),
        SupportedRelease(version: "iOS 27.2 Beta 4", build: "24B5110a", notes: "Developer Beta", releaseDate: "October 13, 2026"),
        SupportedRelease(version: "iOS 27.2 RC", build: "24B115", notes: "Release Candidate", releaseDate: "October 19, 2026"),
        SupportedRelease(version: "iOS 27.2", build: "24B119", notes: "Final Release", releaseDate: "October 26, 2026"),
        SupportedRelease(version: "iOS 27.3 Beta 1", build: "24C5037i", notes: "Developer + Public Beta", releaseDate: "November 3, 2026"),
    ]

    /// The device's marketing iOS version, e.g. "27.0.1".
    static var deviceVersion: String {
        UIDevice.current.systemVersion
    }

    /// The device's iOS build number, e.g. "24A446"
    /// (sysctl kern.osversion — the same string Apple's build
    /// train uses, so it can be matched against the allowlist).
    static var deviceBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    /// The allowlist entry matching this device, if any.
    static var matchedRelease: SupportedRelease? {
        supportedReleases.first { $0.build == deviceBuild }
    }

    /// True only when the device's build is on the allowlist.
    static var isSupported: Bool {
        matchedRelease != nil
    }

    /// "iOS 27.0.1 (24A446)" — for status lines and the
    /// unsupported screen.
    static var deviceSummary: String {
        "iOS \(deviceVersion) (\(deviceBuild))"
    }
}
