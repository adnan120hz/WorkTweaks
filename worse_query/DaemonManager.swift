import Foundation
import Combine
import Darwin

// MARK: - Daemon catalog
//
// Knowledge credit: the category → launchd-label mapping follows
// the daemon catalog published by Nugget (leminlimez, AGPL-3.0) —
// the same knowledge-credit style as the CacheExtra catalog.
// Disabling a daemon means listing its label in
// /var/db/com.apple.xpc.launchd/disabled.plist with value true;
// launchd then refuses to start it after the next restart.

struct DaemonCategory {
    let id: String
    let name: String
    let detail: String
    let labels: [String]
    var risky: Bool = false
}

enum DaemonCatalog {
    static let all: [DaemonCategory] = [
        DaemonCategory(id: "OTA", name: "Block OTA Updates",
                       detail: "Stops OTA and software update checks and downloads.",
                       labels: ["com.apple.mobile.softwareupdated",
                                "com.apple.OTATaskingAgent",
                                "com.apple.softwareupdateservicesd",
                                "com.apple.mobile.NRDUpdated"]),
        DaemonCategory(id: "UsageTrackingAgent", name: "Usage Tracking Agent",
                       detail: "Stops collection of app usage data for analytics.",
                       labels: ["com.apple.UsageTrackingAgent"]),
        DaemonCategory(id: "GameCenter", name: "Game Center",
                       detail: "Stops Game Center processes and syncing.",
                       labels: ["com.apple.gamed"]),
        DaemonCategory(id: "ScreenTime", name: "Screen Time",
                       detail: "Stops Screen Time monitoring and reporting.",
                       labels: ["com.apple.ScreenTimeAgent",
                                "com.apple.homed",
                                "com.apple.familycircled",
                                "com.apple.familynotification",
                                "com.apple.asktod"]),
        DaemonCategory(id: "CrashReports", name: "Logs, Dumps & Crash Reports",
                       detail: "Stops diagnostic logging and automatic crash report collection.",
                       labels: ["com.apple.ReportCrash",
                                "com.apple.ReportCrash.Jetsam",
                                "com.apple.ReportMemoryException",
                                "com.apple.OTACrashCopier",
                                "com.apple.analyticsd",
                                "com.apple.wifianalyticsd",
                                "com.apple.aslmanager",
                                "com.apple.coresymbolicationd",
                                "com.apple.crash_mover",
                                "com.apple.crashreportcopymobile",
                                "com.apple.DumpBasebandCrash",
                                "com.apple.DumpPanic",
                                "com.apple.logd",
                                "com.apple.logd.admin",
                                "com.apple.logd.events",
                                "com.apple.logd.watchdog",
                                "com.apple.logd_helper",
                                "com.apple.logd_reporter",
                                "com.apple.logd_reporter.report_statistics",
                                "com.apple.system.logger",
                                "com.apple.hangreporter",
                                "com.apple.hangtracerd",
                                "com.apple.spindump",
                                "com.apple.tailspind",
                                "com.apple.rtcreportingd",
                                "com.apple.syslogd",
                                "com.apple.signpost.signpost_reporter",
                                "com.apple.pluginkit.pkreporter",
                                "com.apple.ProxiedCrashCopier",
                                "com.apple.ProxiedCrashCopier.ProxyingDevice",
                                "com.apple.ReportSystemMemory"]),
        DaemonCategory(id: "Diagnostics", name: "Diagnostics",
                       detail: "Stops diagnostic and sysdiagnose services.",
                       labels: ["com.apple.diagnosticd",
                                "com.apple.diagnosticextensionsd",
                                "com.apple.diagnosticservicesd",
                                "com.apple.diagnosticspushd",
                                "com.apple.symptomsd-diag",
                                "com.apple.sysdiagnose",
                                "com.apple.sysdiagnose.darwinos",
                                "com.apple.sysdiagnose_helper"]),
        DaemonCategory(id: "ATWAKEUP", name: "ATWAKEUP",
                       detail: "The AirTraffic wakeup service (atc).",
                       labels: ["com.apple.atc.atwakeup"]),
        DaemonCategory(id: "Tips", name: "Tips",
                       detail: "Stops suggestions and notifications from the Tips app.",
                       labels: ["com.apple.tipsd"]),
        DaemonCategory(id: "VPN", name: "VPN",
                       detail: "The built-in IPsec VPN service (racoon).",
                       labels: ["com.apple.racoon"]),
        DaemonCategory(id: "Location", name: "Location",
                       detail: "Location services (locationd).",
                       labels: ["com.apple.locationd"]),
        DaemonCategory(id: "ChineseLAN", name: "Chinese WLAN",
                       detail: "The WLAN service used in the China region.",
                       labels: ["com.apple.wapic",
                                "com.apple.wifi.wapic"]),
        DaemonCategory(id: "HealthKit", name: "HealthKit",
                       detail: "Health data sync service (healthd).",
                       labels: ["com.apple.healthd"]),
        DaemonCategory(id: "AirPrint", name: "AirPrint",
                       detail: "Wireless printer discovery (printd).",
                       labels: ["com.apple.printd"]),
        DaemonCategory(id: "AssistiveTouch", name: "AssistiveTouch",
                       detail: "The AssistiveTouch service.",
                       labels: ["com.apple.assistivetouchd"]),
        DaemonCategory(id: "iCloud", name: "iCloud",
                       detail: "The iCloud media service (itunescloudd).",
                       labels: ["com.apple.itunescloudd"]),
        DaemonCategory(id: "InternetTethering", name: "Internet Tethering",
                       detail: "Personal Hotspot sharing.",
                       labels: ["com.apple.MobileInternetSharing"]),
        DaemonCategory(id: "PassBook", name: "Wallet",
                       detail: "The Wallet / Passbook service (passd).",
                       labels: ["com.apple.passd"]),
        DaemonCategory(id: "Spotlight", name: "Spotlight",
                       detail: "Spotlight search indexing and knowledge services.",
                       labels: ["com.apple.searchd",
                                "com.apple.corespotlightservice",
                                "com.apple.spotlightknowledged",
                                "com.apple.spotlightknowledged.updater",
                                "com.apple.spotlight.IndexAgent"]),
        DaemonCategory(id: "VoiceControl", name: "Voice Control",
                       detail: "Voice Control and assistant voice services.",
                       labels: ["com.apple.assistant_service",
                                "com.apple.assistantd",
                                "com.apple.voiced"]),
        DaemonCategory(id: "NanoTimeKit", name: "NanoTimeKit",
                       detail: "The Apple Watch time kit companion service.",
                       labels: ["com.apple.nanotimekitcompaniond"]),
        DaemonCategory(id: "FollowUp", name: "FollowUp",
                       detail: "The system follow-up notification service.",
                       labels: ["com.apple.followupd"]),
        DaemonCategory(id: "thermalmonitord", name: "thermalmonitord",
                       detail: "Disabling thermalmonitord affects the device's thermal management.",
                       labels: ["com.apple.thermalmonitord"],
                       risky: true),
    ]

