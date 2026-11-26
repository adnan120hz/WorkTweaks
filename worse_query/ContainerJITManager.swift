import Foundation
import Combine
import Darwin

// MARK: - JIT for Install IPA on Container (Phase 3)
//
// Modelled on SideInstaller v2.2.0 `ios-app/JIT.swift:870-1127`
// (`JITManager`), adapted to the LiveContainer guest model. Only UI
// state lives here; the session does the device work over its own
// tunnel.
//
// THE FLOW — READ THIS BEFORE CHANGING IT. A guest launch KILLS the
// current process (`LCContainerPatch.launchGuest` → relaunch), so the
// task's literal "launch the guest first, then attach to our own pid"
// cannot happen in one process lifetime. The real flow is ARM →
// RELAUNCH → ATTACH AT STARTUP:
//
//   1. `enable(guest)` (this process, host UI): `getReady()` checks
//      Developer Mode + pairing file + VPN tunnel + DDI downloaded +
//      DDI mounted, then persists the pending JIT
//      (`wtJitPending`) and calls `ContainerManager.launch(guest, jit: true)`.
//      The process dies; the guest is selected for the next launch.
//   2. `resumePendingSessionIfNeeded()` (next process, App.init,
//      BEFORE `ContainerLaunch.checkSelectedGuest()`): starts the
//      `WTJITSession` thread, waits bounded (15 s) for the attach to
//      our own pid, and only then lets LiveContainerMain run the
//      guest — so the guest never makes a JIT call before the debugger
//      is attached. On attach failure the guest still launches, just
//      JIT-less, and the failure is recorded for the section to show.
//   3. While the guest runs there IS no host UI (the guest is the
//      foreground app in this process). The session serves on its
//      thread and persists its outcome to UserDefaults
//      (`wtJitLast*`); when the guest quits and the host UI returns,
//      the section shows the last outcome + prepared bytes.
//
// The toggle therefore never shows a live "JIT is ON right now" while
// the guest runs — it shows ARMED (about to relaunch with JIT) and,
// after the guest quits, the last outcome. Anything else would be a
// fake. The session's `KeepAlive` silent audio (the existing
// `KeepAlive` from PairingKeepAlive.swift — reused, not rebuilt) runs
// for the session's lifetime in the guest process, so iOS doesn't
// suspend the process while the debugger is attached; UIBackgroundModes
// `audio` is already injected by CI.
//
// One session at a time. Login ≠ JIT: this manager knows nothing
// about Apple ID sign-in (parallel workstream); it only needs the
// pairing file + VPN tunnel that already exist.

@MainActor
final class ContainerJITManager: ObservableObject {

    static let shared = ContainerJITManager()

    /// The tunnel gateway: the Local Dev VPN address (10.7.0.1). Same
    /// constant Airlift uses (`al_set_target_host("10.7.0.1")`).
    static let deviceIP = "10.7.0.1"

    /// Per-guest JIT mode, by bundle ID (`WTJITMode` raw values).
    static let modesKey = "wtJitModes"
    /// The armed session, written by `enable` and consumed once by
    /// `resumePendingSessionIfNeeded`. A `[String: String]` dictionary:
    /// bundleID / name / protocol (see `WTJITProtocol` case names:
    /// "detach", "universal", "legacy", "geode" — legacy carries its
    /// region count separately under "regions").
    static let pendingKey = "wtJitPending"
    /// Last session outcome, for the section after the guest quits.
    static let lastGuestKey = "wtJitLastGuest"
    static let lastOutcomeKey = "wtJitLastOutcome" // detached / appEnded / failed
    static let lastDetailKey = "wtJitLastDetail"
    static let lastPreparedBytesKey = "wtJitLastPreparedBytes"
    static let lastEndedAtKey = "wtJitLastEndedAt"

    /// How long the startup path waits for the attach before letting
    /// the guest run anyway (JIT-less). The guest must not start before
    /// the attach succeeds or fails, but the launch must not hang
    /// forever on a dead tunnel either.
    static let attachTimeout: TimeInterval = 15

    /// The session running in this process (guest process only). Kept
    /// so it is never dropped while its thread serves; the thread also
    /// retains it. Nil in the host UI process.
    static var activeSession: WTJITSession?

    @Published private(set) var isPreparing = false
    /// True while a JIT arm is persisted and the relaunch hasn't
    /// happened yet (only visible in the host UI process, briefly).
    @Published private(set) var isArmed = false
    @Published var lastError: String?
    /// The last session outcome, read from UserDefaults (see
    /// `refreshLastOutcome()`).
    @Published private(set) var lastOutcome: String?
    @Published private(set) var lastOutcomeDetail: String?
    @Published private(set) var lastPreparedBytes: UInt64 = 0
    @Published private(set) var lastGuestName: String?
    @Published private(set) var lastEndedAt: Date?

