// MARK: - Airlift Passcode Themes (.passthm)
//
// Ported from adnan120hz/aircard-ios (Models.swift + AppViewModel.swift):
// PasscodeThemeReader, PasscodeThemeInfo, CreatorMode, PasscodeLanguageTarget,
// PasscodeBoldTarget, KeypadLocales, KeypadLayout, ImageEngine, the
// PhotosPickerItem loader, PasscodeThemePackager, and the flashPassthm()
// staging + exploit flow. Filename rules, language list, TelephonyUI
// target dirs and the `_big` marker are copied exactly from aircard.
//
// WorkTweaks adaptations (nothing else changed):
// - No `syncTargetHostsToRust()` — aircard-only tunnel-host sync; the
//   exploit call takes the pairing path directly.
// - VPN warning uses WorkTweaks' own VPNTunnelStatus detector.
// - Pairing file comes from PairingController.pairingFilePath() and
//   PairingStore.hasPairingFile (Sandbox -> Utilities -> Get Pairing File).
// - No respring/restart anywhere: restart is manual-guide only in WorkTweaks.
// - NOT ported: poster slicing (SliceMode, slicePoster, cropToCircle,
//   zoom/offset/drag, maskToCircles) — creator mode here is per-digit
//   photo picker only. Documents-folder theme listing is also not ported;
//   import is via the file importer only.

import Foundation
import UIKit
import CoreGraphics
import ImageIO
import PhotosUI
import CoreTransferable
import Combine
import AirliftFFI

// MARK: - Theme info

struct PasscodeThemeInfo: Identifiable {
    var id: String { filePath }
    let name: String
    let filePath: String
    let fileCount: Int
    let keysPreview: [String: UIImage]
    var rawKeyData: [String: Data] = [:]
}

enum CreatorMode: String, CaseIterable, Identifiable {
    case applyTheme = "Apply .passthm"
    case themeCreator = "Create Theme"
    var id: String { rawValue }
}

enum PasscodeLanguageTarget: String, CaseIterable, Identifiable {
    case all = "All Languages (Universal)"
    case uk = "Ukrainian (uk)"
    case ru = "Russian (ru)"
    case en = "English (en)"
    case other = "Other / Fallback"
    case es = "Spanish (es)"
    case de = "German (de)"
    case fr = "French (fr)"
    case pl = "Polish (pl)"
    case it = "Italian (it)"
    case pt = "Portuguese (pt)"
    case tr = "Turkish (tr)"
    case ja = "Japanese (ja)"
    case ko = "Korean (ko)"
    case zh = "Chinese (zh)"
    case ar = "Arabic (ar)"
    case he = "Hebrew (he)"

    var id: String { rawValue }

    var code: String {
        switch self {
        case .all: return "all"
        case .uk: return "uk"
        case .ru: return "ru"
        case .en: return "en"
        case .other: return "other"
        case .es: return "es"
        case .de: return "de"
        case .fr: return "fr"
        case .pl: return "pl"
        case .it: return "it"
        case .pt: return "pt"
        case .tr: return "tr"
        case .ja: return "ja"
        case .ko: return "ko"
        case .zh: return "zh"
        case .ar: return "ar"
        case .he: return "he"
        }
    }
}

enum PasscodeBoldTarget: String, CaseIterable, Identifiable {
    case both = "Universal (Regular + Bold)"
    case boldOnly = "Bold Text Only (Fast)"
    case regularOnly = "Regular Font Only (Fast)"

    var id: String { rawValue }

    var code: String {
        switch self {
        case .both: return "both"
        case .boldOnly: return "bold"
        case .regularOnly: return "regular"
        }
    }
}

enum KeypadLocales {
    static let all: [String] = [
        "en", "other", "ru", "uk", "es", "fr", "de", "it", "pt", "tr", "pl", "nl", "ja", "ko", "zh", "ar", "he"
    ]

    static let cyrillicRU: [String: String] = [
        "2": "А Б В Г",
        "3": "Д Е Ж З",
        "4": "И Й К Л",
        "5": "М Н О П",
        "6": "Р С Т У",
        "7": "Ф Х Ц Ч",
        "8": "Ш Щ Ъ Ы",
        "9": "Ь Э Ю Я",
    ]

