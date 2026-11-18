import Foundation

// MARK: - Status Bar overrides (v6.1)
//
// The iOS 27+ `StatusBarOverrides.archive` writer, implemented here
// from the documented archive format (the record SpringBoard
// unarchives itself). This is WorkTweaks' own implementation of
// the format — it does not copy another project's file.
//
//     _SBSystemStatusStatusBarOverridesArchiveRecord
//       +-- statusBarData : STStatusBarData
//       |     +-- cellularEntry          : STStatusBarDataCellularEntry
//       |     +-- secondaryCellularEntry : STStatusBarDataCellularEntry
//       +-- suppressedBackgroundActivityIdentifiers : NSSet (empty)
//
// Lives in **HomeDomain** at `/Library/SpringBoard/StatusBarOverrides.archive`,
// so it rides the ordinary backup restore (iOS 26 partial restore path).
//
// Scope (iOS 27+): only the carrier **name**, its **service badge**,
// its **signal-bar count** (`displayValue`) and fixed network type
// survive. Time/date/battery/wifi overrides and the per-item
// toggles are not offered on iOS 27+.
//
// Failure mode is safe: when the record decodes empty, SpringBoard
// removes the file itself and the stock carrier names come back.

/// One override field: whether it is set, its text, and its
/// numeric value (for bars / network type).
struct StatusBarField {
    var set: Bool = false
    var text: String = ""
    var value: Int = 0
}

/// The user's Status Bar overrides (primary + secondary SIM).
struct StatusBarOverrides {
    var carrierName = StatusBarField()
    var secondaryCarrierName = StatusBarField()
    var serviceBadge = StatusBarField()
    var secondaryServiceBadge = StatusBarField()
    var signalBars = StatusBarField()
    var secondarySignalBars = StatusBarField()
    var dataNetworkType = StatusBarField()
    var secondaryDataNetworkType = StatusBarField()

    /// True when at least one override is set.
    var hasAny: Bool {
        carrierName.set || secondaryCarrierName.set
            || serviceBadge.set || secondaryServiceBadge.set
            || signalBars.set || secondarySignalBars.set
            || dataNetworkType.set || secondaryDataNetworkType.set
    }
}

/// Fixed network-type labels (the values SpringBoard draws).
/// The numbers are the `type` values in the cellular entry.
enum StatusBarNetworkType {
    static let options: [(value: Int, label: String)] = [
        (0, "—"),
        (4, "3G"),
        (5, "4G"),
        (7, "4G+"),
        (8, "LTE"),
        (9, "LTE+"),
        (10, "5G"),
        (11, "5G+"),
        (12, "5G Ultra / UWB"),
        (13, "5G UC"),
    ]

    static func label(for value: Int) -> String {
        options.first { $0.value == value }?.label ?? "—"
    }
}

// MARK: - Keyed-archiver classes (own types, archived names registered)

/// One `STStatusBarDataCellularEntry`. Declared at top level on
/// purpose: a keyed archiver resolves `$classname` through
/// `NSStringFromClass`, which traps on a nested or file-private
/// class. The *archived* name is registered explicitly in
/// `StatusBarArchiveBuilder.build`, so nothing about the
/// device-visible name comes from these Swift types.
final class WTStatusBarCellularEntry: NSObject, NSCoding {
    var string: String?
    var crossfadeString: String?
    var badgeString: String?
    var displayValue: Int?
    var networkType: Int

    init(string: String?, badge: String?, displayValue: Int?, networkType: Int = 0) {
        self.string = string
        self.crossfadeString = string
        self.badgeString = badge
        self.displayValue = displayValue
        self.networkType = networkType
    }

    convenience init(coder: NSCoder) {
        self.init(string: nil, badge: nil, displayValue: nil)
        if coder.containsValue(forKey: "string") {
            string = coder.decodeObject(forKey: "string") as? String
        }
        if coder.containsValue(forKey: "crossfadeString") {
            crossfadeString = coder.decodeObject(forKey: "crossfadeString") as? String
        }
        if coder.containsValue(forKey: "badgeString") {
            badgeString = coder.decodeObject(forKey: "badgeString") as? String
        }
        networkType = coder.decodeInteger(forKey: "type")
        if coder.containsValue(forKey: "displayValue") {
            displayValue = coder.decodeInteger(forKey: "displayValue")
        }
    }

