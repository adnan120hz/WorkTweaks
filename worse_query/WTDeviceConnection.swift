import Foundation
import WTIDevice
import Darwin

// MARK: - JIT transport (RPPairing tunnel + RSD services)
//
// Port of the JIT-relevant subset of SideInstaller v2.2.0
// `ios-app/DeviceConnection.swift` (MIT, FrizzleM; idevice FFI by
// jkcoxson), adapted to WorkTweaks:
//
// - RPPAIRING ROUTE ONLY. The CoreDeviceProxy / lockdown route
//   (`tunnel_create_usb`, `idevice_tcp_provider_new`, `lockdownd_new`,
//   `lockdownd_pair`) is NOT ported: from iOS 26.4 on, lockdownd hangs up
//   on loopback connections, so that route cannot work on this user's
//   iOS 27.0.1 anyway. One tunnel, one pairing-file kind.
// - NO PROBE / KNOCK. SideInstaller's `si_probe_pairing_port` /
//   `si_find_pairing_port` (its own Rust helpers) are skipped in v1: the
//   listener is dialled on port 49152 first, then on the port this iPhone
//   advertises over Bonjour (`_remotepairing._tcp`). Port-knocking
//   (49152–65535) is the known gap if the listener is on neither.
// - DEBUG-PROXY-ONLY debug session. `openDebugSession` opens
//   debugserver directly over RSD; DVT's remote server + process
//   control are NOT opened (see WTDebugServerSession). A LiveContainer
//   guest runs inside WorkTweaks, so there is no installed app to launch
//   suspended — the session attaches to WorkTweaks' own pid with
//   vAttach instead.
// - Logging is `print("[JIT] ...")`, like ContainerManager's
//   `print("[Container] ...")`: stdout is captured by the Console into
//   the Log tab. No `L()` here — this runs off the main thread, and the
//   UI translates error strings with `wtLang.tr` at display time, the
//   same way ContainerView does for `manager.lastResult`.
//
// Every call blocks, so never call these on the main thread — except
// `WTDeviceEnvironment.developerModeIsOn`, which is a local sysctl.
// The class is `@unchecked Sendable` with `nonisolated` members for the
// same reason: the JIT session drives it from its own thread. (The
// project sets default actor isolation to MainActor, so the
// `nonisolated` annotations are load-bearing, not decoration.)

/// Whether Developer Mode is on, from the
/// `security.mac.amfi.developer_mode_status` sysctl AMFI publishes; nil
/// when this iOS won't let the app read it. Port of
/// `Engine.developerModeIsOn` (SideInstaller).
enum WTDeviceEnvironment {
    nonisolated static var developerModeIsOn: Bool? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("security.mac.amfi.developer_mode_status", &value, &size, nil, 0) == 0,
              size == MemoryLayout<Int32>.size else { return nil }
        return value != 0
    }

    /// The hardware model, e.g. "iPhone14,7"; the simulated one in the
    /// simulator. Port of `ProblemReport.sysctlString`.
    nonisolated static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: buffer)
        return text.isEmpty ? nil : text
    }
}

/// What kind of pairing file this is, read from its plist keys. Port of
/// `PairingFileKind` (SideInstaller `PairingTargets.swift`).
struct WTPairingFileKind: Hashable {
    /// RPPairing record (`public_key`, `private_key`, `identifier`), used
    /// by `tunnel_create_rppairing`. Created by on-device pairing
    /// (iOS 27+) and on a computer by idevice_pair's "Remote pairing".
    let hasRemotePairing: Bool
    /// Lockdown record (`HostCertificate`, `HostPrivateKey`,
    /// `DeviceCertificate`). NOT used by the v1 JIT route.
    let hasLockdown: Bool
    /// The device's UDID, if the file includes one.
    let udid: String?

    var isUsable: Bool { hasRemotePairing || hasLockdown }

    static let none = WTPairingFileKind(hasRemotePairing: false, hasLockdown: false, udid: nil)

