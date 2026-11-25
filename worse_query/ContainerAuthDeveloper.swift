import Foundation

// MARK: - Container Apple ID auth: developer services (QH65B2)
//
// Ported from Signed Apps (pinned 61d013e8). Adaptations: the
// portal `AppGroup` model is renamed DeveloperAppGroup (WorkTweaks
// already has an AppGroup type in SandboxView); the anisette
// override UserDefaults key is wt.container.anisetteURL.
// The assign-group call sends applicationGroups as an ARRAY
// (Stage 3.2) — the scalar shape links nothing.

/// Errors from the developer-services (QH65B2) protocol.
enum DeveloperError: LocalizedError {
    /// A local/protocol problem (bad response, missing data, HTTP error).
    case message(String)
    /// Apple's own error: `resultCode != 0`, with the server's
    /// user-facing string (isideload's `SideloadError::DeveloperError`).
    case server(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .server(let code, let message): return "Developer error \(code): \(message)"
        }
    }

    var serverCode: Int? {
        if case .server(let code, _) = self { return code }
        return nil
    }
}

// MARK: - Plist value helpers

func plistString(_ value: Any?) -> String? { value as? String }
func plistInt(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
func plistBool(_ value: Any?) -> Bool? { (value as? NSNumber)?.boolValue }
func plistData(_ value: Any?) -> Data? { value as? Data }
func plistDate(_ value: Any?) -> Date? { value as? Date }
func plistDict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
func plistArray(_ value: Any?) -> [Any]? { value as? [Any] }
func plistDictArray(_ value: Any?) -> [[String: Any]]? {
    plistArray(value)?.compactMap { $0 as? [String: Any] }
}

/// The name to register an App ID or app group under — isideload's
/// `normalize_app_names` (dev/mod.rs): Apple refuses names with
/// anything but ASCII letters and digits ("Developer error 35").
func normalizeAppName(_ name: String) -> String {
    let normalized = name.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    return normalized.isEmpty ? "App" : String(normalized)
}

// MARK: - Portal models (plist keys as deserialized by isideload)

struct DeveloperTeam {
    var name: String?
    var teamId: String
    var type: String?
    var status: String?

    init?(_ dict: [String: Any]) {
        guard let teamId = plistString(dict["teamId"]) else { return nil }
        self.teamId = teamId
        name = plistString(dict["name"])
        type = plistString(dict["type"])
        status = plistString(dict["status"])
    }
}

struct DevelopmentCertificate: Identifiable {
    var name: String?
    var certificateId: String?
    var serialNumber: String?
    var machineId: String?
    var machineName: String?
    var certContent: Data?
    var certificatePlatform: String?
    var certificateTypeName: String?
    var certificateTypePlatform: String?
    var status: String?
    var expirationDate: Date?

    var id: String {
        certificateId ?? serialNumber ?? "\(machineId ?? "?")|\(name ?? "?")"
    }

    init(_ dict: [String: Any]) {
        name = plistString(dict["name"])
        certificateId = plistString(dict["certificateId"])
        serialNumber = plistString(dict["serialNumber"])
        machineId = plistString(dict["machineId"])
        machineName = plistString(dict["machineName"])
        certContent = plistData(dict["certContent"])
        certificatePlatform = plistString(dict["certificatePlatform"])
        certificateTypeName = plistString(plistDict(dict["certificateType"])?["name"])
        certificateTypePlatform = plistString(plistDict(dict["certificateType"])?["platform"])
        status = plistString(dict["status"])
        expirationDate = plistDate(dict["expirationDate"])
    }
}

struct CertRequest {
    var certRequestId: String

    init?(_ dict: [String: Any]) {
        guard let id = plistString(dict["certRequestId"]) else { return nil }
        certRequestId = id
    }
}

struct DeveloperDevice: Identifiable {
    var name: String?
    var deviceId: String?
    var deviceNumber: String
    var status: String?

    var id: String { deviceNumber }

    init?(_ dict: [String: Any]) {
        guard let number = plistString(dict["deviceNumber"]) else { return nil }
        deviceNumber = number
        name = plistString(dict["name"])
        deviceId = plistString(dict["deviceId"])
        status = plistString(dict["status"])
    }
}

struct AppId {
    var appIdId: String
    var identifier: String
    var name: String
    var features: [String: Any]
    var expirationDate: Date?

    init?(_ dict: [String: Any]) {
        guard let appIdId = plistString(dict["appIdId"]),
              let identifier = plistString(dict["identifier"]),
              let name = plistString(dict["name"]) else { return nil }
        self.appIdId = appIdId
        self.identifier = identifier
        self.name = name
        features = plistDict(dict["features"]) ?? [:]
        expirationDate = plistDate(dict["expirationDate"])
    }
}

struct ListAppIdsResponse {
    var appIds: [AppId]
    var maxQuantity: Int?
    var availableQuantity: Int?
}

struct DeveloperAppGroup {
    var name: String?
    var identifier: String
    var applicationGroup: String

    init?(_ dict: [String: Any]) {
        guard let identifier = plistString(dict["identifier"]),
              let applicationGroup = plistString(dict["applicationGroup"]) else { return nil }
        self.identifier = identifier
        self.applicationGroup = applicationGroup
        name = plistString(dict["name"])
    }
}

struct PortalProvisioningProfile {
    var encodedProfile: Data
    var filename: String
    var provisioningProfileId: String
    var name: String
    var status: String
    var type: String
    var distributionMethod: String
    var uuid: String
    var dateExpire: Date
    var appIdId: String

    init?(_ dict: [String: Any]) {
        guard let encodedProfile = plistData(dict["encodedProfile"]),
              let filename = plistString(dict["filename"]),
              let provisioningProfileId = plistString(dict["provisioningProfileId"]),
              let name = plistString(dict["name"]),
              let status = plistString(dict["status"]),
              let type = plistString(dict["type"]),
              let distributionMethod = plistString(dict["distributionMethod"]),
              let uuid = plistString(dict["UUID"]),
              let dateExpire = plistDate(dict["dateExpire"]),
              let appIdId = plistString(dict["appIdId"]) else { return nil }
        self.encodedProfile = encodedProfile
        self.filename = filename
        self.provisioningProfileId = provisioningProfileId
        self.name = name
        self.status = status
        self.type = type
        self.distributionMethod = distributionMethod
        self.uuid = uuid
        self.dateExpire = dateExpire
        self.appIdId = appIdId
    }
}

// MARK: - Developer services client

/// A port of isideload's `DeveloperSession` + the `dev` API traits
/// (the engine inside iLoader 2.4.1): plist POSTs to
/// developerservices2.apple.com/services/QH65B2, with GrandSlam's
/// base headers, the anisette header map, and the session's
/// X-Apple-GS-Token / X-Apple-I-Identity-Id on every request.
final class DeveloperSession {
    private let session: AppleSession
    var log: (String) -> Void = { _ in }

    /// Same transport discipline as the GrandSlam client: an
    /// ephemeral session, one connection per host, `Connection:
    /// close` — Apple's edge answers reused keep-alive connections
    /// with 5xx.
    private let http: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config)
    }()

    init(session: AppleSession) {
        self.session = session
    }

    /// isideload's `dev_url`: the `ios/` segment is the default;
    /// `listTeams` is the one call made with no platform segment.
    private func devURL(_ endpoint: String, segment: String = "ios/") -> URL {
        URL(string: "https://developerservices2.apple.com/services/QH65B2/\(segment)\(endpoint).action?clientId=XABBG36SBA")!
    }

    /// `DeveloperSession::get_headers`: fresh anisette data (the
    /// generator is consulted per request in isideload), reduced to
    /// its header map, plus the two session headers.
    private func makeHeaders() async throws -> [String: String] {
        let anisetteServer = UserDefaults.standard.string(forKey: "wt.container.anisetteURL") ?? ""
        let anisette = try await Anisette.fetch(serverURLString: anisetteServer, log: { _ in })
        return [
            "Content-Type": "text/x-xml-plist",
            "Accept": "text/x-xml-plist",
            "X-Mme-Client-Info": anisette.deviceDescription,
            "User-Agent": anisette.userAgent,
            "X-Xcode-Version": "14.2 (14C18)",
            "X-Apple-App-Info": "com.apple.gs.xcode.auth",
            "X-Mme-Device-Id": anisette.deviceUniqueIdentifier,
            "X-Apple-I-MD": anisette.oneTimePassword,
            "X-Apple-I-MD-M": anisette.machineID,
            "X-Apple-GS-Token": session.authToken,
            "X-Apple-I-Identity-Id": session.adsid,
            "Connection": "close",
        ]
    }

    /// `send_dev_request_internal`: the base envelope (clientId,
    /// protocolVersion, requestId, userLocale) merged under the
    /// call's own body keys; a non-zero `resultCode` becomes a
    /// pending server error that only fails the call if the caller
    /// cannot extract what it asked for (or asked for nothing).
    private func sendRequest(endpoint: String, segment: String = "ios/",
                             body: [String: Any]) async throws -> (dict: [String: Any], serverError: DeveloperError?) {
        var full: [String: Any] = [
            "clientId": "XABBG36SBA",
            "protocolVersion": "QH65B2",
            "requestId": UUID().uuidString.uppercased(),
            "userLocale": ["en_US"],
        ]
        for (key, value) in body { full[key] = value }

        let bodyData = try PropertyListSerialization.data(fromPropertyList: full, format: .xml, options: 0)
        var request = URLRequest(url: devURL(endpoint, segment: segment))
        request.httpMethod = "POST"
        request.httpBody = bodyData
        for (key, value) in try await makeHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await http.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw DeveloperError.message("Developer request failed (HTTP \(httpResponse.statusCode))")
        }
        guard let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw DeveloperError.message("Failed to parse the developer request response.")
        }

        var serverError: DeveloperError?
        if let code = plistInt(dict["resultCode"]) {
            if code != 0 {
                let resultString = plistString(dict["resultString"]) ?? "No error message given."
                let userString = plistString(dict["userString"]) ?? resultString
                serverError = .server(code: code, message: userString)
                log("developer request returned error code \(code): \(userString) (\(resultString))")
            }
        } else {
            log("warning: no resultCode in developer request response")
        }
        return (dict, serverError)
    }

    /// `send_dev_request`: extract `key` from the response; a
    /// pending server error wins only when extraction fails.
    private func sendRequest<T>(endpoint: String, segment: String = "ios/",
                                body: [String: Any], responseKey: String,
                                parse: (Any) -> T?) async throws -> T {
        let (dict, serverError) = try await sendRequest(endpoint: endpoint, segment: segment, body: body)
        if let raw = dict[responseKey], let value = parse(raw) {
            return value
        }
        if let serverError { throw serverError }
        throw DeveloperError.message("Developer response is missing '\(responseKey)'.")
    }

    /// `send_dev_request_no_response`: any server error fails the
    /// call; otherwise the whole response dictionary is returned.
    private func sendRequestNoResponse(endpoint: String, segment: String = "ios/",
                                       body: [String: Any]) async throws -> [String: Any] {
        let (dict, serverError) = try await sendRequest(endpoint: endpoint, segment: segment, body: body)
        if let serverError { throw serverError }
        return dict
    }

    // MARK: Teams (teams.rs)

    func listTeams() async throws -> [DeveloperTeam] {
        try await sendRequest(endpoint: "listTeams", segment: "", body: [:], responseKey: "teams") {
            plistDictArray($0)?.compactMap(DeveloperTeam.init)
        }
    }

    // MARK: Certificates (certificates.rs)

    func listAllDevelopmentCerts(team: DeveloperTeam) async throws -> [DevelopmentCertificate] {
        try await sendRequest(endpoint: "listAllDevelopmentCerts", body: ["teamId": team.teamId],
                              responseKey: "certificates") {
            plistDictArray($0)?.map(DevelopmentCertificate.init)
        }
    }

    /// `list_ios_certs`: keep the ones Apple labels iOS, assuming
    /// iOS when neither the certificate nor its type says otherwise.
    func listIOSCerts(team: DeveloperTeam) async throws -> [DevelopmentCertificate] {
        let certs = try await listAllDevelopmentCerts(team: team)
        return certs.filter { cert in
            if let platform = cert.certificatePlatform {
                return platform.lowercased() == "ios"
            }
            if let platform = cert.certificateTypePlatform {
                return platform.lowercased() == "ios"
            }
            return true
        }
    }

    /// `revoke_development_cert`: revoke by serial number. When
    /// Apple answers 7252 — the serial belongs to a cross-platform
    /// "Apple Development" certificate (the kind Xcode makes) that
    /// the platform endpoint cannot revoke — find the certificate
    /// in the full list and delete it by ID through the JSON:API
    /// instead, as certificates.rs does. Any other error stands.
    func revokeDevelopmentCert(team: DeveloperTeam, serialNumber: String) async throws {
        do {
            _ = try await sendRequestNoResponse(
                endpoint: "revokeDevelopmentCert",
                body: ["teamId": team.teamId, "serialNumber": serialNumber])
            return
        } catch {
            guard (error as? DeveloperError)?.serverCode == 7252 else { throw error }
            let certs = try await listAllDevelopmentCerts(team: team)
            guard let certificateId = certs.first(where: {
                $0.serialNumber?.caseInsensitiveCompare(serialNumber) == .orderedSame
            })?.certificateId else {
                throw error
            }
            log("certificate \(serialNumber) isn't an iOS one; deleting it by ID \(certificateId)")
            try await deleteCertificate(team: team, certificateId: certificateId)
        }
    }

    /// `delete_certificate`: delete a certificate of any type by
    /// its certificateId, through `DELETE services/v1/certificates/<id>`.
    func deleteCertificate(team: DeveloperTeam, certificateId: String) async throws {
        _ = try await sendServicesRequest(path: "certificates/\(certificateId)", team: team, method: "DELETE")
    }

    // MARK: Services API (developer_session.rs)

    /// `services_url`: Xcode's JSON:API endpoint (`services/v1`).
    private func servicesURL(_ path: String) -> URL {
        URL(string: "https://developerservices2.apple.com/services/v1/\(path)")!
    }

    /// `send_services_request`: always a POST, with the real
    /// method in `X-HTTP-Method-Override` and the query (just
    /// `teamId`) in the body's `urlEncodedQueryParams`. JSON:API
    /// errors and bare HTTP failures both become errors; an empty
    /// body (a DELETE answers with no content) reads as nil.
    @discardableResult
    func sendServicesRequest(path: String, team: DeveloperTeam, method: String) async throws -> [String: Any]? {
        var request = URLRequest(url: servicesURL(path))
        request.httpMethod = "POST"
        for (key, value) in try await makeHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue(method, forHTTPHeaderField: "X-HTTP-Method-Override")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["urlEncodedQueryParams": "teamId=\(team.teamId)"])

        let (data, response) = try await http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        var json: [String: Any]?
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DeveloperError.message("Failed to parse the developer services response.")
            }
            json = parsed
        }
        if let errors = json?["errors"] as? [[String: Any]], !errors.isEmpty {
            let message = errors.map { entry -> String in
                let code = entry["code"] as? String ?? ""
                let detail = entry["detail"] as? String ?? ""
                let title = entry["title"] as? String ?? ""
                if !detail.isEmpty { return "\(detail) (\(code))" }
                if !title.isEmpty { return "\(title) (\(code))" }
                return code
            }.joined(separator: "; ")
            log("developer services request returned \(status): \(message)")
            throw DeveloperError.message("Developer services error \(status): \(message)")
        }
        guard (200...299).contains(status) else {
            throw DeveloperError.message("Developer services request returned \(status)")
        }
        return json
    }

    /// `submit_development_csr`. isideload generates a fresh
    /// machine ID per submission; ours is persisted by the caller
    /// (CertificateIdentity) so the identity is stable across runs —
    /// the wire request is identical.
    func submitDevelopmentCSR(team: DeveloperTeam, csrContent: String,
                              machineName: String, machineId: String) async throws -> CertRequest {
        try await sendRequest(endpoint: "submitDevelopmentCSR",
                              body: ["teamId": team.teamId, "csrContent": csrContent,
                                     "machineName": machineName, "machineId": machineId],
                              responseKey: "certRequest") {
            ($0 as? [String: Any]).flatMap(CertRequest.init)
        }
    }

    // MARK: Devices (devices.rs)

    func listDevices(team: DeveloperTeam) async throws -> [DeveloperDevice] {
        try await sendRequest(endpoint: "listDevices", body: ["teamId": team.teamId],
                              responseKey: "devices") {
            plistDictArray($0)?.compactMap(DeveloperDevice.init)
        }
    }

    func addDevice(team: DeveloperTeam, name: String, udid: String) async throws -> DeveloperDevice {
        try await sendRequest(endpoint: "addDevice",
                              body: ["teamId": team.teamId, "name": name, "deviceNumber": udid],
                              responseKey: "device") {
            ($0 as? [String: Any]).flatMap(DeveloperDevice.init)
        }
    }

    // MARK: App IDs (app_ids.rs)

    func listAppIds(team: DeveloperTeam) async throws -> ListAppIdsResponse {
        let dict = try await sendRequestNoResponse(endpoint: "listAppIds", body: ["teamId": team.teamId])
        return ListAppIdsResponse(
            appIds: plistDictArray(dict["appIds"])?.compactMap(AppId.init) ?? [],
            maxQuantity: plistInt(dict["maxQuantity"]),
            availableQuantity: plistInt(dict["availableQuantity"]))
    }

    func addAppId(team: DeveloperTeam, name: String, identifier: String) async throws -> AppId {
        try await sendRequest(endpoint: "addAppId",
                              body: ["teamId": team.teamId, "identifier": identifier,
                                     "name": normalizeAppName(name)],
                              responseKey: "appId") {
            ($0 as? [String: Any]).flatMap(AppId.init)
        }
    }

    /// `update_app_id`: the feature entries ride at the top level
    /// of the request body, next to teamId and appIdId.
    func updateAppId(team: DeveloperTeam, appId: AppId, features: [String: Any]) async throws -> AppId {
        var body: [String: Any] = ["teamId": team.teamId, "appIdId": appId.appIdId]
        for (key, value) in features { body[key] = value }
        return try await sendRequest(endpoint: "updateAppId", body: body, responseKey: "appId") {
            ($0 as? [String: Any]).flatMap(AppId.init)
        }
    }

    /// AppId::ensure_group_feature (app_ids.rs): the application
    /// groups feature is the flag `APG3427HIY`.
    func ensureGroupFeature(team: DeveloperTeam, appId: inout AppId) async throws {
        if plistBool(appId.features["APG3427HIY"]) == true { return }
        appId = try await updateAppId(team: team, appId: appId, features: ["APG3427HIY": true])
    }

    func downloadTeamProvisioningProfile(team: DeveloperTeam, appId: AppId) async throws -> PortalProvisioningProfile {
        try await sendRequest(endpoint: "downloadTeamProvisioningProfile",
                              body: ["teamId": team.teamId, "appIdId": appId.appIdId],
                              responseKey: "provisioningProfile") {
            ($0 as? [String: Any]).flatMap(PortalProvisioningProfile.init)
        }
    }

    // MARK: App groups (app_groups.rs)

    func listAppGroups(team: DeveloperTeam) async throws -> [DeveloperAppGroup] {
        try await sendRequest(endpoint: "listApplicationGroups", body: ["teamId": team.teamId],
                              responseKey: "applicationGroupList") {
            plistDictArray($0)?.compactMap(DeveloperAppGroup.init)
        }
    }

    func addAppGroup(team: DeveloperTeam, name: String, identifier: String) async throws -> DeveloperAppGroup {
        try await sendRequest(endpoint: "addApplicationGroup",
                              body: ["teamId": team.teamId, "name": normalizeAppName(name),
                                     "identifier": identifier],
                              responseKey: "applicationGroup") {
            ($0 as? [String: Any]).flatMap(DeveloperAppGroup.init)
        }
    }

    /// AltSign's `assignAppID:toGroups:` sends `applicationGroups`
    /// as an ARRAY of the groups' portal IDs (`applicationGroup`
    /// values) — not the scalar string isideload sends. The plist
    /// endpoint accepts the scalar with resultCode 0 but links
    /// nothing (device-verified: assign "succeeds", yet the
    /// downloaded profile carries no application-groups), so this
    /// matches AltSign's array shape exactly.
    func assignAppGroup(team: DeveloperTeam, appGroup: DeveloperAppGroup, appId: AppId) async throws {
        _ = try await sendRequestNoResponse(endpoint: "assignApplicationGroupToAppId",
                                            body: ["teamId": team.teamId,
                                                   "applicationGroups": [appGroup.applicationGroup],
                                                   "appIdId": appId.appIdId])
    }

    /// `ensure_app_group`: reuse the group with this identifier,
    /// or add it.
    func ensureAppGroup(team: DeveloperTeam, name: String, identifier: String) async throws -> DeveloperAppGroup {
        let groups = try await listAppGroups(team: team)
        if let existing = groups.first(where: { $0.identifier == identifier }) {
            return existing
        }
        log("adding application group \(identifier)")
        return try await addAppGroup(team: team, name: name, identifier: identifier)
    }
}

