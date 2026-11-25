import Foundation
import Security

// MARK: - Container Apple ID auth: certificate identity
//
// Ported from Signed Apps (pinned 61d013e8). Adaptations:
// Crypto/Keychain renamed to the ContainerAuth variants;
// machineName is "WorkTweaks" (the name Apple shows for the
// certificate); plus privateKeyPKCS1(email:) for the .p12
// export the Container uses to store its signing certificate.

enum CertificateError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

// MARK: - Minimal DER writer (just what a CSR and PKCS#8 wrapper need)

enum DER {
    static func lengthBytes(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        var bytes: [UInt8] = []
        var value = length
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func tlv(tag: UInt8, content: Data) -> Data {
        var out = Data([tag])
        out.append(lengthBytes(content.count))
        out.append(content)
        return out
    }

    static func sequence(_ parts: [Data]) -> Data { tlv(tag: 0x30, content: concat(parts)) }
    static func set(_ parts: [Data]) -> Data { tlv(tag: 0x31, content: concat(parts)) }
    static func oid(_ content: [UInt8]) -> Data { tlv(tag: 0x06, content: Data(content)) }
    static func null() -> Data { Data([0x05, 0x00]) }
    static func utf8String(_ string: String) -> Data { tlv(tag: 0x0c, content: Data(string.utf8)) }
    static func printableString(_ string: String) -> Data { tlv(tag: 0x13, content: Data(string.utf8)) }
    static func octetString(_ payload: Data) -> Data { tlv(tag: 0x04, content: payload) }

    static func integer(_ value: Int) -> Data {
        var bytes: [UInt8] = []
        var remaining = value
        repeat {
            bytes.insert(UInt8(remaining & 0xff), at: 0)
            remaining >>= 8
        } while remaining > 0
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(tag: 0x02, content: Data(bytes))
    }

    /// BIT STRING with zero unused bits.
    static func bitString(_ payload: Data) -> Data {
        var content = Data([0])
        content.append(payload)
        return tlv(tag: 0x03, content: content)
    }

    private static func concat(_ parts: [Data]) -> Data {
        var out = Data()
        for part in parts { out.append(part) }
        return out
    }

    // OID content bytes used below.
    static let oidRSAEncryption: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]
    static let oidSHA256WithRSAEncryption: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b]
    static func oidNameComponent(_ component: UInt8) -> [UInt8] { [0x55, 0x04, component] }
}

// MARK: - Minimal DER reader (just what parsing our certificate needs)

struct DERReader {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    var isAtEnd: Bool { offset >= bytes.count }

    func peekTag() -> UInt8? {
        offset < bytes.count ? bytes[offset] : nil
    }

    mutating func readTLV() throws -> (tag: UInt8, content: Data) {
        guard offset + 2 <= bytes.count else {
            throw CertificateError.message("Truncated DER.")
        }
        let tag = bytes[offset]
        var index = offset + 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count >= 1, count <= 4, index + count <= bytes.count else {
                throw CertificateError.message("Invalid DER length.")
            }
            length = 0
            for _ in 0..<count {
                length = length << 8 | Int(bytes[index])
                index += 1
            }
        }
        guard index + length <= bytes.count else {
            throw CertificateError.message("Truncated DER value.")
        }
        let content = Data(bytes[index..<(index + length)])
        offset = index + length
        return (tag, content)
    }

    mutating func expect(_ tag: UInt8) throws -> Data {
        let (actual, content) = try readTLV()
        guard actual == tag else {
            throw CertificateError.message("Unexpected DER tag \(actual), expected \(tag).")
        }
        return content
    }
}

// MARK: - Certificate parsing

struct ParsedCertificate {
    var commonName: String?
    /// isideload's `get_serial_number`: hex of the serial, leading
    /// zeroes trimmed, uppercased.
    var serialHex: String
    var notAfter: Date
    /// The subject public key's BIT STRING payload — for an RSA
    /// key, the PKCS#1 RSAPublicKey DER.
    var publicKeyPKCS1: Data
}

