// MARK: - Airlift Wallet Cards
//
// Ported from adnan120hz/aircard-ios (WalletScanParser.swift,
// AppViewModel.swift wallet section, Models.swift ImageEngine).
// Custom Apple Wallet card art ("skins"): scan for card IDs in the
// device syslog, attach a skin image per card, and flash the skins
// into the card's .pkpass folder on-device via the Airlift exploit.
//
// Exact aircard behaviour kept:
//  * WalletScanParser regexes + placeholder IDs, verbatim.
//  * Card art is a 1536x969 PNG; flash writes the full skin set
//    (see WalletImageEngine.prepareAllCardSkins) into
//    /var/mobile/Library/Passes/Cards/<cardId>.pkpass, then
//    invalidates the .cache / .pkcache leaves.
//  * Skins are stored in Documents/WalletCards/card_<safeId>.png;
//    card IDs + names + networks persist in UserDefaults under the
//    aircard keys, so a card list survives reinstalls of either app.
//  * Apple Card uses dynamic Metal GPU rendering and cannot take
//    static art (see the note in AirliftWalletView).
//
// Flash and live scanning both need the pairing file (Sandbox ->
// Utilities -> Get Pairing File). Nothing is faked: without a
// pairing file the engine refuses to scan or flash.

import Foundation
import Combine
import UIKit
import ImageIO
import AirliftFFI

// MARK: - Payment network (verbatim port of aircard WalletScanParser.swift)

public enum PaymentNetwork: String, CaseIterable, Codable {
    case visa = "Visa"
    case mastercard = "Mastercard"
    case amex = "American Express"
    case unionPay = "UnionPay"
    case discover = "Discover"
    case jcb = "JCB"
    case appleCard = "Apple Card"
    case transit = "Transit Card"
    case unknown = "Payment Card"

    public var iconName: String {
        switch self {
        case .visa: return "creditcard.fill"
        case .mastercard: return "creditcard.fill"
        case .amex: return "creditcard.fill"
        case .unionPay: return "creditcard.fill"
        case .discover: return "creditcard.fill"
        case .jcb: return "creditcard.fill"
        case .appleCard: return "apple.logo"
        case .transit: return "tram.fill"
        case .unknown: return "creditcard"
        }
    }

    public var displayName: String { rawValue }

    public static func from(activationID: String) -> PaymentNetwork {
        let upper = activationID.uppercased()
        if upper.hasPrefix("A000000003") { return .visa }
        if upper.hasPrefix("A000000004") { return .mastercard }
        if upper.hasPrefix("A000000025") { return .amex }
        if upper.hasPrefix("A000000333") { return .unionPay }
        if upper.hasPrefix("A000000152") { return .discover }
        if upper.hasPrefix("A000000065") { return .jcb }
        return .unknown
    }

    public static func fromAID(_ aid: String) -> PaymentNetwork? {
        let net = from(activationID: aid)
        return net == .unknown ? nil : net
    }
}

public struct ActivationMatch: Equatable {
    public let aid: String
    public let network: PaymentNetwork?
    public let id: String?

    public init(aid: String, network: PaymentNetwork? = nil, id: String? = nil) {
        self.aid = aid
        self.network = network ?? PaymentNetwork.fromAID(aid)
        self.id = id
    }
}

// MARK: - Wallet scan parser (verbatim port of aircard WalletScanParser.swift)

public enum WalletScanParser {
    static let cardReferences: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"/([-A-Za-z0-9_+=]{20,64})\.(?:pkpass|cache|pkcache)(?=[/\s\"'\),]|$)"#),
        try! NSRegularExpression(pattern: #"/(?:Cards|Passes/Cards)/([-A-Za-z0-9_+=]{20,64})(?=[/\s\"'\),]|$)"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"PDCardFileManager:\s*writing card\s+([-A-Za-z0-9_+=]{20,64})(?=[\s\"'\),]|$)"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"PDPassLibrary:\s*wrote pass\s+([-A-Za-z0-9_+=]{20,64})(?=[\s\"'\),]|$)"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"VerificationCheck\.([-A-Za-z0-9_+=]{20,64})(?=[\s\"'\),]|$)"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"selected pass uniqueID\s*:\s*\"?([-A-Za-z0-9_+=]{20,64})\"?"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"Dashboard loading[^:]*:\s*for\s+([-A-Za-z0-9_+=]{20,80})(?=[,\s\"'\)]|$)"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"Dashboard loading[^:]*:\s+([-A-Za-z0-9_+=]{20,80})\s+-"#, options: .caseInsensitive),
    ]

