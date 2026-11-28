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

    // MARK: - Deploy method availability (v8.0)
    //
    // Deploy package has exactly two methods, each gated to its
    // own iOS range. The main launch gate above (isSupported,
    // 18+) is NOT touched: these rows and gates only decide
    // which Deploy method a device is offered.
    //
    //   Normal — iOS 26.0 (23A341) to iOS 27.3 beta 1 (24C5037i).
    //     worse_query is patched in iOS 27.3 beta 2 (24C5049d).
    //   Airlift — iOS 17 / 18 / 26 / 27, with iOS 27 capped at
    //     max 27.2 beta 2 (24B5089g).
    //
    // iOS 17 rows (below) come verbatim from the user-provided
    // v80-ios17-versions.md — betas 17.0b1 21A5248v through
    // 17.7.1 RC 21H216, releases 17.0 21A329 through 17.7.2
    // 21H221, multi-build versions expanded to one row per
    // build. iOS 18/26/27 rows are the supportedReleases table
    // above (already in v7.0) — no new tables for them.

    /// The iOS 17 builds Airlift Deploy supports. Kept apart
    /// from supportedReleases on purpose: iOS 17 is NOT a
    /// launch-supported version, it only gets Deploy via
    /// Airlift. One row per unique build (an RC and its final
    /// release share a build, so they merge into one row with
    /// both names in the notes, like the table above).
    static let airliftIOS17Releases: [SupportedRelease] = [
        SupportedRelease(version: "iOS 17.0 Beta 1", build: "21A5248v", notes: "Developer Beta 1", releaseDate: "June 5, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0 Beta 2", build: "21A5268h", notes: "Developer Beta 2", releaseDate: "June 21, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0 Beta 3", build: "21A5277h", notes: "Developer Beta 3", releaseDate: "July 5, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0 Beta 3", build: "21A5277j", notes: "Reissue", releaseDate: "July 11, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0 Beta 4", build: "21A5291h", notes: "Developer Beta 4", releaseDate: "July 25, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0 Beta 4", build: "21A5291j", notes: "Reissue", releaseDate: "July 31, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0 Beta 5", build: "21A5303d", notes: "Developer Beta 5", releaseDate: "August 8, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0 Beta 6", build: "21A5312c", notes: "Developer Beta 6", releaseDate: "August 15, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0 Beta 7", build: "21A5319a", notes: "Developer Beta 7", releaseDate: "August 22, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0 Beta 8", build: "21A5326a", notes: "Developer Beta 8", releaseDate: "August 29, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0", build: "21A326", notes: "iPhone 15 — factory-installed build", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.0", build: "21A327", notes: "iPhone 15 — factory-installed build", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.0", build: "21A329", notes: "Release Candidate / Final Release — Non-iPhone 15", releaseDate: "September 12, 2023", partial: true),
        SupportedRelease(version: "iOS 17.0", build: "21A331", notes: "iPhone 15 — release build", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.0.1", build: "21A340", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.0.2", build: "21A350", notes: "iPhone 15", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.0.2", build: "21A351", notes: "Non-iPhone 15", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.0.3", build: "21A360", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.1 Beta 1", build: "21B5045h", notes: "Developer Beta 1", releaseDate: "September 27, 2023", partial: true),
        SupportedRelease(version: "iOS 17.1 Beta 2", build: "21B5056e", notes: "Developer Beta 2", releaseDate: "October 3, 2023", partial: true),
        SupportedRelease(version: "iOS 17.1 Beta 3", build: "21B5066a", notes: "Developer Beta 3", releaseDate: "October 10, 2023", partial: true),
        SupportedRelease(version: "iOS 17.1", build: "21B74", notes: "Release Candidate / Final Release — Non-iPhone 15", releaseDate: "October 17, 2023", partial: true),
        SupportedRelease(version: "iOS 17.1 RC 2", build: "21B77", notes: "Release Candidate", releaseDate: "October 20, 2023", partial: true),
        SupportedRelease(version: "iOS 17.1", build: "21B80", notes: "iPhone 15", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.1.1", build: "21B91", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.1.2", build: "21B101", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.2 Beta 1", build: "21C5029g", notes: "Developer Beta 1", releaseDate: "October 26, 2023", partial: true),
        SupportedRelease(version: "iOS 17.2 Beta 2", build: "21C5040g", notes: "Developer Beta 2", releaseDate: "November 9, 2023", partial: true),
        SupportedRelease(version: "iOS 17.2 Beta 3", build: "21C5046c", notes: "Developer Beta 3", releaseDate: "November 14, 2023", partial: true),
        SupportedRelease(version: "iOS 17.2 Beta 4", build: "21C5054b", notes: "Developer Beta 4", releaseDate: "November 28, 2023", partial: true),
        SupportedRelease(version: "iOS 17.2", build: "21C62", notes: "Release Candidate / Final Release", releaseDate: "December 5, 2023", partial: true),
        SupportedRelease(version: "iOS 17.2.1", build: "21C66", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.3 Beta 1", build: "21D5026f", notes: "Developer Beta 1", releaseDate: "December 12, 2023", partial: true),
        SupportedRelease(version: "iOS 17.3 Beta 2", build: "21D5036c", notes: "Developer Beta 2", releaseDate: "January 3, 2024", partial: true),
        SupportedRelease(version: "iOS 17.3 Beta 3", build: "21D5044a", notes: "Developer Beta 3", releaseDate: "January 9, 2024", partial: true),
        SupportedRelease(version: "iOS 17.3", build: "21D50", notes: "Release Candidate / Final Release", releaseDate: "January 17, 2024", partial: true),
        SupportedRelease(version: "iOS 17.3.1", build: "21D61", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.4 Beta 1", build: "21E5184i", notes: "Developer Beta 1", releaseDate: "January 25, 2024", partial: true),
        SupportedRelease(version: "iOS 17.4 Beta 1", build: "21E5184k", notes: "Reissue", releaseDate: "January 30, 2024", partial: true),
        SupportedRelease(version: "iOS 17.4 Beta 2", build: "21E5195e", notes: "Developer Beta 2", releaseDate: "February 6, 2024", partial: true),
        SupportedRelease(version: "iOS 17.4 Beta 3", build: "21E5200d", notes: "Developer Beta 3", releaseDate: "February 13, 2024", partial: true),
        SupportedRelease(version: "iOS 17.4 Beta 4", build: "21E5209b", notes: "Developer Beta 4", releaseDate: "February 20, 2024", partial: true),
        SupportedRelease(version: "iOS 17.4 RC", build: "21E217", notes: "Release Candidate", releaseDate: "February 27, 2024", partial: true),
        SupportedRelease(version: "iOS 17.4", build: "21E219", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.4.1", build: "21E236", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.4.1", build: "21E237", notes: "Revised build", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.5 Beta 1", build: "21F5048f", notes: "Developer Beta 1", releaseDate: "April 2, 2024", partial: true),
        SupportedRelease(version: "iOS 17.5 Beta 2", build: "21F5058e", notes: "Developer Beta 2", releaseDate: "April 16, 2024", partial: true),
        SupportedRelease(version: "iOS 17.5 Beta 3", build: "21F5063f", notes: "Developer Beta 3", releaseDate: "April 23, 2024", partial: true),
        SupportedRelease(version: "iOS 17.5 Beta 4", build: "21F5073b", notes: "Developer Beta 4", releaseDate: "April 30, 2024", partial: true),
        SupportedRelease(version: "iOS 17.5", build: "21F79", notes: "Release Candidate / Final Release", releaseDate: "May 7, 2024", partial: true),
        SupportedRelease(version: "iOS 17.5.1", build: "21F90", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.6 Beta 1", build: "21G5052e", notes: "Developer Beta 1", releaseDate: "June 17, 2024", partial: true),
        SupportedRelease(version: "iOS 17.6 Beta 2", build: "21G5061c", notes: "Developer Beta 2", releaseDate: "July 1, 2024", partial: true),
        SupportedRelease(version: "iOS 17.6 Beta 3", build: "21G5066d", notes: "Developer Beta 3", releaseDate: "July 9, 2024", partial: true),
        SupportedRelease(version: "iOS 17.6 Beta 4", build: "21G5075a", notes: "Developer Beta 4", releaseDate: "July 16, 2024", partial: true),
        SupportedRelease(version: "iOS 17.6 RC", build: "21G79", notes: "Release Candidate", releaseDate: "July 23, 2024", partial: true),
        SupportedRelease(version: "iOS 17.6", build: "21G80", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.6.1", build: "21G93", notes: "", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.6.1", build: "21G101", notes: "Revised build", releaseDate: "", partial: true),
        SupportedRelease(version: "iOS 17.7", build: "21H16", notes: "Release Candidate / Final Release — Last iPhone model still receiving features", releaseDate: "September 9, 2024", partial: true),
        SupportedRelease(version: "iOS 17.7.1", build: "21H216", notes: "Release Candidate / Final Release", releaseDate: "October 21, 2024", partial: true),
        SupportedRelease(version: "iOS 17.7.2", build: "21H221", notes: "Last iPhone", releaseDate: "", partial: true),
    ]

    /// Why a Deploy method is not offered on this device.
    enum DeployGate {
        case available
        case belowMinimum
        case aboveMaximum
        case unknownBuild
    }

    /// Normal Deploy (worse_query): iOS 26.0 .. iOS 27.3 beta 1.
    static var normalDeployGate: DeployGate {
        let build = deviceBuild
        guard !build.isEmpty else { return .unknownBuild }
        if let idx = supportedReleases.firstIndex(where: { $0.build == build }) {
            let lo = supportedReleases.firstIndex(where: { $0.build == "23A341" }) ?? 0
            let hi = supportedReleases.firstIndex(where: { $0.build == "24C5037i" }) ?? supportedReleases.count
            if idx < lo { return .belowMinimum }
            if idx > hi { return .aboveMaximum }
            return .available
        }
        // Not a listed build: decide by build-train order.
        // Below iOS 26.0 is below the minimum; above
        // iOS 27.3 beta 1 (worse_query patched in beta 2) is
        // above the maximum.
        if compareBuilds(build, "23A341") == .orderedAscending { return .belowMinimum }
        if compareBuilds(build, "24C5037i") == .orderedDescending { return .aboveMaximum }
        return .available
    }

    /// Deploy via Airlift: iOS 17 / 18 / 26 / 27, iOS 27 capped
    /// at max 27.2 beta 2 (24B5089g).
    static var airliftDeployGate: DeployGate {
        let build = deviceBuild
        guard !build.isEmpty else { return .unknownBuild }
        if airliftIOS17Releases.contains(where: { $0.build == build }) { return .available }
        if let idx = supportedReleases.firstIndex(where: { $0.build == build }) {
            // iOS 18 (22*) and iOS 26 (23*) are fully in range.
            if build.hasPrefix("22") || build.hasPrefix("23") { return .available }
            // iOS 27 (24*): table order decides — the 27.2 beta 2
            // row is the cap. (Table order is chronological, which
            // matters here: 27.2 RC/final builds sort before the
            // betas lexicographically but come after them.)
            let cap = supportedReleases.firstIndex(where: { $0.build == "24B5089g" }) ?? supportedReleases.count
            return idx <= cap ? .available : .aboveMaximum
        }
        // Not a listed build: decide by train. 21*/22*/23* are
        // iOS 17/18/26 (available); 24* is iOS 27, capped at
        // 27.2 beta 2; anything newer is above the maximum.
        if build.hasPrefix("21") || build.hasPrefix("22") || build.hasPrefix("23") { return .available }
        if build.hasPrefix("24") {
            if compareBuilds(build, "24A5355q") == .orderedAscending { return .belowMinimum }
            return compareBuilds(build, "24B5089g") == .orderedDescending ? .aboveMaximum : .available
        }
        return .aboveMaximum
    }

    static var normalDeployAvailable: Bool { normalDeployGate == .available }
    static var airliftDeployAvailable: Bool { airliftDeployGate == .available }

    // MARK: - PosterBoard method availability (v8.0)
    //
    // Normal and Flake both write through the worse_query
    // escape, so they share Normal Deploy's range: iOS 26.0 ..
    // iOS 27.3 beta 1. worse_query is patched in iOS 27.3 beta 2
    // (24C5049d), and Flake's README says the same about Flake
    // itself ("This tool does NOT support iOS 18- and 27.3
    // Developer Beta 2+. It will NEVER be supported on these
    // versions.") — there is no flake fix for 27.3 beta 2+.
    //
    // Via Airlift is capped at iOS 27.2 beta 2 like Deploy via
    // Airlift, AND it still needs the local escape to resolve
    // the PosterBoard container and read the store version
    // first — on iOS 17/18 the container can neither be
    // resolved nor read, so there is nothing to stage into.
    // Its range is therefore iOS 26.0 .. iOS 27.2 beta 2, not
    // Deploy via Airlift's iOS 17/18/26/27 range. When the
    // escape gate is above its maximum, both PosterBoard gates
    // are closed and the page shows the honest blocked state.

    /// Normal + Flake PosterBoard import (worse_query path):
    /// iOS 26.0 .. iOS 27.3 beta 1.
    static var posterBoardEscapeGate: DeployGate { normalDeployGate }

    /// PosterBoard import via Airlift: iOS 26.0 .. 27.2 beta 2.
    static var posterBoardAirliftGate: DeployGate {
        switch normalDeployGate {
        case .belowMinimum:
            return .belowMinimum
        case .unknownBuild:
            return .unknownBuild
        case .aboveMaximum:
            return .aboveMaximum
        case .available:
            break
        }
        return airliftDeployGate
    }

    static var posterBoardEscapeAvailable: Bool { posterBoardEscapeGate == .available }
    static var posterBoardAirliftAvailable: Bool { posterBoardAirliftGate == .available }

    /// Apple build-train order: year digits, train letter,
    /// finals (no letter suffix — RC / final releases) sort
    /// AFTER the betas of the same train letter, then build
    /// number, then the beta suffix letter. So 24B115 (27.2 RC)
    /// sorts after 24B5089g (27.2 beta 2), and 24A435 (27.0 RC)
    /// after the 27.0 betas but before every 24B build.
    /// Unparseable strings fall back to a plain comparison.
    static func compareBuilds(_ lhs: String, _ rhs: String) -> ComparisonResult {
        func key(_ s: String) -> (Int, String, Int, Int, String)? {
            guard let re = try? NSRegularExpression(pattern: #"^(\d+)([A-Z])(\d+)([a-z]?)$"#),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  m.numberOfRanges == 5 else { return nil }
            func group(_ i: Int) -> String {
                let r = m.range(at: i)
                guard r.location != NSNotFound, let range = Range(r, in: s) else { return "" }
                return String(s[range])
            }
            return (Int(group(1)) ?? 0, group(2), group(4).isEmpty ? 1 : 0, Int(group(3)) ?? 0, group(4))
        }
        guard let l = key(lhs), let r = key(rhs) else {
            return lhs.compare(rhs)
        }
        if l.0 != r.0 { return l.0 < r.0 ? .orderedAscending : .orderedDescending }
        if l.1 != r.1 { return l.1 < r.1 ? .orderedAscending : .orderedDescending }
        if l.2 != r.2 { return l.2 < r.2 ? .orderedAscending : .orderedDescending }
        if l.3 != r.3 { return l.3 < r.3 ? .orderedAscending : .orderedDescending }
        if l.4 != r.4 { return l.4 < r.4 ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }
}