func parseCertificate(_ der: Data) throws -> ParsedCertificate {
    var top = DERReader(der)
    var cert = DERReader(try top.expect(0x30))
    var tbs = DERReader(try cert.expect(0x30))
    if tbs.peekTag() == 0xa0 { _ = try tbs.readTLV() } // [0] version
    let serialBytes = try tbs.expect(0x02)
    let serialHex = serialBytes.map { String(format: "%02x", $0) }.joined()
        .uppercased().drop(while: { $0 == "0" })
    _ = try tbs.expect(0x30) // signature algorithm
    _ = try tbs.expect(0x30) // issuer
    var validity = DERReader(try tbs.expect(0x30))
    _ = try validity.readTLV() // notBefore
    let (notAfterTag, notAfterContent) = try validity.readTLV()
    guard let notAfter = parseDERTime(tag: notAfterTag, content: notAfterContent) else {
        throw CertificateError.message("Could not parse the certificate's expiration date.")
    }
    let subject = try tbs.expect(0x30)
    var spki = DERReader(try tbs.expect(0x30))
    _ = try spki.expect(0x30) // algorithm
    let bitString = try spki.expect(0x03)
    guard bitString.first == 0 else {
        throw CertificateError.message("Unexpected public key encoding.")
    }
    return ParsedCertificate(
        commonName: commonName(inName: subject),
        serialHex: serialHex.isEmpty ? "0" : String(serialHex),
        notAfter: notAfter,
        publicKeyPKCS1: bitString.dropFirst())
}

/// Walk an RDNSequence for the CN (2.5.4.3) component.
private func commonName(inName nameContent: Data) -> String? {
    var reader = DERReader(nameContent)
    while !reader.isAtEnd {
        guard let setContent = try? reader.expect(0x31) else { return nil }
        var setReader = DERReader(setContent)
        while !setReader.isAtEnd {
            guard let pair = try? setReader.expect(0x30) else { return nil }
            var pairReader = DERReader(pair)
            guard let oidContent = try? pairReader.expect(0x06),
                  let (_, value) = try? pairReader.readTLV() else { return nil }
            if [UInt8](oidContent) == [0x55, 0x04, 0x03] {
                return String(bytes: [UInt8](value), encoding: .utf8)
            }
        }
    }
    return nil
}

/// UTCTime (0x17, "YYMMDDHHMMSSZ") and GeneralizedTime (0x18,
/// "YYYYMMDDHHMMSSZ") — Apple issues Zulu times; trailing offsets
/// are tolerated by keeping only the leading digits.
private func parseDERTime(tag: UInt8, content: Data) -> Date? {
    guard let text = String(bytes: [UInt8](content), encoding: .ascii) else { return nil }
    let digits = String(text.prefix(while: { $0.isNumber }))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    func slice(_ range: Range<Int>) -> Int? {
        let start = digits.index(digits.startIndex, offsetBy: range.lowerBound)
        let end = digits.index(digits.startIndex, offsetBy: range.upperBound)
        return Int(digits[start..<end])
    }
    switch tag {
    case 0x17: // UTCTime: YY MM DD HH MM SS
        guard digits.count >= 12,
              let yy = slice(0..<2), let month = slice(2..<4), let day = slice(4..<6),
              let hour = slice(6..<8), let minute = slice(8..<10), let second = slice(10..<12)
        else { return nil }
        components.year = yy < 50 ? 2000 + yy : 1900 + yy
        components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
    case 0x18: // GeneralizedTime: YYYY MM DD HH MM SS
        guard digits.count >= 14,
              let year = slice(0..<4), let month = slice(4..<6), let day = slice(6..<8),
              let hour = slice(8..<10), let minute = slice(10..<12), let second = slice(12..<14)
        else { return nil }
        components.year = year
        components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
    default:
        return nil
    }
    return components.date
}

// MARK: - Certificate identity

/// The signing identity, mirroring isideload's `CertificateIdentity`
/// (sideload/cert_identity.rs): one RSA-2048 key per account, kept
/// in the Keychain (PKCS#8 DER, keyed by the account's email hash,
/// as isideload keys it by the SHA256 of the email); the portal
/// certificate that belongs to it is found by comparing public keys
/// — never by revoking anything. If none matches, a new certificate
/// is requested with a CSR built exactly as isideload builds it.
final class CertificateIdentity {
    /// Sent as the CSR's `machineName`; SideInstaller passes its own
    /// app name the same way ("SideInstaller"), isideload's default
    /// is "isideload".
    static let machineName = "WorkTweaks"

    let machineId: String
    let machineName: String
    let certificateDER: Data
    let portalName: String?
    let serialNumber: String
    let expirationDate: Date
    let commonName: String?

    private init(machineId: String, machineName: String, certificateDER: Data,
                 portalName: String?, serialNumber: String, expirationDate: Date,
                 commonName: String?) {
        self.machineId = machineId
        self.machineName = machineName
        self.certificateDER = certificateDER
        self.portalName = portalName
        self.serialNumber = serialNumber
        self.expirationDate = expirationDate
        self.commonName = commonName
    }

