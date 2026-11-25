import Foundation
import Darwin

// MARK: - How JIT stays on
//
// Port of SideInstaller v2.2.0 `ios-app/JIT.swift` (the pure-Swift layer:
// JITProtocol / JITMode / JITDevice / JITApps / GDBRemote / GDBStopReply /
// JITSession), adapted to the LiveContainer guest model. The serve loop,
// the universal / legacy / geode calls, prepareRegion, allocateExecutable
// and copyCode are verbatim — they are the StikDebug-compatible answers.
//
// CRITICAL ADAPTATION — SELF-ATTACH, NOT DVT LAUNCH: SideInstaller
// launches the target app suspended via DVT `process_control_launch_app`
// and then `vAttach`es to its pid. A LiveContainer guest is NOT an
// installed app, so that call CANNOT work — the guest runs INSIDE
// WorkTweaks (LiveContainerMain, after the relaunch). This session
// therefore attaches to WorkTweaks' OWN pid (`getpid()`) with `vAttach`
// after the guest is running. DVT process control is NOT opened at all
// (see `WTDeviceConnection.openDebugSession` — debug-proxy-only), and
// there is no `launchSuspended` and no DVT `kill`: `quit()` detaches
// instead of killing, because killing our own pid would kill the guest
// AND WorkTweaks.
//
// THE FLOW THAT MAKES THIS POSSIBLE (see ContainerJITManager): the
// toggle ARMS the session (persists the guest + protocol), the guest
// launches via the normal relaunch, and on the next process start —
// BEFORE LiveContainerMain runs the guest — the session thread
// attaches to the still-host process. The guest's JIT calls then land
// on an already-attached debugger. `attachAndWait` is the bounded wait
// the startup path uses so the guest never starts before the attach
// has succeeded or failed.
//
// SELF-ATTACH IS UNPROVEN: no device has ever attached debugserver to
// its own pid over its own VPN tunnel. If `vAttach` fails, the toggle
// stays OFF and the UI says so + the external-enabler fallback
// (SideInstaller JIT tab / StikDebug — there is no JIT deep link).
// Login ≠ JIT; the session must stay attached in background for
// A15/iOS 27 (universal/legacy/geode protocols); on pre-A15/pre-iOS-26
// devices detach mode suffices (`JITDevice.preparesRegions` false).
//
// Logging is `print("[JIT] ...")` (Console → Log tab), like
// ContainerManager. No `L()` here — this runs off the main thread.

/// How the debugger keeps JIT on for the guest it is attached to.
///
/// Being debugged marks a process, and up to iOS 18 that's all JIT needs:
/// iOS then lets it map memory that's writable and executable until it
/// quits. From iOS 26 the chips whose Trusted Execution Monitor guards
/// code pages (`WTJITDevice`) still refuse such memory, so an app asks the
/// debugger to prepare each region it wants to write code to, with a
/// breakpoint, and the debugger has to stay attached to answer. Apps ask
/// in one of the ways StikDebug's scripts answer, so the same ways are
/// answered here, in Swift.
enum WTJITProtocol: Hashable {
    /// Attach, then let go at once.
    case detach
    /// Stay attached and answer the app's `brk #0xf00d` calls, `x16` saying
    /// which: 0 lets go of the app, 1 prepares a region (`x0` its address, or
    /// 0 to have one allocated, `x1` its size) and returns its address in
    /// `x0`. The calls StikDebug's universal script answers.
    case universal
    /// Stay attached until the app has had `regions` regions prepared with
    /// `brk #0x69` (`x0` the address, `x1` the size), then let go. The calls
    /// StikDebug's legacy script answers: UTM, DolphiniOS, Flycast and ARMSX2
    /// make one, maciOS three.
    case legacy(regions: Int)
    /// Geode's calls: `brk #0x69` prepares a region (64 KB when `x1` is 0),
    /// `#0x70` copies `x2` bytes of code from `x1` to `x0`, `#0x71` lets go.
    case geode

    /// True when the debugger stays attached while the app runs.
    var staysAttached: Bool { self != .detach }

    /// What the JIT section calls it.
    var title: String {
        switch self {
        case .detach: "Attach and detach"
        case .universal: "Universal"
        case .legacy: "Legacy"
        case .geode: "Geode"
        }
    }