    static let inSessionList = try! NSRegularExpression(
        pattern: #"passIDs\[(?:InSession|global)\]\s*[:=]\s*(?:\{\s*)?\(([^)]*)\)"#,
        options: .caseInsensitive
    )

    static let cardID = try! NSRegularExpression(pattern: #"(?<![-A-Za-z0-9_+=])[-A-Za-z0-9_+=]{20,64}(?![-A-Za-z0-9_+=])"#)

    static let activation = try! NSRegularExpression(
        pattern: #"setActivePaymentApplet.{0,4096}?requestedApplet\s*:.{0,4096}?(?:identifier\s*=\s*|\"identifier\"\s*:\s*\")([A-Fa-f0-9]{10,64})\b"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    static let fallbackToken = try! NSRegularExpression(
        pattern: #"(?<![-A-Za-z0-9+/=])([A-Za-z0-9+/_-]{27}=)(?![-A-Za-z0-9+/=])"#
    )

    static let placeholders: Set<String> = [
        "OM6NYhwXMZrAw0sRUjR62wmF4ZQ=",
        "M6nDwZrkYbFlsodLgCbvyFZQ1cc=",
        "kJL-D0rr-SZhbj2c8nK-OQ9hCMY=",
        "hwAtAmHKYwsQrJbT5cTNDsaxVME="
    ]

    public static func cardIDs(in line: String) -> [String] {
        let lineRange = NSRange(line.startIndex..., in: line)
        var seen = Set<String>()
        var result: [String] = []

        func add(_ id: String) {
            guard !placeholders.contains(id), seen.insert(id).inserted else { return }
            result.append(id)
        }

        for pattern in cardReferences {
            for match in pattern.matches(in: line, range: lineRange) {
                guard let range = Range(match.range(at: 1), in: line) else { continue }
                add(String(line[range]))
            }
        }

        for match in inSessionList.matches(in: line, range: lineRange) {
            guard let range = Range(match.range(at: 1), in: line) else { continue }
            let sessionString = String(line[range])
            let sessionRange = NSRange(sessionString.startIndex..., in: sessionString)
            for cardMatch in cardID.matches(in: sessionString, range: sessionRange) {
                guard let cardRange = Range(cardMatch.range, in: sessionString) else { continue }
                add(String(sessionString[cardRange]))
            }
        }

        return result
    }

    public static func fallbackCardIDs(in line: String) -> [String] {
        let lineRange = NSRange(line.startIndex..., in: line)
        var seen = Set<String>()
        return fallbackToken.matches(in: line, range: lineRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: line) else { return nil }
            let id = String(line[range])
            guard !placeholders.contains(id), seen.insert(id).inserted else { return nil }
            return id
        }
    }

    public static func activationMatches(in line: String) -> [ActivationMatch] {
        var matches: [ActivationMatch] = []
        let lineRange = NSRange(line.startIndex..., in: line)

        // 1. JSON-style activation: {"aid": "...", "passId": "..."}
        let jsonPattern = try! NSRegularExpression(
            pattern: #"\"aid\"\s*:\s*\"([A-Fa-f0-9]{10,64})\"[^}]*\"passId\"\s*:\s*\"([-A-Za-z0-9_+=]{20,64})\""#,
            options: .caseInsensitive
        )
        for match in jsonPattern.matches(in: line, range: lineRange) {
            guard let r1 = Range(match.range(at: 1), in: line),
                  let r2 = Range(match.range(at: 2), in: line) else { continue }
            let aid = String(line[r1]).uppercased()
            let passId = String(line[r2])
            matches.append(ActivationMatch(aid: aid, network: PaymentNetwork.fromAID(aid), id: passId))
        }

        // 2. Stockholm / activation line with pass ID and AID:
        let passAndAidPattern = try! NSRegularExpression(
            pattern: #"(?:activating payment pass ID|pass ID)\s*:\s*([-A-Za-z0-9_+=]{20,64}).*?AID\s*:\s*([A-Fa-f0-9]{10,64})"#,
            options: .caseInsensitive
        )
        for match in passAndAidPattern.matches(in: line, range: lineRange) {
            guard let r1 = Range(match.range(at: 1), in: line),
                  let r2 = Range(match.range(at: 2), in: line) else { continue }
            let passId = String(line[r1])
            let aid = String(line[r2]).uppercased()
            matches.append(ActivationMatch(aid: aid, network: PaymentNetwork.fromAID(aid), id: passId))
        }

        // 3. General activation applet match:
        for match in activation.matches(in: line, range: lineRange) {
            guard let range = Range(match.range(at: 1), in: line) else { continue }
            let aid = String(line[range]).uppercased()
            if !matches.contains(where: { $0.aid == aid }) {
                matches.append(ActivationMatch(aid: aid, network: PaymentNetwork.fromAID(aid), id: nil))
            }
        }

        return matches
    }