    private static let ownKeys: Set<String> = [
        "string", "crossfadeString", "badgeString", "displayValue", "type",
    ]

    func encode(with coder: NSCoder) {
        for (key, entry) in StatusBarArchiveBuilder.entryDefaults where !Self.ownKeys.contains(key) {
            switch entry {
            case .null: coder.encode(nil, forKey: key)
            case .value(let wrapped): coder.encode(wrapped, forKey: key)
            }
        }
        if let string { coder.encode(string, forKey: "string") }
        if let string { coder.encode(string, forKey: "crossfadeString") }
        if let badgeString { coder.encode(badgeString, forKey: "badgeString") }
        if let displayValue { coder.encode(displayValue, forKey: "displayValue") }
        coder.encode(networkType, forKey: "type")
    }
}

/// `STStatusBarData` — the two carrier entries, either optional.
final class WTStatusBarData: NSObject, NSCoding {
    var cellularEntry: WTStatusBarCellularEntry?
    var secondaryCellularEntry: WTStatusBarCellularEntry?

    init(cellularEntry: WTStatusBarCellularEntry?, secondaryCellularEntry: WTStatusBarCellularEntry?) {
        self.cellularEntry = cellularEntry
        self.secondaryCellularEntry = secondaryCellularEntry
    }

    convenience init(coder: NSCoder) {
        self.init(cellularEntry: nil, secondaryCellularEntry: nil)
        if coder.containsValue(forKey: "cellularEntry") {
            cellularEntry = coder.decodeObject(of: WTStatusBarCellularEntry.self, forKey: "cellularEntry")
        }
        if coder.containsValue(forKey: "secondaryCellularEntry") {
            secondaryCellularEntry = coder.decodeObject(of: WTStatusBarCellularEntry.self, forKey: "secondaryCellularEntry")
        }
    }

    func encode(with coder: NSCoder) {
        if let cellularEntry { coder.encode(cellularEntry, forKey: "cellularEntry") }
        if let secondaryCellularEntry { coder.encode(secondaryCellularEntry, forKey: "secondaryCellularEntry") }
    }
}

/// The root record.
final class WTStatusBarRecord: NSObject, NSCoding {
    let data: WTStatusBarData

    init(data: WTStatusBarData) { self.data = data }

    convenience init(coder: NSCoder) {
        self.init(data: coder.decodeObject(of: WTStatusBarData.self, forKey: "statusBarData")
            ?? WTStatusBarData(cellularEntry: nil, secondaryCellularEntry: nil))
    }

    func encode(with coder: NSCoder) {
        coder.encode(data, forKey: "statusBarData")
        coder.encode(NSSet(), forKey: "suppressedBackgroundActivityIdentifiers")
    }
}

// MARK: - Builder

enum StatusBarArchiveBuilder {
    /// HomeDomain path, relative to `/var/mobile`.
    static let relativePath = "/Library/SpringBoard/StatusBarOverrides.archive"
    static let domain = "HomeDomain"

    static let maxCarrierLength = 64
    static let maxBadgeLength = 8
    static let maxBars = 5

    static let recordClassName = "_SBSystemStatusStatusBarOverridesArchiveRecord"
    static let dataClassName = "STStatusBarData"
    static let cellularClassName = "STStatusBarDataCellularEntry"

    /// One entry field, distinguishing "archiver null" from a real value.
    enum EntryValue {
        case null
        case value(Any)
    }

    /// Fixed cellular-entry values. `status` 5 is "connected" and
    /// `enabled` true is what makes the entry render at all.
    static let entryDefaults: [String: EntryValue] = [
        "badgeString": .null,
        "callForwardingEnabled": .value(false),
        "displayRawValue": .value(0),
        "enabled": .value(true),
        "isBootstrapCellular": .value(false),
        "lowDataModeActive": .value(false),
        "numberSharingState": .value(0),
        "rawValue": .value(0),
        "showsSOSWhenDisabled": .value(false),
        "sosAvailable": .value(false),
        "status": .value(5),
        "suffixString": .null,
        "type": .value(0),
        "wifiCallingEnabled": .value(false),
    ]