    static let cyrillicUK: [String: String] = [
        "2": "А Б В Г",
        "3": "Д Е Ж З",
        "4": "І Ї Й К",
        "5": "Л М Н О",
        "6": "П Р С Т",
        "7": "У Ф Х Ц",
        "8": "Ч Ш Щ Ь",
        "9": "Ю Я",
    ]
}

// MARK: - Keypad Layout (matching AirCard exactly)

struct KeypadButtonGeometry: Identifiable {
    var id: String { digit }
    let digit: String
    let letters: String
    let row: Int
    let col: Int
}

enum KeypadLayout {
    static let buttonDiameter: CGFloat = 75.0
    static let gridWidth: CGFloat = 305.0
    static let gridHeight: CGFloat = 1148.0 / 3.0   // ≈382.67
    static let colWidth: CGFloat = 305.0 / 3.0        // ≈101.67
    static let rowHeight: CGFloat = 1148.0 / 12.0     // ≈95.67

    static let allButtons: [KeypadButtonGeometry] = [
        KeypadButtonGeometry(digit: "1", letters: "",        row: 0, col: 0),
        KeypadButtonGeometry(digit: "2", letters: "A B C",  row: 0, col: 1),
        KeypadButtonGeometry(digit: "3", letters: "D E F",  row: 0, col: 2),
        KeypadButtonGeometry(digit: "4", letters: "G H I",  row: 1, col: 0),
        KeypadButtonGeometry(digit: "5", letters: "J K L",  row: 1, col: 1),
        KeypadButtonGeometry(digit: "6", letters: "M N O",  row: 1, col: 2),
        KeypadButtonGeometry(digit: "7", letters: "P Q R S",row: 2, col: 0),
        KeypadButtonGeometry(digit: "8", letters: "T U V",  row: 2, col: 1),
        KeypadButtonGeometry(digit: "9", letters: "W X Y Z",row: 2, col: 2),
        KeypadButtonGeometry(digit: "0", letters: "+",      row: 3, col: 1),
    ]

    static let subtexts: [String: String] = [
        "0": "+",  "1": "",      "2": "A B C",  "3": "D E F",
        "4": "G H I", "5": "J K L", "6": "M N O",
        "7": "P Q R S", "8": "T U V", "9": "W X Y Z"
    ]
}

// MARK: - Safe Image Engine (iOS: ImageIO downsampling)

enum ImageEngine {

    /// Decodes image data directly at reduced dimensions using ImageIO.
    /// Never loads the full uncompressed 48MP bitmap into memory, preventing Jetsam OOM crashes.
    static func safeImageFromData(_ data: Data, maxDimension: CGFloat = 2048) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data).map { normalizeAndDownsample($0, maxDimension: maxDimension) }
        }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(data: data).map { normalizeAndDownsample($0, maxDimension: maxDimension) }
    }

    /// Normalizes image orientation and downsamples huge camera images (48MP/RAW)
    /// to avoid Jetsam OOM crashes on iOS.
    static func normalizeAndDownsample(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: max(1, floor(size.width * scale)),
                                height: max(1, floor(size.height * scale)))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

// MARK: - PasscodeThemeReader (.passthm → key images)

enum PasscodeThemeReader {

    /// Extract key-button images from a .passthm zip file.
    /// Returns a dict [digit → UIImage], raw data dict [digit → Data], and the total file count.
    static func inspect(url: URL) -> (keys: [String: UIImage], rawData: [String: Data], fileCount: Int)? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("airlift_inspect_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Extract zip via Rust al_passthm_extract (handles deflated & stored zip entries)
        let rc = url.path.withCString { arcC in
            tempDir.path.withCString { dstC in
                al_passthm_extract(arcC, dstC)
            }
        }
        guard rc == 0 else { return nil }

        let files = (FileManager.default.subpaths(atPath: tempDir.path) ?? [])
        guard !files.isEmpty else { return nil }

        var keys: [String: UIImage] = [:]
        var rawData: [String: Data] = [:]
        var fileCount = 0

        for file in files {
            guard !file.hasPrefix("."), !file.contains("__MACOSX") else { continue }
            let lower = file.lowercased()
            guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") else { continue }

            fileCount += 1
            let filename = (file as NSString).lastPathComponent
            if let digit = extractDigit(from: filename) {
                if keys[digit] == nil {
                    let filePath = tempDir.appendingPathComponent(file).path
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                        rawData[digit] = data
                        if let img = ImageEngine.safeImageFromData(data, maxDimension: 512) {
                            keys[digit] = img
                        }
                    }
                }
            }
        }

