import Foundation

// MARK: - Container Apple ID auth: anisette (anisette-v3)
//
// Ported from Signed Apps (pinned 61d013e8), updated to the
// SideInstaller v2.2.0 system (2026-11-24, verified from its
// source): the server list is lillq's pool first, then the
// macOS-ADI order; and the current-Mac client identity spells
// its OS "Mac OS X" — Apple has answered "macOS" with HTTP 503
// since 2026-11-20. The Signed Apps copy still said "<macOS;
// 26.6;25F84>"; that spelling is fixed here (it is the one
// difference from the frozen source, and the fix is in the
// WorkTweaks copy only — Signed Apps itself is untouched).

/// Anisette data, field-for-field the same set ALTAnisetteData
/// carries in AltSign (machineID, oneTimePassword, localUserID,
/// routingInfo, deviceUniqueIdentifier, deviceSerialNumber,
/// deviceDescription, date, locale, timeZone).
struct AnisetteData {
    var machineID: String            // X-Apple-I-MD-M
    var oneTimePassword: String      // X-Apple-I-MD
    var localUserID: String          // X-Apple-I-MD-LU
    var routingInfo: UInt64          // X-Apple-I-MD-RINFO
    var deviceUniqueIdentifier: String // X-Mme-Device-Id
    var deviceSerialNumber: String   // X-Apple-I-SRL-NO
    var deviceDescription: String    // X-MMe-Client-Info
    var date: Date
    var localeIdentifier: String
    var timeZoneAbbreviation: String
    /// Which server supplied this data (for the Log tab).
    var serverUsed: String = ""
    /// The User-Agent GrandSlam is told, paired with
    /// `deviceDescription` by `clientInfoToUse` — the two must match
    /// the anisette library, or Apple answers -80045.
    var userAgent: String = ""

    /// X-Apple-I-Client-Time, formatted exactly like AltSign
    /// (NSISO8601DateFormatter with default options).
    var clientTimeString: String {
        ISO8601DateFormatter().string(from: date)
    }
}

enum AnisetteError: LocalizedError {
    case badResponse(String)
    case message(String)
    case notProvisioned
    var errorDescription: String? {
        switch self {
        case .badResponse(let what): return "Anisette server response is missing \(what)."
        case .message(let text): return text
        case .notProvisioned: return "The anisette server says this identity is not provisioned with it (ADI -45061)."
        }
    }
}

/// One anisette server's own identity — isideload's `AnisetteState`
/// (anisette/remote_v3/state.rs): 16 random bytes made once, plus
/// the `adi_pb` blob the provisioning ceremony returns. An identity
/// is provisioned through one server and belongs to that server's
/// ADI library (another library refuses it with -45061), so one
/// state is kept per server, in the Keychain.
struct AnisetteState {
    var keychainIdentifier: Data
    var adiPB: Data?

    var isProvisioned: Bool { adiPB != nil }

    /// `get_md_lu`: the SHA256 of the identifier — sent hex-encoded
    /// as X-Apple-I-MD-LU, and used as the local user ID.
    var mdLU: Data { ContainerAuthCrypto.sha256(keychainIdentifier) }
    var mdLUHex: String { mdLU.map { String(format: "%02x", $0) }.joined() }

