import Foundation

// MARK: - Stored ZIP writer (shared)
//
// Minimal ZIP writer used by the Wi-Fi file sharing folder
// download and the Voice Memos batch export: STORE (no
// compression), data descriptors (flag bit 3) so file data
// streams in 64 KB chunks without a pre-pass for CRC/sizes,
// central directory at the end. One file at a time is ever
// in memory. Files >= 4 GB are refused (ZIP32 limit).
// Written for WorkTweaks — the Save Vault has its own
// private writer with the same shape; this one is shared.

final class WTStoredZipWriter {
    private let url: URL
    private var handle: FileHandle?
    private var offset: UInt64 = 0
    private var central = Data()
    private var entryCount = 0

    init(url: URL) {
        self.url = url
    }

    func open() -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let h = FileHandle(forWritingAtPath: url.path) else { return false }
        handle = h
        return true
    }

    func close(success: Bool) {
        guard let h = handle else { return }
        if success {
            let cdOffset = UInt32(offset)
            h.write(central)
            offset += UInt64(central.count)
            var eocd = Data()
            eocd += le32(0x0605_4B50)
            eocd += le16(0)
            eocd += le16(0)
            eocd += le16(UInt16(entryCount))
            eocd += le16(UInt16(entryCount))
            eocd += le32(UInt32(central.count))
            eocd += le32(cdOffset)
            eocd += le16(0)
            h.write(eocd)
        }
        try? h.close()
        handle = nil
    }

    private func dosDateTime() -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: Date()
        )
        let time = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        let date = UInt16((((c.year ?? 1980) - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        return (time, date)
    }

    private func le16(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 2)
    }

    private func le32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }

    func addDirectory(name: String) -> Bool {
        guard let h = handle else { return false }
        let (time, date) = dosDateTime()
        let nameBytes = [UInt8](name.utf8)
        let localOffset = UInt32(offset)
        var header = Data()
        header += le32(0x0403_4B50)
        header += le16(20)
        header += le16(0x0800)
        header += le16(0)
        header += le16(time)
        header += le16(date)
        header += le32(0)
        header += le32(0)
        header += le32(0)
        header += le16(UInt16(nameBytes.count))
        header += le16(0)
        header += Data(nameBytes)
        h.write(header)
        offset += UInt64(header.count)
        var cd = Data()
        cd += le32(0x0201_4B50)
        cd += le16(20)
        cd += le16(20)
        cd += le16(0x0800)
        cd += le16(0)
        cd += le16(time)
        cd += le16(date)
        cd += le32(0)
        cd += le32(0)
        cd += le32(0)
        cd += le16(UInt16(nameBytes.count))
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le32(0x10)
        cd += le32(localOffset)
        cd += Data(nameBytes)
        central += cd
        entryCount += 1
        return true
    }

    /// Add one file from disk, streaming it in 64 KB chunks.
    /// Symlinks are never followed — the caller checks first.
    func addFile(name: String, path: String) -> Bool {
        guard let h = handle else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              size < 4_294_967_295 else {
            print("[Zip] refused file >= 4 GB: \(name)")
            return false
        }
        guard let input = FileHandle(forReadingAtPath: path) else {
            print("[Zip] could not open \(name)")
            return false
        }
        defer { try? input.close() }
        let (time, date) = dosDateTime()
        let nameBytes = [UInt8](name.utf8)
        let localOffset = UInt32(offset)
        var header = Data()
        header += le32(0x0403_4B50)
        header += le16(20)
        header += le16(0x0808) // UTF-8 + data descriptor
        header += le16(0)      // method: stored
        header += le16(time)
        header += le16(date)
        header += le32(0)      // crc (in descriptor)
        header += le32(0)      // compressed size (in descriptor)
        header += le32(0)      // uncompressed size (in descriptor)
        header += le16(UInt16(nameBytes.count))
        header += le16(0)
        header += Data(nameBytes)
        h.write(header)
        offset += UInt64(header.count)

        var crcState: UInt32 = 0xFFFF_FFFF
        var written: UInt64 = 0
        while true {
            guard let chunk = try? input.read(upToCount: 65_536), !chunk.isEmpty else { break }
            crcState = chunk.withUnsafeBytes { crc32Update(crcState, $0) }
            h.write(chunk)
            written += UInt64(chunk.count)
            if chunk.count < 65_536 { break }
        }
        let crc = crcState ^ 0xFFFF_FFFF
        var descriptor = Data()
        descriptor += le32(0x0807_4B50)
        descriptor += le32(crc)
        descriptor += le32(UInt32(written))
        descriptor += le32(UInt32(written))
        h.write(descriptor)
        offset += written + UInt64(descriptor.count)

        var cd = Data()
        cd += le32(0x0201_4B50)
        cd += le16(20)
        cd += le16(20)
        cd += le16(0x0808)
        cd += le16(0)
        cd += le16(time)
        cd += le16(date)
        cd += le32(crc)
        cd += le32(UInt32(written))
        cd += le32(UInt32(written))
        cd += le16(UInt16(nameBytes.count))
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le32(0)
        cd += le32(localOffset)
        cd += Data(nameBytes)
        central += cd
        entryCount += 1
        return true
    }

    /// Add one in-memory blob (small files only — manifests,
    /// text notes). Large content goes through addFile.
    func addData(name: String, data: Data) -> Bool {
        guard let h = handle else { return false }
        guard data.count < 4_294_967_295 else { return false }
        let (time, date) = dosDateTime()
        let nameBytes = [UInt8](name.utf8)
        let localOffset = UInt32(offset)
        let crc = data.withUnsafeBytes { crc32Update(0xFFFF_FFFF, $0) } ^ 0xFFFF_FFFF
        var header = Data()
        header += le32(0x0403_4B50)
        header += le16(20)
        header += le16(0x0808)
        header += le16(0)
        header += le16(time)
        header += le16(date)
        header += le32(0)
        header += le32(0)
        header += le32(0)
        header += le16(UInt16(nameBytes.count))
        header += le16(0)
        header += Data(nameBytes)
        h.write(header)
        h.write(data)
        var descriptor = Data()
        descriptor += le32(0x0807_4B50)
        descriptor += le32(crc)
        descriptor += le32(UInt32(data.count))
        descriptor += le32(UInt32(data.count))
        h.write(descriptor)
        offset += UInt64(header.count) + UInt64(data.count) + UInt64(descriptor.count)

        var cd = Data()
        cd += le32(0x0201_4B50)
        cd += le16(20)
        cd += le16(20)
        cd += le16(0x0808)
        cd += le16(0)
        cd += le16(time)
        cd += le16(date)
        cd += le32(crc)
        cd += le32(UInt32(data.count))
        cd += le32(UInt32(data.count))
        cd += le16(UInt16(nameBytes.count))
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le16(0)
        cd += le32(0)
        cd += le32(localOffset)
        cd += Data(nameBytes)
        central += cd
        entryCount += 1
        return true
    }

    // MARK: CRC-32 (IEEE, table-driven)

    private static let crcTable: [UInt32] = {
        (0..<256).map { i in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    /// Incremental CRC-32 update. `state` is the running
    /// (unfinalized) state — start with 0xFFFF_FFFF and XOR
    /// with 0xFFFF_FFFF once at the end to finalize.
    private func crc32Update(_ state: UInt32, _ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var c = state
        for byte in bytes {
            c = Self.crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c
    }
}