    nonisolated static func of(path: String) -> WTPairingFileKind {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return .none }
        return of(data: data)
    }

    nonisolated static func of(data: Data) -> WTPairingFileKind {
        guard !data.isEmpty,
              let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = parsed as? [String: Any]
        else { return .none }

        // idevice rejects a key that isn't exactly 32 bytes, so check the
        // length here too rather than calling a file usable that it will
        // refuse.
        let ed25519 = { (key: String) in (dict[key] as? Data)?.count == 32 }
        let remote = ed25519("public_key") && ed25519("private_key")
            && (dict["identifier"] as? String)?.isEmpty == false

        let present = { (key: String) in
            (dict[key] as? Data)?.isEmpty == false || (dict[key] as? String)?.isEmpty == false
        }
        let lockdown = present("HostCertificate") && present("HostPrivateKey")
            && present("DeviceCertificate")

        let udid = (dict["UDID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return WTPairingFileKind(hasRemotePairing: remote, hasLockdown: lockdown, udid: udid)
    }
}

final class WTDeviceConnection: @unchecked Sendable {

    // idevice opaque handles import as OpaquePointer.
    nonisolated(unsafe) private var adapter: OpaquePointer?
    nonisolated(unsafe) private var handshake: OpaquePointer?
    /// Answers the heartbeat over the RSD tunnel while a debugger stays
    /// attached to an app over this connection (`startDebugHeartbeat`).
    nonisolated(unsafe) private var debugHeartbeat: WTLockdownHeartbeat?
    /// The port this iPhone's remote-pairing listener was found on when it
    /// wasn't `rsdPort`: the one it advertised. The next connect dials it
    /// first, so the search runs once per run of the app. The listener
    /// only moves when it starts again, as it does when the iPhone
    /// restarts, which ends the run anyway.
    nonisolated(unsafe) private var movedListenerPort: UInt16?

    nonisolated init() {}

    /// RemoteServiceDiscovery port reached over the VPN loopback.
    nonisolated static let rsdPort: UInt16 = 49152

    nonisolated var isConnected: Bool { adapter != nil && handshake != nil }

    struct FFIError: Error, CustomStringConvertible {
        let code: Int32
        let subCode: Int32
        let message: String
        var description: String { "idevice FFI error code=\(code) sub=\(subCode): \(message)" }
    }

    /// A tunnel failure with user-facing advice, plus the raw FFI error
    /// for logs. The raw FFI message only shows the last attempt's errno,
    /// which looks the same for very different causes (port-filtering
    /// VPN, no listener, stale pairing file). The Rust side classifies
    /// the cause into `kind`.
    struct TunnelError: Error, CustomStringConvertible, LocalizedError {
        let kind: TunnelFailureKind
        let advice: String
        /// The unclassified FFI error, for the debug log — never presented.
        let underlying: FFIError
        var description: String { advice }
        var errorDescription: String? { advice }
    }

    /// Consume an `IdeviceFfiError*` into an `FFIError` (null == success).
    nonisolated private func ffiError(_ err: UnsafeMutablePointer<IdeviceFfiError>?,
                                      _ fallback: String) -> FFIError? {
        Self.takeFFIError(err, fallback)
    }

    /// `ffiError` for code that runs without a connection, like the
    /// heartbeat's thread.
    nonisolated fileprivate static func takeFFIError(_ err: UnsafeMutablePointer<IdeviceFfiError>?,
                                                     _ fallback: String) -> FFIError? {
        guard let err = err else { return nil }
        let code = err.pointee.code
        let sub = err.pointee.sub_code
        let msg = err.pointee.message.flatMap { String(validatingUTF8: $0) } ?? fallback
        idevice_error_free(err)
        return FFIError(code: code, subCode: sub, message: msg.isEmpty ? fallback : msg)
    }

    /// Turn a returned IdeviceFfiError* into a thrown error (null ==
    /// success).
    nonisolated private func check(_ err: UnsafeMutablePointer<IdeviceFfiError>?, _ fallback: String) throws {
        if let error = ffiError(err, fallback) { throw error }
    }

    nonisolated private func fail(_ message: String) -> FFIError {
        FFIError(code: -1, subCode: 0, message: message)
    }

    /// User-facing advice for each tunnel failure kind, listing the hosts
    /// that were tried. `port` is the remote-pairing port dialled last.
    nonisolated private func tunnelAdvice(kind: TunnelFailureKind,
                                          deviceIP: String,
                                          port: UInt16 = WTDeviceConnection.rsdPort,
                                          candidates: [String],
                                          raw: FFIError?) -> String {
        let tried = ([deviceIP, "127.0.0.1"] + candidates).joined(separator: ", ")
        switch kind {
        case TunnelFailureHostsRefused:
            return """
                The device answered on the RSD port at \(deviceIP), then the tunnel port \
                it opened was unreachable on that same address — dropped or refused, \
                across \(tried). The device is there; what's in front of it is forwarding \
                some ports and not others. The tunnel opens on a fresh high port every \
                attempt, so a rule-based proxy that forwards the RSD port alone can never \
                cover it. Use a loopback VPN that blanket-forwards every port on the RSD \
                subnet. Re-pairing won't help — the pairing is fine.
                """
        case TunnelFailureTimeout:
            return """
                The tunnel port never answered and never refused on any address \
                (\(tried)) — the connection is being swallowed rather than rejected. \
                That's usually a VPN or firewall dropping traffic on the RSD subnet. \
                Check the VPN is still up, then try again.
                """
        case TunnelFailureTlsHandshake:
            return """
                Something accepted the tunnel connection but failed the encrypted \
                handshake on top of it. Either another process holds that port, or this \
                pairing file's key no longer matches the device. Pair again, and if that \
                doesn't take, restart the loopback VPN.
                """
        case TunnelFailurePairVerify:
            return """
                The device rejected this pairing file: it's for a different device, or \
                the pairing was revoked (a reset, a restore, or Developer Mode being \
                turned off). Pair with this iPhone again to get a fresh file.
                """
        case TunnelFailureRsdUnreachable:
            // ECONNREFUSED means the tunnel works and the address is right,
            // but nothing is listening on the pairing port (often Developer
            // Mode is off), so don't blame the VPN. iOS says whether
            // Developer Mode is on, where it lets the app read it.
            if Self.wasRefused(raw) {
                switch WTDeviceEnvironment.developerModeIsOn {
                case false?:
                    return "Something at \(deviceIP):\(port) refused the connection, so the tunnel is carrying traffic, but this iPhone isn't listening on its pairing port: Developer Mode is off. Turn it on under Settings › Privacy & Security › Developer Mode (the iPhone restarts), then try again."
                case true?:
                    return "Something at \(deviceIP):\(port) refused the connection, so the tunnel is carrying traffic, but this iPhone isn't listening on its pairing port, although Developer Mode is on. Pair this iPhone again (Sandbox → Utilities → Get Pairing File), then try again. If it still fails, restart the iPhone."
                case nil:
                    return "Something at \(deviceIP):\(port) refused the connection, so the tunnel is carrying traffic — the device just isn't listening on its pairing port. That port only opens while Developer Mode is on, and iOS asks for it again after every restart: turn it on under Settings › Privacy & Security › Developer Mode, then try again. If it's already on, pair this iPhone again (Sandbox → Utilities → Get Pairing File)."
                }
            }
            return """
                Couldn't reach the device at \(deviceIP):\(port) at all. The \
                loopback VPN is most likely off, or Device IP isn't the address it \
                carries: in LocalDevVPN that's the one under Settings › Device IP \
                (10.7.0.1 by default), not the "Connected to" address on its main screen.
                """
        default:
            return """
                The tunnel didn't come up, and the failure didn't match any known cause. \
                The raw error is in the log.
                """
        }
    }

    /// True if the connection was refused rather than timed out. Both are
    /// classified as `RsdUnreachable`, so this checks the raw message.
    nonisolated static func wasRefused(_ raw: FFIError?) -> Bool {
        guard let message = raw?.message.lowercased() else { return false }
        return message.contains("connection refused") || message.contains("os error 61")
    }

    /// True when iOS itself refused the connection (EPERM), before
    /// anything left this iPhone. It does that for the iPhone's own
    /// addresses: loopback, its Wi-Fi address, and a loopback VPN's own
    /// end of the tunnel.
    nonisolated static func wasBlockedLocally(_ error: Error) -> Bool {
        let raw = (error as? FFIError) ?? (error as? TunnelError)?.underlying
        guard let message = raw?.message.lowercased() else { return false }
        return message.contains("operation not permitted") || message.contains("os error 1)")
    }

    /// `error` as a tunnel failure iOS refused itself, with advice instead
    /// of the raw errno.
    nonisolated private func blockedLocally(_ error: Error, deviceIP: String) -> TunnelError {
        let raw = (error as? FFIError) ?? (error as? TunnelError)?.underlying
            ?? fail(String(describing: error))
        return TunnelError(
            kind: TunnelFailureRsdUnreachable,
            advice: "iOS refused the connection to \(deviceIP) on this iPhone, before anything was sent. It does that for this iPhone's own addresses, like the “Connected to” address on LocalDevVPN's main screen. Device IP, in Settings › Advanced, has to be the address under LocalDevVPN's Settings › Device IP: 10.7.0.1 by default. If it already is, turn LocalDevVPN off and on again, then try again.",
            underlying: raw)
    }

    // MARK: Connect / disconnect

    /// Opens the loopback tunnel and RSD handshake over the RPPairing
    /// route (`tunnel_create_rppairing`): straight to the device's
    /// remote-pairing listener with an Ed25519 record, from on-device
    /// pairing (iOS 27+) or made on a computer (idevice_pair's "Remote
    /// pairing"). v1 has no other route: the lockdown/CoreDeviceProxy
    /// route is not ported (see the file header).
    nonisolated func connect(deviceIP: String, pairingFilePath: String, hostname: String = "WorkTweaks") throws {
        let kind = WTPairingFileKind.of(path: pairingFilePath)
        guard kind.hasRemotePairing else {
            throw fail("\((pairingFilePath as NSString).lastPathComponent) isn't a remote-pairing file: it carries no remote-pairing key pair (public_key / private_key / identifier). Pair this iPhone (Sandbox → Utilities → Get Pairing File) or import a remote-pairing file.")
        }
        do {
            try connectRemotePairing(deviceIP: deviceIP,
                                     pairingFilePath: pairingFilePath,
                                     hostname: hostname)
        } catch {
            if Self.wasBlockedLocally(error) {
                throw blockedLocally(error, deviceIP: deviceIP)
            }
            throw error
        }
    }

    /// The RPPairing route: straight to the device's remote-pairing
    /// listener.
    ///
    /// The listener is dialled on `rsdPort`, the port it nearly always
    /// has. It takes whatever port is free when it starts, so when it
    /// isn't there it's looked for on the port this iPhone advertises
    /// over Bonjour (`WTNetworkStatus.ownRemotePairingAdvert`). The next
    /// connect dials the port it was found on first (`movedListenerPort`).
    ///
    /// v1 difference from SideInstaller: no `si_probe_pairing_port`
    /// probe before each dial and no `si_find_pairing_port` knock over
    /// 49152–65535 — those are SideInstaller's own Rust helpers, not
    /// vendored. A dial that fails refused moves on to the next port;
    /// any other failure throws at once. The Rust dial itself is
    /// bounded (breadth-first sweep, ~18 s worst case).
    nonisolated private func connectRemotePairing(deviceIP: String, pairingFilePath: String,
                                                  hostname: String) throws {
        var pf: OpaquePointer?
        try pairingFilePath.withCString { p in
            try check(rp_pairing_file_read(p, &pf), "failed to read pairing file at \(pairingFilePath)")
        }
        guard let pairingFile = pf else { throw fail("pairing file handle was null") }
        defer { rp_pairing_file_free(pairingFile) }

        // createListener returns a port but no host, so the Rust side tries
        // the RSD address, loopback, then these local interface addresses,
        // all within one shared timeout.
        let candidates = WTNetworkStatus.tunnelHostCandidates()
        /// Nil when the tunnel came up on `port`.
        func reach(_ port: UInt16) throws -> DialFailure? {
            try dialRemotePairing(pairingFile, deviceIP: deviceIP, port: port,
                                  hostname: hostname, candidates: candidates)
        }

        var port = Self.rsdPort
        if let moved = movedListenerPort {
            print("[JIT] Dialling port \(moved), where this iPhone's remote pairing listener was found before …")
            port = moved
        }
        // Ports the listener isn't on, which the next attempts skip.
        var passed: [UInt16] = []
        // Dial 49152 (or the remembered port) first.
        if let miss = try reach(port) {
            if !Self.refusedOutright(miss) {
                throw tunnelError(miss, deviceIP: deviceIP, port: port, candidates: candidates)
            }
            print("[JIT] Port \(port) refused.")
            passed.append(port)
            // The remembered port isn't it any more: fall back to 49152.
            if port != Self.rsdPort {
                movedListenerPort = nil
                port = Self.rsdPort
                if let retried = try reach(port) {
                    if !Self.refusedOutright(retried) {
                        throw tunnelError(retried, deviceIP: deviceIP, port: port, candidates: candidates)
                    }
                    print("[JIT] Port \(port) refused.")
                    passed.append(port)
                    // Fall through to the Bonjour advert below with the
                    // last miss.
                    return try finishAfterRefusals(lastMiss: retried, lastPort: port, passed: passed,
                                                   deviceIP: deviceIP, candidates: candidates, reach: reach)
                } else {
                    return
                }
            }
            return try finishAfterRefusals(lastMiss: miss, lastPort: port, passed: passed,
                                           deviceIP: deviceIP, candidates: candidates, reach: reach)
        }
    }

    /// After every dialled port refused: try the Bonjour-advertised port
    /// once, then give up with the last failure's advice. Throws the
    /// tunnel error; returns only when a dial succeeds (unreachable in
    /// practice — `reach` throws or returns nil on success).
    nonisolated private func finishAfterRefusals(lastMiss: DialFailure, lastPort: UInt16, passed: [UInt16],
                                                 deviceIP: String, candidates: [String],
                                                 reach: (UInt16) throws -> DialFailure?) throws {
        let advert = WTNetworkStatus.ownRemotePairingAdvert()
        print("[JIT] Port \(lastPort) refused. This iPhone's remote pairing advertisement: \(advert.summary).")
        if let moved = advert.port, !passed.contains(moved) {
            print("[JIT] Dialling the advertised port \(moved) instead …")
            if let retried = try reach(moved) {
                if Self.refusedOutright(retried) {
                    // The advert's port refused too: report this refusal,
                    // not the earlier port's, so the port in the advice is
                    // the last one tried.
                    print("[JIT] Port \(moved) refused.")
                    throw tunnelError(retried, deviceIP: deviceIP, port: moved, candidates: candidates)
                } else {
                    // The listener answered there; what failed comes after it.
                    movedListenerPort = moved
                    throw tunnelError(retried, deviceIP: deviceIP, port: moved, candidates: candidates)
                }
            } else {
                print("[JIT] The tunnel opened on port \(moved).")
                movedListenerPort = moved
                return
            }
        }
        // No advert, or the listener isn't on its port either. v1 stops
        // here: no port-knock (si_find_pairing_port is not vendored).
        print("[JIT] No other port answered as this iPhone's pairing listener (port-knock is not in v1).")
        throw tunnelError(lastMiss, deviceIP: deviceIP, port: lastPort, candidates: candidates)
    }

    /// Why a `dialRemotePairing` failed.
    private struct DialFailure {
        let raw: FFIError
        let kind: TunnelFailureKind
    }

    /// True when `failure` got no further than a refused connection:
    /// nothing listens on that port.
    nonisolated private static func refusedOutright(_ failure: DialFailure) -> Bool {
        failure.kind == TunnelFailureRsdUnreachable && wasRefused(failure.raw)
    }

    /// What `connectRemotePairing` throws when the last port it tried
    /// failed, `port`.
    nonisolated private func tunnelError(_ failure: DialFailure, deviceIP: String, port: UInt16,
                                         candidates: [String]) -> TunnelError {
        TunnelError(kind: failure.kind,
                    advice: tunnelAdvice(kind: failure.kind,
                                         deviceIP: deviceIP,
                                         port: port,
                                         candidates: candidates,
                                         raw: failure.raw),
                    underlying: failure.raw)
    }

    /// One tunnel attempt to the remote-pairing listener at
    /// `deviceIP:port`. Nil when the tunnel came up, and the adapter and
    /// handshake are now this connection's.
    nonisolated private func dialRemotePairing(_ pairingFile: OpaquePointer, deviceIP: String, port: UInt16,
                                               hostname: String, candidates: [String]) throws -> DialFailure? {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            throw fail("invalid device IP: \(deviceIP)")
        }

        let cHosts: [UnsafePointer<CChar>?] = candidates.map { UnsafePointer(strdup($0)) }
        defer { for p in cHosts { free(UnsafeMutablePointer(mutating: p)) } }

        var newAdapter: OpaquePointer?
        var newHandshake: OpaquePointer?
        var failureKind = TunnelFailureNone
        let err = withUnsafePointer(to: &addr) { aptr in
            aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                hostname.withCString { host in
                    cHosts.withUnsafeBufferPointer { extra in
                        // A nil pin_callback pair-verifies with the existing file.
                        tunnel_create_rppairing_multihost(
                            sa, socklen_t(MemoryLayout<sockaddr_in>.stride),
                            host, pairingFile, nil, nil,
                            extra.baseAddress, UInt(extra.count), &failureKind,
                            &newAdapter, &newHandshake)
                    }
                }
            }
        }
        if let raw = ffiError(err, "tunnel_create_rppairing failed (is a loopback VPN connected, Wi-Fi on, device IP \(deviceIP)?)") {
            // Log the raw error; the caller throws the classified one.
            print("[JIT] tunnel dial failed — raw error: \(raw)")
            return DialFailure(raw: raw, kind: failureKind)
        }
        guard newAdapter != nil, newHandshake != nil else {
            throw fail("tunnel created without valid handles")
        }
        disconnect()
        adapter = newAdapter
        handshake = newHandshake
        return nil
    }

    nonisolated func disconnect() {
        debugHeartbeat?.stop()
        debugHeartbeat = nil
        if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
        if let adapter { adapter_free(adapter); self.adapter = nil }
    }

    // MARK: RSD handshake summary

    /// Basic info straight off the RSD handshake (no extra service
    /// connection).
    nonisolated func rsdSummary() throws -> String {
        guard let handshake else { throw fail("not connected") }
        var uuid: UnsafeMutablePointer<CChar>?
        try check(rsd_get_uuid(handshake, &uuid), "rsd_get_uuid failed")
        let uuidStr = uuid.flatMap { String(validatingUTF8: $0) } ?? "?"
        if let uuid { idevice_string_free(uuid) }

        var proto: UInt = 0
        try check(rsd_get_protocol_version(handshake, &proto), "rsd_get_protocol_version failed")
        return "RSD uuid=\(uuidStr) protocol=\(proto)"
    }
}