// MARK: - Saved provisioning profiles

/// A downloaded team profile, parsed back out of its PKCS#7 blob
/// for display: the XML plist is embedded verbatim inside it.
struct SavedProfile: Identifiable {
    var bundleId: String
    var name: String
    var expirationDate: Date?
    var applicationGroups: [String]
    var fileURL: URL

    var id: String { bundleId }
}

enum ProfileStore {
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("profiles", isDirectory: true)
    }

    static func save(_ data: Data, bundleId: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = bundleId.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let url = directory.appendingPathComponent("\(safe).mobileprovision")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func loadAll() -> [SavedProfile] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "mobileprovision" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let bundleId = url.deletingPathExtension().lastPathComponent
                return parse(data, bundleId: bundleId, fileURL: url)
            }
    }

    /// The profile's embedded XML plist, decoded.
    static func profileDictionary(_ data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8))?.lowerBound,
              let end = data.range(of: Data("</plist>".utf8), options: .backwards)?.upperBound,
              let dict = try? PropertyListSerialization.propertyList(
                from: data[start..<end], options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return dict
    }

    /// Decisive diagnostics for the assign-group problem: every
    /// Entitlements key Apple actually generated, plus the values
    /// of `application-identifier` and `application-groups`
    /// ("absent" when the key is missing, "empty" when it is an
    /// empty array). Returns nil when the blob can't be parsed.
    static func entitlementsSummary(_ data: Data) -> String? {
        guard let dict = profileDictionary(data),
              let entitlements = plistDict(dict["Entitlements"]) else {
            return nil
        }
        let keys = entitlements.keys.sorted().joined(separator: ", ")
        let applicationIdentifier = plistString(entitlements["application-identifier"]) ?? "absent"
        let groupsValue: String
        if let groupList = plistArray(entitlements["application-groups"]) {
            let strings = groupList.compactMap { $0 as? String }
            groupsValue = strings.isEmpty ? "empty" : strings.joined(separator: ", ")
        } else {
            groupsValue = "absent"
        }
        return "keys: \(keys); application-identifier: \(applicationIdentifier); application-groups: \(groupsValue)"
    }

    static func parse(_ data: Data, bundleId: String, fileURL: URL) -> SavedProfile? {
        guard let dict = profileDictionary(data) else {
            return nil
        }
        let entitlements = plistDict(dict["Entitlements"])
        let groups = plistArray(entitlements?["application-groups"])?.compactMap { $0 as? String } ?? []
        return SavedProfile(
            bundleId: bundleId,
            name: plistString(dict["Name"]) ?? bundleId,
            expirationDate: plistDate(dict["ExpirationDate"]),
            applicationGroups: groups,
            fileURL: fileURL)
    }
}
