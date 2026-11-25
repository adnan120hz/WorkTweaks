import CryptoKit
import Foundation

// MARK: - Container Apple ID auth: crypto primitives
//
// Ported from Signed Apps (adnan120hz/iloader-instal, pinned
// commit 61d013e8 — Stage 2/3 system, FROZEN there; this copy
// lives in WorkTweaks so the Container can sign in and provision
// without touching Signed Apps). The primitives are AltSign's
// (CommonCrypto + AES-GCM from CryptoKit), unchanged.
//
// isideload (Nicholas Sharp) is MIT; SideInstaller's sign-in /
// provisioning system (FrizzleM) is a CUSTOM license — the
// attribution row "SideInstaller by FrizzleM" is in LicenseView.

/// Thin wrappers over CommonCrypto (plus AES-GCM from CryptoKit),
/// mirroring the primitives AltSign takes from corecrypto.
enum ContainerAuthCrypto {
    static func sha256(_ data: Data) -> Data {
        var out = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                _ = CC_SHA256(inPtr.baseAddress, CC_LONG(data.count), outPtr.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return out
    }

    static func hmacSHA256(key: Data, message: Data) -> Data {
        var out = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        out.withUnsafeMutableBytes { outPtr in
            key.withUnsafeBytes { keyPtr in
                message.withUnsafeBytes { msgPtr in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyPtr.baseAddress, key.count,
                           msgPtr.baseAddress, message.count, outPtr.baseAddress)
                }
            }
        }
        return out
    }

    /// PBKDF2-HMAC-SHA256 with a fixed 32-byte output (ccpbkdf2_hmac).
    static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int) -> Data? {
        var out = Data(count: 32)
        let status = out.withUnsafeMutableBytes { outPtr in
            password.withUnsafeBytes { pwPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.bindMemory(to: CChar.self).baseAddress, password.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outPtr.bindMemory(to: UInt8.self).baseAddress, 32)
                }
            }
        }
        return status == kCCSuccess ? out : nil
    }

    /// AES-256-CBC decrypt with PKCS7 padding (ccaes_cbc + ccpad_pkcs7).
    static func aesCBCDecrypt(key: Data, iv: Data, data: Data) -> Data? {
        let outCapacity = data.count + kCCBlockSizeAES128
        var out = Data(count: outCapacity)
        var outLength = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    data.withUnsafeBytes { inPtr in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress, key.count, ivPtr.baseAddress,
                                inPtr.baseAddress, data.count,
                                outPtr.baseAddress, outCapacity, &outLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.count = outLength
        return out
    }

    /// AES-256-GCM open (used for the apptokens "et" blob):
    /// layout = "XYZ" | 16-byte nonce | ciphertext | 16-byte tag,
    /// with the 3 version bytes as additional authenticated data —
    /// exactly AltSign's ALTDecryptDataGCM.
    static func aesGCMDecryptAppToken(key: Data, blob: Data) -> Data? {
        guard blob.count >= 35 else { return nil }
        let bytes = [UInt8](blob)
        guard Array(bytes[0..<3]) == [UInt8]("XYZ".utf8) else { return nil }
        let nonceData = Data(bytes[3..<19])
        let ciphertext = Data(bytes[19..<(bytes.count - 16)])
        let tag = Data(bytes[(bytes.count - 16)...])
        guard let nonce = try? AES.GCM.Nonce(data: nonceData) else { return nil }
        let key256 = SymmetricKey(data: key)
        guard let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag) else { return nil }
        return try? AES.GCM.open(box, using: key256, authenticating: Data("XYZ".utf8))
    }
}