// MARK: - Developer disk image (DDI)

extension WTDeviceConnection {
    nonisolated func mountedDeveloperImageCount() throws -> Int {
        guard let adapter, let handshake else { throw fail("not connected") }
        var client: OpaquePointer?
        try check(image_mounter_connect_rsd(adapter, handshake, &client),
                  "image_mounter_connect_rsd failed")
        guard let client else { throw fail("image mounter client was null") }
        defer { image_mounter_free(client) }

        var devices: UnsafeMutablePointer<plist_t?>?
        var count = 0
        try check(image_mounter_copy_devices(client, &devices, &count),
                  "image_mounter_copy_devices failed")
        if let devices {
            for i in 0..<count { plist_free(devices[i]) }
            idevice_data_free(UnsafeMutableRawPointer(devices).assumingMemoryBound(to: UInt8.self),
                              UInt(count * MemoryLayout<plist_t?>.stride))
        }
        return count
    }

    /// Mounts the personalized developer disk image (same as StikDebug):
    /// reads the UniqueChipID from lockdownd, then sends the image, trust
    /// cache, manifest and chip ID to image_mounter over the RSD tunnel.
    nonisolated func mountPersonalizedDeveloperImage(imagePath: String,
                                                     trustcachePath: String,
                                                     manifestPath: String,
                                                     progress: ((Double) -> Void)? = nil) throws {
        guard let adapter, let handshake else { throw fail("not connected") }

        // Mapped, not read: the image is tens of megabytes.
        let image = try Data(contentsOf: URL(fileURLWithPath: imagePath), options: .mappedIfSafe)
        let trustcache = try Data(contentsOf: URL(fileURLWithPath: trustcachePath), options: .mappedIfSafe)
        let manifest = try Data(contentsOf: URL(fileURLWithPath: manifestPath), options: .mappedIfSafe)
        guard !image.isEmpty, !trustcache.isEmpty, !manifest.isEmpty else {
            throw fail("developer disk image files are empty — download them again")
        }

        let chipID = try uniqueChipID()

        var client: OpaquePointer?
        try check(image_mounter_connect_rsd(adapter, handshake, &client),
                  "image_mounter_connect_rsd failed")
        guard let client else { throw fail("image mounter client was null") }
        defer { image_mounter_free(client) }

        // The callback fires on idevice's thread; the box is freed below.
        let box = progress.map { Unmanaged.passRetained(WTProgressBox($0)).toOpaque() }
        defer { if let box { Unmanaged<WTProgressBox>.fromOpaque(box).release() } }

        let err = image.withUnsafeBytes { img in
            trustcache.withUnsafeBytes { tc in
                manifest.withUnsafeBytes { man in
                    image_mounter_mount_personalized_with_callback_rsd(
                        client, adapter, handshake,
                        img.bindMemory(to: UInt8.self).baseAddress, image.count,
                        tc.bindMemory(to: UInt8.self).baseAddress, trustcache.count,
                        man.bindMemory(to: UInt8.self).baseAddress, manifest.count,
                        nil, chipID,
                        box == nil ? nil : wtMountProgressCb, box)
                }
            }
        }
        try check(err, "mounting the developer disk image failed")
    }

