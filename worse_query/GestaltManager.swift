import Foundation
import Combine
import SwiftUI
import Darwin
import MachO
import UIKit

// ============================================================================
// MARK: - Port of mond/helpers/mg.swift (adnan120hz/mond)
//
// This file is a faithful port of mond's MobileGestalt engine:
//   * the tweak catalog is mond's `all_tweaks`, verbatim — same titles,
//     same keys, same values, same read/write semantics, same minv gates;
//   * load / apply / revert follow mg_load / mg_apply / mg_revert;
//   * writes go through mg_write: by default ("Persist after reboot",
//     UserDefaults `atomic_write` = true, registered in WorkTweaksApp)
//     the plist is rewritten IN PLACE on the same inode
//     (open O_RDWR -> ftruncate -> write -> fsync -> verify -> rollback),
//     because iOS regenerates a replaced MobileGestalt cache file;
//   * the sandbox grant follows mond's unsbx.swift grant_mg(): the
//     extension is taken on the gestalt *directory* and held.
//
// The only deliberate deviations, all forced by how this app is signed
// (ESign rewrites the App Group with a team suffix) or by features the
// user asked for on top of mond:
//   * the App Group string comes from AppGroupResolver (mond hardcodes
//     its own group; ours must be discovered from the signed profile);
//   * Alertinator pop-ups become Log lines / `notice` alerts;
//   * the Backup tab's snapshot system is layered on top: a pre-apply
//     snapshot is saved before every Apply, and restores write through
//     the same mg_write path.
// ============================================================================

func doubleSystemVersion() -> Double {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return Double(v.majorVersion) + Double(v.minorVersion) / 10.0
}

func machineName() -> String {
    var sysInfo = utsname()
    uname(&sysInfo)
    let mirror = Mirror(reflecting: sysInfo.machine)
    return mirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
}

func hasHomeButton() -> Bool {
    let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
    return (windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0) == 0
}

/// mond: is_device_good()
func isDeviceGoodForNoDynamicIsland() -> Bool {
    let supported = ["iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5", "iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone17,5"]
    return supported.contains(machineName()) && doubleSystemVersion() < 19.0
}

enum MGPaths {
    // mond: TweakPaths
    static let gestalt = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    static let gestaltDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/"

    // mond: AppPaths.backups (Application Support/backups)
    static var backupsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var savedGestaltURL: URL {
        backupsDir.appendingPathComponent("SavedGestalt.plist")
    }
}

// MARK: - CacheData offsets (mond: cache_data_offset / cache_data_safe_offset)

private var cacheDataOffsets: [String: Int] = [:]

func cacheDataOffset(_ key: String) -> Int {
    if let cached = cacheDataOffsets[key] {
        print("(cachedata) cached result for \(key): \(cached)")
        return cached
    }

    let libMG = "/usr/lib/libMobileGestalt.dylib"
    _ = dlopen(libMG, RTLD_GLOBAL)

    var header: UnsafePointer<mach_header_64>?
    for i in 0..<_dyld_image_count() {
        if String(cString: _dyld_get_image_name(i)) == libMG {
            header = unsafeBitCast(_dyld_get_image_header(i), to: UnsafePointer<mach_header_64>.self)
            break
        }
    }
    // Diagnostics (WorkTweaks addition): log which scan stage fails so a
    // blocked CacheData tweak can be traced on-device from the Log tab.
    guard let header else {
        print("(cachedata) stage 1 FAILED: libMobileGestalt.dylib not in dyld image list (\( _dyld_image_count()) images)")
        for i in 0..<_dyld_image_count() {
            let name = String(cString: _dyld_get_image_name(i))
            if name.contains("Gestalt") {
                print("(cachedata) stage 1 candidate image: \(name)")
            }
        }
        return 0
    }

    var textSize = 0
    guard let cstring = getsectiondata(header, "__TEXT", "__cstring", &textSize) else {
        print("(cachedata) stage 2 FAILED: no __TEXT,__cstring section")
        return 0
    }
    let cstr = cstring.withMemoryRebound(to: CChar.self, capacity: textSize) { $0 }

    var keyPtr = cstr
    var keyFound = false
    while Int(keyPtr - cstr) < textSize {
        if String(cString: keyPtr) == key { keyFound = true; break }
        keyPtr += strlen(keyPtr) + 1
    }
    guard keyFound else {
        print("(cachedata) stage 3 FAILED: key \(key) not found in __cstring (\(textSize) bytes scanned)")
        cacheDataOffsets[key] = 0
        return 0
    }

    var constSize = 0
    var constSegment = "__AUTH_CONST"
    var ptr = getsectiondata(header, "__AUTH_CONST", "__const", &constSize)?.withMemoryRebound(to: UInt.self, capacity: constSize / 8) { $0 }
    if ptr == nil {
        constSegment = "__DATA_CONST"
        ptr = getsectiondata(header, "__DATA_CONST", "__const", &constSize)?.withMemoryRebound(to: UInt.self, capacity: constSize / 8) { $0 }
    }

    guard let ptr else {
        print("(cachedata) stage 4 FAILED: no __const section in __AUTH_CONST or __DATA_CONST")
        return 0
    }
    for i in 0..<constSize / 8 {
        if ptr[i] == UInt(bitPattern: keyPtr) {
            let offset = Int((ptr.advanced(by: i).withMemoryRebound(to: UInt16.self, capacity: 1) { $0[0x9a / 2] }) << 3)
            print("(cachedata) OK: \(key) -> offset \(offset) (via \(constSegment), entry \(i)/\(constSize / 8))")
            cacheDataOffsets[key] = offset
            return offset
        }
    }

    // Stage 5 failure analysis: on arm64e the table may hold authenticated
    // pointers whose high bits differ from the plain address — count how
    // many entries match once the high 16 bits are masked off.
    let plainAddr = UInt(bitPattern: keyPtr)
    var maskedMatches = 0
    var firstRaw: UInt = 0
    for i in 0..<constSize / 8 {
        if i == 0 { firstRaw = ptr[i] }
        if (ptr[i] & 0x0000_FFFF_FFFF_FFFF) == (plainAddr & 0x0000_FFFF_FFFF_FFFF) { maskedMatches += 1 }
    }
    print("(cachedata) stage 5 FAILED: key pointer not found in \(constSegment),__const (\(constSize / 8) entries scanned); masked(PAC-stripped) matches: \(maskedMatches); key addr: \(String(plainAddr, radix: 16)); first entry raw: \(String(firstRaw, radix: 16))")
    cacheDataOffsets[key] = 0
    return 0
}

func cacheDataSafeOffset(_ key: String, in data: NSMutableData) -> Int? {
    let offset = cacheDataOffset(key)
    guard offset > 0, offset <= data.length - MemoryLayout<Int>.size else {
        print("(cachedata) safe-offset REJECTED for \(key): offset \(offset), CacheData length \(data.length)")
        return nil
    }
    print("(cachedata) safe-offset OK for \(key): \(offset) (CacheData length \(data.length))")
    return offset
}