    /// What was picked for each guest, by bundle ID.
    @Published private var modes: [String: String] =
        UserDefaults.standard.dictionary(forKey: ContainerJITManager.modesKey) as? [String: String] ?? [:]

    /// Silent audio, so the process isn't suspended while the debugger
    /// stays attached to the guest. The existing `KeepAlive` from
    /// PairingKeepAlive.swift — reused, not rebuilt.
    private let keepAlive = KeepAlive()

    private var containerManager: ContainerManager { ContainerManager.shared }

    var isBusy: Bool { isPreparing }

    // MARK: - Per-guest mode

    func mode(for guest: ContainerGuest) -> WTJITMode {
        modes[guest.bundleID].flatMap(WTJITMode.init(rawValue:)) ?? .automatic
    }

    func setMode(_ mode: WTJITMode, for guest: ContainerGuest) {
        modes[guest.bundleID] = mode == .automatic ? nil : mode.rawValue
        UserDefaults.standard.set(modes, forKey: Self.modesKey)
    }

    /// How JIT stays on for `guest` here, with the mode picked for it.
    func jitProtocol(for guest: ContainerGuest) -> WTJITProtocol {
        WTJITApps.resolve(mode(for: guest), appName: guest.displayName,
                          preparesRegions: WTJITDevice.preparesRegions)
    }

    /// The legacy region count the resolved protocol carries (1 when
    /// the mode is legacy and the guest isn't a known legacy app).
    func legacyRegions(for guest: ContainerGuest) -> Int {
        if case .legacy(let regions) = jitProtocol(for: guest) { return regions }
        return 1
    }

    // MARK: - Arm (host UI process)

    /// Arms JIT for `guest`: checks the transport + Developer Mode +
    /// DDI, persists the pending JIT, then launches the guest (which
    /// relaunches this process — `launch` does not return on success).
    /// The session itself starts on the next launch, before the guest
    /// runs (see `resumePendingSessionIfNeeded`).
    func enable(_ guest: ContainerGuest) {
        guard !isBusy else { return }
        // Persistent JIT diagnostics: the tap + the gate
        // result, with the booleans that explain it.
        WTJITDiag.append(step: "enable", detail: "tap \(guest.bundleID) jitLaunchable=\(guest.isJITLaunchable) patched=\(guest.isPatched) 32bit=\(guest.is32bit) signed=\(guest.signed) certStored=\(LCContainerPatch.hasCertificate())")
        // JIT-scoped gate: an unsigned guest may arm JIT when a
        // certificate is stored (LC's iOS 26 gate only checks a cert
        // IS stored; the debugger attaches before the guest runs).
        // "Needs certificate" is only honest when NO cert is stored.
        guard guest.isJITLaunchable else {
            if guest.is32bit {
                lastError = "32-bit — needs JIT + classic mode, which is not in this build."
            } else if !guest.isPatched {
                lastError = "Not patched yet — install it again before enabling JIT."
            } else {
                lastError = "Needs certificate to launch — import a .p12 first."
            }
            WTJITDiag.append(step: "enable", detail: "gate refused for \(guest.bundleID): \(lastError ?? "unknown reason")")
            return
        }
        lastError = nil
        isPreparing = true
        let jitProtocol = jitProtocol(for: guest)
        let regions = legacyRegions(for: guest)
        print("[JIT] === JIT: \(guest.displayName) (\(guest.bundleID), \(jitProtocol.logName)) ===")
        Task {
            do {
                do {
                    try await getReady()
                } catch {
                    // Diagnostics only: the outer catch below
                    // still handles the failure (clears the
                    // pending JIT, reports it). This inner catch
                    // just records which phase failed.
                    WTJITDiag.append(step: "getReady", detail: "error: \((error as? LocalizedError)?.errorDescription ?? String(describing: error))")
                    throw error
                }
                WTJITDiag.append(step: "getReady", detail: "ok")
                Self.persistPending(guest: guest, jitProtocol: jitProtocol, regions: regions)
                WTJITDiag.append(step: "pending", detail: "persisted \(guest.bundleID) protocol=\(jitProtocol.logName)")
                isArmed = true
                isPreparing = false
                // Relaunch into the guest. On success the process
                // dies inside launch() (SIGKILL once iOS confirms
                // the self-open), so launch() never returns and the
                // lines after it never run — the pending JIT stays
                // armed for the next process to consume. launch()
                // returns or throws ONLY when the launch didn't
                // take; the catch below then clears the pending JIT
                // and reports the failure honestly. (The old code
                // awaited a fire-and-forget launch that returned
                // the moment the open was *requested*, so the
                // cleanup below ran in microseconds and cleared
                // the pending JIT before the SIGKILL landed.)
                try await containerManager.launch(guest, jit: true)
                // Defensive only: launch() should never return on
                // success. If it ever does, the launch didn't take
                // — route through the same failure path as a throw,
                // so the catch below clears the pending JIT.
                throw ContainerError.message("The guest didn't launch — JIT was not armed.")
            } catch {
                // The launch didn't take (or getReady() failed
                // first, in which case nothing was persisted and
                // this is a no-op): the pending JIT must not survive
                // into the next host-UI launch, so clear it and
                // disarm now.
                Self.clearPending()
                isArmed = false
                isPreparing = false
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                lastError = message
                WTJITDiag.append(step: "enable", detail: "failed: \(message)")
                print("[JIT] ⛔️ JIT: \(message)")
            }
        }
    }