    /// The device's UniqueChipID, which personalizing the image is keyed on.
    nonisolated private func uniqueChipID() throws -> UInt64 {
        guard let adapter, let handshake else { throw fail("not connected") }
        var client: OpaquePointer?
        try check(lockdownd_connect_rsd(adapter, handshake, &client), "lockdownd_connect_rsd failed")
        guard let client else { throw fail("lockdownd client was null") }
        defer { lockdownd_client_free(client) }

        var value: plist_t?
        try check("UniqueChipID".withCString { lockdownd_get_value(client, $0, nil, &value) },
                  "lockdownd_get_value(UniqueChipID) failed")
        guard let value else { throw fail("device reported no UniqueChipID") }
        defer { plist_free(value) }

        var chipID: UInt64 = 0
        plist_get_uint_val(value, &chipID)
        guard chipID != 0 else { throw fail("device reported an empty UniqueChipID") }
        return chipID
    }
}

// MARK: - Developer Mode (AMFI)

extension WTDeviceConnection {
    /// What can be asked of AMFI about Developer Mode.
    enum DeveloperModeRequest {
        /// Shows Developer Mode under Settings › Privacy & Security.
        case reveal
        /// Turns Developer Mode on. iOS restarts right away, then asks to
        /// confirm after unlock. Refused while the device has a passcode.
        case enable
    }