        return keys.isEmpty ? nil : (keys, rawData, fileCount)
    }

    /// Extract digit matching AirCard's regex logic for themes
    static func extractDigit(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
        let stemClean = stem
            .replacingOccurrences(of: "--white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "@3x", with: "")
            .replacingOccurrences(of: "@2x", with: "")

        // 1. AirCard pattern: (?:^[a-zA-Z]+-)?([0-9*#])(?:-([^-\n]+))?
        if let regex = try? NSRegularExpression(pattern: #"(?:^[a-zA-Z]+-)?([0-9*#])"#, options: .caseInsensitive) {
            let nsString = stemClean as NSString
            let match = regex.firstMatch(in: stemClean, range: NSRange(location: 0, length: nsString.length))
            if let match = match, match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                if range.location != NSNotFound {
                    let d = nsString.substring(with: range)
                    if "0123456789".contains(d) { return d }
                }
            }
        }

        // 2. Fallback: search for single digit in filename
        for ch in stemClean {
            if "0123456789".contains(ch) { return String(ch) }
        }
        return nil
    }
}

// MARK: - PasscodeThemePackager (native Swift zip via Foundation)

enum PasscodeThemePackager {

    /// Build a .passthm zip archive in memory and return its Data.
    static func buildPassthm(
        keys: [String: UIImage],
        telephonyVersion: String = "all",
        language: PasscodeLanguageTarget = .all,
        bold: PasscodeBoldTarget = .both
    ) throws -> Data {
        var zipData = Data()
        var centralDirectory = Data()
        var centralDirCount: UInt16 = 0

        func addEntry(name: String, content: Data) {
            guard let nameData = name.data(using: .utf8) else { return }
            let crc = crc32(content)
            let localHeader = makeLocalFileHeader(name: nameData, content: content, crc: crc)
            let offset = UInt32(zipData.count)
            zipData.append(localHeader)
            zipData.append(content)
            centralDirectory.append(
                makeCentralDirEntry(name: nameData, content: content, crc: crc, offset: offset))
            centralDirCount += 1
        }

        let targetVers: [String]
        if telephonyVersion == "all" || telephonyVersion.isEmpty {
            targetVers = ["TelephonyUI-10", "TelephonyUI-9", "TelephonyUI-8"]
        } else {
            targetVers = [telephonyVersion]
        }

        let langs: [String]
        if language == .all {
            langs = KeypadLocales.all
        } else {
            langs = language.code == "other" ? ["other"] : [language.code, "other"]
        }

        let boldSuffixes: [String]
        switch bold {
        case .both: boldSuffixes = ["", "-bold"]
        case .boldOnly: boldSuffixes = ["-bold"]
        case .regularOnly: boldSuffixes = [""]
        }

        for ver in targetVers {
            addEntry(name: "\(ver)/_big", content: Data())

            for (digit, image) in keys {
                guard let pngData = image.pngData() else { continue }
                let stdSubtext = KeypadLayout.subtexts[digit] ?? ""

                for lang in langs {
                    for bld in boldSuffixes {
                        // 1. Blank subtext
                        addEntry(name: "\(ver)/\(lang)-\(digit)---white\(bld).png", content: pngData)

                        // 2. Standard Latin subtext
                        if !stdSubtext.isEmpty {
                            addEntry(name: "\(ver)/\(lang)-\(digit)-\(stdSubtext)--white\(bld).png", content: pngData)
                            let noSpace = stdSubtext.replacingOccurrences(of: " ", with: "")
                            if noSpace != stdSubtext {
                                addEntry(name: "\(ver)/\(lang)-\(digit)-\(noSpace)--white\(bld).png", content: pngData)
                            }
                        }

                        // 3. Cyrillic subtexts
                        if (lang == "ru" || language == .all), let ruSub = KeypadLocales.cyrillicRU[digit] {
                            addEntry(name: "\(ver)/\(lang)-\(digit)-\(ruSub)--white\(bld).png", content: pngData)
                        }
                        if (lang == "uk" || language == .all), let ukSub = KeypadLocales.cyrillicUK[digit] {
                            addEntry(name: "\(ver)/\(lang)-\(digit)-\(ukSub)--white\(bld).png", content: pngData)
                        }
                    }
                }
            }
        }

        // End of central directory record
        let cdOffset = UInt32(zipData.count)
        let cdSize   = UInt32(centralDirectory.count)
        zipData.append(centralDirectory)
        zipData.append(makeEndRecord(count: centralDirCount, size: cdSize, offset: cdOffset))
        return zipData
    }