    /// Disarms a pending JIT (before the relaunch). There is no live
    /// session to stop in the host UI process.
    func disarm() {
        Self.clearPending()
        isArmed = false
        lastError = nil
    }

    /// Developer Mode, the pairing file, the VPN tunnel, and the
    /// developer disk image, which debugserver comes with.
    private func getReady() async throws {
        // Fast local check first (sysctl, no tunnel): a definite "off"
        // refuses at once; "unknown" (nil) goes on — the lockdownd
        // check after connect is authoritative.
        if WTDeviceEnvironment.developerModeIsOn == false {
            throw ContainerError.message("JIT needs Developer Mode. Turn it on under Settings › Privacy & Security › Developer Mode, and confirm it after the restart.")
        }
        guard PairingStore.hasPairingFile else {
            throw ContainerError.message("No pairing file — pair this iPhone first in Sandbox → Utilities → Get Pairing File.")
        }
        guard VPNTunnelStatus.isTunnelUp else {
            throw ContainerError.message("Local Dev VPN isn't connected. Connect it, then try again.")
        }
        if !WTDeveloperDiskImage.isDownloaded {
            print("[JIT] Developer disk image not downloaded — downloading…")
            try await WTDeveloperDiskImage.downloadMissing { _ in }
        }
        // Hoisted before the detached task: PairingController is a
        // MainActor class, so its pairing path can't be read from the
        // detached (nonisolated) closure. The step counter lives inside
        // the detached task for the same reason — the mount progress
        // closure runs on the main thread (via the FFI callback), but
        // it is created in the detached task.
        let pairingPath = PairingController.pairingFilePath()
        let deviceIP = Self.deviceIP
        let mounted = try await Task.detached(priority: .userInitiated) { () throws -> Bool in
            let connection = WTDeviceConnection()
            defer { connection.disconnect() }
            try connection.connect(deviceIP: deviceIP, pairingFilePath: pairingPath)
            // Authoritative Developer Mode check, over lockdownd.
            if try connection.developerModeEnabled() == false {
                throw ContainerError.message("JIT needs Developer Mode. Turn it on under Settings › Privacy & Security › Developer Mode, and confirm it after the restart.")
            }
            let count = try connection.mountedDeveloperImageCount()
            if count > 0 {
                print("[JIT] Developer disk image already mounted (\(count) image(s)).")
                return false
            }
            print("[JIT] No developer disk image mounted — mounting the personalized one…")
            var lastLogged = -1
            try connection.mountPersonalizedDeveloperImage(
                imagePath: WTDeveloperDiskImage.imagePath,
                trustcachePath: WTDeveloperDiskImage.trustcachePath,
                manifestPath: WTDeveloperDiskImage.manifestPath) { fraction in
                    let step = Int(fraction * 4) * 25
                    guard step > lastLogged else { return }
                    lastLogged = step
                    print("[JIT] DDI mount: \(step)%")
                }
            print("[JIT] Developer disk image mounted.")
            return true
        }.value
        _ = mounted
    }

    // MARK: - Resume at startup (guest process)