    /// Whether Developer Mode is on, read from lockdownd's AMFI domain (as
    /// pymobiledevice3 does). Nil when the device gives no answer.
    nonisolated func developerModeEnabled() throws -> Bool? {
        guard let adapter, let handshake else { throw fail("not connected") }
        var client: OpaquePointer?
        try check(lockdownd_connect_rsd(adapter, handshake, &client), "lockdownd_connect_rsd failed")
        guard let client else { throw fail("lockdownd client was null") }
        defer { lockdownd_client_free(client) }

        var value: plist_t?
        try check("DeveloperModeStatus".withCString { key in
            "com.apple.security.mac.amfi".withCString { domain in
                lockdownd_get_value(client, key, domain, &value)
            }
        }, "lockdownd_get_value(DeveloperModeStatus) failed")
        guard let value else { return nil }
        defer { plist_free(value) }
        guard plist_get_node_type(value) == PLIST_BOOLEAN else { return nil }
        var enabled: UInt8 = 0
        plist_get_bool_val(value, &enabled)
        return enabled != 0
    }

    /// Sends `request` to AMFI's RSD shim over the open tunnel.
    nonisolated func requestDeveloperMode(_ request: DeveloperModeRequest) throws {
        guard let adapter, let handshake else { throw fail("not connected") }
        var client: OpaquePointer?
        try check(amfi_connect_rsd(adapter, handshake, &client), "amfi_connect_rsd failed")
        guard let client else { throw fail("AMFI client was null") }
        defer { amfi_client_free(client) }
        try send(request, to: client)
    }

    nonisolated private func send(_ request: DeveloperModeRequest, to client: OpaquePointer) throws {
        switch request {
        case .reveal:
            try check(amfi_reveal_developer_mode_option_in_ui(client),
                      "amfi_reveal_developer_mode_option_in_ui failed")
        case .enable:
            try check(amfi_enable_developer_mode(client), "amfi_enable_developer_mode failed")
        }
    }
}

// MARK: - Debugging (debugserver over RSD, for JIT)