    static func buildPassthm(keys: [String: UIImage]) throws -> Data {
        try buildPassthm(keys: keys, telephonyVersion: "all", language: .all, bold: .both)
    }

    // MARK: - Zip primitives

    private static func makeLocalFileHeader(name: Data, content: Data, crc: UInt32) -> Data {
        var d = Data()
        d.appendLE32(0x04034b50)   // Local file header signature
        d.appendLE16(20)           // Version needed: 2.0
        d.appendLE16(0x0800)       // Flags: UTF-8 file names (bit 11)
        d.appendLE16(0)            // Compression: stored
        d.appendLE16(0)            // Last mod time
        d.appendLE16(0)            // Last mod date
        d.appendLE32(crc)
        d.appendLE32(UInt32(content.count))   // Compressed size
        d.appendLE32(UInt32(content.count))   // Uncompressed size
        d.appendLE16(UInt16(name.count))
        d.appendLE16(0)            // Extra field length
        d.append(name)
        return d
    }

    private static func makeCentralDirEntry(
        name: Data, content: Data, crc: UInt32, offset: UInt32
    ) -> Data {
        var d = Data()
        d.appendLE32(0x02014b50)   // Central dir file header signature
        d.appendLE16(20)           // Version made by
        d.appendLE16(20)           // Version needed
        d.appendLE16(0x0800)       // Flags: UTF-8 file names (bit 11)
        d.appendLE16(0)            // Compression: stored
        d.appendLE16(0)            // Last mod time
        d.appendLE16(0)            // Last mod date
        d.appendLE32(crc)
        d.appendLE32(UInt32(content.count))
        d.appendLE32(UInt32(content.count))
        d.appendLE16(UInt16(name.count))
        d.appendLE16(0)            // Extra field length
        d.appendLE16(0)            // File comment length
        d.appendLE16(0)            // Disk number start
        d.appendLE16(0)            // Internal file attributes
        d.appendLE32(0)            // External file attributes
        d.appendLE32(offset)       // Relative offset of local header
        d.append(name)
        return d
    }

    private static func makeEndRecord(count: UInt16, size: UInt32, offset: UInt32) -> Data {
        var d = Data()
        d.appendLE32(0x06054b50)   // End of central directory signature
        d.appendLE16(0)            // Disk number
        d.appendLE16(0)            // Disk with start of central directory
        d.appendLE16(count)
        d.appendLE16(count)
        d.appendLE32(size)
        d.appendLE32(offset)
        d.appendLE16(0)            // Comment length
        return d
    }

    /// CRC-32 (ISO 3309 / ITU-T V.42).
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var b = UInt32(byte)
            for _ in 0..<8 {
                let mixed = (crc ^ b) & 1
                crc >>= 1
                if mixed != 0 { crc ^= 0xEDB8_8320 }
                b >>= 1
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE16(_ v: UInt16) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
    mutating func appendLE32(_ v: UInt32) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
}

// MARK: - Flash phase

enum PasscodeFlashPhase: Equatable {
    case idle, running, done(ok: Bool)
}

// MARK: - Airlift Passcode Engine

/// Holds the loaded .passthm theme / creator keys and runs the flash.
/// Mirrors aircard's AppViewModel passthm flow; the shared instance is used
/// by the view so the Rust log callback (a C function pointer, which cannot
/// capture locals) can reach the log through the static shared reference.
@MainActor
final class AirliftPasscodeEngine: ObservableObject {
    static let shared = AirliftPasscodeEngine()