    static var main: [DaemonCategory] { all.filter { !$0.risky } }
    static var risky: [DaemonCategory] { all.filter { $0.risky } }
}

// MARK: - Access state

enum DaemonAccessState: Equatable {
    case probing
    case ready
    case blocked(code: Int64, message: String)
}

// MARK: - Manager
//
// Fail-safe by design, mirroring the NuggetIPadOSLocator pattern:
// access to /var/db/com.apple.xpc.launchd (a root-owned directory)
// is probed before anything is offered, and nothing is ever
// written without a successful grant AND a successful read/parse
// of the existing disabled.plist. The kernel may refuse this
// directory the same way it refused /var/Managed Preferences —
// in that case the page reports the refusal honestly.

final class DaemonManager: ObservableObject {
    @Published var state: DaemonAccessState = .probing
    @Published var toggles: [String: Bool] = [:]
    @Published var showRestartRequired = false
    @Published var errorMessage: String?
    @Published var restartAlertTitle: String?
    @Published var restartAlertMessage = ""

    static let directoryPath = "/var/db/com.apple.xpc.launchd"
    private static let parentPath = "/var/db"
    private static let fileName = "disabled.plist"

    /// The directory spelling that the winning grant covers
    /// (pathleak may surface the /private/... spelling).
    private var resolvedDirectory = DaemonManager.directoryPath
    private var plistPath: String { resolvedDirectory + "/" + DaemonManager.fileName }