extension WTDeviceConnection {
    /// Opens what enabling JIT needs over this connection's tunnel:
    /// debugserver, to attach to WorkTweaks' own pid.
    ///
    /// DEBUG-PROXY-ONLY (v1 decision, from the code): SideInstaller also
    /// opens DVT's remote server + process control, to launch the app
    /// suspended (`process_control_launch_app`). A LiveContainer guest is
    /// NOT an installed app and cannot be launched that way — it runs
    /// in-process via LiveContainerMain — so DVT launch is meaningless
    /// here. `debug_proxy_connect_rsd` reaches debugserver directly over
    /// RSD (idevice-ffi `debug_proxy.rs`: `DebugProxyClient::connect_rsd`
    /// takes only the adapter + handshake), and debugserver itself comes
    /// with the mounted developer disk image, so without one mounted
    /// this is what fails. If the device test proves debug-proxy-only
    /// attach does NOT work, the fallback is to open the DVT leg too
    /// (remote_server_* + process_control_*, not declared in v1).
    nonisolated func openDebugSession() throws -> WTDebugServerSession {
        guard let adapter, let handshake else { throw fail("not connected") }
        var proxy: OpaquePointer?
        if let error = ffiError(debug_proxy_connect_rsd(adapter, handshake, &proxy),
                                "debug_proxy_connect_rsd failed (is the developer disk image mounted?)") {
            throw error
        }
        guard let proxy else {
            throw fail("debug proxy handle was null")
        }
        return WTDebugServerSession(debugProxy: proxy)
    }

    /// Answers the heartbeat over the RSD tunnel
    /// (`com.apple.mobile.heartbeat.shim.remote`) until this connection
    /// closes, as StikDebug does while its debugger stays attached to an
    /// app. When it doesn't start, the reason is logged and the session
    /// goes on without it, as StikDebug's does.
    nonisolated func startDebugHeartbeat(deviceIP: String) {
        guard debugHeartbeat == nil, let adapter, let handshake else { return }
        var client: OpaquePointer?
        if let error = ffiError(heartbeat_connect_rsd(adapter, handshake, &client),
                                "heartbeat_connect_rsd failed") {
            print("[JIT] Debugger heartbeat didn't start (\(error)). Going on without it …")
            return
        }
        guard let client else { return }
        debugHeartbeat = WTLockdownHeartbeat(
            client: client, deviceIP: deviceIP, label: "Debugger heartbeat",
            endedAdvice: "The debugger stays attached without it, as long as the tunnel stays up.")
    }

}

/// Carries a Swift closure through the C mount callback's `void *context`.
private final class WTProgressBox: @unchecked Sendable {
    let report: (Double) -> Void
    nonisolated init(_ report: @escaping (Double) -> Void) { self.report = report }
}

/// image_mounter progress callback, driving the DDI mount progress.
private let wtMountProgressCb: @convention(c) (Int, Int, UnsafeMutableRawPointer?) -> Void = { done, total, context in
    guard let context, total > 0 else { return }
    let report = Unmanaged<WTProgressBox>.fromOpaque(context).takeUnretainedValue().report
    let fraction = Double(done) / Double(total)
    DispatchQueue.main.async { report(fraction) }
}

// MARK: - Lockdown heartbeat

/// Answers lockdownd's heartbeat (`com.apple.mobile.heartbeat`) on a
/// thread of its own. Port of `LockdownHeartbeat`
/// (DeviceConnection.swift:2263-2381).
///
/// lockdownd sees an app coming through the loopback VPN as a host on the
/// network, and wants such a host to answer its heartbeat: a Marco about
/// every 10 s, each answered with a Polo. While none is answering, iOS
/// closes what that host starts. On the RPPairing route the heartbeat is
/// only needed while a debugger stays attached (`startDebugHeartbeat`,
/// over the RSD shim); the tunnel itself needs none.
private final class WTLockdownHeartbeat: @unchecked Sendable {
    /// The device IP the heartbeat reaches.
    let deviceIP: String
    /// Owned by the thread, which frees it on the way out.
    private let client: OpaquePointer
    /// What the log calls it.
    private let label: String
    /// What the log says after it ends.
    private let endedAdvice: String
    nonisolated(unsafe) private let condition = NSCondition()
    nonisolated(unsafe) private var answered = 0
    nonisolated(unsafe) private var ended = false
    nonisolated(unsafe) private var stopped = false

    /// idevice's `IdeviceError::Heartbeat` code, which comes with sub-code
    /// 1 when the device is going to sleep and 2 when a Marco is late.
    private static let heartbeatErrorCode: Int32 = 100
    private static let sleepyTimeSubCode: Int32 = 1

    /// Takes `client`, from `heartbeat_connect_rsd`, and starts answering
    /// it.
    nonisolated init(client: OpaquePointer, deviceIP: String,
         label: String = "Lockdown heartbeat",
         endedAdvice: String = "iOS closes the tunnel within seconds without it. Another app with this pairing file (SideStore, StikDebug, Feather) starting its own heartbeat ends this one.") {
        self.client = client
        self.deviceIP = deviceIP
        self.label = label
        self.endedAdvice = endedAdvice
        let thread = Thread { [self] in run() }
        thread.name = "worktweaks.jit-heartbeat"
        // A Polo that goes out too late closes the tunnel, mid-session too.
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// True once a Marco has been answered, until the heartbeat stops or ends.
    nonisolated var isAnswering: Bool {
        condition.lock(); defer { condition.unlock() }
        return answered > 0 && !ended && !stopped
    }

    /// Waits up to `timeout` for the first Marco to be answered. False if
    /// it wasn't, or the heartbeat ended first.
    nonisolated func waitUntilAnswered(timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock(); defer { condition.unlock() }
        while answered == 0, !ended, !stopped {
            if !condition.wait(until: deadline) { break }
        }
        return answered > 0
    }

    /// Stops answering. The thread notices at the next Marco, at most
    /// about 10 s later, then closes the connection.
    nonisolated func stop() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
    }

    nonisolated private var isStopped: Bool {
        condition.lock(); defer { condition.unlock() }
        return stopped
    }