    @Published var passcodeMode: CreatorMode = .applyTheme
    @Published var loadedTheme: PasscodeThemeInfo? = nil
    @Published var customKeys: [String: UIImage] = [:]

    @Published var targetTelephonyVersion: String = "TelephonyUI-10"
    @Published var passcodeLanguageTarget: PasscodeLanguageTarget = AirliftPasscodeEngine.detectedDeviceLanguage
    @Published var passcodeBoldTarget: PasscodeBoldTarget = .both

    @Published var flashPhase: PasscodeFlashPhase = .idle
    @Published var flashProgress: Double = 0
    @Published var flashLog: [String] = []

    @Published var errorMessage: String? = nil
    @Published var showSuccessAlert: Bool = false
    @Published var successAlertMessage: String = ""
    @Published var exportedThemeURL: URL? = nil

    /// C-callback entry point (nonisolated): appends a flash log line.
    /// Mirrors AirliftWalletEngine.appendFlashLog in this project.
    nonisolated static func appendFlashLog(_ line: String) {
        Task { @MainActor in
            shared.flashLog.append(line)
        }
    }

    static var detectedDeviceLanguage: PasscodeLanguageTarget {
        let code = Locale.preferredLanguages.first?.components(separatedBy: "-").first?.lowercased() ?? "en"
        for target in PasscodeLanguageTarget.allCases {
            if target.code == code {
                return target
            }
        }
        return .en
    }

    /// True when a pairing file is saved in the app.
    var hasPairingFile: Bool {
        PairingStore.hasPairingFile
    }

    /// Keys to flash: creator mode uses the per-digit custom keys;
    /// apply mode uses the loaded theme's preview keys.
    var effectiveKeys: [String: UIImage] {
        switch passcodeMode {
        case .themeCreator:
            return customKeys
        case .applyTheme:
            return loadedTheme?.keysPreview ?? [:]
        }
    }

    var canFlashPassthm: Bool {
        guard hasPairingFile && flashPhase != .running else { return false }
        switch passcodeMode {
        case .applyTheme:
            return loadedTheme != nil && !(loadedTheme?.keysPreview.isEmpty ?? true)
        case .themeCreator:
            return !effectiveKeys.isEmpty
        }
    }

    // MARK: - Passthm Load

    func loadPassthm(url: URL) {
        Task.detached {
            let result = PasscodeThemeReader.inspect(url: url)
            await MainActor.run {
                if let (keys, rawData, count) = result {
                    self.loadedTheme = PasscodeThemeInfo(
                        name: url.deletingPathExtension().lastPathComponent,
                        filePath: url.path,
                        fileCount: count,
                        keysPreview: keys,
                        rawKeyData: rawData
                    )
                } else {
                    self.errorMessage = "Failed to read .passthm — invalid or unsupported format."
                }
            }
        }
    }

    func clearLoadedTheme() {
        loadedTheme = nil
        exportedThemeURL = nil
        flashPhase = .idle
        flashProgress = 0
        flashLog.removeAll()
    }

    // MARK: - Creator keys

    func setIndividualKey(digit: String, image: UIImage) {
        customKeys[digit] = image
        exportedThemeURL = nil
    }

    func clearIndividualKey(digit: String) {
        customKeys.removeValue(forKey: digit)
        exportedThemeURL = nil
    }

    func clearAllCreator() {
        customKeys.removeAll()
        exportedThemeURL = nil
        flashPhase = .idle
        flashProgress = 0
        flashLog.removeAll()
    }

    /// Copy the loaded theme's keys into the creator so the user can edit them.
    func adoptThemeIntoCreator() {
        guard let theme = loadedTheme else { return }
        for (digit, img) in theme.keysPreview {
            customKeys[digit] = img
        }
        exportedThemeURL = nil
        passcodeMode = .themeCreator
    }