    /// `get_device_id`: the identifier read as a UUID
    /// (Uuid::from_bytes(...).to_string() — lowercase, hyphenated).
    var deviceID: String {
        let b = [UInt8](keychainIdentifier)
        guard b.count == 16 else { return "" }
        return String(format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                      b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                      b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    }

    // MARK: Persistence (Keychain, one identity per server)

    private static func identifierKey(host: String) -> String { "anisette.state.\(host).identifier" }
    private static func adiPBKey(host: String) -> String { "anisette.state.\(host).adi_pb" }

    static func load(host: String, log: (String) -> Void) -> AnisetteState {
        if let data = ContainerAuthKeychain.loadData(identifierKey(host: host)), data.count == 16 {
            let adiPB = ContainerAuthKeychain.loadData(adiPBKey(host: host))
            log(adiPB != nil
                ? "anisette identity for \(host): loaded (provisioned)"
                : "anisette identity for \(host): loaded (not provisioned yet)")
            return AnisetteState(keychainIdentifier: data, adiPB: adiPB)
        }
        let state = AnisetteState(
            keychainIdentifier: Data((0..<16).map { _ in UInt8.random(in: 0...255) }),
            adiPB: nil)
        save(state, host: host)
        log("anisette identity for \(host): created a new one")
        return state
    }

    static func save(_ state: AnisetteState, host: String) {
        ContainerAuthKeychain.saveData(state.keychainIdentifier, for: identifierKey(host: host))
        if let adiPB = state.adiPB {
            ContainerAuthKeychain.saveData(adiPB, for: adiPBKey(host: host))
        } else {
            ContainerAuthKeychain.delete(adiPBKey(host: host))
        }
    }
}

/// Anisette from an anisette-v3 server, the way isideload (the
/// library iLoader desktop runs) does it:
///
/// - Stage 2.3: the app provisions its OWN per-device identity with
///   the server once (the /v3/provisioning_session ceremony in
///   `provision`), keeps it in the Keychain, and mints each
///   sign-in's headers from it with POST /v3/get_headers
///   (`requestHeaders`). The earlier stateless fetch — borrowing
///   the server's shared identity from its root response — is gone:
///   a shared identity is not a machine Apple can trust, and the
///   sign-in stalled at SRP init (-80043) with it.
/// - The server list and the identity rules follow SideInstaller
///   (FrizzleM, via the isideload library) — the system that kept
///   signing in through Apple's October 2026 GrandSlam changes:
///   since 2026-10-12 Apple refuses sign-ins whose reported client
///   identity doesn't match the anisette data's ADI library
///   (-80045), and since 2026-10-21 it refuses the sign-in token
///   for Android-ADI anisette outright (-80046). Only macOS-ADI
///   servers are left, so the legacy ani.sidestore.io is gone.
/// - The identity GrandSlam is told is NOT the server's raw client
///   info: `clientInfoToUse` rewrites it exactly like isideload —
///   a stock/Android identity becomes a Windows PC, and the
///   macOS-ADI servers' 10.12.6 Mac becomes a current Mac, each
///   with the matching User-Agent.
enum Anisette {
    /// SideInstaller v2.2.0 (AnisetteServers.swift): lillq's pool
    /// is the default and fallback; then the macOS-ADI order
    /// (new.ani.sidestore.io, mac-ani.jkcoxson.com,
    /// ani.iloader.app, ani3.stikstore.app, ani.jkcoxson.com,
    /// ani2.stikstore.app).
    static let builtInServers = [
        "https://anisette.lillq.me",
        "https://new.ani.sidestore.io",
        "https://mac-ani.jkcoxson.com",
        "https://ani.iloader.app",
        "https://ani3.stikstore.app",
        "https://ani.jkcoxson.com",
        "https://ani2.stikstore.app",
    ]

    // Identity constants, verbatim from isideload's remote_v3.
    static let windowsClientInfo = "<PC> <Windows;6.2(0,0);9200> <com.apple.AuthKit/1 (com.apple.iTunes/12.12.4.1)>"
    static let akdUserAgent = "akd/1.0 CFNetwork/808.1.4"
    // FIXED vs the Signed Apps copy (see the file header):
    // "Mac OS X", not "macOS" — Apple's edge 503s "macOS"
    // since 2026-11-20. Verified against isideload 0.5.2's
    // CURRENT_MAC_CLIENT_INFO in SideInstaller v2.2.0.
    static let currentMacClientInfo = "<MacBookPro18,3> <Mac OS X;26.6;25F84> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
    static let currentMacUserAgent = "AuthKit/1 (Macintosh; OS X 26.6) (com.apple.akd/1.0)"
    static let stockClients = ["<MacBookPro13,2> <macOS;13.1;22C65>", "<MacBookPro15,1> <Mac OS X;10.15.2;19C57>"]

    /// GrandSlam's URL bag endpoint, and the client the bag is
    /// re-asked as when the sign-in client isn't a Mac (isideload's
    /// grandslam.rs: a non-Mac client's bag can lack the
    /// gsa.apple.com URLs sign-in uses).
    private static let urlBagURL = URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup")!
    private static let macBagClientInfo = "<Mac15,7> <macOS;27.0;26A5378j> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
    private static let bagKeys = ["gsService", "midStartProvisioning", "midFinishProvisioning", "trustedDeviceSecondaryAuth", "validateCode"]