    /// What the log calls it.
    var logName: String {
        switch self {
        case .detach: "attach and detach"
        case .universal: "universal calls"
        case .legacy(let regions): "legacy calls, \(regions) region\(regions == 1 ? "" : "s")"
        case .geode: "Geode's calls"
        }
    }
}

/// What the JIT section offers for a guest, kept per bundle ID.
enum WTJITMode: String, CaseIterable, Identifiable {
    /// The guest's own way when it's a known app, on an iPhone that needs one.
    case automatic
    case detach
    case universal
    case legacy
    case geode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .detach: "Attach and detach"
        case .universal: "Universal"
        case .legacy: "Legacy"
        case .geode: "Geode"
        }
    }
}

// MARK: - This device

/// Whether this iPhone needs JIT memory prepared by the debugger.
enum WTJITDevice {
    /// True from iOS 26 on the chips whose Trusted Execution Monitor guards
    /// code pages (A15 and M2 on), and from iOS 27 on all but the 2020 iPad
    /// Pros', as StikDebug tells them apart.
    static var preparesRegions: Bool {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
                ?? WTDeviceEnvironment.sysctlString("hw.machine") else {
            return major >= 27
        }
        return preparesRegions(model: model, osMajorVersion: major)
    }

    /// `preparesRegions` for a hardware model, e.g. "iPhone17,1", on an iOS
    /// major version.
    static func preparesRegions(model: String, osMajorVersion: Int) -> Bool {
        guard osMajorVersion >= 26 else { return false }
        let family = model.prefix { $0.isLetter }
        let numbers = model.dropFirst(family.count).split(separator: ",").compactMap { Int($0) }
        guard numbers.count == 2 else { return osMajorVersion >= 27 }
        let (major, minor) = (numbers[0], numbers[1])
        if osMajorVersion >= 27 {
            // The A12Z of the 2020 iPad Pros (iPad8,9–8,12) is the one without.
            return !(family == "iPad" && major == 8 && (9...12).contains(minor))
        }
        switch family {
        // iPhone14,x and iPad14,x are the first with A15 and M2.
        case "iPhone", "iPad": return major >= 14
        default: return false
        }
    }
}

// MARK: - Known apps

/// Apps known to ask for JIT one particular way, by name: the apps StikDebug
/// supports, and which of its scripts each is given.
enum WTJITApps {
    private static let known: [String: WTJITProtocol] = {
        var table: [String: WTJITProtocol] = [:]
        for name in ["Amethyst", "Andarium", "MeloNX", "XeniOS", "MeloCafé", "Manic EMU", "DukeX",
                     "TachyonU", "touchHLE", "HyperHLE", "Applesauce", "RPCS3", "AetherPS4",
                     "Husk", "Utsuro", "Henge"] {
            table[key(name)] = .universal
        }
        for name in ["UTM", "DolphiniOS", "Flycast", "ARMSX2 iOS"] {
            table[key(name)] = .legacy(regions: 1)
        }
        table[key("maciOS")] = .legacy(regions: 3)
        table[key("Geode")] = .geode
        return table
    }()

    /// A name as the table is keyed: case and accents don't matter, so
    /// "MeloCafe" finds "MeloCafé".
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func knownProtocol(forName name: String) -> WTJITProtocol? {
        known[key(name)]
    }

    /// What `mode` comes to for an app called `appName`, on a device that does
    /// or doesn't need regions prepared.
    static func resolve(_ mode: WTJITMode, appName: String, preparesRegions: Bool) -> WTJITProtocol {
        switch mode {
        case .automatic:
            // Without TXM, being debugged is all an app needs.
            guard preparesRegions else { return .detach }
            // An app that isn't on the list most likely makes the universal
            // calls, which apps written for iOS 26 make.
            return knownProtocol(forName: appName) ?? .universal
        case .detach:
            return .detach
        case .universal:
            return .universal
        case .legacy:
            if case .legacy(let regions)? = knownProtocol(forName: appName) {
                return .legacy(regions: regions)
            }
            return .legacy(regions: 1)
        case .geode:
            return .geode
        }
    }
}

// MARK: - GDB remote protocol

/// The parts of GDB's remote serial protocol that JIT takes, as debugserver
/// speaks it on arm64.
enum WTGDBRemote {
    /// Register numbers debugserver uses: x0–x28 are 0–28, then fp, lr, sp, pc.
    static let pc = 32
    /// The page size of iOS on arm64, which regions are prepared a page at a
    /// time in.
    static let pageSize: UInt64 = 16_384