// MARK: - iPadOS CacheData locator (Nugget: MobileGestaltCacheDataTweak)
//
// Port of leminlimez/Nugget's MobileGestaltCacheDataTweak — a purely
// file-based way to find the iPadOS device-class slot inside CacheData:
// it pattern-matches the CacheData hex string instead of scanning
// libMobileGestalt.dylib in memory (mond's approach, whose scan fails
// on this device/iOS). WorkGestalt/worse_query contain no tweak code,
// so per the user's direction this tweak uses the file method.
// sliceStart/sliceLength are Nugget's constants; every offset below is
// a HEX-STRING character index, exactly as in Nugget's implementation.

enum NuggetIPadOSLocator {
    static let sliceStart = 1616
    static let sliceLength = 200

    // Performance (fix for app-wide lag): the locator only ever reads
    // bytes ~[770, 920] of CacheData (anchor window + validated slots).
    // It works byte-natively on that window only — never converting the
    // whole CacheData to a hex string — and memoizes the result keyed
    // by those bytes + the total length, because tweak read() runs on
    // every UI pass and must stay effectively O(1).
    private static var cached: (region: Data, totalLength: Int, slot: Int, value: Character)?
    private static let regionLower = 700
    private static let regionUpper = 1000

    private static func hexDigit(_ nibble: UInt8) -> Character {
        Character(UnicodeScalar(nibble < 10 ? 48 + nibble : 87 + nibble))
    }

    private static func hexChar(_ bytes: UnsafePointer<UInt8>, atHexIndex i: Int) -> Character {
        let byte = bytes[i / 2]
        return hexDigit(i % 2 == 0 ? byte >> 4 : byte & 0x0F)
    }

    private static func region(of cacheData: NSData) -> Data {
        let lower = min(regionLower, cacheData.length)
        let upper = min(regionUpper, cacheData.length)
        guard upper > lower else { return Data() }
        return Data(bytes: cacheData.bytes.advanced(by: lower), count: upper - lower)
    }

    /// Finds the "left" device-class slot. Returns (slot, currentValue)
    /// or (nil, error) with Nugget's error messages when the pattern
    /// does not hold on this CacheData.
    static func locate(in cacheData: NSData) -> (slot: Int?, value: Character?, error: String?) {
        let totalHexCount = cacheData.length * 2
        guard totalHexCount > sliceStart else {
            return (nil, nil, "CacheData is too short!")
        }

        if let cached, cached.totalLength == cacheData.length, cached.region == region(of: cacheData) {
            return (cached.slot, cached.value, nil)
        }

        let bytes = cacheData.bytes.bindMemory(to: UInt8.self, capacity: cacheData.length)

        // Nugget: find `0+(?:5555)*([0-9a-f]{4})` in the slice (hex chars
        // [sliceStart, sliceStart+sliceLength) = bytes [808, 908)); the
        // first capture whose 4 hex chars contain >= 3 non-zero chars
        // anchors the offsets. Only this window is hex-encoded.
        let windowStartByte = sliceStart / 2
        let windowEndByte = min((sliceStart + sliceLength) / 2, cacheData.length)
        var windowChars: [Character] = []
        windowChars.reserveCapacity((windowEndByte - windowStartByte) * 2)
        for i in windowStartByte..<windowEndByte {
            windowChars.append(hexDigit(bytes[i] >> 4))
            windowChars.append(hexDigit(bytes[i] & 0x0F))
        }
        let slice = String(windowChars)
        let regex = try! NSRegularExpression(pattern: "0+(?:5555)*([0-9a-f]{4})")
        var offset: Int?
        for match in regex.matches(in: slice, range: NSRange(slice.startIndex..., in: slice)) {
            let group = (slice as NSString).substring(with: match.range(at: 1))
            if group.filter({ $0 != "0" }).count >= 3 {
                offset = sliceStart + match.range(at: 1).location
                break
            }
        }
        guard let offset else {
            return (nil, nil, "Pattern not found in CacheData.")
        }

        let roffset = offset + 13
        let loffset = offset - 67 // Nugget: "real" left offset
        if roffset >= totalHexCount - 1 || roffset - 1 < 0 {
            return (nil, nil, "Right offset out of range. Right Offset: \(roffset), Data Length: \(totalHexCount)")
        }
        if loffset <= 0 || loffset + 1 >= totalHexCount {
            return (nil, nil, "Left offset out of range. Left Offset: \(loffset), Data Length: \(totalHexCount)")
        }

        for (sideOffset, name) in [(roffset, "right"), (loffset, "left")] {
            let value = hexChar(bytes, atHexIndex: sideOffset)
            if value != "1" && value != "3" {
                return (nil, nil, "Value at \(name) offset is not 1 or 3. Value[\(sideOffset)] = \(value), Data Length: \(totalHexCount)")
            }
            let before = hexChar(bytes, atHexIndex: sideOffset - 1)
            let after = hexChar(bytes, atHexIndex: sideOffset + 1)
            if before != "0" || after != "0" {
                return (nil, nil, "Values of \(name) offset neighbors are not 0. Value[\(sideOffset - 1)] = \(before), Value[\(sideOffset + 1)] = \(after), Data Length: \(totalHexCount)")
            }
        }

        let value = hexChar(bytes, atHexIndex: loffset)
        cached = (region(of: cacheData), cacheData.length, loffset, value)
        print("(ipados) Nugget locator: slot \(loffset), current value \(value) (anchor offset \(offset))")
        return (loffset, value, nil)
    }

    /// Sets the device-class slot to "3" (iPadOS on) or "1" (off) inside
    /// the dictionary's CacheData — a single-nibble edit in place.
    /// Returns an error string or nil.
    static func setSlot(in dict: NSMutableDictionary, enabled: Bool) -> String? {
        guard let cacheData = dict["CacheData"] as? NSMutableData else {
            return "CacheData is missing from MobileGestalt."
        }
        let located = locate(in: cacheData)
        if let error = located.error { return error }
        guard let slot = located.slot else { return "Pattern not found in CacheData." }

        let bytes = cacheData.mutableBytes.bindMemory(to: UInt8.self, capacity: cacheData.length)
        let byteIndex = slot / 2
        let nibble: UInt8 = enabled ? 0x3 : 0x1
        if slot % 2 == 0 {
            bytes[byteIndex] = (bytes[byteIndex] & 0x0F) | (nibble << 4)
        } else {
            bytes[byteIndex] = (bytes[byteIndex] & 0xF0) | nibble
        }
        cached = nil
        print("(ipados) Nugget locator: slot \(slot) set to \(enabled ? "3" : "1")")
        return nil
    }
}

// MARK: - Tweak model (mond: mg_tweak)