    nonisolated private func run() {
        defer {
            heartbeat_client_free(client)
            condition.lock()
            ended = true
            condition.broadcast()
            condition.unlock()
        }
        // How long to wait for the next Marco: what iOS asked for, plus slack.
        var wait: UInt64 = 15
        while !isStopped {
            var interval: UInt64 = 0
            if let error = WTDeviceConnection.takeFFIError(heartbeat_get_marco(client, wait, &interval),
                                                           "heartbeat_get_marco failed") {
                if isStopped { return }
                // A late Marco, or an iPhone going to sleep, doesn't end the
                // heartbeat. The connection closing does.
                if error.code == Self.heartbeatErrorCode {
                    if error.subCode == Self.sleepyTimeSubCode {
                        print("[JIT] \(label): the iPhone is going to sleep.")
                    }
                    continue
                }
                print("[JIT] \(label) ended (\(error)). \(endedAdvice)")
                return
            }
            if isStopped { return }
            if let error = WTDeviceConnection.takeFFIError(heartbeat_send_polo(client),
                                                           "heartbeat_send_polo failed") {
                print("[JIT] \(label) ended: the answer didn't go out (\(error)).")
                return
            }
            wait = interval + 5
            condition.lock()
            answered += 1
            let first = answered == 1
            condition.broadcast()
            condition.unlock()
            if first {
                print("[JIT] \(label) answered. iOS asks every \(interval) s.")
            }
        }
    }
}

// MARK: - Debugging session (debug-proxy-only)

/// debugserver attached over one tunnel: what enabling JIT runs on
/// (`WTJITSession`). From `WTDeviceConnection.openDebugSession`.
///
/// v1 difference from SideInstaller's `DebugServerSession`: NO DVT
/// remote server, NO process control — no `launchSuspended`, no `kill`.
/// A guest cannot be launched or killed through DVT (it runs in-process
/// as LiveContainerMain); `quit()` in the session detaches instead of
/// killing, because killing our own pid would kill the guest AND
/// WorkTweaks.
///
/// Blocking, like the rest of the FFI. One thread drives debugserver:
/// GDB's remote protocol is a question and its answer, so packets from
/// two threads would take each other's answers.
final class WTDebugServerSession: @unchecked Sendable {
    nonisolated(unsafe) private var debugProxy: OpaquePointer?

    nonisolated fileprivate init(debugProxy: OpaquePointer) {
        self.debugProxy = debugProxy
    }

    deinit { close() }

    nonisolated private func check(_ err: UnsafeMutablePointer<IdeviceFfiError>?, _ fallback: String) throws {
        if let error = WTDeviceConnection.takeFFIError(err, fallback) { throw error }
    }

    nonisolated private static let closed = WTDeviceConnection.FFIError(code: -1, subCode: 0,
                                                                        message: "the debugging session is closed")

    /// Sends one packet's content (idevice frames it and adds the
    /// checksum) and returns debugserver's answer, nil when none came.
    nonisolated func send(_ packet: String) throws -> String? {
        guard let debugProxy else { throw Self.closed }
        guard let command = debugserver_command_new(packet, nil, 0) else {
            throw WTDeviceConnection.FFIError(code: -1, subCode: 0,
                                              message: "couldn't make the debugserver packet \(packet.prefix(24))")
        }
        defer { debugserver_command_free(command) }
        var response: UnsafeMutablePointer<CChar>?
        let err = debug_proxy_send_command(debugProxy, command, &response)
        defer { if let response { idevice_string_free(response) } }
        try check(err, "debugserver didn't answer \(packet.prefix(24))")
        return response.map { String(cString: $0) }
    }

    /// Sends bytes as they are, such as several framed packets at once,
    /// whose answers `readResponse` then takes in order.
    nonisolated func sendRaw(_ bytes: [UInt8]) throws {
        guard let debugProxy else { throw Self.closed }
        try bytes.withUnsafeBufferPointer { buffer in
            try check(debug_proxy_send_raw(debugProxy, buffer.baseAddress, UInt(buffer.count)),
                      "debug_proxy_send_raw failed")
        }
    }

    /// The next answer debugserver sends, nil when what came wasn't one.
    nonisolated func readResponse() throws -> String? {
        guard let debugProxy else { throw Self.closed }
        var response: UnsafeMutablePointer<CChar>?
        let err = debug_proxy_read_response(debugProxy, &response)
        defer { if let response { idevice_string_free(response) } }
        try check(err, "debug_proxy_read_response failed")
        return response.map { String(cString: $0) }
    }

    /// Acknowledges what debugserver sent, while acknowledgements are on.
    nonisolated func sendAck() throws {
        guard let debugProxy else { throw Self.closed }
        try check(debug_proxy_send_ack(debugProxy), "debug_proxy_send_ack failed")
    }

    /// Whether idevice expects and sends acknowledgements. Off after
    /// `QStartNoAckMode`, which turns them off at debugserver's end.
    nonisolated func setAcknowledgements(_ on: Bool) {
        guard let debugProxy else { return }
        debug_proxy_set_ack_mode(debugProxy, on ? 1 : 0)
    }

    /// Closes debugserver. Detach (`D`) first: what debugserver does
    /// with an app it's still attached to when its connection goes isn't
    /// something to count on.
    nonisolated func close() {
        if let debugProxy { debug_proxy_free(debugProxy); self.debugProxy = nil }
    }
}

// MARK: - Tunnel host candidates & Bonjour advert

/// The loopback/VPN address helpers `connect` needs. Port of the
/// JIT-relevant part of SideInstaller's `NetworkStatus.swift`.
enum WTNetworkStatus {
    struct Interface {
        let name: String
        let ipv4: String
        /// The kernel's netmask, so subnet tests needn't assume a prefix length.
        let netmask: String?
    }

    nonisolated static func interfaces() -> [Interface] {
        var result: [Interface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            guard let ipv4 = numericHost(addr) else { continue }
            result.append(Interface(name: name, ipv4: ipv4,
                                    netmask: cur.pointee.ifa_netmask.flatMap(numericHost)))
        }
        return result
    }