    // MARK: - Passthm Flash

    func flashPassthm() {
        guard canFlashPassthm else { return }

        let isCreator = (passcodeMode == .themeCreator)
        let keys: [String: UIImage]
        let rawKeys: [String: Data]

        if isCreator {
            keys = effectiveKeys
            rawKeys = [:] // CRITICAL: Never use rawKeyData from previously loaded zip in creator mode!
        } else if let theme = loadedTheme {
            keys = theme.keysPreview
            rawKeys = theme.rawKeyData
        } else {
            return
        }

        guard !keys.isEmpty else {
            errorMessage = "No key images loaded."
            return
        }

        flashPhase = .running
        flashProgress = 0
        flashLog.removeAll()
        errorMessage = nil

        if VPNTunnelStatus.tunnelAddresses.isEmpty {
            flashLog.append("⚠️ Notice: Loopback VPN (LocalDevVPN or SideStore WireGuard) is strongly recommended for on-device operations.")
        }

        let pairingPath = PairingController.pairingFilePath()
        let targetVer = targetTelephonyVersion
        let targetLang = passcodeLanguageTarget
        let targetBold = passcodeBoldTarget
        let detected = AirliftPasscodeEngine.detectedDeviceLanguage.code

        Task.detached { [weak self] in
            guard let self = self else { return }

            let stageThemeDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("airlift_passthm_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: stageThemeDir, withIntermediateDirectories: true)

            let langs: [String]
            if targetLang == .all {
                langs = KeypadLocales.all
            } else {
                var l = [targetLang.code]
                if targetLang.code != "other" {
                    l.append("other")
                }
                if targetLang.code != detected && detected != "other" && !l.contains(detected) {
                    l.append(detected)
                }
                langs = l
            }
            let boldSuffixes: [String]
            switch targetBold {
            case .both: boldSuffixes = ["", "-bold"]
            case .boldOnly: boldSuffixes = ["-bold"]
            case .regularOnly: boldSuffixes = [""]
            }

            // Stage keypad images with all configured language & weight variants
            for (digit, image) in keys {
                let imgData: Data
                if let raw = rawKeys[digit] {
                    imgData = raw
                } else if let png = image.pngData() {
                    imgData = png
                } else {
                    continue
                }
                let stdSubtext = KeypadLayout.subtexts[digit] ?? ""

                for lang in langs {
                    for bld in boldSuffixes {
                        if digit == "0" {
                            // Blank variant: lang-0---white[-bold].png
                            try? imgData.write(to: stageThemeDir.appendingPathComponent("\(lang)-0---white\(bld).png"))
                            // Plus variant: lang-0-+--white[-bold].png
                            try? imgData.write(to: stageThemeDir.appendingPathComponent("\(lang)-0-+--white\(bld).png"))
                        } else if digit == "1" {
                            // Blank variant: lang-1---white[-bold].png
                            try? imgData.write(to: stageThemeDir.appendingPathComponent("\(lang)-1---white\(bld).png"))
                        } else {
                            // 1. Blank subtext
                            try? imgData.write(to: stageThemeDir.appendingPathComponent("\(lang)-\(digit)---white\(bld).png"))

                            // 2. Standard Latin subtext
                            if !stdSubtext.isEmpty {
                                try? imgData.write(to: stageThemeDir.appendingPathComponent("\(lang)-\(digit)-\(stdSubtext)--white\(bld).png"))
                                let noSpace = stdSubtext.replacingOccurrences(of: " ", with: "")
                                if noSpace != stdSubtext {
                                    try? imgData.write(to: stageThemeDir.appendingPathComponent("\(lang)-\(digit)-\(noSpace)--white\(bld).png"))
                                }
                            }

                            // 3. Cyrillic subtexts
                            if (lang == "ru" || targetLang == .all), let ruSub = KeypadLocales.cyrillicRU[digit] {
                                try? imgData.write(to: stageThemeDir.appendingPathComponent("\(lang)-\(digit)-\(ruSub)--white\(bld).png"))
                            }
                            if (lang == "uk" || targetLang == .all), let ukSub = KeypadLocales.cyrillicUK[digit] {
                                try? imgData.write(to: stageThemeDir.appendingPathComponent("\(lang)-\(digit)-\(ukSub)--white\(bld).png"))
                            }
                        }
                    }
                }
            }

            // iOS TelephonyUI @3x high-res indicator marker
            try? Data().write(to: stageThemeDir.appendingPathComponent("_big"))

            await MainActor.run {
                self.flashLog.append("⚡ Staged theme assets (\(targetVer) · \(langs.joined(separator: ", ").uppercased()) · \(targetBold.code)). Injecting into iOS caches…")
                self.flashProgress = 0.2
            }

            let targetDirs: [String]
            if targetVer == "all" {
                targetDirs = [
                    "/var/mobile/Library/Caches/TelephonyUI-10",
                    "/var/mobile/Library/Caches/TelephonyUI-9",
                    "/var/mobile/Library/Caches/TelephonyUI-8"
                ]
            } else {
                targetDirs = [
                    "/var/mobile/Library/Caches/\(targetVer)"
                ]
            }

            var allOk = true
            var lastErr: String? = nil

            for (idx, targetPath) in targetDirs.enumerated() {
                let targetName = (targetPath as NSString).lastPathComponent
                await MainActor.run {
                    self.flashLog.append("  Writing to \(targetName)…")
                }

                var stepOk = false
                await withCheckedContinuation { cont in
                    DispatchQueue.global(qos: .userInitiated).async {
                        var outError: UnsafeMutablePointer<CChar>? = nil
                        let rc = pairingPath.withCString { pairC in
                            stageThemeDir.path.withCString { srcC in
                                targetPath.withCString { tgtC in
                                    al_exploit_write_dir(pairC, srcC, tgtC, { _, msg in
                                        guard let msg = msg else { return }
                                        let line = String(cString: msg)
                                        AirliftPasscodeEngine.appendFlashLog("    " + line)
                                    }, nil, &outError)
                                }
                            }
                        }
                        if let p = outError {
                            lastErr = String(validatingUTF8: p)
                            al_string_free(p)
                        }
                        stepOk = (rc == 0)
                        cont.resume()
                    }
                }

                if !stepOk {
                    allOk = false
                    await MainActor.run {
                        self.flashLog.append("  ⚠️ Write to \(targetName) failed: \(lastErr ?? "error")")
                    }
                } else {
                    await MainActor.run {
                        self.flashLog.append("  ✅ Injected into \(targetName)")
                    }
                }

                await MainActor.run {
                    self.flashProgress = 0.2 + Double(idx + 1) * 0.25
                }
            }

            try? FileManager.default.removeItem(at: stageThemeDir)

            await MainActor.run {
                if allOk {
                    self.flashProgress = 1.0
                    self.flashPhase = .done(ok: true)
                    self.flashLog.append("🎉 Passcode theme applied! Lock your iPhone to see it.")
                    self.successAlertMessage = "Passcode theme successfully applied!\n\nLock your iPhone to see your new passcode keypad. If it does not show, restart your iPhone manually (Volume Up, Volume Down, then hold the Side button)."
                    self.showSuccessAlert = true
                } else {
                    self.flashPhase = .done(ok: false)
                    self.flashLog.append("❌ One or more theme injections failed.")
                }
            }
        }
    }

    // MARK: - Export .passthm

    /// Build a .passthm zip from the creator keys and return its file URL.
    func exportPassthm() -> URL? {
        let keys = effectiveKeys
        guard !keys.isEmpty else {
            errorMessage = "Please configure at least one key before exporting."
            return nil
        }
        do {
            let zipData = try PasscodeThemePackager.buildPassthm(
                keys: keys,
                telephonyVersion: targetTelephonyVersion,
                language: passcodeLanguageTarget,
                bold: passcodeBoldTarget
            )
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("WorkTweaks_Custom_\(Int(Date().timeIntervalSince1970)).passthm")
            try zipData.write(to: tempURL)
            self.exportedThemeURL = tempURL
            return tempURL
        } catch {
            errorMessage = "Failed to export theme: \(error.localizedDescription)"
            return nil
        }
    }
}