    public static func activationIDs(in line: String) -> [ActivationMatch] {
        return activationMatches(in: line)
    }

    public static func activationAIDs(in line: String) -> [String] {
        return activationMatches(in: line).map(\.aid)
    }
}

// MARK: - Wallet card model (port of aircard CardItem)

struct WalletCard: Identifiable, Equatable {
    let id: String
    var isSelected: Bool = true
    var displayName: String? = nil
    var network: PaymentNetwork? = nil
    var isVerified: Bool = true
    /// Primary skin data: 1536x969 PNG (see WalletImageEngine.prepareCardImage).
    var skinData: Data? = nil
    /// Downsampled thumbnail for display (max 512px).
    var skinImage: UIImage? = nil

    init(
        id: String,
        displayName: String? = nil,
        network: PaymentNetwork? = nil,
        isSelected: Bool = true,
        isVerified: Bool = true,
        skinData: Data? = nil,
        skinImage: UIImage? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.network = network
        self.isSelected = isSelected
        self.isVerified = isVerified
        self.skinData = skinData
        self.skinImage = skinImage
    }

    var uiImage: UIImage? {
        skinImage ?? (skinData.flatMap { UIImage(data: $0) })
    }

    var title: String {
        if let name = displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let net = network {
            return net.displayName.hasSuffix("Card") ? net.displayName : "\(net.displayName) Card"
        }
        return "Payment Card"
    }

    /// Normalizes and cleans a card identifier, stripping paths, extensions
    /// (.pkpass, .cache), quotes, and whitespace. Validates length and format.
    /// Verbatim from aircard CardItem.cleanCardId.
    static func cleanCardId(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "'\",()<>;[]{}"))
        if s.contains("/") {
            s = (s as NSString).lastPathComponent
        }
        for ext in [".pkpass", ".cache", ".pkcache"] {
            if s.hasSuffix(ext) {
                s = String(s.dropLast(ext.count))
            }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "'\",()<>;[]{}. "))
        if s.count >= 20 && s.count <= 64 && !s.contains("/") {
            if s.count == 36 && s.filter({ $0 == "-" }).count == 4 {
                return nil // UUID format, not a card hash
            }
            return s
        }
        return nil
    }

    static func == (lhs: WalletCard, rhs: WalletCard) -> Bool {
        lhs.id == rhs.id &&
        lhs.isSelected == rhs.isSelected &&
        lhs.displayName == rhs.displayName &&
        lhs.network == rhs.network &&
        lhs.isVerified == rhs.isVerified &&
        lhs.skinImage === rhs.skinImage &&
        (lhs.skinData?.count == rhs.skinData?.count)
    }
}

enum WalletFlashPhase: Equatable {
    case idle, running, done(ok: Bool)
}

// MARK: - Wallet image engine (port of aircard ImageEngine card-skin helpers)

enum WalletImageEngine {

    /// Decodes image data directly at reduced dimensions using ImageIO.
    /// Never loads the full uncompressed 48MP bitmap into memory.
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

    /// Normalizes image orientation and downsamples huge camera images.
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