    /// Winning sandbox-extension handle, kept for the session.
    private var handle: Int64 = -255
    /// Most recent probe result code, for the blocked message.
    private var lastProbeCode: Int64 = -255
    private var didProbe = false

    /// Existing disabled.plist contents, preserved verbatim for
    /// every non-catalog key.
    private var existingDict: [String: Any] = [:]
    private var fileExisted = false

    deinit {
        if handle > 0 {
            releaseExtension(handle)
        }
    }

    // MARK: Probe

    func probeIfNeeded() {
        guard !didProbe else { return }
        didProbe = true
        probe()
    }

    private func probe() {
        print("[Daemons] probing access to \(Self.directoryPath) ...")

        // Probe 1: an extension on the launchd directory itself.
        let h1 = consumeExtension(Self.directoryPath)
        lastProbeCode = h1
        print("[Daemons] probe 1 (consumeExtension on directory) -> \(h1)")
        if h1 > 0 {
            if adoptGrant(handle: h1, directory: Self.directoryPath, probe: 1) { return }
        }

        // Probe 2: parentdir-style grant on /var/db — the fork's
        // pattern for reaching a directory through its parent.
        let h2 = consumeExtension(Self.parentPath)
        lastProbeCode = h2
        print("[Daemons] probe 2 (parentdir grant on \(Self.parentPath)) -> \(h2)")
        if h2 > 0 {
            if adoptGrant(handle: h2, directory: Self.directoryPath, probe: 2) { return }
        }

        // Probe 3: pathleak enumeration to locate the directory,
        // then an extension on whatever spelling it surfaces.
        print("[Daemons] probes 1-2 failed; falling back to pathleak ...")
        probeViaPathleak()
    }