    /// The sum of a packet's bytes, as two hex digits.
    static func checksum(_ data: String) -> String {
        hexByte(data.utf8.reduce(UInt8(0)) { $0 &+ $1 })
    }

    /// A packet ready to send as it is: `$data#checksum`.
    static func frame(_ data: String) -> String {
        "$\(data)#\(checksum(data))"
    }

    static func hexByte(_ value: UInt8) -> String {
        let digits = String(value, radix: 16)
        return digits.count == 1 ? "0" + digits : digits
    }

    /// A register's value as debugserver reads and writes them: 8 bytes in
    /// memory order (little-endian), in hex.
    static func littleEndianHex(_ value: UInt64) -> String {
        (0..<8).map { hexByte(UInt8(truncatingIfNeeded: value >> (8 * UInt64($0)))) }.joined()
    }

    /// Reads bytes in memory order back into a number: a register (8 bytes)
    /// or an instruction (4). Nil when it isn't whole bytes of hex.
    static func littleEndianValue<S: StringProtocol>(_ hex: S) -> UInt64? {
        let digits = Array(hex.utf8)
        guard !digits.isEmpty, digits.count % 2 == 0, digits.count <= 16 else { return nil }
        var value: UInt64 = 0
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            value |= UInt64(high << 4 | low) << (UInt64(index / 2) * 8)
        }
        return value
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return character - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    /// The immediate of a `brk #imm` instruction, nil for any other.
    static func brkImmediate(_ instruction: UInt32) -> UInt16? {
        guard instruction & 0xFFE0_001F == 0xD420_0000 else { return nil }
        return UInt16(truncatingIfNeeded: instruction >> 5)
    }

    /// How many pages `size` bytes reach into.
    static func pageCount(_ size: UInt64) -> Int {
        size == 0 ? 0 : Int((size - 1) / pageSize + 1)
    }

    /// The write that prepares the page at `address`: one byte, 0x69, at its
    /// start (what StikDebug's `prepare_memory_region` writes), framed.
    static func pageWrite(at address: UInt64) -> String {
        frame("M\(String(address, radix: 16)),1:69")
    }
}

/// debugserver's answer to an attach or a continue: why the app stopped, with
/// the stopped thread's registers, or that it's gone.
struct WTGDBStopReply: Equatable {
    enum Reason: Equatable {
        /// Stopped on this signal: a breakpoint's is SIGTRAP (5).
        case signal(UInt8)
        /// Quit, with this exit status.
        case exited(UInt8)
        /// Ended by this signal.
        case killed(UInt8)
    }

    let reason: Reason
    /// The stopped thread, as debugserver names it (hex).
    let thread: String?
    /// The registers the stop came with, by number (`WTGDBRemote.pc`).
    let registers: [Int: UInt64]

    /// Nil for anything that isn't a stop reply (`T05thread:…;00:…;`, `S05`,
    /// `W00`, `X09`).
    init?(_ reply: String) {
        guard let kind = reply.first else { return nil }
        let code = reply.dropFirst().prefix(2)
        guard code.count == 2, let number = UInt8(code, radix: 16) else { return nil }
        var thread: String?
        var registers: [Int: UInt64] = [:]
        switch kind {
        case "W":
            reason = .exited(number)
        case "X":
            reason = .killed(number)
        case "S":
            reason = .signal(number)
        case "T":
            reason = .signal(number)
            for field in reply.dropFirst(3).split(separator: ";") {
                guard let colon = field.firstIndex(of: ":") else { continue }
                let key = field[..<colon]
                let value = field[field.index(after: colon)...]
                if key == "thread" {
                    thread = String(value)
                    continue
                }
                // Registers go by their number in hex; every other key is a word.
                guard key.count <= 2, let register = Int(key, radix: 16),
                      let registerValue = WTGDBRemote.littleEndianValue(value) else { continue }
                registers[register] = registerValue
            }
        default:
            return nil
        }
        self.thread = thread
        self.registers = registers
    }
}

// MARK: - Session