    /// Starts the armed JIT session for the guest this process is about
    /// to run. Call from `WorkTweaksApp.init()`, on the main thread,
    /// BEFORE `ContainerLaunch.checkSelectedGuest()`:
    ///
    ///     ContainerJITManager.resumePendingSessionIfNeeded()
    ///     ContainerLaunch.checkSelectedGuest()
    ///
    /// No-op when nothing is armed. Attaches to this process's own pid
    /// and waits up to `attachTimeout` for the attach; the guest never
    /// starts before the attach has succeeded or failed. On failure the
    /// guest still launches (JIT-less) and the failure is recorded for
    /// the section to show when the host UI returns — nothing here
    /// throws, and nothing here stops the launch.
    nonisolated static func resumePendingSessionIfNeeded() {
        precondition(Thread.isMainThread, "resumePendingSessionIfNeeded runs from WorkTweaksApp.init(), on the main thread")
        MainActor.assumeIsolated {
            Self.resumeOnMainThread()
        }
    }

    @MainActor
    private static func resumeOnMainThread() {
        guard let pending = UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String],
              let bundleID = pending["bundleID"], !bundleID.isEmpty else {
            // Diagnostics: one line per launch even when
            // nothing is armed — it proves the app actually
            // relaunched (vs never relaunching at all).
            WTJITDiag.append(step: "resume", detail: "no pending JIT")
            return
        }
        // Consumed once: a crash must not re-arm forever.
        UserDefaults.standard.removeObject(forKey: pendingKey)
        shared.isArmed = false
        let name = pending["name"] ?? bundleID
        let jitProtocol = decodePendingProtocol(pending)
        WTJITDiag.append(step: "resume", detail: "pending JIT found \(bundleID) name=\(name) protocol=\(jitProtocol.logName)")
        guard let selected = UserDefaults.standard.string(forKey: "selected"), !selected.isEmpty else {
            // No guest is about to run — the relaunch didn't happen.
            // Attaching would serve nothing.
            recordOutcome(guestName: name, outcome: "failed",
                          detail: "JIT was armed, but no guest was selected when the app launched, so the session never started.",
                          preparedBytes: 0)
            WTJITDiag.append(step: "resume", detail: "no guest selected — pending dropped, session never started")
            print("[JIT] Pending JIT dropped: no guest selected at launch.")
            return
        }
        _ = selected
        print("[JIT] === JIT (startup): \(name) (\(bundleID), \(jitProtocol.logName)) — attaching to own pid before the guest runs ===")
        WTJITDiag.append(step: "attach", detail: "start for \(name) (\(bundleID)) timeout=\(Int(attachTimeout))s")
        shared.keepAlive.startAudio()
        let session = WTJITSession(bundleID: bundleID, name: name, jitProtocol: jitProtocol,
                                   deviceIP: deviceIP,
                                   pairingFilePath: PairingController.pairingFilePath()) { event in
            Self.handleSessionEvent(event, guestName: name)
        }
        activeSession = session
        // Watchdog-relevant timing: how long the init-time
        // attach wait took. The guest never starts before this
        // returns, so a wait near the 15 s timeout is the prime
        // suspect if the new process dies at startup (H2).
        let attachStart = Date()
        let attached = session.attachAndWait(timeout: attachTimeout)
        let attachElapsed = Date().timeIntervalSince(attachStart)
        if attached {
            WTJITDiag.append(step: "attach", detail: "attached in \(String(format: "%.1f", attachElapsed))s")
            print("[JIT] JIT attached at startup for \(name) — the guest runs under the debugger now.")
        } else {
            // A wait that ran the full timeout vs one that
            // failed early are different failures: the session
            // thread signals failure promptly when it knows,
            // so elapsed << timeout means "failed", elapsed ~=
            // timeout means "timed out".
            let outcome = attachElapsed >= attachTimeout - 0.5 ? "timed out" : "failed"
            WTJITDiag.append(step: "attach", detail: "\(outcome) after \(String(format: "%.1f", attachElapsed))s — guest launches without JIT")
            // The session thread is still running and will report its
            // own failure via onEvent; this records the timeout so the
            // section has something to show even if the thread never
            // reports back.
            recordOutcome(guestName: name, outcome: "failed",
                          detail: "The debugger didn't attach within \(Int(attachTimeout)) seconds. The guest launched without JIT — try the external route: SideInstaller JIT tab / StikDebug (there is no JIT deep link).",
                          preparedBytes: 0)
            print("[JIT] ⛔️ JIT: attach timed out after \(Int(attachTimeout)) s; guest launches without JIT.")
        }
    }

    /// The `WTJITProtocol` a persisted pending dict encodes.
    private static func decodePendingProtocol(_ pending: [String: String]) -> WTJITProtocol {
        switch pending["protocol"] {
        case "detach": return .detach
        case "universal": return .universal
        case "legacy": return .legacy(regions: Int(pending["regions"] ?? "") ?? 1)
        case "geode": return .geode
        default: return .universal
        }
    }

    private static func persistPending(guest: ContainerGuest, jitProtocol: WTJITProtocol, regions: Int) {
        var pending: [String: String] = [
            "bundleID": guest.bundleID,
            "name": guest.displayName,
        ]
        switch jitProtocol {
        case .detach: pending["protocol"] = "detach"
        case .universal: pending["protocol"] = "universal"
        case .legacy: pending["protocol"] = "legacy"; pending["regions"] = String(regions)
        case .geode: pending["protocol"] = "geode"
        }
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }

    private static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    // MARK: - Session events → persisted outcome

    /// Records a session event's outcome to UserDefaults (and the
    /// shared manager's published state when it exists), so the section
    /// can show it after the guest quits and the host UI returns.
    @MainActor
    private static func handleSessionEvent(_ event: WTJITSession.Event, guestName: String) {
        switch event {
        case .phase(let phase):
            switch phase {
            case .attached:
                print("[JIT] JIT is on for \(guestName).")
            case .ended(let outcome):
                shared.keepAlive.stopAudio()
                activeSession = nil
                switch outcome {
                case .detached(let afterServing):
                    WTJITDiag.append(step: "session", detail: "ended: detached for \(guestName)")
                    recordOutcome(guestName: guestName, outcome: "detached",
                                  detail: afterServing
                                    ? "\(guestName) has the JIT memory it asked for, so WorkTweaks let go of it. JIT stays on until it quits."
                                    : "JIT is on for \(guestName) until it quits.",
                                  preparedBytes: shared.lastPreparedBytes)
                    print("[JIT] JIT: on for \(guestName).")
                case .appEnded:
                    WTJITDiag.append(step: "session", detail: "ended: guest quit \(guestName)")
                    recordOutcome(guestName: guestName, outcome: "appEnded",
                                  detail: "\(guestName) quit, so the JIT session ended.",
                                  preparedBytes: shared.lastPreparedBytes)
                    print("[JIT] JIT: session for \(guestName) ended.")
                case .failed(let message):
                    WTJITDiag.append(step: "session", detail: "ended: failed for \(guestName): \(message)")
                    recordOutcome(guestName: guestName, outcome: "failed",
                                  detail: message,
                                  preparedBytes: shared.lastPreparedBytes)
                    print("[JIT] ⛔️ JIT: \(message)")
                }
            default:
                break
            }
        case .prepared(let bytes):
            let total = shared.lastPreparedBytes + bytes
            shared.lastPreparedBytes = total
            UserDefaults.standard.set(Int(total), forKey: lastPreparedBytesKey)
        }
    }

    /// Writes one outcome row. `preparedBytes` comes from the manager's
    /// running total (0 when called before any region was prepared).
    @MainActor
    private static func recordOutcome(guestName: String, outcome: String, detail: String, preparedBytes: UInt64) {
        UserDefaults.standard.set(guestName, forKey: lastGuestKey)
        UserDefaults.standard.set(outcome, forKey: lastOutcomeKey)
        UserDefaults.standard.set(detail, forKey: lastDetailKey)
        UserDefaults.standard.set(Int(preparedBytes), forKey: lastPreparedBytesKey)
        UserDefaults.standard.set(Date(), forKey: lastEndedAtKey)
        shared.lastGuestName = guestName
        shared.lastOutcome = outcome
        shared.lastOutcomeDetail = detail
        shared.lastPreparedBytes = preparedBytes
        shared.lastEndedAt = Date()
    }

    /// Re-reads the last outcome from UserDefaults (call on appear —
    /// the guest process wrote it while this process was gone).
    func refreshLastOutcome() {
        lastGuestName = UserDefaults.standard.string(forKey: Self.lastGuestKey)
        lastOutcome = UserDefaults.standard.string(forKey: Self.lastOutcomeKey)
        lastOutcomeDetail = UserDefaults.standard.string(forKey: Self.lastDetailKey)
        lastPreparedBytes = UInt64(UserDefaults.standard.integer(forKey: Self.lastPreparedBytesKey))
        lastEndedAt = UserDefaults.standard.object(forKey: Self.lastEndedAtKey) as? Date
        isArmed = UserDefaults.standard.dictionary(forKey: Self.pendingKey) != nil
    }

    /// Clears the last outcome row (section's "Clear" button).
    func clearLastOutcome() {
        for key in [Self.lastGuestKey, Self.lastOutcomeKey, Self.lastDetailKey,
                    Self.lastPreparedBytesKey, Self.lastEndedAtKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        lastOutcome = nil
        lastOutcomeDetail = nil
        lastPreparedBytes = 0
        lastGuestName = nil
        lastEndedAt = nil
    }
}