    private func probeViaPathleak() {
        // Baseline inode, the same trick leakPaths uses: a temp
        // file's inode bounds the pathleak scan.
        let files = FileManager.default
        let baselineURL = files.temporaryDirectory.appendingPathComponent(".baseline_\(UUID().uuidString)")
        var baselineInode: UInt64 = 0
        do {
            try "helloworld".write(to: baselineURL, atomically: true, encoding: .utf8)
            var info = stat()
            if stat(baselineURL.path, &info) == 0 {
                baselineInode = info.st_ino
            }
            try files.removeItem(at: baselineURL)
        } catch {
            print("[Daemons] probe 3: failed to get baseline inode: \(error)")
            DispatchQueue.main.async { [weak self] in self?.finishBlocked() }
            return
        }

        let baseline = baselineInode
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let found = pathleak(Self.directoryPath, baseline) ?? []
            print("[Daemons] probe 3 pathleak found \(found.count) candidate path(s) for \(Self.directoryPath)")
            for candidate in found {
                let h = consumeExtension(candidate)
                self.lastProbeCode = h
                print("[Daemons] probe 3 (consumeExtension on \(candidate)) -> \(h)")
                guard h > 0 else { continue }
                let outcome = self.tryLoad(plistDirectory: candidate)
                switch outcome {
                case .loaded, .parseBlocked:
                    DispatchQueue.main.async {
                        self.handle = h
                        self.resolvedDirectory = candidate
                        print("[Daemons] probe 3 won: handle \(h) on \(candidate)")
                        self.finishLoad(outcome: outcome)
                    }
                    return
                case .ioFailure:
                    releaseExtension(h)
                }
            }
            DispatchQueue.main.async { self.finishBlocked() }
        }
    }

    /// A grant handle was issued — now prove it by reading the
    /// plist through it. Returns true when this grant is the one
    /// (loaded, or blocked by an unparseable existing file).
    private func adoptGrant(handle h: Int64, directory: String, probe: Int) -> Bool {
        let outcome = tryLoad(plistDirectory: directory)
        switch outcome {
        case .loaded, .parseBlocked:
            handle = h
            resolvedDirectory = directory
            print("[Daemons] probe \(probe) won: handle \(h) on \(directory)")
            finishLoad(outcome: outcome)
            return true
        case .ioFailure:
            print("[Daemons] probe \(probe): grant \(h) issued but the plist could not be read through it; continuing")
            releaseExtension(h)
            return false
        }
    }

    private enum LoadOutcome {
        case loaded
        case ioFailure
        case parseBlocked(String)
    }

    /// Reads and parses disabled.plist under the given directory.
    /// Missing file = empty dict (allowed). An existing file that
    /// fails to parse blocks the feature — no writes, ever.
    private func tryLoad(plistDirectory: String) -> LoadOutcome {
        let path = plistDirectory + "/" + Self.fileName
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            existingDict = [:]
            fileExisted = false
            print("[Daemons] \(path) does not exist yet — starting from an empty dict")
            return .loaded
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            print("[Daemons] read failed for \(path): \(error)")
            return .ioFailure
        }
        do {
            let parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dict = parsed as? [String: Any] else {
                print("[Daemons] \(path) parsed but is not a dictionary — refusing to touch it")
                return .parseBlocked("disabled.plist exists but is not a readable dictionary, so WorkTweaks won't change it.")
            }
            existingDict = dict
            fileExisted = true
            print("[Daemons] loaded \(path): \(dict.count) key(s), \(data.count) byte(s)")
            return .loaded
        } catch {
            print("[Daemons] parse failed for \(path): \(error) — refusing to touch it")
            return .parseBlocked("disabled.plist exists but could not be parsed, so WorkTweaks won't change it.")
        }
    }

    private func finishLoad(outcome: LoadOutcome) {
        switch outcome {
        case .loaded:
            initToggles()
            state = .ready
            print("[Daemons] ready — toggles initialized from disabled.plist")
        case .parseBlocked(let message):
            state = .blocked(code: lastProbeCode, message: message)
            print("[Daemons] blocked: \(message)")
        case .ioFailure:
            break // unreachable: ioFailure never reaches finishLoad
        }
    }

    private func finishBlocked() {
        let code = lastProbeCode
        let message: String
        switch code {
        case -6:
            message = "The kernel refused access to the launchd directory (result -6). iOS would not issue a sandbox extension for \(Self.directoryPath), so daemon settings can't be read or changed from this app."
        case -255:
            message = "The launchd directory could not be found (result -255). \(Self.directoryPath) does not appear to exist on this device."
        default:
            message = "Access to the launchd directory failed (result \(code)), so daemon settings can't be read or changed from this app."
        }
        state = .blocked(code: code, message: message)
        print("[Daemons] blocked: \(message)")
    }

    // MARK: Toggles

    /// A category is ON only when it is fully applied: every one
    /// of its labels present in the plist with value true. A
    /// partially present category counts as OFF — turning it on
    /// completes the set.
    private func initToggles() {
        var map: [String: Bool] = [:]
        for category in DaemonCatalog.all {
            map[category.id] = category.labels.allSatisfy {
                (existingDict[$0] as? NSNumber)?.boolValue == true
            }
        }
        toggles = map
    }

    // MARK: Apply

    func apply() {
        guard case .ready = state else { return }
        var merged = existingDict
        for category in DaemonCatalog.all {
            if toggles[category.id] == true {
                for label in category.labels { merged[label] = true }
            } else {
                for label in category.labels { merged.removeValue(forKey: label) }
            }
        }

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: merged, format: .xml, options: 0)
            let beforeBytes = fileExisted ? ((try? Data(contentsOf: URL(fileURLWithPath: plistPath)))?.count ?? 0) : 0
            let beforeKeys = existingDict.count
            try writeInPlace(data)
            existingDict = merged
            fileExisted = true
            print("[Daemons] wrote \(plistPath): keys \(beforeKeys) -> \(merged.count), bytes \(beforeBytes) -> \(data.count)")
            print("[Daemons] Changes saved - a full restart is required.")
            showRestartRequired = true
        } catch {
            print("[Daemons] apply failed: \(error)")
            errorMessage = "Couldn't write disabled.plist: \(error.localizedDescription)"
        }
    }

    /// In-place write, same shape as GestaltManager's mg_write:
    /// open the existing file, truncate, write, sync, verify —
    /// never an atomic replacement (a replaced file would get a
    /// new inode and could lose the access the grant negotiated).
    /// A missing file is created inside the granted directory.
    private func writeInPlace(_ data: Data) throws {
        let url = URL(fileURLWithPath: plistPath)
        if FileManager.default.fileExists(atPath: plistPath) {
            let original = try Data(contentsOf: url)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            do {
                try handle.truncate(atOffset: 0)
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: data)
                try handle.synchronize()
            } catch {
                // Roll back to the original bytes.
                try? handle.truncate(atOffset: 0)
                try? handle.seek(toOffset: 0)
                try? handle.write(contentsOf: original)
                try? handle.synchronize()
                throw error
            }
            let verify = try Data(contentsOf: url)
            guard verify == data else {
                try? handle.truncate(atOffset: 0)
                try? handle.seek(toOffset: 0)
                try? handle.write(contentsOf: original)
                try? handle.synchronize()
                throw NSError(domain: "DaemonManager", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "write verification failed"])
            }
        } else {
            guard FileManager.default.createFile(atPath: plistPath, contents: data) else {
                throw NSError(domain: "DaemonManager", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "couldn't create disabled.plist in \(resolvedDirectory)"])
            }
            let verify = try Data(contentsOf: url)
            guard verify == data else {
                throw NSError(domain: "DaemonManager", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "write verification failed"])
            }
        }
    }

    // MARK: Restart attempt (mirrors GestaltManager.attemptRestart)
    //
    // Stock iOS gives apps no public restart API, so this only
    // fires when FrontBoard's private system service answers a
    // restart selector — and says so honestly when it doesn't.

    private var restartCheckItem: DispatchWorkItem?

    func attemptRestart() {
        _ = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW)

        var invoked = false
        if let serviceClass = NSClassFromString("FBSSystemService"),
           let sharedMethod = class_getClassMethod(serviceClass, NSSelectorFromString("sharedService")) {
            typealias SharedFactory = @convention(c) (AnyObject, Selector) -> AnyObject
            let factory = unsafeBitCast(method_getImplementation(sharedMethod), to: SharedFactory.self)
            let service = factory(serviceClass, NSSelectorFromString("sharedService"))
            for name in ["reboot", "restart", "shutdown"] {
                let sel = NSSelectorFromString(name)
                if service.responds(to: sel) {
                    _ = service.perform(sel)
                    invoked = true
                    print("[Daemons] (restart) invoked FBSSystemService.\(name)")
                    break
                }
            }
        }

        let manualSteps = "Restart manually: press Volume Up, then Volume Down, then hold the Side button until the Apple logo appears — or go to Settings > General > Shut Down, slide to power off, then turn the device back on."

        if invoked {
            restartAlertTitle = "Restart Command Sent"
            restartAlertMessage = "Your device should restart within a few seconds. If you're still seeing this after 10 seconds, the restart did not actually happen.\n\n\(manualSteps)"
            restartCheckItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.restartAlertTitle != nil else { return }
                self.restartAlertTitle = "Restart Failed"
                self.restartAlertMessage = "The device did not restart, so the automatic restart failed — iOS does not give apps a reliable way to restart the device.\n\n\(manualSteps)"
                print("[Daemons] (restart) still alive after 10s — restart did not happen")
            }
            restartCheckItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
        } else {
            restartAlertTitle = "Restart Failed"
            restartAlertMessage = "Automatic restart isn't available on this device — iOS does not give apps a way to restart the device directly.\n\n\(manualSteps)"
            print("[Daemons] (restart) no restart selector available — honest failure")
        }
    }
}