struct GestaltTweak: Identifiable {
    enum InfoType {
        case info
        case warning
        case error
    }

    let id: String
    let title: String
    let minv: Double?
    let infoType: InfoType?
    let infoMessage: String?
    /// CacheExtra keys this tweak touches (drives the Backup tab's
    /// per-key listing; CacheData-only tweaks have none).
    let keys: [String]
    let canApply: (NSMutableDictionary) -> String?
    let read: (NSMutableDictionary) -> Bool
    let writeOn: (NSMutableDictionary) -> Void
    let writeOff: (NSMutableDictionary) -> Void

    func isOn(in dict: NSMutableDictionary) -> Bool { read(dict) }

    func supported() -> Bool {
        guard let minv else { return true }
        return doubleSystemVersion() >= minv
    }
}

private func slug(_ title: String) -> String {
    var out = ""
    for ch in title.lowercased() {
        if ch.isLetter || ch.isNumber {
            out.append(ch)
        } else if !out.isEmpty && out.last != "_" {
            out.append("_")
        }
    }
    while out.last == "_" { out.removeLast() }
    return out
}

private func mutableCacheExtra(_ dict: NSMutableDictionary) -> NSMutableDictionary? {
    if let extra = dict["CacheExtra"] as? NSMutableDictionary {
        return extra
    }
    guard let extra = dict["CacheExtra"] as? NSDictionary else { return nil }
    let mutable = NSMutableDictionary(dictionary: extra)
    dict["CacheExtra"] = mutable
    return mutable
}

/// mond: mg_tweak init(key:value:) / init(keys:value:) (+ info variants)
private func makeTweak<T: Equatable>(
    title: String,
    minv: Double? = nil,
    keys: [String],
    value: T,
    infoType: GestaltTweak.InfoType? = nil,
    infoMessage: String? = nil
) -> GestaltTweak {
    GestaltTweak(
        id: slug(title),
        title: title,
        minv: minv,
        infoType: infoType,
        infoMessage: infoMessage,
        keys: keys,
        canApply: { _ in nil },
        read: { dict in
            guard let extra = dict["CacheExtra"] as? NSDictionary,
                  let key = keys.first else { return false }
            return extra[key] as? T == value
        },
        writeOn: { dict in
            guard let extra = mutableCacheExtra(dict) else { return }
            for key in keys {
                extra[key] = value
            }
        },
        writeOff: { dict in
            guard let extra = mutableCacheExtra(dict) else { return }
            for key in keys {
                extra.removeObject(forKey: key)
            }
        }
    )
}

private let regionCodeKey = "h63QSdBCiT/z0WU6rdQv6Q"
private let regionInfoKey = "yK+xavymRGZ3xWc1tb8XDg"

// MARK: - Catalog (mond: all_tweaks, verbatim)