    /// Resize image to a specific size (cover-fit, centered).
    static func resizeImage(_ image: UIImage, targetSize: CGSize) -> Data? {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return nil }
        let scale = max(targetSize.width / imgSize.width, targetSize.height / imgSize.height)
        let scaledSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let origin = CGPoint(x: (targetSize.width - scaledSize.width) / 2,
                             y: (targetSize.height - scaledSize.height) / 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let out = renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
        return out.pngData()
    }

    /// Resize image to exactly 1536x969 PNG — Wallet card skin preview and primary storage.
    static func prepareCardImage(from image: UIImage) -> Data? {
        let normalized = normalizeAndDownsample(image, maxDimension: 2560)
        return resizeImage(normalized, targetSize: CGSize(width: 1536, height: 969))
    }

    /// Prepares all exact resolution files for Apple Wallet pass skins.
    /// Emits cardBackgroundCombined, diffuse, background, and strip so all
    /// Apple Pay passes are covered. Verbatim from aircard.
    static func prepareAllCardSkins(from image: UIImage) -> [String: Data] {
        let normalized = normalizeAndDownsample(image, maxDimension: 2560)
        var skins: [String: Data] = [:]

        let bg3x = resizeImage(normalized, targetSize: CGSize(width: 1536, height: 969))
        let bg2x = resizeImage(normalized, targetSize: CGSize(width: 1024, height: 646))

        if let data3x = bg3x {
            skins["cardBackgroundCombined@3x.png"] = data3x
            skins["diffuse@3x.png"] = data3x
            skins["background@3x.png"] = data3x
            skins["strip@3x.png"] = data3x
        }
        if let data2x = bg2x {
            skins["cardBackgroundCombined@2x.png"] = data2x
            skins["diffuse@2x.png"] = data2x
            skins["background@2x.png"] = data2x
            skins["strip@2x.png"] = data2x
        }

        // Vector PDF variants for Suica, Pasmo, ICOCA, and transit/transport passes
        let pdfRect = CGRect(origin: .zero, size: CGSize(width: 1536, height: 969))
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pdfRect)
        let pdfData = pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            normalized.draw(in: pdfRect)
        }
        skins["cardBackgroundCombined.pdf"] = pdfData
        skins["background.pdf"] = pdfData
        skins["strip.pdf"] = pdfData

        return skins
    }
}

// MARK: - Wallet engine (port of aircard AppViewModel wallet section)

@MainActor
final class AirliftWalletEngine: ObservableObject {

    static let shared = AirliftWalletEngine()

    @Published var cards: [WalletCard] = []
    @Published var isScanningCards: Bool = false
    @Published var scanStatusText: String = ""
    @Published var flashPhase: WalletFlashPhase = .idle
    @Published var flashProgress: Double = 0
    @Published var flashLog: [String] = []

    private var lastObservedNetwork: PaymentNetwork? = nil

    /// The placeholder IDs the parser ignores (same set as WalletScanParser).
    private static let dummyCardHashes = WalletScanParser.placeholders

    /// UserDefaults keys, in first-non-empty wins order (same as aircard).
    private let storageKeys = [
        "aircard.cards",
        "aircard-ios.cards",
        "airlift.cards",
        "mak5er.savedCards",
        "LumiCards.savedCards",
        "savedCards"
    ]

    /// True when a pairing file is saved in the app.
    var hasPairingFile: Bool { PairingStore.hasPairingFile }

    /// True when the Local Dev VPN tunnel is up (utun 10.7.x.x).
    var hasVPN: Bool { VPNTunnelStatus.isTunnelUp }

    var canFlashCards: Bool {
        hasPairingFile &&
        hasVPN &&
        flashPhase != .running &&
        cards.contains { $0.isSelected && ($0.skinImage != nil || $0.skinData != nil) }
    }

    init() {
        loadSavedCards()
    }

    // MARK: - Target host (aircard syncTargetHostsToRust, simplified)

    /// Points the Rust core at the Local Dev VPN gateway (10.7.0.1, the
    /// aircard default) so the tunnel connects over the VPN interface
    /// rather than 127.0.0.1. Aircard also appends tunnel candidates from
    /// its NetworkStatus helper; WorkTweaks uses the gateway only.
    private nonisolated func syncTargetHost() {
        "10.7.0.1".withCString { _ = al_set_target_host($0) }
    }

    // MARK: - Live scanner

