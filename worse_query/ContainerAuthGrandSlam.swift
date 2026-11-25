import Foundation

// MARK: - Container Apple ID auth: GrandSlam sign-in
//
// Ported from Signed Apps (pinned 61d013e8). Only the Crypto
// references are renamed (ContainerAuthCrypto); the flow is
// verbatim: SRP init -> complete -> negotiation check ->
// decrypt spd -> 2FA -> apptokens.

/// A signed-in Apple developer session: the DSID (adsid) plus the
/// Xcode app token, as produced by AltSign's authenticate flow.
struct AppleSession {
    let adsid: String
    let authToken: String
    let email: String

    /// X-Apple-Identity-Token for developer-services requests.
    var identityToken: String {
        Data("\(adsid):\(authToken)".utf8).base64EncodedString()
    }
}

enum GrandSlamError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// The GrandSlam authentication flow, ported step-by-step from
/// AltSign's ALTAppleAPI+Authentication.m:
/// SRP init -> SRP complete -> negotiation-protocol check ->
/// decrypt spd -> (2FA via trusted device if required) ->
/// apptokens exchange for the Xcode token.
final class GrandSlamAuthenticator {
    var log: (String) -> Void = { _ in }

    /// A dedicated session for GrandSlam traffic. Requests also send
    /// `Connection: close`: a fresh connection per request, because
    /// Apple's GSA edge answers reused keep-alive connections with
    /// 5xx (found by SideSign/isideload; a sign-in makes 3+ calls).
    private let http: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config)
    }()

    private static let gsURL = URL(string: "https://gsa.apple.com/grandslam/GsService2")!
    private static let appTokenService = "com.apple.gs.xcode.auth"

    // The negotiation-protocol hash AltSign accumulates across the
    // handshake (ccdigest over strings, "|" separators, and
    // length-prefixed data blobs).
    private final class NegotiationHash {
        private var parts: [Data] = []
        func updateString(_ s: String) { parts.append(Data(s.utf8)) }
        func updateData(_ d: Data) {
            var length = UInt32(d.count).littleEndian
            var prefixed = Data(bytes: &length, count: 4)
            prefixed.append(d)
            parts.append(prefixed)
        }
        func finalize() -> Data {
            var all = Data()
            for p in parts { all.append(p) }
            return ContainerAuthCrypto.sha256(all)
        }
    }

    func authenticate(email: String, password: String, anisetteServer: String,
                      provideTwoFactorCode: @escaping () async -> String?) async throws -> AppleSession {
        try await authenticate(email: email, password: password, anisetteServer: anisetteServer,
                               provideTwoFactorCode: provideTwoFactorCode, isRetryAfterTwoFactor: false)
    }

    private func authenticate(email: String, password: String, anisetteServer: String,
                              provideTwoFactorCode: @escaping () async -> String?,
                              isRetryAfterTwoFactor: Bool) async throws -> AppleSession {
        log("fetching anisette data…")
        let anisette = try await Anisette.fetch(serverURLString: anisetteServer, log: log)
        log("anisette OK (device \(anisette.deviceSerialNumber), routing \(anisette.routingInfo), via \(anisette.serverUsed))")
        log("client identity: \(anisette.deviceDescription)")

        let cpd = clientDictionary(anisette: anisette)
        let srp = SRPClient()
        let negHash = NegotiationHash()
        negHash.updateString("s2k")
        negHash.updateString(",")
        negHash.updateString("s2k_fo")
        negHash.updateString("|")

        log("SRP init…")
        let initResponse = try await sendAuthRequest(
            parameters: ["A2k": srp.publicAData, "ps": ["s2k", "s2k_fo"], "cpd": cpd, "u": email, "o": "init"],
            anisette: anisette)

        negHash.updateString("|")
        guard let sp = initResponse["sp"] as? String else {
            throw GrandSlamError.message("Init response is missing the protocol (sp).")
        }
        negHash.updateString(sp)
        guard let c = initResponse["c"] as? String,
              let salt = initResponse["s"] as? Data,
              let iterations = (initResponse["i"] as? NSNumber)?.intValue,
              let serverB = initResponse["B"] as? Data else {
            throw GrandSlamError.message("Init response is missing SRP fields (c/s/i/B).")
        }
        log("init OK: protocol \(sp), \(iterations) iterations")

        guard let passwordKey = GrandSlamAuthenticator.derivePasswordKey(password: password, isS2K: sp == "s2k", salt: salt, iterations: iterations) else {
            throw GrandSlamError.message("Password key derivation failed.")
        }
        guard let m1 = srp.processChallenge(username: email, passwordKey: passwordKey, salt: salt, serverBData: serverB) else {
            throw GrandSlamError.message("SRP challenge processing failed (safety check).")
        }

        log("SRP complete…")
        let completeResponse = try await sendAuthRequest(
            parameters: ["c": c, "M1": m1, "cpd": cpd, "u": email, "o": "complete"],
            anisette: anisette)

        guard let m2 = completeResponse["M2"] as? Data else {
            throw GrandSlamError.message("Complete response is missing M2.")
        }
        guard srp.verifySession(m2: m2) else {
            throw GrandSlamError.message("Failed to verify the session (M2 mismatch) — usually a wrong password or an SRP mismatch.")
        }
        log("session verified")

        negHash.updateString("|")
        guard let spd = completeResponse["spd"] as? Data else {
            throw GrandSlamError.message("Complete response is missing spd.")
        }
        negHash.updateData(spd)
        negHash.updateString("|")
        if let sc = completeResponse["sc"] as? Data {
            negHash.updateData(sc)
        }
        negHash.updateString("|")
        guard let np = completeResponse["np"] as? Data else {
            throw GrandSlamError.message("Complete response is missing np.")
        }
        guard let hmacKey = srp.derivedKey(named: "HMAC key:") else {
            throw GrandSlamError.message("No session key for the negotiation check.")
        }
        let expectedNP = ContainerAuthCrypto.hmacSHA256(key: hmacKey, message: negHash.finalize())
        guard expectedNP == np else {
            throw GrandSlamError.message("Negotiation-protocol check failed (np mismatch).")
        }

        guard let decrypted = decryptSPD(srp: srp, spd: spd),
              let spdDict = try? PropertyListSerialization.propertyList(from: decrypted, options: [], format: nil) as? [String: Any],
              let adsid = spdDict["adsid"] as? String,
              let idmsToken = spdDict["GsIdmsToken"] as? String else {
            throw GrandSlamError.message("Could not decrypt or parse the login response (spd).")
        }
        log("login response decrypted (adsid \(adsid))")

        let authType = (completeResponse["Status"] as? [String: Any])?["au"] as? String
        if authType == "trustedDeviceSecondaryAuth" {
            log("two-factor authentication required (trusted device)")
            guard !isRetryAfterTwoFactor else {
                throw GrandSlamError.message("Two-factor was requested again after validation — giving up this attempt.")
            }
            try await validateTwoFactor(adsid: adsid, idmsToken: idmsToken, anisette: anisette, provideCode: provideTwoFactorCode)
            log("two-factor validated — restarting authentication")
            return try await authenticate(email: email, password: password, anisetteServer: anisetteServer,
                                          provideTwoFactorCode: provideTwoFactorCode, isRetryAfterTwoFactor: true)
        }
        if let authType {
            log("auth type: \(authType) — proceeding to app tokens")
        }

        guard let sk = spdDict["sk"] as? Data, let tokenC = spdDict["c"] as? Data else {
            throw GrandSlamError.message("Login response is missing sk/c for the app-token exchange.")
        }
        let checksum = ContainerAuthCrypto.hmacSHA256(key: sk, message: Data("apptokens".utf8) + Data(adsid.utf8) + Data(Self.appTokenService.utf8))
        log("requesting app token for \(Self.appTokenService)…")
        let tokenResponse = try await sendAuthRequest(
            parameters: ["u": adsid, "app": [Self.appTokenService], "c": tokenC, "t": idmsToken,
                         "checksum": checksum, "cpd": cpd, "o": "apptokens"],
            anisette: anisette)
        guard let et = tokenResponse["et"] as? Data,
              let decryptedToken = ContainerAuthCrypto.aesGCMDecryptAppToken(key: sk, blob: et),
              let tokenDict = try? PropertyListSerialization.propertyList(from: decryptedToken, options: [], format: nil) as? [String: Any],
              let perApp = (tokenDict["t"] as? [String: Any])?[Self.appTokenService] as? [String: Any],
              let token = perApp["token"] as? String else {
            throw GrandSlamError.message("Could not decrypt or parse the app token.")
        }
        log("app token received")
        return AppleSession(adsid: adsid, authToken: token, email: email)
    }

    // MARK: - Pieces

    /// ALTPBKDF2SRP: PBKDF2 over SHA256(password) for "s2k", or over
    /// the lowercase hex of SHA256(password) for "s2k_fo".
    static func derivePasswordKey(password: String, isS2K: Bool, salt: Data, iterations: Int) -> Data? {
        let digest = ContainerAuthCrypto.sha256(Data(password.utf8))
        let input: Data
        if isS2K {
            input = digest
        } else {
            input = Data(digest.map { String(format: "%02x", $0) }.joined().utf8)
        }
        return ContainerAuthCrypto.pbkdf2SHA256(password: input, salt: salt, iterations: iterations)
    }

    private func decryptSPD(srp: SRPClient, spd: Data) -> Data? {
        guard let key = srp.derivedKey(named: "extra data key:"),
              let ivFull = srp.derivedKey(named: "extra data iv:") else { return nil }
        return ContainerAuthCrypto.aesCBCDecrypt(key: key, iv: Data(ivFull.prefix(16)), data: spd)
    }

    private func clientDictionary(anisette: AnisetteData) -> [String: Any] {
        [
            "bootstrap": true,
            "icscrec": true,
            "loc": anisette.localeIdentifier,
            "pbe": false,
            "prkgen": true,
            "svct": "iCloud",
            "X-Apple-I-Client-Time": anisette.clientTimeString,
            "X-Apple-Locale": anisette.localeIdentifier,
            "X-Apple-I-TimeZone": anisette.timeZoneAbbreviation,
            "X-Apple-I-MD": anisette.oneTimePassword,
            "X-Apple-I-MD-LU": anisette.localUserID,
            "X-Apple-I-MD-M": anisette.machineID,
            "X-Apple-I-MD-RINFO": NSNumber(value: anisette.routingInfo),
            "X-Mme-Device-Id": anisette.deviceUniqueIdentifier,
            "X-Apple-I-SRL-NO": anisette.deviceSerialNumber,
        ]
    }

    private func sendAuthRequest(parameters: [String: Any], anisette: AnisetteData) async throws -> [String: Any] {
        let body: [String: Any] = ["Header": ["Version": "1.0.1"], "Request": parameters]
        let bodyData = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        var request = URLRequest(url: Self.gsURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        // isideload's GrandSlam base_headers: one consistent identity
        // (the clientInfoToUse result + its paired user agent) on
        // every request.
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Accept")
        request.setValue(anisette.deviceDescription, forHTTPHeaderField: "X-MMe-Client-Info")
        request.setValue(anisette.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("14.2 (14C18)", forHTTPHeaderField: "X-Xcode-Version")
        request.setValue(Self.appTokenService, forHTTPHeaderField: "X-Apple-App-Info")
        request.setValue("close", forHTTPHeaderField: "Connection")

        let (data, _) = try await http.data(for: request)
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let response = plist["Response"] as? [String: Any] else {
            throw GrandSlamError.message("Apple's auth server returned an unreadable response.")
        }
        if let status = response["Status"] as? [String: Any],
           let ec = (status["ec"] as? NSNumber)?.intValue, ec != 0 {
            if ec == -22406 {
                throw GrandSlamError.message("Incorrect Apple ID or password (-22406).")
            }
            let em = status["em"] as? String ?? "Unknown auth error"
            throw GrandSlamError.message("\(em) (\(ec))")
        }
        return response
    }

    private func validateTwoFactor(adsid: String, idmsToken: String, anisette: AnisetteData,
                                   provideCode: @escaping () async -> String?) async throws {
        let identityToken = Data("\(adsid):\(idmsToken)".utf8).base64EncodedString()
        var headers: [String: String] = [
            "Content-Type": "text/x-xml-plist",
            "User-Agent": anisette.userAgent,
            "Accept": "text/x-xml-plist",
            "Accept-Language": "en-us",
            "X-Apple-App-Info": Self.appTokenService,
            "X-Xcode-Version": "14.2 (14C18)",
            "Connection": "close",
            "X-Apple-Identity-Token": identityToken,
            "X-Apple-I-MD-M": anisette.machineID,
            "X-Apple-I-MD": anisette.oneTimePassword,
            "X-Apple-I-MD-LU": anisette.localUserID,
            "X-Apple-I-MD-RINFO": String(anisette.routingInfo),
            "X-Mme-Device-Id": anisette.deviceUniqueIdentifier,
            "X-MMe-Client-Info": anisette.deviceDescription,
            "X-Apple-I-Client-Time": anisette.clientTimeString,
            "X-Apple-Locale": anisette.localeIdentifier,
            "X-Apple-I-TimeZone": anisette.timeZoneAbbreviation,
        ]

        log("requesting a trusted-device code…")
        var trigger = URLRequest(url: URL(string: "https://gsa.apple.com/auth/verify/trusteddevice")!)
        for (k, v) in headers { trigger.setValue(v, forHTTPHeaderField: k) }
        _ = try await http.data(for: trigger)

        guard let code = await provideCode() else {
            throw GrandSlamError.message("Two-factor entry was cancelled.")
        }
        headers["security-code"] = code
        var validate = URLRequest(url: URL(string: "https://gsa.apple.com/grandslam/GsService2/validate")!)
        for (k, v) in headers { validate.setValue(v, forHTTPHeaderField: k) }
        let (data, _) = try await http.data(for: validate)
        guard let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw GrandSlamError.message("Two-factor validation returned an unreadable response.")
        }
        let ec = (dict["ec"] as? NSNumber)?.intValue ?? (dict["ec"] as? String).flatMap(Int.init) ?? -1
        if ec == -21669 {
            throw GrandSlamError.message("Incorrect verification code (-21669).")
        }
        guard ec == 0 else {
            let em = dict["em"] as? String ?? "Two-factor validation failed"
            throw GrandSlamError.message("\(em) (\(ec))")
        }
    }
}