/// One guest run under the debugger to turn JIT on for it: attach to
/// WorkTweaks' own pid, then serve the guest's JIT calls until the
/// debugger lets go, the guest quits, or the session is quit.
///
/// Runs on a thread of its own over a tunnel of its own, a second
/// `WTDeviceConnection`, as StikDebug opens a fresh tunnel for each
/// session: the other flows open a fresh tunnel on the shared connection
/// for each thing they do, which would end a session held on it, and one
/// that stays attached lasts as long as the app runs.
///
/// SELF-ATTACH (see the file header): the guest is already running
/// in-process when this starts — there is no launch step. The pid
/// attached to is `getpid()`, this process.
final class WTJITSession: @unchecked Sendable {

    enum Phase: Equatable {
        case connecting
        case attaching
        /// JIT is on, and the debugger stays attached answering the guest.
        case attached
        case ended(Outcome)

        var isEnded: Bool {
            if case .ended = self { return true }
            return false
        }
    }

    enum Outcome: Equatable {
        /// JIT is on and the debugger let go: at once, or once the guest
        /// had what it asked for.
        case detached(afterServing: Bool)
        /// The guest quit, or was quit, before the debugger let go.
        case appEnded
        case failed(String)
    }

    enum Event {
        case phase(Phase)
        /// A region of this many bytes was prepared for the guest.
        case prepared(UInt64)
    }

    let bundleID: String
    let name: String
    let jitProtocol: WTJITProtocol
    private let deviceIP: String
    private let pairingFilePath: String
    private let onEvent: @MainActor (Event) -> Void

