import Security
import Foundation

// MARK: - Container Apple ID auth: SRP-6a client
//
// Ported from Signed Apps (pinned 61d013e8). SRP-6a matching
// Apple's corecrypto `ccsrp` as configured by AltSign: group =
// RFC 5054 2048-bit, hash = SHA-256, option SRP6a_HASH
// (k = H(N|PAD(g)), u = H(PAD(A)|PAD(B)), K = H(PAD(S))),
// and `noUsernameInX` set — so x = H(salt | H(":" |
// passwordKey)), the username is skipped inside x but the ":"
// is still hashed, and H(username) still appears in M1. Every
// formula below is a direct port of ccsrp_generate_x / _M /
// _H_AMK / _K_from_S.

final class SRPClient {
    static let primeHex = "AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050A37329CBB4A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50E8083969EDB767B0CF6095179A163AB3661A05FBD5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF747359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A436C6481F1D2B9078717461A5B9D32E688F87748544523B524B0D57D5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6AF874E7303CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB694B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F9E4AFF73"

    static var N: BigInt { BigInt(data: Data(hexString: primeHex)) }
    static let g = BigInt(2)
    static let byteCount = 256

    private let a: BigInt
    let publicA: BigInt
    private(set) var sessionKey: Data? // K
    private var expectedHAMK: Data?

    init() {
        var random = Data(count: 256)
        let status = random.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 256, $0.baseAddress!) }
        precondition(status == errSecSuccess)
        let n = SRPClient.N
        a = BigInt(data: random).mod(n - BigInt(1)) + BigInt(1)
        publicA = BigInt.modPow(SRPClient.g, a, n)
    }

    var publicAData: Data { publicA.data(paddedTo: SRPClient.byteCount) }

    /// Runs the client side of the challenge; returns M1 (32 bytes).
    func processChallenge(username: String, passwordKey: Data, salt: Data, serverBData: Data) -> Data? {
        let n = SRPClient.N
        let B = BigInt(data: serverBData)
        guard !B.mod(n).isZero else { return nil }

        let padA = publicAData
        let padB = B.data(paddedTo: SRPClient.byteCount)

        let u = BigInt(data: ContainerAuthCrypto.sha256(padA + padB))
        guard !u.mod(n).isZero else { return nil }

        // x = H(salt | H(":" | passwordKey))   (noUsernameInX)
        let innerHash = ContainerAuthCrypto.sha256(Data(":".utf8) + passwordKey)
        let x = BigInt(data: ContainerAuthCrypto.sha256(salt + innerHash))

        // k = H(PAD(N) | PAD(g))
        let k = BigInt(data: ContainerAuthCrypto.sha256(n.data(paddedTo: SRPClient.byteCount) + SRPClient.g.data(paddedTo: SRPClient.byteCount)))

        // S = (B - k * g^x) ^ (a + u*x) mod N
        let gx = BigInt.modPow(SRPClient.g, x, n)
        let kgx = BigInt.modMul(k, gx, n)
        let base = BigInt.modSub(B.mod(n), kgx, n)
        let exponent = a + u * x
        let S = BigInt.modPow(base, exponent, n)

        // K = H(PAD(S))
        let K = ContainerAuthCrypto.sha256(S.data(paddedTo: SRPClient.byteCount))
        sessionKey = K

        // M1 = H( (H(PAD(N)) XOR H(PAD(g))) | H(username) | salt | PAD(A) | PAD(B) | K )
        let hashN = ContainerAuthCrypto.sha256(n.data(paddedTo: SRPClient.byteCount))
        let hashG = ContainerAuthCrypto.sha256(SRPClient.g.data(paddedTo: SRPClient.byteCount))
        var xor = Data(count: 32)
        for i in 0..<32 { xor[i] = hashN[i] ^ hashG[i] }
        let m1 = ContainerAuthCrypto.sha256(xor + ContainerAuthCrypto.sha256(Data(username.utf8)) + salt + padA + padB + K)

        // HAMK = H( PAD(A) | M1 | K )
        expectedHAMK = ContainerAuthCrypto.sha256(padA + m1 + K)
        return m1
    }

    func verifySession(m2: Data) -> Bool {
        expectedHAMK != nil && expectedHAMK == m2
    }

    /// ALTCreateSessionKey: HMAC-SHA256(key: K, message: name).
    func derivedKey(named name: String) -> Data? {
        guard let sessionKey else { return nil }
        return ContainerAuthCrypto.hmacSHA256(key: sessionKey, message: Data(name.utf8))
    }
}

extension Data {
    init(hexString: String) {
        var data = Data()
        data.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            data.append(UInt8(hexString[index..<next], radix: 16) ?? 0)
            index = next
        }
        self = data
    }
}