enum TweakCatalog {
    static let all: [GestaltTweak] = [
        makeTweak(title: "Enable Dynamic Island Capability", minv: 19.0, keys: ["YlEtTtHlNesRBMal1CqRaA"], value: 1, infoType: .info, infoMessage: "An alternate way to enable the Dynamic Island, as used by Nugget."),
        makeTweak(title: "Always-On Display", minv: 18.0, keys: ["2OOJf1VhaM7NxfRok3HbWQ", "j8/Omm6s1lsmTDFsXjsBfA"], value: 1, infoType: .warning, infoMessage: "Can increase screen burn-in risk on devices that don't officially support it."),
        makeTweak(title: "AOD Vibrancy", minv: 18.0, keys: ["ykpu7qyhqFweVMKtxNylWA"], value: 1, infoType: .info, infoMessage: "Turn this on if your Always-On Display renders incorrectly."),
        makeTweak(title: "Disable Wallpaper Parallax", keys: ["UIParallaxCapability"], value: 0, infoType: .info, infoMessage: "Prevents the wallpaper from moving when you tilt or move the device."),
        makeTweak(title: "Enable Liquid Glass Low-Performance Mode", minv: 19.0, keys: ["SAGvsp6O6kAQ4fEfDJpC4Q"], value: 1, infoType: .info, infoMessage: "Intended for iOS 26 and newer."),
        makeTweak(title: "Disable Liquid Glass Low-Performance Mode", minv: 19.0, keys: ["SAGvsp6O6kAQ4fEfDJpC4Q"], value: 0, infoType: .info, infoMessage: "Don't use this at the same time as the option above."),
        makeTweak(title: "Boot & Shutdown Chime", keys: ["QHxt+hGLaBPbQJbXiUJX3w"], value: 1, infoType: .info, infoMessage: "Adds the chime sound when the device powers on or shuts down."),
        makeTweak(title: "Charge Limit Menu", minv: 17.0, keys: ["37NVydb//GP/GrhuTN+exg"], value: 1, infoType: .info, infoMessage: "Reveals the Settings menu; whether it actually limits charging depends on your hardware."),
        makeTweak(title: "Tap to Wake", keys: ["yZf3GTRMGTuwSV/lD7Cagw"], value: 1, infoType: .info, infoMessage: "Meant for devices like the iPhone SE where tapping to wake isn't otherwise available."),
        makeTweak(title: "iPhone 16 Camera Control Settings", minv: 18.0, keys: ["CwvKxM2cEogD3p+HYgaW0Q", "oOV1jhJbdV3AddkcCg0AEA"], value: 1, infoType: .info, infoMessage: "Exposes the Camera Control settings and its related capabilities."),
        makeTweak(title: "Apple Pencil Settings", keys: ["yhHcB0iH0d1XzPO/CFd3ow"], value: 1, infoType: .info, infoMessage: "Reveals the Apple Pencil settings page."),
        makeTweak(title: "Action Button Settings", minv: 17.0, keys: ["cT44WE1EohiwRzhsZ8xEsw"], value: 1, infoType: .info, infoMessage: "Reveals the Action Button settings page."),
        makeTweak(title: "Collision SOS", keys: ["HCzWusHQwZDea6nNhaKndw"], value: 1, infoType: .info, infoMessage: "Reveals the collision detection options in the SOS settings."),
        makeTweak(title: "Pulse Width Modulation", minv: 19.0, keys: ["6IejgN+1Fmu5/QrZFOIeNw"], value: 1),
        makeTweak(title: "Security Research Device Mode", minv: 26.0, keys: ["XYlJKKkj2hztRP1NWWnhlw"], value: 1, infoType: .info, infoMessage: "Flags the device as an Apple Security Research Device."),
        makeTweak(title: "Allow iPad Apps", keys: ["9MZ5AdH43csAUajl/dU+IQ"], value: [1, 2], infoType: .info, infoMessage: "Allows iPad apps to be installed on iPhone."),
        makeTweak(title: "Stage Manager Support", keys: ["qeaj75wk3HF4DwQ8qbIi7g"], value: 1, infoType: .info, infoMessage: "Flags the device as capable of Stage Manager."),
        makeTweak(title: "Apple Internal Install", keys: ["EqrsVvjcYDdxHBiQmGhAWw"], value: 1, infoType: .warning, infoMessage: "Turns on internal features like the Metal HUD; some services may act up."),
        makeTweak(title: "Internal Storage View", keys: ["LBJfwOEzExRxzlAnSuI7eg"], value: 1, infoType: .warning, infoMessage: "Displays internal files in the Storage settings; can be dangerous on some iPads."),

        // mond: Disable Region Restrictions (custom closures)
        GestaltTweak(
            id: slug("Disable Region Restrictions"),
            title: "Disable Region Restrictions",
            minv: nil,
            infoType: .info,
            infoMessage: "This tweak may be broken or have no effect on some iOS versions or devices.\n\nWarning from mond: Please do not use this feature to bypass region restrictions that would equate to breaking regional laws (e.g. disabling the camera shutter sound).",
            keys: [regionCodeKey, regionInfoKey],
            canApply: { _ in nil },
            read: { dict in
                guard let extra = dict["CacheExtra"] as? NSMutableDictionary else { return false }
                return extra[regionCodeKey] as? String == "LL" &&
                       extra[regionInfoKey] as? String == "LL/A"
            },
            writeOn: { dict in
                guard let extra = dict["CacheExtra"] as? NSMutableDictionary else { return }
                extra[regionCodeKey] = "LL"
                extra[regionInfoKey] = "LL/A"
            },
            writeOff: { dict in
                guard let extra = dict["CacheExtra"] as? NSMutableDictionary else { return }
                extra.removeObject(forKey: regionCodeKey)
                extra.removeObject(forKey: regionInfoKey)
            }
        ),

        // mond: Apple Intelligence (custom closures)
        GestaltTweak(
            id: slug("Apple Intelligence"),
            title: "Apple Intelligence",
            minv: 18.1,
            infoType: .info,
            infoMessage: "How to use this tweak:\n1. Spoof to the model next to the first one supported by Apple Intelligence.\n2. Spoof back to your model.\n3. Spoof to your final model and you should see the Apple Intelligence icon in Settings.\n4. Connect iPhone to power and leave the Settings > Storage tab open for ~1 hour.\n\nNOTE: Do not spoof back.",
            keys: ["A62OafQ85EJAiiqKn4agtg"],
            canApply: { _ in nil },
            read: { dict in
                guard let extra = dict["CacheExtra"] as? NSMutableDictionary else { return false }
                return (extra["A62OafQ85EJAiiqKn4agtg"] as? Int) == 1
            },
            writeOn: { dict in
                guard let extra = dict["CacheExtra"] as? NSMutableDictionary else { return }
                extra["A62OafQ85EJAiiqKn4agtg"] = 1
            },
            writeOff: { dict in
                guard let extra = dict["CacheExtra"] as? NSMutableDictionary else { return }
                extra.removeObject(forKey: "A62OafQ85EJAiiqKn4agtg")
            }
        ),

        // Enable iPadOS Mode — CacheExtra keys from mond/Nugget (same 5),
        // but the CacheData device-class slot is located with Nugget's
        // file-based pattern method (per the user's direction for this
        // tweak), NOT mond's libMobileGestalt.dylib scan.
        GestaltTweak(
            id: slug("Enable iPadOS Mode"),
            title: "Enable iPadOS Mode",
            minv: nil,
            infoType: .warning,
            infoMessage: "Experimental and high risk; This is a very dangerous tweak to use! If you use an alphanumeric passcode, DO NOT USE THIS TWEAK AT ALL! Please do not turn off \"Show Dock In Stage Manager\" or your device will BOOTLOOP when rotating to landscape! Some users have also reported that enabling the iPadOS UI and then tapping Stage Manager can cause the device to enter Recovery Mode, even when the UI itself appears unchanged. The Settings search bar may move to the top before this happens. With these three things in mind, you may experience general instability, or other major issues such as app data randomly disappearing.",
            keys: ["mG0AnH/Vy1veoqoLRAIgTA", "UCG5MkVahJxG1YULbbd5Bg", "ZYqko/XM5zD3XBfN5RmaXA", "nVh/gwNpy7Jv1NOk00CMrw", "uKc7FPnEO++lVhHWHFlGbQ"],
            canApply: { dict in
                guard let cacheData = dict["CacheData"] as? NSMutableData else {
                    return "CacheData is missing from MobileGestalt."
                }
                let located = NuggetIPadOSLocator.locate(in: cacheData)
                if let error = located.error {
                    return "Failed to enable iPadOS: \(error)"
                }
                return nil
            },
            read: { dict in
                guard let extra = dict["CacheExtra"] as? NSMutableDictionary,
                      let cacheData = dict["CacheData"] as? NSMutableData else { return false }
                let values: [String: Int] = [
                    "mG0AnH/Vy1veoqoLRAIgTA": 1,
                    "UCG5MkVahJxG1YULbbd5Bg": 1,
                    "ZYqko/XM5zD3XBfN5RmaXA": 1,
                    "nVh/gwNpy7Jv1NOk00CMrw": 1,
                    "uKc7FPnEO++lVhHWHFlGbQ": 1,
                ]
                guard values.allSatisfy({ key, value in (extra[key] as? Int) == value }) else { return false }
                return NuggetIPadOSLocator.locate(in: cacheData).value == "3"
            },
            writeOn: { dict in
                guard let extra = dict["CacheExtra"] as? NSMutableDictionary else { return }
                if let error = NuggetIPadOSLocator.setSlot(in: dict, enabled: true) {
                    print("(ipados) write failed: \(error)")
                    return
                }
                let values: [String: Int] = [
                    "mG0AnH/Vy1veoqoLRAIgTA": 1,
                    "UCG5MkVahJxG1YULbbd5Bg": 1,
                    "ZYqko/XM5zD3XBfN5RmaXA": 1,
                    "nVh/gwNpy7Jv1NOk00CMrw": 1,
                    "uKc7FPnEO++lVhHWHFlGbQ": 1,
                ]
                for (key, value) in values {
                    extra[key] = value
                }
            },
            writeOff: { dict in
                // Restore the slot when locatable, but always remove the
                // CacheExtra keys so the tweak can be cleaned up.
                _ = NuggetIPadOSLocator.setSlot(in: dict, enabled: false)
                guard let extra = dict["CacheExtra"] as? NSMutableDictionary else { return }
                let keys = ["mG0AnH/Vy1veoqoLRAIgTA", "UCG5MkVahJxG1YULbbd5Bg", "ZYqko/XM5zD3XBfN5RmaXA", "nVh/gwNpy7Jv1NOk00CMrw", "uKc7FPnEO++lVhHWHFlGbQ"]
                for key in keys {
                    extra.removeObject(forKey: key)
                }
            }
        ),

        // mond: Internal Features (custom closures, patches CacheData)
        GestaltTweak(
            id: slug("Internal Features"),
            title: "Internal Features",
            minv: nil,
            infoType: nil,
            infoMessage: nil,
            keys: [],
            canApply: { dict in
                guard let cacheData = dict["CacheData"] as? NSMutableData else {
                    return "CacheData is missing from MobileGestalt."
                }
                let keys = ["EqrsVvjcYDdxHBiQmGhAWw", "Oji6HRoPi7rH7HPdWVakuw", "LBJfwOEzExRxzlAnSuI7eg"]
                for key in keys {
                    if cacheDataSafeOffset(key, in: cacheData) == nil {
                        return "CacheData offset not found for \(key). Internal Features binary patch is not supported on this device/iOS version."
                    }
                }
                return nil
            },
            read: { dict in
                guard let cacheData = dict["CacheData"] as? NSMutableData,
                      let off = cacheDataSafeOffset("EqrsVvjcYDdxHBiQmGhAWw", in: cacheData) else { return false }
                return cacheData.bytes.load(fromByteOffset: off, as: Int.self) == 1
            },
            writeOn: { dict in
                guard let cacheData = dict["CacheData"] as? NSMutableData,
                      let offInstall = cacheDataSafeOffset("EqrsVvjcYDdxHBiQmGhAWw", in: cacheData),
                      let offBundle = cacheDataSafeOffset("Oji6HRoPi7rH7HPdWVakuw", in: cacheData),
                      let offBuild = cacheDataSafeOffset("LBJfwOEzExRxzlAnSuI7eg", in: cacheData) else { return }

                cacheData.mutableBytes.storeBytes(of: 1, toByteOffset: offInstall, as: Int.self)
                cacheData.mutableBytes.storeBytes(of: 1, toByteOffset: offBundle, as: Int.self)
                cacheData.mutableBytes.storeBytes(of: 1, toByteOffset: offBuild, as: Int.self)
            },
            writeOff: { dict in
                guard let cacheData = dict["CacheData"] as? NSMutableData,
                      let offInstall = cacheDataSafeOffset("EqrsVvjcYDdxHBiQmGhAWw", in: cacheData),
                      let offBundle = cacheDataSafeOffset("Oji6HRoPi7rH7HPdWVakuw", in: cacheData),
                      let offBuild = cacheDataSafeOffset("LBJfwOEzExRxzlAnSuI7eg", in: cacheData) else { return }

                cacheData.mutableBytes.storeBytes(of: 0, toByteOffset: offInstall, as: Int.self)
                cacheData.mutableBytes.storeBytes(of: 0, toByteOffset: offBundle, as: Int.self)
                cacheData.mutableBytes.storeBytes(of: 0, toByteOffset: offBuild, as: Int.self)
            }
        ),
    ]