    func toggleCardScanning() {
        if isScanningCards {
            stopCardScanning()
        } else {
            startCardScanning()
        }
    }

    func startCardScanning() {
        guard !isScanningCards else { return }
        guard hasPairingFile else {
            scanStatusText = "Pairing file is required before scanning. Pair this iPhone first in Sandbox → Utilities → Get Pairing File."
            return
        }
        syncTargetHost()

        isScanningCards = true
        scanStatusText = "Open Apple Pay (double-click Side button) and tap your card…"

        let pairingPath = PairingController.pairingFilePath()

        let thread = Thread {
            var outError: UnsafeMutablePointer<CChar>? = nil

            let rc = pairingPath.withCString { pairC in
                al_syslog_stream_start(
                    pairC,
                    { _, line in
                        guard let line = line else { return }
                        let lineStr = String(cString: line)
                        let lower = lineStr.lowercased()
                        // Pre-filter on background thread to prevent flooding the main runloop
                        if lower.contains("pass") ||
                           lower.contains("card") ||
                           lower.contains("stockholm") ||
                           lower.contains("wallet") ||
                           lower.contains("nanopass") ||
                           lower.contains("verificationcheck") ||
                           lower.contains("nfcd") ||
                           lower.contains("dashboard") ||
                           lower.contains("activation") ||
                           lower.contains("setactivepaymentapplet") {
                            AirliftWalletEngine.handleSyslogLine(lineStr)
                        }
                    },
                    nil,
                    &outError
                )
            }

            let errStr = outError.flatMap { String(validatingUTF8: $0) }
            if let p = outError { al_string_free(p) }

            Task { @MainActor in
                AirliftWalletEngine.shared.isScanningCards = false
                if rc != 0 {
                    let msg = errStr ?? "rc=\(rc)"
                    AirliftWalletEngine.shared.scanStatusText = "Scanner stopped: \(msg)"
                } else {
                    AirliftWalletEngine.shared.scanStatusText = "Scanning stopped. Total cards: \(AirliftWalletEngine.shared.cards.count)."
                }
            }
        }
        thread.name = "WorkTweaks.WalletScanner"
        thread.stackSize = 4 * 1024 * 1024 // 4 MB stack
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func stopCardScanning() {
        al_syslog_stream_stop()
        isScanningCards = false
        scanStatusText = "Scanning stopped. Total cards: \(cards.count)."
        saveCards()
    }

    /// C-callback entry point (nonisolated): forwards a syslog line to the engine.
    nonisolated static func handleSyslogLine(_ line: String) {
        Task { @MainActor in
            shared.processSyslogLine(line)
        }
    }

    /// C-callback entry point (nonisolated): appends a flash log line.
    nonisolated static func appendFlashLog(_ line: String) {
        Task { @MainActor in
            shared.flashLog.append(line)
        }
    }

    func processSyslogLine(_ line: String) {
        let lower = line.lowercased()
        let isWalletSubsystem = lower.contains("passd") ||
                                lower.contains("passbook") ||
                                lower.contains("passkit") ||
                                lower.contains("stockholm") ||
                                lower.contains("nanopassd") ||
                                lower.contains("wallet") ||
                                lower.contains("pdcardfilemanager") ||
                                lower.contains("pdpasslibrary") ||
                                lower.contains("verificationcheck") ||
                                lower.contains("/cards/") ||
                                lower.contains("nfcd") ||
                                lower.contains("dashboard") ||
                                lower.contains("activation")

        guard isWalletSubsystem else { return }

        let isWalletContext = lower.contains("card") ||
                              lower.contains("pass") ||
                              lower.contains("payment") ||
                              lower.contains("pkpass") ||
                              lower.contains("uniqueid") ||
                              lower.contains("identifier") ||
                              lower.contains("face") ||
                              lower.contains("cache") ||
                              lower.contains("stockholm") ||
                              lower.contains("pdcardfilemanager") ||
                              lower.contains("pdpasslibrary") ||
                              lower.contains("verificationcheck") ||
                              lower.contains("/cards/") ||
                              lower.contains("dashboard loading") ||
                              lower.contains("passids") ||
                              lower.contains("applet") ||
                              lower.contains("nfexpressmodemanager")

        guard isWalletContext else { return }

        // 1. Process activations / AIDs to track payment network & instant card ID
        let activations = WalletScanParser.activationIDs(in: line)
        for act in activations {
            if let net = act.network {
                self.lastObservedNetwork = net
            }
            if let id = act.id, let clean = WalletCard.cleanCardId(id), !Self.dummyCardHashes.contains(clean) {
                self.registerDiscoveredCard(id: clean, network: act.network ?? self.lastObservedNetwork)
            }
        }

        // 2. High-confidence regex extraction
        let candidates = WalletScanParser.cardIDs(in: line)
        var foundAny = false
        for cand in candidates {
            if let clean = WalletCard.cleanCardId(cand), !Self.dummyCardHashes.contains(clean) {
                foundAny = true
                self.registerDiscoveredCard(id: clean, network: self.lastObservedNetwork)
            }
        }

        // 3. Fallback token extraction if no cards matched yet
        if !foundAny && candidates.isEmpty {
            let fallbacks = WalletScanParser.fallbackCardIDs(in: line)
            for cand in fallbacks {
                if let clean = WalletCard.cleanCardId(cand), !Self.dummyCardHashes.contains(clean) {
                    self.registerDiscoveredCard(id: clean, network: self.lastObservedNetwork)
                }
            }
        }
    }

    private func registerDiscoveredCard(id: String, network: PaymentNetwork? = nil) {
        if let existingIdx = self.cards.firstIndex(where: { $0.id == id }) {
            if self.cards[existingIdx].network == nil, let net = network {
                self.cards[existingIdx].network = net
                self.saveCards()
            }
            return
        }
        let newCard = WalletCard(
            id: id,
            displayName: nil,
            network: network,
            isSelected: true,
            isVerified: true
        )
        self.cards.append(newCard)
        self.saveCards()
        let netSuffix = network != nil ? " (\(network!.displayName))" : ""
        self.scanStatusText = "Found card: \(id)\(netSuffix)"
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // MARK: - Persistence

    nonisolated static func cardImagePath(for cardId: String) -> URL {
        let safeId = cardId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cardsDir = docDir.appendingPathComponent("WalletCards", isDirectory: true)
        if !FileManager.default.fileExists(atPath: cardsDir.path) {
            try? FileManager.default.createDirectory(at: cardsDir, withIntermediateDirectories: true)
        }
        return cardsDir.appendingPathComponent("card_\(safeId).png")
    }

    func loadSavedCards() {
        var foundHashes: [String] = []
        for key in storageKeys {
            if let saved = UserDefaults.standard.stringArray(forKey: key), !saved.isEmpty {
                foundHashes = saved
                break
            }
        }
        var unique: [String] = []
        for raw in foundHashes {
            if let clean = WalletCard.cleanCardId(raw), !unique.contains(clean) {
                unique.append(clean)
            }
        }
        let displayNames = UserDefaults.standard.dictionary(forKey: "aircard.cardDisplayNames") as? [String: String] ?? [:]
        let networks = UserDefaults.standard.dictionary(forKey: "aircard.cardPaymentNetworks") as? [String: String] ?? [:]

        cards = unique.filter { !Self.dummyCardHashes.contains($0) }.map { id in
            let path = Self.cardImagePath(for: id)
            let data = try? Data(contentsOf: path)
            // Downsampled thumbnail keeps RAM minimal, preventing Jetsam OOM kills
            let img = data.flatMap { WalletImageEngine.safeImageFromData($0, maxDimension: 512) }
            return WalletCard(
                id: id,
                displayName: displayNames[id],
                network: networks[id].flatMap { PaymentNetwork(rawValue: $0) },
                isSelected: true,
                isVerified: true,
                skinData: data,
                skinImage: img
            )
        }
    }

    func saveCards() {
        let hashes = cards.map(\.id)
        UserDefaults.standard.set(hashes, forKey: "aircard.cards")
        UserDefaults.standard.set(hashes, forKey: "airlift.cards")
        UserDefaults.standard.set(hashes, forKey: "mak5er.savedCards")

        var displayNames: [String: String] = [:]
        var networks: [String: String] = [:]
        for card in cards {
            if let d = card.displayName, !d.isEmpty {
                displayNames[card.id] = d
            }
            if let n = card.network {
                networks[card.id] = n.displayName
            }
        }
        UserDefaults.standard.set(displayNames, forKey: "aircard.cardDisplayNames")
        UserDefaults.standard.set(networks, forKey: "aircard.cardPaymentNetworks")
    }

    // MARK: - Card management

    func clearAllCards() {
        for card in cards {
            let path = Self.cardImagePath(for: card.id)
            try? FileManager.default.removeItem(at: path)
        }
        cards.removeAll()
        saveCards()
    }

    func updateCardName(id: String, newName: String) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        cards[idx].displayName = trimmed.isEmpty ? nil : trimmed
        saveCards()
    }

    func setSkinForAllCards(image: UIImage) {
        for card in cards where card.isSelected {
            setCardImage(for: card.id, image: image)
        }
    }

    func selectAllCards(_ selected: Bool) {
        guard !cards.isEmpty else { return }
        cards = cards.map {
            var c = $0
            c.isSelected = selected
            return c
        }
    }

    func addCardHash(_ raw: String) {
        let parts = raw.components(separatedBy: CharacterSet(charactersIn: " \n\r\t,;"))
        var added = 0
        for p in parts {
            if let clean = WalletCard.cleanCardId(p),
               !cards.contains(where: { $0.id == clean }) {
                cards.append(WalletCard(id: clean, displayName: nil, network: nil, isSelected: true, isVerified: true))
                added += 1
            }
        }
        if added > 0 { saveCards() }
    }

    func setCardSelected(id: String, selected: Bool) {
        if let idx = cards.firstIndex(where: { $0.id == id }) {
            cards[idx].isSelected = selected
        }
    }

    func deleteCard(id: String) {
        cards.removeAll { $0.id == id }
        saveCards()
        let path = Self.cardImagePath(for: id)
        try? FileManager.default.removeItem(at: path)
    }

    func clearCardImage(for cardId: String) {
        if let idx = cards.firstIndex(where: { $0.id == cardId }) {
            cards[idx].skinImage = nil
            cards[idx].skinData = nil
        }
        let path = Self.cardImagePath(for: cardId)
        try? FileManager.default.removeItem(at: path)
    }

    func setCardImage(for cardId: String, image: UIImage) {
        guard let idx = cards.firstIndex(where: { $0.id == cardId }) else { return }
        // Keep a lightweight thumbnail in memory for responsive UI & OOM protection
        let thumb = WalletImageEngine.normalizeAndDownsample(image, maxDimension: 512)
        cards[idx].skinImage = thumb

        let actualId = cards[idx].id
        let path = Self.cardImagePath(for: actualId)
        // Generate full resolution PNG data asynchronously in background
        Task.detached(priority: .userInitiated) {
            let data = WalletImageEngine.prepareCardImage(from: image)
            if let data = data {
                try? data.write(to: path)
            }
            await MainActor.run {
                if let i = AirliftWalletEngine.shared.cards.firstIndex(where: { $0.id == actualId }) {
                    AirliftWalletEngine.shared.cards[i].skinData = data
                }
            }
        }
    }

    // MARK: - Flash (via Airlift exploit)

    func flashCards() {
        guard canFlashCards else { return }
        let selected = cards.filter { $0.isSelected && ($0.skinImage != nil || $0.skinData != nil) }
        guard !selected.isEmpty else { return }

        syncTargetHost()

        flashPhase = .running
        flashProgress = 0
        flashLog.removeAll()

        let pairingPath = PairingController.pairingFilePath()

        Task.detached { [weak self] in
            guard let self = self else { return }
            let total = Double(selected.count)
            var successCount = 0
            for (i, card) in selected.enumerated() {
                let cleanId = WalletCard.cleanCardId(card.id) ?? card.id
                let safeCardId = cleanId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")

                await MainActor.run {
                    self.flashLog.append("[\(i+1)/\(selected.count)] Flashing card \(cleanId.prefix(12))…")
                    self.flashProgress = Double(i) / total
                }

                // Load source image at full resolution on demand to save memory
                let sourceImg: UIImage? = {
                    if let d = card.skinData, let img = UIImage(data: d) { return img }
                    let p = Self.cardImagePath(for: cleanId)
                    if let d = try? Data(contentsOf: p), let img = UIImage(data: d) { return img }
                    return card.skinImage
                }()

                guard let sourceImg = sourceImg else {
                    await MainActor.run { self.flashLog.append("  No image for card \(cleanId.prefix(8))") }
                    continue
                }

                // 1. Prepare multi-resolution skins
                let allSkins = WalletImageEngine.prepareAllCardSkins(from: sourceImg)
                guard !allSkins.isEmpty else {
                    await MainActor.run { self.flashLog.append("  Failed to generate card skins") }
                    continue
                }

                let stageCardDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("airlift_card_\(safeCardId)_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: stageCardDir, withIntermediateDirectories: true)

                for (name, data) in allSkins {
                    try? data.write(to: stageCardDir.appendingPathComponent(name))
                }

                // Exact aircard target: the card's .pkpass folder on-device.
                let pkpassTarget = "/var/mobile/Library/Passes/Cards/\(cleanId).pkpass"

                await MainActor.run {
                    self.flashLog.append("  Injecting skins into \(cleanId.prefix(10)).pkpass…")
                }

                var writeOk = false
                var errDesc: String? = nil
                await withCheckedContinuation { cont in
                    DispatchQueue.global(qos: .userInitiated).async {
                        var outError: UnsafeMutablePointer<CChar>? = nil
                        let rc = pairingPath.withCString { pairC in
                            stageCardDir.path.withCString { srcC in
                                pkpassTarget.withCString { tgtC in
                                    al_exploit_write_dir(pairC, srcC, tgtC, { _, msg in
                                        guard let msg = msg else { return }
                                        let line = String(cString: msg)
                                        AirliftWalletEngine.appendFlashLog("    " + line)
                                    }, nil, &outError)
                                }
                            }
                        }
                        if let p = outError {
                            errDesc = String(validatingUTF8: p)
                            al_string_free(p)
                        }
                        writeOk = (rc == 0)
                        cont.resume()
                    }
                }

                try? FileManager.default.removeItem(at: stageCardDir)

                if !writeOk {
                    await MainActor.run {
                        self.flashLog.append("  Failed to write card skins: \(errDesc ?? "exploit error")")
                    }
                    continue
                }

                await MainActor.run {
                    self.flashLog.append("  Skins applied! Invalidating pass cache…")
                }

                // 2. Invalidate cache leaves (best effort: some iOS versions don't have .cache or .pkcache folders)
                let stageInvDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("airlift_inv_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: stageInvDir, withIntermediateDirectories: true)
                for leaf in ["FrontFace", "Preview", "PlaceHolder"] {
                    try? Data("corrupted".utf8).write(to: stageInvDir.appendingPathComponent(leaf))
                }

                for ext in [".cache", ".pkcache"] {
                    let cacheTarget = "/var/mobile/Library/Passes/Cards/\(cleanId)\(ext)"
                    await withCheckedContinuation { cont in
                        DispatchQueue.global(qos: .userInitiated).async {
                            var outError: UnsafeMutablePointer<CChar>? = nil
                            _ = pairingPath.withCString { pairC in
                                stageInvDir.path.withCString { srcC in
                                    cacheTarget.withCString { tgtC in
                                        al_exploit_write_dir(pairC, srcC, tgtC, nil, nil, &outError)
                                    }
                                }
                            }
                            if let p = outError { al_string_free(p) }
                            cont.resume()
                        }
                    }
                }
                try? FileManager.default.removeItem(at: stageInvDir)

                successCount += 1
                await MainActor.run {
                    self.flashLog.append("  Pass cache invalidated")
                    self.flashProgress = Double(i + 1) / total
                }
            }

            await MainActor.run {
                if successCount > 0 {
                    self.flashPhase = .done(ok: true)
                    self.flashProgress = 1.0
                    ApplyHistory.record(source: "Airlift — Wallet Cards", detail: "\(successCount)/\(selected.count) card(s) flashed with custom art.")
                    self.flashLog.append("\(successCount)/\(selected.count) card(s) flashed! Force-close Wallet app to see changes.")
                } else {
                    self.flashPhase = .done(ok: false)
                    self.flashLog.append("Card flash failed. Check connection and try again.")
                }
            }
        }
    }
}