    var displayName: String { portalName ?? commonName ?? "Development certificate" }

    // MARK: Storage

    private static func emailHash(_ email: String) -> String {
        ContainerAuthCrypto.sha256(Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func privateKeyKey(email: String) -> String { "dev.privateKey.\(emailHash(email))" }
    private static func certificateKey(email: String) -> String { "dev.certificate.\(emailHash(email))" }
    private static let machineIdStorageKey = "dev.machineId"

    /// The machine ID submitted with CSRs — generated once and
    /// persisted, so this install presents one stable machine.
    static var persistedMachineId: String {
        if let existing = ContainerAuthKeychain.load(machineIdStorageKey) {
            return existing
        }
        let generated = UUID().uuidString.uppercased()
        ContainerAuthKeychain.save(generated, for: machineIdStorageKey)
        return generated
    }

    // MARK: Key handling

    /// SecKeyCopyExternalRepresentation speaks PKCS#1 for RSA keys;
    /// the Keychain stores PKCS#8, so wrap/unwrap the PKCS#1 core.
    private static func wrapPKCS8(pkcs1: Data) -> Data {
        DER.sequence([
            DER.integer(0),
            DER.sequence([DER.oid(DER.oidRSAEncryption), DER.null()]),
            DER.octetString(pkcs1),
        ])
    }

    private static func unwrapPKCS8(_ pkcs8: Data) throws -> Data {
        var reader = DERReader(pkcs8)
        var body = DERReader(try reader.expect(0x30))
        _ = try body.expect(0x02) // version
        _ = try body.expect(0x30) // algorithm
        return try body.expect(0x04)
    }

    private static func loadOrCreatePrivateKey(email: String) throws -> SecKey {
        if let stored = ContainerAuthKeychain.loadData(privateKeyKey(email: email)) {
            let pkcs1 = try unwrapPKCS8(stored)
            var error: Unmanaged<CFError>?
            let attributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            ]
            guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) else {
                throw CertificateError.message("Could not restore the saved private key.")
            }
            return key
        }
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw CertificateError.message("Could not generate an RSA key pair.")
        }
        guard let pkcs1 = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw CertificateError.message("Could not export the generated private key.")
        }
        ContainerAuthKeychain.saveData(wrapPKCS8(pkcs1: pkcs1), for: privateKeyKey(email: email))
        return key
    }

    private static func publicKeyPKCS1(_ privateKey: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CertificateError.message("Could not derive the public key.")
        }
        var error: Unmanaged<CFError>?
        guard let der = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw CertificateError.message("Could not export the public key.")
        }
        return der
    }

    /// The stored private key as PKCS#1 DER, for the .p12 export
    /// the Container uses to store its provisioned certificate
    /// (WTPKCS12Export builds the .p12 from this + the leaf DER).
    /// The key never leaves the device: it goes straight from the
    /// Keychain into the export, and the .p12 is stored in the
    /// App Group defaults the same way a manually imported one is.
    static func privateKeyPKCS1(email: String) throws -> Data {
        let privateKey = try loadOrCreatePrivateKey(email: email)
        var error: Unmanaged<CFError>?
        guard let pkcs1 = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw CertificateError.message("Could not export the private key.")
        }
        return pkcs1
    }

    // MARK: CSR

    /// isideload's `build_csr` (rcgen, PKCS_RSA_SHA256): an empty
    /// subject-alternative list and the fixed placeholder
    /// distinguished name rcgen is handed — C=US, ST=STATE,
    /// L=LOCAL, O=ORGNIZATION (sic, as in the source), CN=CN.
    /// The machine name travels in the submission body, not here.
    static func buildCSR(privateKey: SecKey) throws -> String {
        func rdn(_ oid: [UInt8], _ value: Data) -> Data {
            DER.set([DER.sequence([DER.oid(oid), value])])
        }
        let subject = DER.sequence([
            rdn(DER.oidNameComponent(6), DER.printableString("US")),
            rdn(DER.oidNameComponent(8), DER.utf8String("STATE")),
            rdn(DER.oidNameComponent(7), DER.utf8String("LOCAL")),
            rdn(DER.oidNameComponent(10), DER.utf8String("ORGNIZATION")),
            rdn(DER.oidNameComponent(3), DER.utf8String("CN")),
        ])
        let publicKeyInfo = DER.sequence([
            DER.sequence([DER.oid(DER.oidRSAEncryption), DER.null()]),
            DER.bitString(try publicKeyPKCS1(privateKey)),
        ])
        let requestInfo = DER.sequence([
            DER.integer(0),
            subject,
            publicKeyInfo,
            DER.tlv(tag: 0xa0, content: Data()), // [0] attributes: none
        ])
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey, .rsaSignatureMessagePKCS1v15SHA256, requestInfo as CFData, &error) as Data? else {
            throw CertificateError.message("Could not sign the certificate request.")
        }
        let csr = DER.sequence([
            requestInfo,
            DER.sequence([DER.oid(DER.oidSHA256WithRSAEncryption), DER.null()]),
            DER.bitString(signature),
        ])
        let base64 = csr.base64EncodedString()
        var lines: [String] = []
        var index = base64.startIndex
        while index < base64.endIndex {
            let next = base64.index(index, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[index..<next]))
            index = next
        }
        return "-----BEGIN CERTIFICATE REQUEST-----\n"
            + lines.joined(separator: "\n")
            + "\n-----END CERTIFICATE REQUEST-----\n"
    }

    // MARK: Retrieve

    private static func identity(from cert: DevelopmentCertificate, parsed: ParsedCertificate) -> CertificateIdentity {
        CertificateIdentity(
            machineId: cert.machineId ?? "",
            machineName: cert.machineName ?? machineName,
            certificateDER: cert.certContent ?? Data(),
            portalName: cert.name,
            serialNumber: cert.serialNumber ?? parsed.serialHex,
            expirationDate: parsed.notAfter,
            commonName: parsed.commonName)
    }

    /// `CertificateIdentity::find_matching`: the team's iOS
    /// certificate whose subject public key equals our key's —
    /// whatever machine name it was requested under.
    private static func findMatching(privateKey: SecKey,
                                     certs: [DevelopmentCertificate]) -> CertificateIdentity? {
        guard let ourPublicKey = try? publicKeyPKCS1(privateKey) else { return nil }
        for cert in certs {
            guard let content = cert.certContent, cert.machineId != nil,
                  let parsed = try? parseCertificate(content) else { continue }
            if parsed.publicKeyPKCS1 == ourPublicKey {
                return identity(from: cert, parsed: parsed)
            }
        }
        return nil
    }

    /// Find-only lookup for display (isideload's
    /// `retrieve_existing`): reading the identity must never mint
    /// — or, on a free account, revoke-and-replace — a certificate.
    static func retrieveExisting(dev: DeveloperSession, team: DeveloperTeam,
                                 email: String) async -> CertificateIdentity? {
        guard let privateKey = try? loadOrCreatePrivateKey(email: email),
              let certs = try? await dev.listIOSCerts(team: team),
              let identity = findMatching(privateKey: privateKey, certs: certs) else {
            return nil
        }
        ContainerAuthKeychain.saveData(identity.certificateDER, for: certificateKey(email: email))
        return identity
    }

    /// The full retrieve: find ours, or request a new certificate
    /// (isideload's `request_certificate`, minus the revoke step —
    /// if Apple answers 7460, the maximum-certificates error
    /// surfaces to the user as-is; nothing is ever revoked).
    static func retrieve(dev: DeveloperSession, team: DeveloperTeam, email: String,
                         log: @escaping (String) -> Void) async throws -> CertificateIdentity {
        let privateKey = try loadOrCreatePrivateKey(email: email)
        let certs = try await dev.listIOSCerts(team: team)
        if let identity = findMatching(privateKey: privateKey, certs: certs) {
            log("found matching certificate (\(identity.machineName))")
            ContainerAuthKeychain.saveData(identity.certificateDER, for: certificateKey(email: email))
            return identity
        }

        log("requesting a new development certificate…")
        let csr = try buildCSR(privateKey: privateKey)
        let request = try await dev.submitDevelopmentCSR(
            team: team, csrContent: csr, machineName: machineName, machineId: persistedMachineId)
        let after = try await dev.listIOSCerts(team: team)
        guard let cert = after.first(where: { $0.certificateId == request.certRequestId }),
              let content = cert.certContent else {
            throw CertificateError.message("Failed to find the certificate after submitting the CSR.")
        }
        let identity = self.identity(from: cert, parsed: try parseCertificate(content))
        ContainerAuthKeychain.saveData(identity.certificateDER, for: certificateKey(email: email))
        log("certificate obtained (\(identity.displayName))")
        return identity
    }
}