    /// Guards what `quit` reads from another thread.
    nonisolated(unsafe) private let lock = NSLock()
    nonisolated(unsafe) private var debug: WTDebugServerSession?
    nonisolated(unsafe) private var quitRequested = false
    /// The session should let go at the next stop instead of serving.
    nonisolated(unsafe) private var detachRequested = false
    nonisolated(unsafe) private var started = false
    /// The attach wait (`attachAndWait`): signalled once the session is
    /// attached, or has failed to attach.
    nonisolated(unsafe) private let attachSemaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) private var attachSignalled = false
    nonisolated(unsafe) private var attachSucceeded = false

    /// Signals handed on to the guest, for the log.
    nonisolated(unsafe) private var signalsPassed = 0
    /// How many writes go out before their answers are read, when a region
    /// is prepared (as StikDebug batches them).
    private static let writesPerRound = 128
    /// Larger than any region an app means to ask for: a size past it is a
    /// garbled register, not a region.
    private static let largestRegion: UInt64 = 32 << 30
    /// The most a Geode copy may move, as Geode's script allows.
    private static let largestCopy: UInt64 = 0x40_0000

    /// `onEvent` runs on the main thread, in order.
    nonisolated init(bundleID: String, name: String, jitProtocol: WTJITProtocol, deviceIP: String,
                     pairingFilePath: String, onEvent: @escaping @MainActor (Event) -> Void) {
        self.bundleID = bundleID
        self.name = name
        self.jitProtocol = jitProtocol
        self.deviceIP = deviceIP
        self.pairingFilePath = pairingFilePath
        self.onEvent = onEvent
    }

    nonisolated func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()
        let thread = Thread { [self] in run() }
        thread.name = "worktweaks.jit"
        // The guest waits at each request until it's answered.
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Starts the session thread (if it isn't started) and waits until
    /// it is attached — or has failed to attach — up to `timeout`.
    /// Returns true when the debugger is attached to our own pid.
    ///
    /// The startup path calls this BEFORE LiveContainerMain runs the
    /// guest, so the guest never makes a JIT call before the debugger
    /// is attached. When called on the main thread, the main run loop
    /// is spun while waiting: the Bonjour advert browse (used when the
    /// pairing listener moved off port 49152) schedules its callbacks
    /// on the main run loop, and a plain semaphore wait would starve
    /// it. The wait still ends at `timeout` at the latest.
    nonisolated func attachAndWait(timeout: TimeInterval) -> Bool {
        start()
        let deadline = Date(timeIntervalSinceNow: timeout)
        while true {
            if attachSemaphore.wait(timeout: .now() + 0.1) == .success {
                lock.lock()
                let ok = attachSucceeded
                lock.unlock()
                return ok
            }
            if Date() >= deadline {
                lock.lock()
                let ok = attachSucceeded
                lock.unlock()
                return ok
            }
            if Thread.isMainThread {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
        }
    }

    /// Ends the session: the debugger lets go at the next stop (or at
    /// once, if it hasn't attached yet). There is NO kill: DVT process
    /// control is not opened in v1, and killing our own pid would kill
    /// the guest AND WorkTweaks. Before the attach, the session stops
    /// before attaching.
    nonisolated func quit() {
        lock.lock()
        quitRequested = true
        detachRequested = true
        lock.unlock()
    }

    nonisolated private var isQuitting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return quitRequested
    }

    nonisolated private var wantsDetach: Bool {
        lock.lock()
        defer { lock.unlock() }
        return detachRequested
    }

    nonisolated private func signalAttach(_ succeeded: Bool) {
        lock.lock()
        guard !attachSignalled else { lock.unlock(); return }
        attachSignalled = true
        attachSucceeded = succeeded
        lock.unlock()
        attachSemaphore.signal()
    }

    nonisolated private func report(_ event: Event) {
        let onEvent = onEvent
        DispatchQueue.main.async {
            MainActor.assumeIsolated { onEvent(event) }
        }
    }

    nonisolated private func log(_ message: String) {
        print("[JIT] \(message)")
    }

    nonisolated private func run() {
        let outcome: Outcome
        do {
            outcome = try openAndServe()
        } catch {
            outcome = .failed(describe(error))
            log("⛔️ JIT: \(Self.text(error))")
        }
        signalAttach(false)
        lock.lock()
        debug = nil
        lock.unlock()
        if signalsPassed > 0 {
            log("JIT: handed \(name) \(signalsPassed) signal(s) of its own while attached.")
        }
        report(.phase(.ended(outcome)))
    }

    nonisolated private func openAndServe() throws -> Outcome {
        report(.phase(.connecting))
        let connection = WTDeviceConnection()
        defer { connection.disconnect() }
        try connection.connect(deviceIP: deviceIP, pairingFilePath: pairingFilePath)
        if let summary = try? connection.rsdSummary() {
            log("JIT: tunnel up (\(summary)).")
        }
        let debug: WTDebugServerSession
        do {
            debug = try connection.openDebugSession()
        } catch {
            throw Failure.debugger(error)
        }
        defer { debug.close() }
        lock.lock()
        self.debug = debug
        let cancelled = quitRequested
        lock.unlock()
        if cancelled {
            signalAttach(false)
            return .appEnded
        }

        report(.phase(.attaching))
        startWithoutAcknowledgements(debug)
        // SELF-ATTACH: the guest runs in this process. vAttach to our
        // own pid. UNPROVEN — no device has done this over its own VPN
        // tunnel yet. If it fails, the outcome says so honestly and the
        // UI offers the external-enabler fallback.
        let pid = UInt64(getpid())
        let answer = try debug.send("vAttach;\(String(pid, radix: 16))") ?? ""
        guard let stop = WTGDBStopReply(answer), case .signal = stop.reason else {
            signalAttach(false)
            throw Failure.attach(answer)
        }
        log("JIT: attached to \(name) (own pid \(pid), \(jitProtocol.logName)).")
        guard jitProtocol.staysAttached else {
            detach(debug)
            signalAttach(true)
            return .detached(afterServing: false)
        }
        if isQuitting {
            detach(debug)
            signalAttach(true)
            return .appEnded
        }
        connection.startDebugHeartbeat(deviceIP: deviceIP)
        report(.phase(.attached))
        signalAttach(true)
        do {
            return try serve(debug)
        } catch let failure as Failure {
            throw failure
        } catch {
            // Quitting can close the connection under the wait.
            if isQuitting { return .appEnded }
            throw Failure.lost(error)
        }
    }

    /// debugserver acknowledges every packet until told not to. StikDebug opens
    /// it the same way and goes on whatever it answers.
    nonisolated private func startWithoutAcknowledgements(_ debug: WTDebugServerSession) {
        do {
            try debug.sendAck()
            try debug.sendAck()
            let answer = try debug.send("QStartNoAckMode")
            if answer != "OK" {
                log("JIT: debugserver answered QStartNoAckMode with \(answer ?? "nothing").")
            }
        } catch {
            log("JIT: QStartNoAckMode failed (\(error)). Going on.")
        }
        debug.setAcknowledgements(false)
    }

    nonisolated private func detach(_ debug: WTDebugServerSession) {
        do {
            let answer = try debug.send("D")
            log("JIT: let go of \(name) (\(answer ?? "no answer")).")
        } catch {
            log("JIT: letting go of \(name) failed (\(error)).")
        }
    }

    // MARK: Serving the guest

    private enum Action {
        /// Carry on, with nothing for the guest.
        case resume
        /// Carry on, handing the guest the signal it stopped on.
        case pass(signal: UInt8, thread: String)
        /// Let go of the guest.
        case detach
    }

    /// Runs the guest until it lets the debugger go, quits, or is quit,
    /// answering each request it stops with.
    nonisolated private func serve(_ debug: WTDebugServerSession) throws -> Outcome {
        var regionsLeft = Int.max
        if case .legacy(let regions) = jitProtocol { regionsLeft = regions }
        var unreadable = 0
        var answer = try resume(debug, "c")
        while true {
            if wantsDetach {
                detach(debug)
                return .detached(afterServing: true)
            }
            guard let stop = WTGDBStopReply(answer) else {
                unreadable += 1
                guard unreadable < 5 else { throw Failure.unexpected(answer) }
                log("JIT: debugserver answered “\(answer.prefix(40))”. Continuing.")
                answer = try resume(debug, "c")
                continue
            }
            unreadable = 0
            switch stop.reason {
            case .exited(let status):
                log("JIT: \(name) quit (exit status \(status)).")
                return .appEnded
            case .killed(let signal):
                log("JIT: \(name) ended on signal \(signal).")
                return .appEnded
            case .signal(let signal):
                switch try act(on: stop, signal: signal, debug, regionsLeft: &regionsLeft) {
                case .resume:
                    answer = try resume(debug, "c")
                case .pass(let signal, let thread):
                    signalsPassed += 1
                    answer = try resume(debug, "vCont;S\(WTGDBRemote.hexByte(signal)):\(thread)")
                case .detach:
                    detach(debug)
                    return .detached(afterServing: true)
                }
            }
        }
    }

    /// Continues the guest and waits until it stops. What it prints comes as O
    /// packets ahead of the stop.
    nonisolated private func resume(_ debug: WTDebugServerSession, _ command: String) throws -> String {
        var answer = try debug.send(command) ?? ""
        while answer.hasPrefix("O"), answer != "OK" {
            answer = try debug.readResponse() ?? ""
        }
        return answer
    }

    /// What a stop asks for: a breakpoint this session answers, or a signal of
    /// the guest's own.
    nonisolated private func act(on stop: WTGDBStopReply, signal: UInt8, _ debug: WTDebugServerSession,
                                 regionsLeft: inout Int) throws -> Action {
        guard let thread = stop.thread else { return .resume }
        let registers = Registers(stop: stop, thread: thread, debug: debug)
        guard let pc = try registers.value(WTGDBRemote.pc),
              let immediate = try brkImmediate(at: pc, debug) else {
            return pass(signal, thread)
        }
        switch jitProtocol {
        case .detach:
            return .detach
        case .universal:
            return try universalCall(immediate, signal: signal, pc: pc, registers)
        case .legacy:
            guard immediate == 0x69 else { return pass(signal, thread) }
            let address = try registers.value(0) ?? 0
            let size = try registers.value(1) ?? 0
            if address != 0 {
                try prepareRegion(at: address, size: size, debug)
            } else {
                log("JIT: \(name) asked for a region at address 0. Skipped.")
            }
            try registers.set(WTGDBRemote.pc, pc &+ 4)
            regionsLeft -= 1
            return regionsLeft > 0 ? .resume : .detach
        case .geode:
            return try geodeCall(immediate, signal: signal, pc: pc, registers)
        }
    }

    /// A signal that isn't a request goes on to the guest, as it would without a
    /// debugger: a breakpoint of its own crashes it, as it would anyway. Not
    /// SIGINT or SIGSTOP, which are how a debugger stops an app itself.
    nonisolated private func pass(_ signal: UInt8, _ thread: String) -> Action {
        if signal == 0 || signal == UInt8(SIGINT) || signal == UInt8(SIGSTOP) { return .resume }
        return .pass(signal: signal, thread: thread)
    }

    nonisolated private func universalCall(_ immediate: UInt16, signal: UInt8, pc: UInt64,
                                           _ registers: Registers) throws -> Action {
        let debug = registers.debug
        switch immediate {
        case 0xf00d:
            try registers.set(WTGDBRemote.pc, pc &+ 4)
            let call = try registers.value(16) ?? .max
            switch call {
            case 0:
                return .detach
            case 1:
                let requested = try registers.value(0) ?? 0
                let size = try registers.value(1) ?? 0
                guard requested != 0 || size != 0 else { return .resume }
                var address = requested
                if address == 0 {
                    guard let allocated = try allocateExecutable(size: size, debug) else { return .resume }
                    address = allocated
                }
                try prepareRegion(at: address, size: size, debug)
                try registers.set(0, address)
                return .resume
            case 2:
                log("JIT: \(name) sent the debugger a script to run (brk #0xf00d, x16 = 2). SideInstaller doesn't run scripts, so it's skipped.")
                return .resume
            default:
                log("JIT: \(name) made JIT call \(call), which SideInstaller doesn't know. Skipped.")
                return .resume
            }
        case 0x68:
            try registers.set(WTGDBRemote.pc, pc &+ 4)
            log("JIT: \(name) sent the debugger a script to run (brk #0x68). SideInstaller doesn't run scripts, so it's skipped.")
            return .resume
        case 0x69:
            try registers.set(WTGDBRemote.pc, pc &+ 4)
            // What StikDebug's universal script answers the legacy call with,
            // so an app that makes both moves on to the calls above.
            try registers.set(0, 0xE000_0069)
            log("JIT: \(name) made the legacy JIT call (brk #0x69), which Universal answers with an error. If it doesn't start, pick Legacy for it on the JIT page.")
            return .resume
        default:
            return pass(signal, registers.thread)
        }
    }

    nonisolated private func geodeCall(_ immediate: UInt16, signal: UInt8, pc: UInt64,
                                       _ registers: Registers) throws -> Action {
        let debug = registers.debug
        switch immediate {
        case 0x69:
            let address = try registers.value(0) ?? 0
            let size = try registers.value(1) ?? 0
            try prepareRegion(at: address, size: size > 0 ? size : 0x10000, debug)
            try registers.set(WTGDBRemote.pc, pc &+ 4)
            return .resume
        case 0x70:
            let destination = try registers.value(0) ?? 0
            let source = try registers.value(1) ?? 0
            let size = try registers.value(2) ?? 0
            if size > Self.largestCopy {
                log("JIT: \(name) asked to copy \(size) bytes, more than Geode's script allows. Skipped.")
            } else {
                try copyCode(from: source, to: destination, size: size, debug)
            }
            try registers.set(WTGDBRemote.pc, pc &+ 4)
            return .resume
        case 0x71:
            try registers.set(WTGDBRemote.pc, pc &+ 4)
            return .detach
        default:
            return pass(signal, registers.thread)
        }
    }

    /// The instruction at `pc`, as a breakpoint's immediate: nil when it isn't
    /// a breakpoint.
    nonisolated private func brkImmediate(at pc: UInt64, _ debug: WTDebugServerSession) throws -> UInt16? {
        let answer = try debug.send("m\(String(pc, radix: 16)),4") ?? ""
        guard answer.utf8.count == 8, let instruction = WTGDBRemote.littleEndianValue(answer) else {
            return nil
        }
        return WTGDBRemote.brkImmediate(UInt32(truncatingIfNeeded: instruction))
    }

    /// Readies a region for the guest to write code to and run it: the debugger
    /// writes a byte at the start of each of its pages, as StikDebug's
    /// `prepare_memory_region` does. The writes go out a round at a time, then
    /// their answers are read.
    nonisolated private func prepareRegion(at address: UInt64, size: UInt64, _ debug: WTDebugServerSession) throws {
        guard size > 0 else { return }
        guard size <= Self.largestRegion, address <= UInt64.max - size else {
            log("JIT: \(name) asked for \(size) bytes at 0x\(String(address, radix: 16)), more than any region. Skipped.")
            return
        }
        let pages = WTGDBRemote.pageCount(size)
        var refused = 0
        var first = 0
        while first < pages {
            let count = min(Self.writesPerRound, pages - first)
            let packets = (first..<first + count).map { page in
                WTGDBRemote.pageWrite(at: address + UInt64(page) * WTGDBRemote.pageSize)
            }
            try debug.sendRaw(Array(packets.joined().utf8))
            for _ in 0..<count {
                if try debug.readResponse() != "OK" { refused += 1 }
            }
            first += count
        }
        report(.prepared(size))
        let refusal = refused > 0 ? ", \(refused) of them refused" : ""
        log("JIT: prepared \(Self.format(size)) at 0x\(String(address, radix: 16)) for \(name) (\(pages) pages\(refusal)).")
    }

    /// Has debugserver allocate `size` bytes the guest can run, for a universal
    /// call that leaves the address to the debugger.
    nonisolated private func allocateExecutable(size: UInt64, _ debug: WTDebugServerSession) throws -> UInt64? {
        let answer = try debug.send("_M\(String(size, radix: 16)),rx") ?? ""
        guard !answer.hasPrefix("E"), let address = UInt64(answer, radix: 16), address != 0 else {
            log("JIT: debugserver couldn't allocate \(Self.format(size)) for \(name) (\(answer.isEmpty ? "no answer" : answer)).")
            return nil
        }
        return address
    }

    /// Geode's patching call: code copied from `source` to `destination` by
    /// the debugger, which may write where the guest can't, 16 KB at a time.
    nonisolated private func copyCode(from source: UInt64, to destination: UInt64, size: UInt64,
                                      _ debug: WTDebugServerSession) throws {
        let chunk: UInt64 = 0x4000
        var offset: UInt64 = 0
        while offset < size {
            let length = min(chunk, size - offset)
            let bytes = try debug.send("m\(String(source &+ offset, radix: 16)),\(String(length, radix: 16))") ?? ""
            guard bytes.utf8.count == Int(length) * 2, bytes.allSatisfy(\.isHexDigit) else {
                log("JIT: couldn't read \(name)'s code at 0x\(String(source &+ offset, radix: 16)) (\(bytes.prefix(8))). Copy stopped.")
                return
            }
            let written = try debug.send("M\(String(destination &+ offset, radix: 16)),\(String(length, radix: 16)):\(bytes)")
            guard written == "OK" else {
                log("JIT: couldn't write \(name)'s code at 0x\(String(destination &+ offset, radix: 16)) (\(written ?? "no answer")). Copy stopped.")
                return
            }
            offset += length
        }
        log("JIT: copied \(Self.format(size)) of \(name)'s code to 0x\(String(destination, radix: 16)).")
    }

    /// A stopped thread's registers: those the stop came with, the rest read
    /// from debugserver.
    private struct Registers {
        let stop: WTGDBStopReply
        let thread: String
        let debug: WTDebugServerSession

        nonisolated func value(_ number: Int) throws -> UInt64? {
            if let value = stop.registers[number] { return value }
            let answer = try debug.send("p\(String(number, radix: 16));thread:\(thread);") ?? ""
            return WTGDBRemote.littleEndianValue(answer)
        }

        nonisolated func set(_ number: Int, _ value: UInt64) throws {
            let answer = try debug.send(
                "P\(String(number, radix: 16))=\(WTGDBRemote.littleEndianHex(value));thread:\(thread);")
            if answer != "OK" {
                print("[JIT] JIT: debugserver didn't set register \(number) (\(answer ?? "no answer")).")
            }
        }
    }

    // MARK: Failures

    /// Where a session failed, for what the section says.
    private enum Failure: Error {
        /// The debugger or DVT didn't open: no disk image, or Developer Mode off.
        case debugger(Error)
        /// debugserver's answer to the attach.
        case attach(String)
        /// The connection failed while the debugger was attached.
        case lost(Error)
        /// debugserver kept answering with something that isn't a stop.
        case unexpected(String)
    }

    nonisolated private func describe(_ error: Error) -> String {
        guard let failure = error as? Failure else { return Self.text(error) }
        switch failure {
        case .debugger(let cause):
            return "Couldn't reach the debugger on this iPhone: \(Self.text(cause))"
        case .attach(let answer):
            return "The debugger couldn't attach to WorkTweaks' own process (\(answer.isEmpty ? "—" : answer)). Self-attach is unproven — try the external route instead: open the SideInstaller JIT tab or StikDebug and enable JIT from there. There is no JIT deep link."
        case .lost(let cause):
            return "The debugger lost \(name) (\(Self.text(cause))). Open it with JIT again."
        case .unexpected(let answer):
            return "The debugger lost \(name) (\(String(answer.prefix(40)))). Open it with JIT again."
        }
    }

    nonisolated static func text(_ error: Error) -> String {
        if let failure = error as? Failure {
            switch failure {
            case .debugger(let cause), .lost(let cause): return text(cause)
            case .attach(let answer), .unexpected(let answer): return "debugserver answered “\(answer.prefix(40))”"
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    nonisolated static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}