    nonisolated private static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        // A netmask's sa_len is sometimes short, so size from the family.
        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        return String(cString: host)
    }

    /// Extra hosts the RPPairing dial tries: this iPhone's own interface
    /// addresses (not the tunnel's, not loopback), en0 first.
    nonisolated static func tunnelHostCandidates() -> [String] {
        let ifs = interfaces().filter {
            !isTunnelInterface($0.name) && !$0.ipv4.hasPrefix("127.")
        }
        return (ifs.filter { $0.name == "en0" } + ifs.filter { $0.name != "en0" })
            .map(\.ipv4)
    }

    nonisolated private static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec")
            || name.hasPrefix("tap") || name.hasPrefix("ppp")
    }

    struct PairingAdvert {
        /// The port this iPhone advertises, nil when none was seen.
        let port: UInt16?
        /// What was seen, for the log.
        let summary: String
    }

    /// Looks for the `_remotepairing._tcp` service this iPhone
    /// advertises: the listener `tunnel_create_rppairing` dials. Its
    /// port is whatever the listener got when it started. That's 49152
    /// (`WTDeviceConnection.rsdPort`), the first port iOS hands out, as
    /// long as nothing took it first, which can't be counted on. Other
    /// iPhones on the network advertise the same service, so only one
    /// resolving to an address this iPhone holds counts.
    ///
    /// Blocks for up to `timeout`. The browse runs on the main run loop,
    /// so never call this on the main thread. (The startup attach path
    /// spins the main run loop while it waits — see
    /// `WTJITSession.attachAndWait`.)
    ///
    /// Requires `_remotepairing._tcp` in NSBonjourServices — added to the
    /// target settings + the CI PlistBuddy step by this change.
    nonisolated static func ownRemotePairingAdvert(timeout: TimeInterval = 3) -> PairingAdvert {
        precondition(!Thread.isMainThread, "the browse needs the main run loop")
        let finder = WTRemotePairingAdvertFinder(ownAddresses: ownAddresses())
        DispatchQueue.main.async { finder.start() }
        let advert = finder.wait(timeout: timeout)
        DispatchQueue.main.async { finder.stop() }
        return advert
    }

    /// Every address this iPhone holds, IPv4 and IPv6, without a scope suffix.
    nonisolated static func ownAddresses() -> Set<String> {
        var result = Set<String>()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr,
                  let host = numericHost(addr, length: socklen_t(addr.pointee.sa_len)) else { continue }
            result.insert(host)
        }
        return result
    }

    /// `addr` as a numeric address, without a `%scope` suffix; nil for a
    /// family other than IPv4 or IPv6.
    nonisolated static func numericHost(_ addr: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
        let family = Int32(addr.pointee.sa_family)
        guard family == AF_INET || family == AF_INET6 else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        return String(cString: host).split(separator: "%").first.map(String.init)
    }
}

/// Browses `_remotepairing._tcp` and resolves each service found until one
/// resolves to an address this iPhone holds. Used from the main thread,
/// except `wait`. Port of SideInstaller's `RemotePairingAdvertFinder`.
private final class WTRemotePairingAdvertFinder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

    private let ownAddresses: Set<String>
    nonisolated(unsafe) private let browser = NetServiceBrowser()
    /// Held while they resolve, or they'd go away.
    nonisolated(unsafe) private var services: [NetService] = []
    nonisolated(unsafe) private var othersResolved = 0
    nonisolated(unsafe) private let lock = NSLock()
    nonisolated(unsafe) private var found: WTNetworkStatus.PairingAdvert?
    nonisolated(unsafe) private let done = DispatchSemaphore(value: 0)

    nonisolated init(ownAddresses: Set<String>) {
        self.ownAddresses = ownAddresses
    }

    nonisolated func start() {
        browser.delegate = self
        // Common modes, so a scroll doesn't hold the callbacks back.
        browser.remove(from: .main, forMode: .default)
        browser.schedule(in: .main, forMode: .common)
        browser.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
    }

    /// Their delegates are unretained, so they're cleared before this goes.
    nonisolated func stop() {
        browser.delegate = nil
        browser.stop()
        for service in services {
            service.delegate = nil
            service.stop()
        }
        services.removeAll()
    }

    nonisolated func wait(timeout: TimeInterval) -> WTNetworkStatus.PairingAdvert {
        _ = done.wait(timeout: .now() + timeout)
        lock.lock()
        defer { lock.unlock() }
        if let found { return found }
        let others = othersResolved == 0 ? "" : " (\(othersResolved) from other devices)"
        return WTNetworkStatus.PairingAdvert(
            port: nil, summary: "none from this iPhone in \(Int(timeout)) s\(others)")
    }

    nonisolated private func finish(_ advert: WTNetworkStatus.PairingAdvert) {
        lock.lock()
        let first = found == nil
        if first { found = advert }
        lock.unlock()
        if first { done.signal() }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.remove(from: .main, forMode: .default)
        service.schedule(in: .main, forMode: .common)
        service.resolve(withTimeout: 2)
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        // Without Local Network permission, or without the type in NSBonjourServices.
        let code = errorDict[NetService.errorCode]?.intValue ?? 0
        finish(WTNetworkStatus.PairingAdvert(port: nil, summary: "the browse failed (error \(code))"))
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let addresses: [String] = (sender.addresses ?? []).compactMap { data in
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress, raw.count >= MemoryLayout<sockaddr>.size else { return nil }
                return WTNetworkStatus.numericHost(base.assumingMemoryBound(to: sockaddr.self),
                                                   length: socklen_t(raw.count))
            }
        }
        guard sender.port > 0, addresses.contains(where: ownAddresses.contains) else {
            if !addresses.isEmpty { lock.lock(); othersResolved += 1; lock.unlock() }
            return
        }
        // Not the service's name, which can be the iPhone's.
        finish(WTNetworkStatus.PairingAdvert(port: UInt16(sender.port),
                                             summary: "port \(sender.port)"))
    }
}