    static func tweak(id: String) -> GestaltTweak? {
        all.first { $0.id == id }
    }

    static func tweak(title: String) -> GestaltTweak? {
        all.first { $0.title == title }
    }
}

// MARK: - Plist value description (Backup tab)

enum PlistValue {
    static func describe(_ any: Any?) -> String {
        guard let any else { return "—" }
        if let number = any as? NSNumber { return number.stringValue }
        if let string = any as? String { return string }
        if let array = any as? [Any] {
            return "[" + array.map { describe($0) }.joined(separator: ", ") + "]"
        }
        if let data = any as? NSData { return "<data \(data.length) bytes>" }
        return String(describing: any)
    }
}

// MARK: - Backup Snapshot (WorkTweaks add-on, kept from the previous design)

struct BackupSnapshot: Identifiable {
    enum Kind: String {
        case original
        case afterApply = "after-apply"
        case manual

        var label: String {
            switch self {
            case .original: return "Original"
            case .afterApply: return "After Apply Tweaks"
            case .manual: return "Manual"
            }
        }
    }

    struct KeyEntry: Identifiable {
        let key: String
        let tweakID: String
        let tweakTitle: String
        let present: Bool
        let valueDescription: String
        var id: String { tweakID + "|" + key }
    }

    /// Filename inside the snapshots folder.
    let id: String
    let kind: Kind
    let date: Date
    let url: URL
    /// Total number of keys inside CacheExtra, not just tweak keys.
    let cacheExtraCount: Int
    /// Tweaks whose mond `read` closure matches this snapshot's contents.
    let enabledTweakIDs: Set<String>
    /// One entry per tweak key, in catalog order.
    let entries: [KeyEntry]
}

// MARK: - Write errors (mond: mg_write_err)

enum MGWriteError: Error, LocalizedError {
    case open(errno: Int32)
    case truncate(errno: Int32)
    case write(errno: Int32)
    case sync(errno: Int32)
    case rollback(errno: Int32)
    case verificationFailed
    case invalidPlist
    case grantFailed(Int64)

    var errorDescription: String? {
        switch self {
        case .open(let e): return "mg_write open failed (errno \(e))."
        case .truncate(let e): return "mg_write truncate failed (errno \(e))."
        case .write(let e): return "mg_write write failed (errno \(e))."
        case .sync(let e): return "mg_write fsync failed (errno \(e))."
        case .rollback(let e): return "mg_write rollback failed (errno \(e))."
        case .verificationFailed: return "mg_write verification failed."
        case .invalidPlist: return "MobileGestalt.plist is invalid or missing CacheExtra."
        case .grantFailed(let code): return "Sandbox extension failed (code \(code))."
        }
    }
}

// MARK: - Manager (mond: mg_load / mg_apply / mg_revert / mg_write)

@MainActor
final class GestaltManager: ObservableObject {
    static let shared = GestaltManager()

    /// mond: mg_dict_now — the live, mutable MobileGestalt dictionary.
    /// Toggles mutate this in memory; Apply serializes and writes it.
    @Published var dictNow: NSMutableDictionary = NSMutableDictionary()
    /// Bumped on every in-memory mutation so SwiftUI re-reads toggle states.
    @Published var dictVersion: Int = 0

    @Published var isLoading = false
    @Published var isValid = false
    @Published var isEmpty = false
    @Published var mgGranted: Bool? = nil
    @Published var grantingMG = false
    @Published var lastError: String?
    /// Transient user-facing notice (replaces mond's Alertinator pop-ups).
    @Published var notice: String?

    /// Set when Apply succeeds: the Tweaks tab offers Respring / Restart.
    @Published var showPostApplyChoice = false
    /// Set after a successful Revert or Backup restore: those changes
    /// require a full device restart (user requirement — a respring is
    /// not enough), so the presenting view shows the Restart Required
    /// dialog instead of auto-respringing.
    @Published var showRestartRequired = false
    /// Honest restart outcome popup (command sent / failed + manual guide).
    @Published var restartAlertTitle: String?
    @Published var restartAlertMessage: String = ""
    private var restartCheckItem: DispatchWorkItem?