    /// Build the archive payload. With no carrier names this returns
    /// the **reset** record: a structurally valid archive whose
    /// status-bar data carries no cellular entries, which SpringBoard
    /// decodes as "no overrides" and then unlinks.
    static func build(_ overrides: StatusBarOverrides) throws -> Data {
        let primary = truncate(overrides.carrierName, max: maxCarrierLength)
        let secondary = truncate(overrides.secondaryCarrierName, max: maxCarrierLength)

        var primaryEntry: WTStatusBarCellularEntry?
        if let primary {
            primaryEntry = WTStatusBarCellularEntry(
                string: primary,
                badge: truncateBadge(overrides.serviceBadge.text),
                displayValue: clampBars(overrides.signalBars.set ? overrides.signalBars.value : nil),
                networkType: overrides.dataNetworkType.set ? max(0, min(30, overrides.dataNetworkType.value)) : 0)
        }
        var secondaryEntry: WTStatusBarCellularEntry?
        if let secondary {
            secondaryEntry = WTStatusBarCellularEntry(
                string: secondary,
                badge: truncateBadge(overrides.secondaryServiceBadge.text),
                displayValue: clampBars(overrides.secondarySignalBars.set ? overrides.secondarySignalBars.value : nil),
                networkType: overrides.secondaryDataNetworkType.set ? max(0, min(30, overrides.secondaryDataNetworkType.value)) : 0)
        }

        let record = WTStatusBarRecord(data: WTStatusBarData(
            cellularEntry: primaryEntry,
            secondaryCellularEntry: secondaryEntry))

        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName(recordClassName, for: WTStatusBarRecord.self)
        archiver.setClassName(dataClassName, for: WTStatusBarData.self)
        archiver.setClassName(cellularClassName, for: WTStatusBarCellularEntry.self)
        archiver.encode(record, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func truncate(_ field: StatusBarField, max: Int) -> String? {
        guard field.set else { return nil }
        let cut = String(field.text.prefix(max))
        return cut.isEmpty ? "" : cut
    }

    private static func truncateBadge(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(trimmed.prefix(maxBadgeLength))
        return cut.isEmpty ? nil : cut
    }

    private static func clampBars(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return max(0, min(maxBars, value))
    }
}

// MARK: - SpringBoard plist overrides (v6.1)

/// SpringBoard plist keys written by the partial restore.
/// `com.apple.springboard.plist` lives in HomeDomain at
/// `/Library/Preferences/com.apple.springboard.plist`.
/// `SBSuppressDynamicIslandCompletely` lives in the managed
/// domain `com.apple.springboard.plist` under
/// `/var/Managed Preferences/mobile/` (ManagedPreferencesDomain).
enum SpringBoardOverrides {
    /// HomeDomain path for com.apple.springboard.plist.
    static let springboardPlistPath = "/Library/Preferences/com.apple.springboard.plist"
    static let springboardDomain = "HomeDomain"

    /// ManagedPreferencesDomain path for the managed springboard plist.
    static let managedSpringboardPath = "/mobile/com.apple.springboard.plist"
    static let managedDomain = "ManagedPreferencesDomain"

    /// Show the battery percentage in the status bar.
    /// Key: `SBShowBatteryPercentage` (Bool).
    static func batteryPercentagePlist(show: Bool) -> Data {
        let plist: [String: Any] = ["SBShowBatteryPercentage": show]
        return (try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0)) ?? Data()
    }

    /// Disable the Dynamic Island system completely.
    /// Key: `SBSuppressDynamicIslandCompletely` (Bool, set = 1).
    /// Domain: managed com.apple.springboard.plist.
    static func suppressDynamicIslandPlist(suppress: Bool) -> Data {
        let plist: [String: Any] = ["SBSuppressDynamicIslandCompletely": suppress]
        return (try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0)) ?? Data()
    }
}
