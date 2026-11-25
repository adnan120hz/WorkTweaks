import Foundation

// MARK: - Container Apple ID auth: big integers
//
// Ported verbatim from Signed Apps (pinned 61d013e8) — the
// minimal big-unsigned-integer the SRP client needs. Limbs are
// little-endian UInt32, always normalized (no leading zero
// limbs; zero is a single zero limb). Division is Knuth's
// Algorithm D — the exact algorithm was fuzz-verified against a
// reference implementation before being ported here.

/// Minimal big-unsigned-integer used by the SRP client.
struct BigInt: Comparable {
    private(set) var limbs: [UInt32]

    init() { limbs = [0] }
    init(_ value: UInt32) { limbs = [value]; normalize() }
    init(limbs: [UInt32]) { self.limbs = limbs.isEmpty ? [0] : limbs; normalize() }

    /// Import big-endian bytes.
    init(data: Data) {
        var out: [UInt32] = []
        var acc: UInt32 = 0
        var bits = 0
        for byte in data.reversed() {
            acc |= UInt32(byte) << bits
            bits += 8
            if bits == 32 {
                out.append(acc)
                acc = 0
                bits = 0
            }
        }
        if bits > 0 { out.append(acc) }
        limbs = out.isEmpty ? [0] : out
        normalize()
    }

    /// Export big-endian, left-padded with zeros to `length` bytes.
    func data(paddedTo length: Int) -> Data {
        var bytes: [UInt8] = []
        for limb in limbs {
            bytes.append(UInt8(limb & 0xFF))
            bytes.append(UInt8((limb >> 8) & 0xFF))
            bytes.append(UInt8((limb >> 16) & 0xFF))
            bytes.append(UInt8((limb >> 24) & 0xFF))
        }
        while bytes.count > 1, bytes.last == 0 { bytes.removeLast() }
        if bytes == [0] { bytes = [] }
        var bigEndian = [UInt8](repeating: 0, count: max(0, length - bytes.count))
        bigEndian.append(contentsOf: bytes.reversed())
        return Data(bigEndian)
    }

    var isZero: Bool { limbs.allSatisfy { $0 == 0 } }
    var bitLength: Int {
        guard let top = limbs.last, top != 0 else { return 0 }
        return (limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }
    func bit(_ i: Int) -> Bool {
        let limb = i / 32
        guard limb < limbs.count else { return false }
        return (limbs[limb] >> (i % 32)) & 1 == 1
    }

    private mutating func normalize() {
        while limbs.count > 1, limbs.last == 0 { limbs.removeLast() }
    }

    static func < (a: BigInt, b: BigInt) -> Bool {
        if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
        for i in stride(from: a.limbs.count - 1, through: 0, by: -1) {
            if a.limbs[i] != b.limbs[i] { return a.limbs[i] < b.limbs[i] }
        }
        return false
    }
    static func == (a: BigInt, b: BigInt) -> Bool { a.limbs == b.limbs }

    static func + (a: BigInt, b: BigInt) -> BigInt {
        var out: [UInt32] = []
        var carry: UInt64 = 0
        for i in 0..<max(a.limbs.count, b.limbs.count) {
            let x = i < a.limbs.count ? UInt64(a.limbs[i]) : 0
            let y = i < b.limbs.count ? UInt64(b.limbs[i]) : 0
            let s = x + y + carry
            out.append(UInt32(s & 0xFFFF_FFFF))
            carry = s >> 32
        }
        if carry > 0 { out.append(UInt32(carry)) }
        return BigInt(limbs: out)
    }

    /// Requires a >= b.
    static func - (a: BigInt, b: BigInt) -> BigInt {
        var out: [UInt32] = []
        var borrow: Int64 = 0
        for i in 0..<a.limbs.count {
            let x = Int64(a.limbs[i])
            let y = i < b.limbs.count ? Int64(b.limbs[i]) : 0
            var d = x - y - borrow
            if d < 0 { d += 1 << 32; borrow = 1 } else { borrow = 0 }
            out.append(UInt32(d))
        }
        return BigInt(limbs: out)
    }

    static func * (a: BigInt, b: BigInt) -> BigInt {
        if a.isZero || b.isZero { return BigInt() }
        var out = [UInt32](repeating: 0, count: a.limbs.count + b.limbs.count)
        for i in 0..<a.limbs.count {
            var carry: UInt64 = 0
            for j in 0..<b.limbs.count {
                let idx = i + j
                let t = UInt64(a.limbs[i]) * UInt64(b.limbs[j]) + UInt64(out[idx]) + carry
                out[idx] = UInt32(t & 0xFFFF_FFFF)
                carry = t >> 32
            }
            var idx = i + b.limbs.count
            while carry > 0 {
                let t = UInt64(out[idx]) + carry
                out[idx] = UInt32(t & 0xFFFF_FFFF)
                carry = t >> 32
                idx += 1
            }
        }
        return BigInt(limbs: out)
    }

    private static func shiftedLeftBits(_ a: [UInt32], _ s: Int) -> [UInt32] {
        if s == 0 { return a }
        var out: [UInt32] = []
        var carry: UInt32 = 0
        for x in a {
            out.append((x << s) | carry)
            carry = x >> (32 - s)
        }
        if carry > 0 { out.append(carry) }
        return out
    }
    private static func shiftedRightBits(_ a: [UInt32], _ s: Int) -> [UInt32] {
        if s == 0 { return a }
        var out = [UInt32](repeating: 0, count: a.count)
        var carry: UInt32 = 0
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            out[i] = (a[i] >> s) | carry
            carry = a[i] << (32 - s)
        }
        return out
    }