    // Device Artwork state (mond globals: og_st, selected_st, product_type,
    // enable_device_name, mg_device_name)
    @Published var selectedST: String = "og"
    @Published var ogST: Int = 0
    @Published var enableDeviceName: Bool = false
    @Published var deviceName: String = ""
    @Published var productType: String = ""

    @Published var snapshots: [BackupSnapshot] = []

    private var mgHandle: Int64 = -255
    private var hasLoaded = false

    // MARK: Subtype tables (mond: selected_st_value / st_to_sel)

    var selectedSTValue: Int {
        switch selectedST {
        case "og": return ogST
        case "no_dynamic_island": return 0
        case "14p": return 2436
        case "14pm": return 2796
        case "15pm": return 2976
        case "16p": return 2622
        case "16pm": return 2868
        case "air": return 2736
        case "x": return 2436
        default: return 0
        }
    }

    static let stToSelMap: [Int: String] = [0: "no_dynamic_island", 2436: "14p", 2796: "14pm", 2976: "15pm", 2622: "16p", 2868: "16pm", 2736: "air"]

    private var stToSel: [Int: String] { Self.stToSelMap }

    // MARK: Storage (snapshots add-on)

    private var snapshotsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkTweaks/Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var originalBackupURL: URL {
        snapshotsDirectory.appendingPathComponent("original.plist")
    }

    var originalSnapshot: BackupSnapshot? {
        snapshots.first { $0.kind == .original }
    }

    var otherSnapshots: [BackupSnapshot] {
        snapshots.filter { $0.kind != .original }
    }

    // MARK: Grant (mond: unsbx.swift grant_path / grant_mg)

    /// Takes the sandbox extension on the gestalt *directory* exactly like
    /// mond's grant_mg() and holds it for the whole session. The App Group
    /// string is the one the signed app can actually access (see
    /// AppGroupResolver) — mond hardcodes its own group because mond is
    /// installed with its entitlements intact.
    @discardableResult
    func grantMGAccess() -> Bool {
        if mgHandle > 0 { return true }
        grantingMG = true
        defer { grantingMG = false }

        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let handle = worse_query(MGPaths.gestaltDir, AppGroupResolver.resolvedGroup, major == 26, false)
        mgHandle = handle
        mgGranted = handle > 0

        switch handle {
        case -1: print("(wq) failed to access group!")
        case -2: print("(wq) failed to resolve functions!")
        case -3: print("(wq) failed to create query!")
        case -4: print("(wq) failed to create symlink!")
        case -5: print("(wq) query rejected!")
        case -6: print("(wq) kernel refused extension issue!")
        case -255: print("(wq) target doesn't exist!")
        default: print("(wq) granted mg access! handle: \(handle)")
        }
        return handle > 0
    }

    // MARK: Load (mond: mg_load)

