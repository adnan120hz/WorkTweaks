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
    /// True when only a subset of features is supported on this
    /// build (App Data + Airlift). iOS 18 and iOS 26 are partial.
    let partial: Bool

    var id: String { build }

    init(version: String, build: String, notes: String, releaseDate: String, partial: Bool = false) {
        self.version = version
        self.build = build
        self.notes = notes
        self.releaseDate = releaseDate
        self.partial = partial
    }
}

enum SupportInfo {
    /// The allowlist — user-specified for v2.0, used verbatim.
    /// Public betas share builds with developer betas, so each
    /// unique build appears once with both names in its notes.
    /// iOS 18 and iOS 26 are partially supported: App Data and
    /// Airlift only. iOS 27 is fully supported.
    static let supportedReleases: [SupportedRelease] = [
        SupportedRelease(version: "iOS 18.0 Beta 1", build: "22A5282m", notes: "Developer Beta 1", releaseDate: "June 10, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0 Beta 2", build: "22A5297f", notes: "Developer Beta 2 / Public Beta 1", releaseDate: "June 24, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0 Beta 3", build: "22A5307f", notes: "Developer Beta 3 / Public Beta 2", releaseDate: "July 8, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0 Beta 3 Update", build: "22A5307i", notes: "Developer Beta 3 Update / Public Beta 2", releaseDate: "July 15, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0 Beta 4", build: "22A5316j", notes: "Developer Beta 4 / Public Beta 3", releaseDate: "July 23, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0 Beta 4 Update", build: "22A5316k", notes: "Developer Beta 4 Update / Public Beta 3", releaseDate: "July 26, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0 Beta 5", build: "22A5326f", notes: "Developer Beta 5 / Public Beta 4", releaseDate: "August 5, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0 Beta 6", build: "22A5338b", notes: "Developer Beta 6 / Public Beta 5", releaseDate: "August 12, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0 Beta 7", build: "22A5346a", notes: "Developer Beta 7 / Public Beta 6", releaseDate: "August 20, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0 Beta 8", build: "22A5350a", notes: "Developer Beta 8 / Public Beta 7", releaseDate: "August 28, 2024", partial: true),
        SupportedRelease(version: "iOS 18.0", build: "22A3354", notes: "Release Candidate / Final Release", releaseDate: "September 16, 2024", partial: true),
        SupportedRelease(version: "iOS 26.0", build: "23A341", notes: "iOS 26 only", releaseDate: "September 15, 2025", partial: true),
        SupportedRelease(version: "iOS 26.0.1", build: "23A355", notes: "iOS 26 only", releaseDate: "September 29, 2025", partial: true),
        SupportedRelease(version: "iOS 26.1", build: "23B85", notes: "iOS 26 only", releaseDate: "November 3, 2025", partial: true),
        SupportedRelease(version: "iOS 26.2", build: "23C55", notes: "iOS 26 only", releaseDate: "December 13, 2025", partial: true),
        SupportedRelease(version: "iOS 26.2.1", build: "23C71", notes: "iOS 26 only", releaseDate: "January 26, 2026", partial: true),
        SupportedRelease(version: "iOS 26.3", build: "23D127", notes: "iOS 26 only", releaseDate: "February 11, 2026", partial: true),
        SupportedRelease(version: "iOS 26.3.1", build: "23D8133", notes: "iOS 26 only", releaseDate: "March 4, 2026", partial: true),
        SupportedRelease(version: "iOS 26.4", build: "23E246", notes: "iOS 26 only", releaseDate: "March 24, 2026", partial: true),
        SupportedRelease(version: "iOS 26.4.1", build: "23E254", notes: "iOS 26 only", releaseDate: "April 8, 2026", partial: true),
        SupportedRelease(version: "iOS 26.4.2", build: "23E261", notes: "iOS 26 only", releaseDate: "April 22, 2026", partial: true),
        SupportedRelease(version: "iOS 26.5", build: "23F77", notes: "iOS 26 only", releaseDate: "May 11, 2026", partial: true),
        SupportedRelease(version: "iOS 26.5.2", build: "23F84", notes: "iOS 26 only", releaseDate: "June 29, 2026", partial: true),
        SupportedRelease(version: "iOS 26.6", build: "23G71", notes: "iOS 26 only", releaseDate: "July 27, 2026", partial: true),
        SupportedRelease(version: "iOS 26.6.1", build: "23G83", notes: "iOS 26 only", releaseDate: "August 17, 2026", partial: true),
        SupportedRelease(version: "iOS 26.6.2", build: "23G90", notes: "iOS 26 only", releaseDate: "September 8, 2026", partial: true),
        SupportedRelease(version: "iOS 26.7.2", build: "23H128", notes: "Final Release (Security)", releaseDate: "October 26, 2026", partial: true),
        SupportedRelease(version: "iOS 27.0 Beta 1", build: "24A5355q", notes: "Developer Beta 1", releaseDate: "June 8, 2026"),
        SupportedRelease(version: "iOS 27.0 Beta 2", build: "24A5370h", notes: "Developer Beta 2 / Public Beta 1", releaseDate: "June 22, 2026"),
        SupportedRelease(version: "iOS 27.0 Beta 3", build: "24A5380h", notes: "Developer Beta 3 / Public Beta 2", releaseDate: "July 6, 2026"),
        SupportedRelease(version: "iOS 27.0 Beta 4", build: "24A5390f", notes: "Developer Beta 4 / Public Beta 3", releaseDate: "July 20, 2026"),
        SupportedRelease(version: "iOS 27.0 Beta 5", build: "24A5408d", notes: "Developer Beta 5 / Public Beta 4", releaseDate: "August 10, 2026"),
        SupportedRelease(version: "iOS 27.0 Beta 6", build: "24A5418b", notes: "Developer Beta 6 / Public Beta 5", releaseDate: "August 17, 2026"),
        SupportedRelease(version: "iOS 27.0 Beta 7", build: "24A5424a", notes: "Developer Beta 7 / Public Beta 6", releaseDate: "August 24, 2026"),
        SupportedRelease(version: "iOS 27.0 Beta 8", build: "24A5430a", notes: "Developer Beta 8 / Public Beta 7", releaseDate: "August 31, 2026"),
        SupportedRelease(version: "iOS 27.0 RC", build: "24A435", notes: "Release Candidate", releaseDate: "September 9, 2026"),
        SupportedRelease(version: "iOS 27.0", build: "24A437", notes: "Final Release", releaseDate: "September 14, 2026"),
        SupportedRelease(version: "iOS 27.0.1", build: "24A446", notes: "Bug Fix Patch", releaseDate: "September 28, 2026"),
        SupportedRelease(version: "iOS 27.1", build: "24B91034", notes: "iPhone Duo only", releaseDate: ""),
        SupportedRelease(version: "iOS 27.2 Beta 1", build: "24B5084k", notes: "Developer Beta", releaseDate: "September 16, 2026"),
        SupportedRelease(version: "iOS 27.2 Beta 2", build: "24B5089g", notes: "Developer Beta", releaseDate: "September 21, 2026"),
        SupportedRelease(version: "iOS 27.2 Beta 3", build: "24B5099f", notes: "Developer Beta", releaseDate: "October 5, 2026"),
        SupportedRelease(version: "iOS 27.2 Beta 4", build: "24B5110a", notes: "Developer Beta", releaseDate: "October 13, 2026"),
        SupportedRelease(version: "iOS 27.2 RC", build: "24B115", notes: "Release Candidate", releaseDate: "October 19, 2026"),
        SupportedRelease(version: "iOS 27.2", build: "24B119", notes: "Final Release", releaseDate: "October 26, 2026"),
        SupportedRelease(version: "iOS 27.2.1", build: "24B156", notes: "Bug Fix Patch", releaseDate: ""),
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

    /// True when the device's build is on the allowlist but only
    /// partially supported (App Data + Airlift). iOS 18 and iOS 26.
    static var isPartiallySupported: Bool {
        matchedRelease?.partial == true
    }

    /// "iOS 27.0.1 (24A446)" — for status lines and the
    /// unsupported screen.
    static var deviceSummary: String {
        "iOS \(deviceVersion) (\(deviceBuild))"
    }
}