    /// Knuth Algorithm D. Returns (quotient, remainder).
    static func divmod(_ uIn: BigInt, _ vIn: BigInt) -> (BigInt, BigInt) {
        precondition(!vIn.isZero, "division by zero")
        let u = uIn.limbs
        let v = vIn.limbs
        if uIn < vIn { return (BigInt(), uIn) }
        if v.count == 1 {
            let d = UInt64(v[0])
            var q = [UInt32](repeating: 0, count: u.count)
            var rem: UInt64 = 0
            for i in stride(from: u.count - 1, through: 0, by: -1) {
                let cur = (rem << 32) | UInt64(u[i])
                q[i] = UInt32(cur / d)
                rem = cur % d
            }
            return (BigInt(limbs: q), BigInt(UInt32(rem)))
        }
        let n = v.count
        let m = u.count - n
        let shift = v[n - 1].leadingZeroBitCount
        let vn = shiftedLeftBits(v, shift)
        var un = shiftedLeftBits(u, shift)
        while un.count < u.count + 1 { un.append(0) }
        var q = [UInt32](repeating: 0, count: m + 1)
        let b: UInt64 = 1 << 32
        for j in stride(from: m, through: 0, by: -1) {
            let num = (UInt64(un[j + n]) << 32) | UInt64(un[j + n - 1])
            var qhat = num / UInt64(vn[n - 1])
            var rhat = num % UInt64(vn[n - 1])
            while true {
                if qhat >= b || qhat * UInt64(vn[n - 2]) > ((rhat << 32) | UInt64(un[j + n - 2])) {
                    qhat -= 1
                    rhat += UInt64(vn[n - 1])
                    if rhat < b { continue }
                }
                break
            }
            // Multiply and subtract
            var borrow: Int64 = 0
            var carry: UInt64 = 0
            for i in 0..<n {
                let p = qhat * UInt64(vn[i]) + carry
                carry = p >> 32
                let pLow = p & 0xFFFF_FFFF
                var sub = Int64(un[i + j]) - borrow - Int64(pLow)
                if sub < 0 { sub += 1 << 32; borrow = 1 } else { borrow = 0 }
                un[i + j] = UInt32(sub)
            }
            let topSub = Int64(un[j + n]) - borrow - Int64(carry)
            un[j + n] = UInt32(topSub & 0xFFFF_FFFF)
            if topSub < 0 {
                // Add back
                qhat -= 1
                var c: UInt64 = 0
                for i in 0..<n {
                    let s = UInt64(un[i + j]) + UInt64(vn[i]) + c
                    un[i + j] = UInt32(s & 0xFFFF_FFFF)
                    c = s >> 32
                }
                un[j + n] = UInt32((UInt64(un[j + n]) + c) & 0xFFFF_FFFF)
            }
            q[j] = UInt32(qhat)
        }
        let r = shiftedRightBits(un, shift)
        return (BigInt(limbs: q), BigInt(limbs: r))
    }

    func mod(_ m: BigInt) -> BigInt { BigInt.divmod(self, m).1 }

    static func modPow(_ base: BigInt, _ exp: BigInt, _ mod: BigInt) -> BigInt {
        if mod == BigInt(1) { return BigInt() }
        var result = BigInt(1)
        var b = base.mod(mod)
        let bits = exp.bitLength
        for i in 0..<bits {
            if exp.bit(i) {
                result = (result * b).mod(mod)
            }
            if i + 1 < bits {
                b = (b * b).mod(mod)
            }
        }
        return result
    }

    /// (a * b) mod m
    static func modMul(_ a: BigInt, _ b: BigInt, _ m: BigInt) -> BigInt { (a * b).mod(m) }
    /// (a - b) mod m, for a, b already < m (result in [0, m)).
    static func modSub(_ a: BigInt, _ b: BigInt, _ m: BigInt) -> BigInt {
        if a >= b { return a - b }
        return m - (b - a)
    }
}