    func load() {
        if hasLoaded {
            reloadFromDisk()
            refreshSnapshots()
            return
        }
        guard !isLoading else { return }
        isLoading = true

        guard grantMGAccess() else {
            isLoading = false
            isValid = false
            lastError = "Sandbox extension failed (code \(mgHandle)). Run App Group Diagnostics in the Sandbox tab."
            refreshSnapshots()
            return
        }

        let gestaltURL = URL(fileURLWithPath: MGPaths.gestalt)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: gestaltURL.path))?[.size] as? UInt64 ?? 0
                let loaded = try NSMutableDictionary(contentsOf: gestaltURL, error: ())

                // mond: cache gestalt into a safe place (SavedGestalt.plist)
                let savedURL = MGPaths.savedGestaltURL
                if !FileManager.default.fileExists(atPath: savedURL.path) {
                    try FileManager.default.copyItem(at: gestaltURL, to: savedURL)
                }

                let savedDict = try NSMutableDictionary(contentsOf: savedURL, error: ())
                let ogExtra = savedDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
                let ogArtwork = ogExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
                guard let ogSubtype = ogArtwork["ArtworkDeviceSubType"] as? Int else {
                    throw NSError(domain: "mg", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get ArtworkDeviceSubType!"])
                }
                guard let ogDeviceName = ogArtwork["ArtworkDeviceProductDescription"] as? String else {
                    throw NSError(domain: "mg", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get ArtworkDeviceProductDescription!"])
                }

                let extra = loaded["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
                let artwork = extra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
                let newSelected = GestaltManager.stToSelMap[artwork["ArtworkDeviceSubType"] as? Int ?? ogSubtype] ?? "og"
                let newDeviceName = artwork["ArtworkDeviceProductDescription"] as? String ?? ogDeviceName
                let newProductType: String
                if let pt = extra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String, !pt.isEmpty {
                    newProductType = pt
                } else {
                    newProductType = machineName()
                }

                // WorkTweaks add-on: first successful load also seeds the
                // Backup tab's original snapshot.
                let snapshotsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("WorkTweaks/Backups", isDirectory: true)
                try? FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
                let ogSnapshotURL = snapshotsDir.appendingPathComponent("original.plist")
                if !FileManager.default.fileExists(atPath: ogSnapshotURL.path),
                   let data = try? Data(contentsOf: gestaltURL) {
                    try? data.write(to: ogSnapshotURL, options: .atomic)
                    print("[WorkTweaks] Original backup saved.")
                }

                DispatchQueue.main.async {
                    self.dictNow = loaded
                    self.ogST = ogSubtype
                    self.selectedST = newSelected
                    self.deviceName = newDeviceName
                    self.enableDeviceName = newDeviceName != ogDeviceName
                    self.productType = newProductType
                    self.isValid = true
                    self.isEmpty = fileSize == 0
                    self.isLoading = false
                    self.hasLoaded = true
                    self.lastError = nil
                    self.dictVersion += 1
                    self.refreshSnapshots()
                }
            } catch {
                DispatchQueue.main.async {
                    print("(mg) failed to load data: \(error)")
                    self.isValid = false
                    self.isEmpty = (try? FileManager.default.attributesOfItem(atPath: gestaltURL.path))?[.size] as? UInt64 == 0
                    self.isLoading = false
                    self.lastError = "Failed to load current MobileGestalt! \(error.localizedDescription)"
                    self.refreshSnapshots()
                }
            }
        }
    }

    /// mond: mg_reload — re-read the on-disk plist into dictNow, and
    /// re-derive the artwork/product state from it.
    func reloadFromDisk() {
        guard let dict = try? NSMutableDictionary(contentsOf: URL(fileURLWithPath: MGPaths.gestalt), error: ()) else { return }
        dictNow = dict
        deriveArtworkState(from: dict)
        dictVersion += 1
    }

    private func deriveArtworkState(from dict: NSMutableDictionary) {
        let extra = dict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
        let artwork = extra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
        if let subtype = artwork["ArtworkDeviceSubType"] as? Int {
            selectedST = stToSel[subtype] ?? "og"
        }
        if let name = artwork["ArtworkDeviceProductDescription"] as? String {
            deviceName = name
        }
        if let pt = extra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String, !pt.isEmpty {
            productType = pt
        }
    }

    // MARK: Toggles (mond: mg_tweak_binding)

    func toggleBinding(for tweak: GestaltTweak) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self else { return false }
                _ = self.dictVersion
                return tweak.isOn(in: self.dictNow)
            },
            set: { [weak self] enabled in
                guard let self else { return }
                if let error = tweak.canApply(self.dictNow) {
                    self.notice = "Cannot apply \(tweak.title): \(error)"
                    print("(mg) cannot apply \(tweak.title): \(error)")
                    return
                }
                if enabled {
                    tweak.writeOn(self.dictNow)
                } else {
                    tweak.writeOff(self.dictNow)
                }
                self.dictVersion += 1
            }
        )
    }

    // MARK: Raw CacheExtra editing (Extra tab)

    /// The live CacheExtra dictionary inside dictNow (same in-memory
    /// model as the toggles: edits are staged until Apply writes them).
    var cacheExtra: NSMutableDictionary? {
        dictNow["CacheExtra"] as? NSMutableDictionary
    }

    func setExtraValue(_ value: Any, forKey key: String) {
        guard let extra = cacheExtra else { return }
        extra[key] = value
        dictVersion += 1
        print("(extra) set \(key) = \(PlistValue.describe(value))")
    }

    func removeExtraKey(_ key: String) {
        guard let extra = cacheExtra else { return }
        extra.removeObject(forKey: key)
        dictVersion += 1
        print("(extra) removed \(key)")
    }

    func isOn(_ tweak: GestaltTweak) -> Bool {
        _ = dictVersion
        return tweak.isOn(in: dictNow)
    }

    // MARK: Apply (mond: mg_apply)

    func apply() {
        do {
            let extra = dictNow["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            dictNow["CacheExtra"] = extra

            // mond: product type spoofing
            if !productType.isEmpty {
                extra["h9jDsbgj7xIVeIQ8S3/X3Q"] = productType
            }

            // mond: device artwork (subtype + optional custom device name)
            let artwork = extra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            extra["oPeik/9e8lQWMszEjbPzng"] = artwork
            artwork["ArtworkDeviceSubType"] = selectedSTValue
            if enableDeviceName {
                artwork["ArtworkDeviceProductDescription"] = deviceName
            }

            // mond serializes as XML.
            let data = try PropertyListSerialization.data(fromPropertyList: dictNow, format: .xml, options: 0)
            try mgWrite(data)
            reloadFromDisk()
            enableDeviceName = false

            // WorkTweaks add-on: automatic backup of the state this
            // Apply just produced — the "After Apply Tweaks" snapshot.
            if let written = try? Data(contentsOf: URL(fileURLWithPath: MGPaths.gestalt)) {
                _ = try? saveSnapshot(kind: .afterApply, data: written)
            }

            print("(mg) successfully overwrote mobilegestalt!")
            lastError = nil
            refreshSnapshots()
            // The user chooses: some tweaks (especially Apple
            // Intelligence) need a full restart, not just a respring —
            // the Tweaks tab presents the Respring / Restart choice.
            showPostApplyChoice = true
        } catch {
            print("(mg) failed to apply mobilegestalt: \(error)")
            lastError = error.localizedDescription
        }
    }

    // MARK: Revert (mond: mg_revert)

    func revert() {
        do {
            let backupData = try Data(contentsOf: MGPaths.savedGestaltURL)
            try mgWrite(backupData)
            reloadFromDisk()
            print("(mg) successfully reverted mobilegestalt!")
            lastError = nil
            refreshSnapshots()
            requireRestart()
        } catch {
            print("(mg) failed to revert mobilegestalt: \(error)")
            lastError = error.localizedDescription
        }
    }

    // MARK: Restart attempt (post-Apply choice)

    /// Attempt a full device restart via FrontBoard's system service.
    ///
    /// Honest by design: stock iOS gives apps no public restart API, so
    /// this only fires when the private service actually responds to a
    /// restart selector. Either way the user gets a popup — "command
    /// sent" plus a 10-second honesty check (if the app is still alive
    /// then, the restart did NOT happen), or an immediate failure popup.
    /// Both failure paths include the manual restart steps.
    func attemptRestart() {
        _ = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW)

        var invoked = false
        if let serviceClass = NSClassFromString("FBSSystemService"),
           let sharedMethod = class_getClassMethod(serviceClass, NSSelectorFromString("sharedService")) {
            typealias SharedFactory = @convention(c) (AnyObject, Selector) -> AnyObject
            let factory = unsafeBitCast(method_getImplementation(sharedMethod), to: SharedFactory.self)
            let service = factory(serviceClass, NSSelectorFromString("sharedService"))
            for name in ["reboot", "restart", "shutdown"] {
                let sel = NSSelectorFromString(name)
                if service.responds(to: sel) {
                    _ = service.perform(sel)
                    invoked = true
                    print("(restart) invoked FBSSystemService.\(name)")
                    break
                }
            }
        }

        let manualSteps = "Restart manually: press Volume Up, then Volume Down, then hold the Side button until the Apple logo appears — or go to Settings > General > Shut Down, slide to power off, then turn the device back on."

        if invoked {
            restartAlertTitle = "Restart Command Sent"
            restartAlertMessage = "Your device should restart within a few seconds. If you're still seeing this after 10 seconds, the restart did not actually happen.\n\n\(manualSteps)"
            restartCheckItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.restartAlertTitle != nil else { return }
                self.restartAlertTitle = "Restart Failed"
                self.restartAlertMessage = "The device did not restart, so the automatic restart failed — iOS does not give apps a reliable way to restart the device.\n\n\(manualSteps)"
                print("(restart) still alive after 10s — restart did not happen")
            }
            restartCheckItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
        } else {
            restartAlertTitle = "Restart Failed"
            restartAlertMessage = "Automatic restart isn't available on this device — iOS does not give apps a way to restart the device directly.\n\n\(manualSteps)\n\nNote: some tweaks (especially Apple Intelligence) only take effect after a full restart, not a respring."
            print("(restart) no restart selector available — honest failure")
        }
    }

    // MARK: Restart required (Revert / Restore)

    /// Revert and Backup restores used to auto-respring; per the user
    /// they now require a full restart. This just raises the flag — the
    /// Tweaks / Backup views present the Restart Required dialog, whose
    /// Restart Device button runs attemptRestart().
    private func requireRestart() {
        print("[WorkTweaks] Changes saved - a full restart is required.")
        showRestartRequired = true
    }

    // MARK: mg_write (mond, verbatim logic)

    func mgWrite(_ data: Data) throws {
        let path = MGPaths.gestalt

        if UserDefaults.standard.bool(forKey: "atomic_write") {
            try mgWriteInPlace(data, to: path)
        } else {
            let targetURL = URL(fileURLWithPath: path)
            let tempURL = targetURL.deletingLastPathComponent()
                .appendingPathComponent(".\(targetURL.lastPathComponent).\(UUID().uuidString).tmp")

            try data.write(to: tempURL, options: [.withoutOverwriting])
            defer { try? FileManager.default.removeItem(at: tempURL) }

            if FileManager.default.fileExists(atPath: targetURL.path) {
                _ = try FileManager.default.replaceItemAt(targetURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: targetURL)
            }
        }
    }

    private func mgWriteInPlace(_ data: Data, to path: String) throws {
        let og = try Data(contentsOf: URL(fileURLWithPath: path))

        let fd = path.withCString {
            open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        }
        guard fd >= 0 else {
            throw MGWriteError.open(errno: errno)
        }
        defer { close(fd) }

        do {
            guard ftruncate(fd, 0) == 0 else {
                throw MGWriteError.truncate(errno: errno)
            }
            try writeAll(fd, data)
            guard fsync(fd) == 0 else {
                throw MGWriteError.sync(errno: errno)
            }
            guard lseek(fd, 0, SEEK_SET) >= 0 else {
                throw MGWriteError.verificationFailed
            }
            let verify = try readAll(fd)
            guard verify == data else {
                throw MGWriteError.verificationFailed
            }
        } catch {
            if ftruncate(fd, 0) == 0,
               lseek(fd, 0, SEEK_SET) >= 0 {
                _ = try? writeAll(fd, og)
                _ = fsync(fd)
            }
            throw error
        }
    }

    private func readAll(_ fd: Int32) throws -> Data {
        var res = Data()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let count = buf.withUnsafeMutableBytes { rawBuffer in
                read(fd, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count > 0 {
                res.append(buf, count: count)
                continue
            }
            if count == 0 {
                return res
            }
            if errno == EINTR {
                continue
            }
            throw MGWriteError.verificationFailed
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) throws {
        guard !data.isEmpty else { return }

        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                throw MGWriteError.write(errno: EFAULT)
            }
            var offset = 0
            while offset < data.count {
                let res = write(fd, base.advanced(by: offset), data.count - offset)
                if res > 0 {
                    offset += res
                    continue
                }
                if res < 0 && errno == EINTR {
                    continue
                }
                throw MGWriteError.write(errno: errno)
            }
        }
    }

    // MARK: Snapshots (WorkTweaks add-on)

    private func saveSnapshot(kind: BackupSnapshot.Kind, data: Data) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name: String
        switch kind {
        case .original: name = "original.plist"
        case .afterApply: name = "afterapply-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).plist"
        case .manual: name = "manual-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).plist"
        }
        let url = snapshotsDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func createManualSnapshot() {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: MGPaths.gestalt))
            _ = try saveSnapshot(kind: .manual, data: data)
            lastError = nil
            refreshSnapshots()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshSnapshots() {
        let files = (try? FileManager.default.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        snapshots = files
            .filter { $0.pathExtension == "plist" }
            .compactMap { makeSnapshot(url: $0) }
            .sorted { $0.date > $1.date }
    }

    private func makeSnapshot(url: URL) -> BackupSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary,
              let extra = parsed["CacheExtra"] as? [String: Any] else {
            return nil
        }
        let root = NSMutableDictionary(dictionary: parsed)

        let name = url.lastPathComponent
        let kind: BackupSnapshot.Kind
        let date: Date
        if name == "original.plist" {
            kind = .original
            date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date ?? Date()
        } else if name.hasPrefix("afterapply-") || name.hasPrefix("preapply-") {
            // "preapply-" is the legacy prefix from before the rename;
            // those snapshots stay listed under the same kind.
            kind = .afterApply
            date = parseSnapshotDate(name) ?? Date()
        } else {
            kind = .manual
            date = parseSnapshotDate(name) ?? Date()
        }

        let enabledIDs = Set(TweakCatalog.all.filter { $0.read(root) }.map(\.id))
        var entries: [BackupSnapshot.KeyEntry] = []
        for tweak in TweakCatalog.all {
            for key in tweak.keys {
                entries.append(BackupSnapshot.KeyEntry(
                    key: key,
                    tweakID: tweak.id,
                    tweakTitle: tweak.title,
                    present: extra[key] != nil,
                    valueDescription: PlistValue.describe(extra[key])
                ))
            }
        }

        return BackupSnapshot(
            id: name,
            kind: kind,
            date: date,
            url: url,
            cacheExtraCount: extra.count,
            enabledTweakIDs: enabledIDs,
            entries: entries
        )
    }

    private func parseSnapshotDate(_ name: String) -> Date? {
        // afterapply-yyyyMMdd-HHmmss-XXXXXX.plist / manual-...
        let parts = name.split(separator: "-")
        guard parts.count >= 3 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: "\(parts[1])-\(parts[2])")
    }

    func deleteSnapshot(_ snapshot: BackupSnapshot) {
        guard snapshot.kind != .original else { return }
        try? FileManager.default.removeItem(at: snapshot.url)
        refreshSnapshots()
    }

    // MARK: Restores (WorkTweaks add-on, writing through mg_write)

    func restore(_ snapshot: BackupSnapshot) {
        do {
            let data = try Data(contentsOf: snapshot.url)
            try mgWrite(data)
            print("[WorkTweaks] Restored backup \(snapshot.id).")
            reloadFromDisk()
            lastError = nil
            requireRestart()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restoreTweak(_ tweak: GestaltTweak, from snapshot: BackupSnapshot) {
        restoreKeys(tweak.keys, from: snapshot)
    }

    func restoreKey(_ entry: BackupSnapshot.KeyEntry, from snapshot: BackupSnapshot) {
        restoreKeys([entry.key], from: snapshot)
    }

    private func restoreKeys(_ keys: [String], from snapshot: BackupSnapshot) {
        guard !keys.isEmpty else {
            notice = "This tweak patches CacheData directly; restore the whole snapshot instead."
            return
        }
        do {
            guard let snapshotRoot = try PropertyListSerialization.propertyList(from: Data(contentsOf: snapshot.url), options: [], format: nil) as? NSDictionary,
                  let snapshotExtra = snapshotRoot["CacheExtra"] as? NSDictionary else {
                throw MGWriteError.invalidPlist
            }

            let working = NSMutableDictionary(dictionary: dictNow)
            let extra = (working["CacheExtra"] as? NSMutableDictionary) ?? NSMutableDictionary()
            working["CacheExtra"] = extra

            for key in keys {
                if let value = snapshotExtra[key] {
                    extra[key] = value
                } else {
                    extra.removeObject(forKey: key)
                }
            }

            let data = try PropertyListSerialization.data(fromPropertyList: working, format: .xml, options: 0)
            try mgWrite(data)
            reloadFromDisk()
            lastError = nil
            print("[WorkTweaks] Restored \(keys.count) key(s) from \(snapshot.id).")
            requireRestart()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