    /// Fresh-connection discipline, like the GrandSlam traffic:
    /// Apple's edge answers reused keep-alive connections with 5xx,
    /// so requests also send `Connection: close`.
    private static let http: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config)
    }()

    /// isideload's `android_adi`: the server names a stock client or
    /// an Android phone, so its anisette comes from Apple's Android
    /// ADI library.
    static func isAndroidADI(clientInfo: String) -> Bool {
        let client = clientInfo.trimmingCharacters(in: .whitespaces)
        return stockClients.contains { client.hasPrefix($0) } || client.contains("<Android;")
    }

    /// The macOS version a client info names, if it names a Mac.
    static func macVersion(clientInfo: String) -> (Int, Int)? {
        for marker in ["<macOS;", "<Mac OS X;"] {
            if let range = clientInfo.range(of: marker) {
                let rest = clientInfo[range.upperBound...]
                let version = rest.split(whereSeparator: { $0 == ";" || $0 == ">" }).first.map(String.init) ?? ""
                let parts = version.trimmingCharacters(in: .whitespaces).split(separator: ".")
                guard let major = parts.first.flatMap({ Int($0) }) else { return nil }
                let minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                return (major, minor)
            }
        }
        return nil
    }

    /// isideload's `client_info_to_use`: the client info + user agent
    /// to tell GrandSlam, given what the server advertises.
    static func clientInfoToUse(advertisedClientInfo: String, advertisedUserAgent: String) -> (clientInfo: String, userAgent: String) {
        let client = advertisedClientInfo.trimmingCharacters(in: .whitespaces)
        if client.isEmpty || isAndroidADI(clientInfo: client) {
            return (windowsClientInfo, akdUserAgent)
        }
        if let version = macVersion(clientInfo: client), version < (10, 13) {
            return (currentMacClientInfo, currentMacUserAgent)
        }
        let ua = advertisedUserAgent.trimmingCharacters(in: .whitespaces)
        return (client, ua.isEmpty ? akdUserAgent : ua)
    }

    static func fetch(serverURLString: String, log: @escaping (String) -> Void = { _ in }) async throws -> AnisetteData {
        let override = serverURLString.trimmingCharacters(in: .whitespaces)
        let candidates = override.isEmpty ? builtInServers : [override]
        var lastError: Error?
        for candidate in candidates {
            do {
                var data = try await fetchOne(urlString: candidate, log: log)
                data.serverUsed = candidate
                return data
            } catch {
                log("anisette via \(candidate) failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        throw lastError ?? AnisetteError.badResponse("a reachable anisette server")
    }

    private static func fetchOne(urlString: String, log: (String) -> Void) async throws -> AnisetteData {
        var base = urlString.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard URL(string: base) != nil else {
            throw AnisetteError.badResponse("a valid URL")
        }

        // The identity GrandSlam is told comes from the server's
        // /v3/client_info through clientInfoToUse — never the raw
        // advertised string. The server's root response still
        // supplies the serial number (and a fallback client info).
        let advertised = await fetchAdvertised(base: base)
        let used = clientInfoToUse(advertisedClientInfo: advertised.clientInfo, advertisedUserAgent: advertised.userAgent)

        var state = AnisetteState.load(host: base, log: log)
        let headers = try await mintHeaders(base: base, state: &state,
                                            clientInfo: used.clientInfo, userAgent: used.userAgent, log: log)

        return AnisetteData(
            machineID: headers.machineID,
            oneTimePassword: headers.oneTimePassword,
            localUserID: state.mdLUHex,
            routingInfo: UInt64(headers.routingInfo) ?? 17106176,
            deviceUniqueIdentifier: state.deviceID,
            deviceSerialNumber: advertised.serial,
            deviceDescription: used.clientInfo,
            date: Date(),
            localeIdentifier: advertised.locale ?? Locale.current.identifier,
            timeZoneAbbreviation: advertised.timeZone ?? TimeZone.current.abbreviation() ?? "PST",
            userAgent: used.userAgent
        )
    }

    // MARK: - What the server advertises

    private struct Advertised {
        var clientInfo = ""
        var userAgent = ""
        var serial = "0"
        var locale: String?
        var timeZone: String?
    }

    /// /v3/client_info first (isideload's `get_client_info` source),
    /// then the root response for the serial number and the
    /// locale/time zone — the fields the stateless fetch read.
    /// Best-effort: an unreachable endpoint just leaves defaults.
    private static func fetchAdvertised(base: String) async -> Advertised {
        var advertised = Advertised()
        if let url = URL(string: base + "/v3/client_info") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            if let (data, _) = try? await http.data(for: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let ci = json["client_info"] as? String { advertised.clientInfo = ci }
                if let ua = json["user_agent"] as? String { advertised.userAgent = ua }
            }
        }
        if let url = URL(string: base),
           let (data, _) = try? await http.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            func field(_ v3: String, _ alt: String) -> String? {
                (json[v3] as? String) ?? (json[alt] as? String)
            }
            if let serial = field("X-Apple-I-SRL-NO", "deviceSerialNumber") { advertised.serial = serial }
            if advertised.clientInfo.isEmpty, let desc = field("X-MMe-Client-Info", "deviceDescription") {
                advertised.clientInfo = desc
            }
            advertised.locale = field("X-Apple-Locale", "locale")
            advertised.timeZone = field("X-Apple-I-TimeZone", "timeZone")
        }
        return advertised
    }

    // MARK: - Headers from the provisioned identity

    private struct MintedHeaders {
        let machineID: String
        let oneTimePassword: String
        let routingInfo: String
    }

    /// The headers of the identity in use: provision it first if it
    /// has no adi_pb, then POST /v3/get_headers. An identity the
    /// server refuses as not provisioned (ADI -45061 — made through
    /// another ADI library, or lost by the server) has its adi_pb
    /// cleared and is provisioned once more before one retry, like
    /// isideload's generator-level second pick.
    private static func mintHeaders(base: String, state: inout AnisetteState,
                                    clientInfo: String, userAgent: String,
                                    log: (String) -> Void) async throws -> MintedHeaders {
        var retriedNotProvisioned = false
        while true {
            if !state.isProvisioned {
                log("provisioning identity with \(base)…")
                let bag = try await fetchURLBag(clientInfo: clientInfo, userAgent: userAgent)
                guard let start = bag["midStartProvisioning"], let finish = bag["midFinishProvisioning"] else {
                    throw AnisetteError.message("GrandSlam's URL bag has no provisioning URLs.")
                }
                try await provision(base: base, state: &state, startURL: start, finishURL: finish,
                                    clientInfo: clientInfo, userAgent: userAgent)
                log("provisioning OK")
            }
            do {
                let headers = try await requestHeaders(base: base, state: state)
                log("anisette headers OK (provisioned identity)")
                return headers
            } catch AnisetteError.notProvisioned {
                if retriedNotProvisioned { throw AnisetteError.notProvisioned }
                retriedNotProvisioned = true
                log("the identity isn't provisioned with \(base) (-45061); clearing it and provisioning again")
                state.adiPB = nil
                AnisetteState.save(state, host: base)
            }
        }
    }

    /// POST /v3/get_headers for `state` (isideload's
    /// `fetch_headers_for`): a 5xx is asked again (3 tries, 1s
    /// apart), a silent server is given 20s.
    private static func requestHeaders(base: String, state: AnisetteState) async throws -> MintedHeaders {
        guard let adiPB = state.adiPB else { throw AnisetteError.notProvisioned }
        let body = try JSONSerialization.data(withJSONObject: [
            "identifier": state.keychainIdentifier.base64EncodedString(),
            "adi_pb": adiPB.base64EncodedString(),
        ])
        guard let url = URL(string: base + "/v3/get_headers") else {
            throw AnisetteError.badResponse("a valid URL")
        }
        var asked = 0
        while true {
            asked += 1
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("close", forHTTPHeaderField: "Connection")
            let (data, response) = try await http.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (500...599).contains(status) && asked < 3 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            guard (200...299).contains(status) else {
                throw AnisetteError.message("The anisette server answered HTTP \(status) for /v3/get_headers.")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? String else {
                throw AnisetteError.badResponse("a get_headers result")
            }
            switch result {
            case "Headers":
                guard let mdm = json["X-Apple-I-MD-M"] as? String,
                      let md = json["X-Apple-I-MD"] as? String,
                      let rinfo = jsonString(json["X-Apple-I-MD-RINFO"]) else {
                    throw AnisetteError.badResponse("the get_headers header values")
                }
                return MintedHeaders(machineID: mdm, oneTimePassword: md, routingInfo: rinfo)
            case "GetHeadersError":
                let message = json["message"] as? String ?? ""
                // "ADI Login error: -45061" / "not provisioned (-45061)":
                // the identity belongs to another ADI library.
                if message.contains("-45061") { throw AnisetteError.notProvisioned }
                throw AnisetteError.message("Failed to get anisette headers: \(message)")
            default:
                throw AnisetteError.badResponse("a known get_headers result")
            }
        }
    }

    /// A JSON value as a string: the value itself if it is one, or a
    /// number's decimal form (routing info arrives either way).
    private static func jsonString(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    // MARK: - Provisioning

    /// isideload's `provision_state`: the /v3/provisioning_session
    /// WebSocket ceremony. The server drives — it asks for the
    /// identifier, then for the two GrandSlam calls
    /// (midStartProvisioning / midFinishProvisioning from the URL
    /// bag, made with the identity's provisioning headers), and
    /// ends by handing back the adi_pb to store.
    private static func provision(base: String, state: inout AnisetteState,
                                  startURL: String, finishURL: String,
                                  clientInfo: String, userAgent: String) async throws {
        var wsString = base
        if wsString.hasPrefix("https://") {
            wsString = "wss://" + String(wsString.dropFirst("https://".count))
        } else if wsString.hasPrefix("http://") {
            wsString = "ws://" + String(wsString.dropFirst("http://".count))
        }
        wsString += "/v3/provisioning_session"
        guard let wsURL = URL(string: wsString) else {
            throw AnisetteError.badResponse("a valid URL")
        }

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var wsRequest = URLRequest(url: wsURL)
        wsRequest.timeoutInterval = 30
        let task = session.webSocketTask(with: wsRequest)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        // The 30s timeout covers connecting, as in isideload; the
        // first receive completes the handshake.
        var firstReceive = true
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                if firstReceive {
                    message = try await receiveWithTimeout(task, seconds: 30)
                } else {
                    message = try await task.receive()
                }
            } catch let error as AnisetteError {
                throw error
            } catch {
                throw AnisetteError.message("Anisette provisioning socket closed unexpectedly")
            }
            firstReceive = false

            guard case .string(let text) = message else {
                throw AnisetteError.message("Failed to parse provisioning message")
            }
            guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let result = json["result"] as? String else {
                throw AnisetteError.message("Unknown provisioning message")
            }
            switch result {
            case "GiveIdentifier":
                try await sendJSON(task, ["identifier": state.keychainIdentifier.base64EncodedString()])
            case "GiveStartProvisioningData":
                let response = try await gsPlistRequest(
                    url: startURL,
                    body: ["Header": [String: Any](), "Request": [String: Any]()],
                    state: state, clientInfo: clientInfo, userAgent: userAgent)
                guard let spim = response["spim"] as? String else {
                    throw AnisetteError.message("Start provisioning response missing spim")
                }
                try await sendJSON(task, ["spim": spim])
            case "GiveEndProvisioningData":
                guard let cpim = json["cpim"] as? String else {
                    throw AnisetteError.message("Unknown provisioning message")
                }
                let response = try await gsPlistRequest(
                    url: finishURL,
                    body: ["Header": [String: Any](), "Request": ["cpim": cpim]],
                    state: state, clientInfo: clientInfo, userAgent: userAgent)
                guard let ptm = response["ptm"] as? String else {
                    throw AnisetteError.message("End provisioning response missing ptm")
                }
                guard let tk = response["tk"] as? String else {
                    throw AnisetteError.message("End provisioning response missing tk")
                }
                try await sendJSON(task, ["ptm": ptm, "tk": tk])
            case "ProvisioningSuccess":
                guard let adiPBString = json["adi_pb"] as? String,
                      let adiPB = Data(base64Encoded: adiPBString) else {
                    throw AnisetteError.message("Unknown provisioning message")
                }
                state.adiPB = adiPB
                AnisetteState.save(state, host: base)
                task.cancel(with: .normalClosure, reason: nil)
                return
            case "Timeout":
                throw AnisetteError.message("Anisette provisioning timed out")
            case "InvalidIdentifier":
                throw AnisetteError.message("Anisette provisioning failed: invalid identifier")
            case "StartProvisioningError":
                throw AnisetteError.message("Anisette provisioning failed: start provisioning error: \(json["message"] as? String ?? "unknown")")
            case "EndProvisioningError":
                throw AnisetteError.message("Anisette provisioning failed: end provisioning error: \(json["message"] as? String ?? "unknown")")
            default:
                throw AnisetteError.message("Unknown provisioning message")
            }
        }
    }

    private static func sendJSON(_ task: URLSessionWebSocketTask, _ object: [String: String]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private static func receiveWithTimeout(_ task: URLSessionWebSocketTask, seconds: TimeInterval) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await task.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AnisetteError.message("Timed out connecting to provisioning socket. Try a different anisette server.")
            }
            guard let message = try await group.next() else {
                throw AnisetteError.message("Anisette provisioning socket closed unexpectedly")
            }
            group.cancelAll()
            return message
        }
    }

    /// A GrandSlam plist POST for the provisioning calls
    /// (isideload's `plist_request`): the base headers every
    /// GrandSlam request carries, plus the identity's provisioning
    /// headers — remote_v3's `provisioning_headers` sends only
    /// X-Apple-I-MD-LU and X-Mme-Device-Id (its client-time headers
    /// are commented out upstream, and there are no anisette
    /// MD/MD-M values yet). Returns the response's `Response` dict.
    private static func gsPlistRequest(url urlString: String, body: [String: Any],
                                       state: AnisetteState,
                                       clientInfo: String, userAgent: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw AnisetteError.badResponse("a valid URL")
        }
        let bodyData = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Accept")
        request.setValue(clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("14.2 (14C18)", forHTTPHeaderField: "X-Xcode-Version")
        request.setValue("com.apple.gs.xcode.auth", forHTTPHeaderField: "X-Apple-App-Info")
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue(state.mdLUHex, forHTTPHeaderField: "X-Apple-I-MD-LU")
        request.setValue(state.deviceID, forHTTPHeaderField: "X-Mme-Device-Id")
        let (data, response) = try await http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw AnisetteError.message("GrandSlam answered HTTP \(status) for a provisioning request.")
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let responseDict = plist["Response"] as? [String: Any] else {
            throw AnisetteError.message("GrandSlam's provisioning response is unreadable.")
        }
        return responseDict
    }

    // MARK: - GrandSlam URL bag

    /// The GrandSlam URL bag (isideload's `fetch_url_bag`): GET
    /// GsService2/lookup with the sign-in client's base headers,
    /// keep the `urls` dict. A bag that lacks the URLs sign-in uses
    /// (with gsService on gsa.apple.com), asked for by a client that
    /// isn't a Mac, is asked for again as a Mac.
    private static func fetchURLBag(clientInfo: String, userAgent: String) async throws -> [String: String] {
        var bag = try await requestURLBag(clientInfo: clientInfo, userAgent: userAgent)
        let complete = bagKeys.allSatisfy { bag[$0] != nil }
            && (bag["gsService"]?.hasPrefix("https://gsa.apple.com/") ?? false)
        if !complete && !isMacClient(clientInfo) {
            bag = try await requestURLBag(clientInfo: macBagClientInfo, userAgent: userAgent)
        }
        return bag
    }

    private static func requestURLBag(clientInfo: String, userAgent: String) async throws -> [String: String] {
        var request = URLRequest(url: urlBagURL)
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Accept")
        request.setValue(clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("14.2 (14C18)", forHTTPHeaderField: "X-Xcode-Version")
        request.setValue("com.apple.gs.xcode.auth", forHTTPHeaderField: "X-Apple-App-Info")
        request.setValue("close", forHTTPHeaderField: "Connection")
        let (data, _) = try await http.data(for: request)
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let urls = plist["urls"] as? [String: Any] else {
            throw AnisetteError.message("GrandSlam's URL bag is unreadable.")
        }
        var bag: [String: String] = [:]
        for (key, value) in urls {
            if let string = value as? String { bag[key] = string }
        }
        return bag
    }

    private static func isMacClient(_ clientInfo: String) -> Bool {
        clientInfo.contains("<macOS;") || clientInfo.contains("<Mac OS X;")
    }
}
