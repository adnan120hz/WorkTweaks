import Foundation
import Combine

// MARK: - Tweak Value

enum TweakValue {
    case int(Int)
    case intArray([Int])
    case string(String)

    var plistValue: Any {
        switch self {
        case .int(let v): return v
        case .intArray(let v): return v
        case .string(let v): return v
        }
    }

    func matches(_ any: Any?) -> Bool {
        switch self {
        case .int(let v):
            return (any as? NSNumber)?.intValue == v
        case .intArray(let v):
            guard let arr = any as? [Int] else { return false }
            return arr == v
        case .string(let v):
            return any as? String == v
        }
    }

    static func describe(_ any: Any?) -> String {
        guard let any else { return "—" }
        if let number = any as? NSNumber { return number.stringValue }
        if let string = any as? String { return string }
        if let array = any as? [Any] {
            return "[" + array.map { describe($0) }.joined(separator: ", ") + "]"
        }
        return String(describing: any)
    }
}

// MARK: - Tweak Model

struct GestaltTweak: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let keys: [String]
    let value: TweakValue
    let warning: String?
    /// Custom-value tweaks (Subtype, Device Spoofing) carry a user-chosen
    /// value instead of a fixed one. `value` is then just the default.
    var isCustomValue: Bool = false
}

enum TweakCatalog {
    static let all: [GestaltTweak] = [
        .init(id: "dynamic_island_subtype",
              title: "Dynamic Island Subtype",
              subtitle: "Choose the Dynamic Island device subtype",
              systemImage: "capsule.portrait",
              keys: ["ArtworkDeviceSubType"],
              value: .int(2556),
              warning: "Common values: 2556 (Pro) or 2796 (Pro Max).",
              isCustomValue: true),

        .init(id: "device_spoofing",
              title: "Device Spoofing",
              subtitle: "Spoof the device ProductType",
              systemImage: "iphone.gen3",
              keys: ["h9jDsbgj7xIVeIQ8S3/X3Q"],
              value: .string("iPhone16,2"),
              warning: "High risk. Can affect Face ID, iCloud and other hardware features.",
              isCustomValue: true),

        .init(id: "dynamic_island",
              title: "Dynamic Island",
              subtitle: "Enable Dynamic Island capability",
              systemImage: "capsule",
              keys: ["YlEtTtHlNesRBMal1CqRaA"],
              value: .int(1),
              warning: "Alternate way to enable Dynamic Island, as used by Nugget."),

        .init(id: "aod",
              title: "Always-On Display",
              subtitle: "Enable Always-On Display",
              systemImage: "moon.stars",
              keys: ["2OOJf1VhaM7NxfRok3HbWQ", "j8/Omm6s1lsmTDFsXjsBfA"],
              value: .int(1),
              warning: "Can increase screen burn-in risk on unsupported devices."),

        .init(id: "aod_vibrancy",
              title: "AOD Vibrancy",
              subtitle: "Fix incorrect Always-On Display rendering",
              systemImage: "sparkles",
              keys: ["ykpu7qyhqFweVMKtxNylWA"],
              value: .int(1),
              warning: "Turn on if AOD renders incorrectly."),

        .init(id: "no_parallax",
              title: "Disable Wallpaper Parallax",
              subtitle: "Stop wallpaper from moving when tilting",
              systemImage: "photo",
              keys: ["UIParallaxCapability"],
              value: .int(0),
              warning: nil),

        .init(id: "charge_limit",
              title: "Charge Limit Menu",
              subtitle: "Reveal charging limit settings",
              systemImage: "battery.75",
              keys: ["37NVydb//GP/GrhuTN+exg"],
              value: .int(1),
              warning: "Actual limit depends on hardware."),

        .init(id: "chime",
              title: "Boot & Shutdown Chime",
              subtitle: "Add power on/off sound",
              systemImage: "speaker.wave.2",
              keys: ["QHxt+hGLaBPbQJbXiUJX3w"],
              value: .int(1),
              warning: nil),

        .init(id: "camera_control",
              title: "Camera Control Settings",
              subtitle: "Expose Camera Control options",
              systemImage: "camera",
              keys: ["CwvKxM2cEogD3p+HYgaW0Q", "oOV1jhJbdV3AddkcCg0AEA"],
              value: .int(1),
              warning: nil),

        .init(id: "action_button",
              title: "Action Button Settings",
              subtitle: "Reveal Action Button configuration",
              systemImage: "button.programmable",
              keys: ["cT44WE1EohiwRzhsZ8xEsw"],
              value: .int(1),
              warning: nil),

        .init(id: "collision_sos",
              title: "Collision SOS",
              subtitle: "Reveal collision detection options",
              systemImage: "car.side.rear.and.collision.and.car.side.front",
              keys: ["HCzWusHQwZDea6nNhaKndw"],
              value: .int(1),
              warning: nil),

        .init(id: "tap_to_wake",
              title: "Tap to Wake",
              subtitle: "Enable tap-to-wake on supported devices",
              systemImage: "hand.tap",
              keys: ["yZf3GTRMGTuwSV/lD7Cagw"],
              value: .int(1),
              warning: "Meant for devices like iPhone SE."),

        .init(id: "pencil",
              title: "Apple Pencil Settings",
              subtitle: "Reveal Apple Pencil settings page",
              systemImage: "pencil.tip",
              keys: ["yhHcB0iH0d1XzPO/CFd3ow"],
              value: .int(1),
              warning: nil),

        .init(id: "stage_manager",
              title: "Stage Manager",
              subtitle: "Flag device as Stage Manager capable",
              systemImage: "rectangle.3.group",
              keys: ["qeaj75wk3HF4DwQ8qbIi7g"],
              value: .int(1),
              warning: nil),

        .init(id: "ipad_apps",
              title: "Allow iPad Apps",
              subtitle: "Install iPad apps on iPhone",
              systemImage: "apps.ipad",
              keys: ["9MZ5AdH43csAUajl/dU+IQ"],
              value: .intArray([1, 2]),
              warning: nil)
    ]

    static func tweak(id: String) -> GestaltTweak? {
        all.first { $0.id == id }
    }
}

// MARK: - Backup Snapshot

struct BackupSnapshot: Identifiable {
    enum Kind: String {
        case original
        case preApply = "pre-apply"
        case manual

        var label: String {
            switch self {
            case .original: return "Original"
            case .preApply: return "Before Apply"
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

    /// Filename inside the Backups folder.
    let id: String
    let kind: Kind
    let date: Date
    let url: URL
    /// Total number of keys inside CacheExtra, not just tweak keys.
    let cacheExtraCount: Int
    /// Tweaks whose value was fully present when this snapshot was taken.
    let enabledTweakIDs: Set<String>
    /// One entry per tweak key, in catalog order.
    let entries: [KeyEntry]
}

// MARK: - Manager

@MainActor
final class GestaltManager: ObservableObject {
    static let shared = GestaltManager()

    @Published var enabled: Set<String> = []
    /// User-chosen values for custom-value tweaks, by tweak id.
    @Published var customValues: [String: TweakValue] = [:]
    @Published var snapshots: [BackupSnapshot] = []
    @Published var isLoading = false
    @Published var isValid = false
    @Published var lastError: String?

    private let gestaltPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

    // MARK: Storage

    private var backupsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkTweaks/Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var originalBackupURL: URL {
        backupsDirectory.appendingPathComponent("original.plist")
    }

    var originalSnapshot: BackupSnapshot? {
        snapshots.first { $0.kind == .original }
    }

    var otherSnapshots: [BackupSnapshot] {
        snapshots.filter { $0.kind != .original }
    }

    // MARK: Load

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try readCurrentData()

            // The very first successful read becomes the original backup.
            // It is the source for per-key restores, so never overwrite it.
            if !FileManager.default.fileExists(atPath: originalBackupURL.path) {
                try data.write(to: originalBackupURL, options: .atomic)
                print("[WorkTweaks] Original backup saved.")
            }

            guard let extra = try parseRoot(data)?["CacheExtra"] as? [String: Any] else {
                throw GestaltError.invalidPlist
            }

            var detected: Set<String> = []
            for tweak in TweakCatalog.all {
                if tweak.isCustomValue, let key = tweak.keys.first, let raw = extra[key] {
                    // A custom-value tweak counts as ON when its key exists
                    // with the right type; adopt the on-device value so the
                    // picker / text field shows what the device really has.
                    switch tweak.value {
                    case .int:
                        if let number = raw as? NSNumber {
                            detected.insert(tweak.id)
                            customValues[tweak.id] = .int(number.intValue)
                        }
                    case .string:
                        if let string = raw as? String {
                            detected.insert(tweak.id)
                            customValues[tweak.id] = .string(string)
                        }
                    case .intArray:
                        break
                    }
                } else if tweak.keys.allSatisfy({ key in tweak.value.matches(extra[key]) }) {
                    detected.insert(tweak.id)
                }
            }
            enabled = detected

            isValid = true
            lastError = nil
        } catch {
            isValid = false
            lastError = error.localizedDescription
        }
        refreshSnapshots()
    }

    // MARK: Toggle (in-memory until Apply)

    func set(_ tweak: GestaltTweak, enabled: Bool) {
        if enabled {
            self.enabled.insert(tweak.id)
            if tweak.isCustomValue && customValues[tweak.id] == nil {
                customValues[tweak.id] = tweak.value
            }
        } else {
            self.enabled.remove(tweak.id)
        }
    }

    func effectiveValue(for tweak: GestaltTweak) -> TweakValue {
        customValues[tweak.id] ?? tweak.value
    }

    func updateValue(for tweakID: String, value: TweakValue) {
        customValues[tweakID] = value
    }

    // MARK: Auto-respring

    private var pendingRespring: DispatchWorkItem?

    /// Every successful write (Apply, Revert, or any Backup restore)
    /// schedules an automatic respring about 2 seconds later, because
    /// gestalt changes only take effect once SpringBoard restarts.
    /// Scheduling again cancels the pending respring, so several quick
    /// restores in a row coalesce into a single one.
    private func scheduleRespring() {
        pendingRespring?.cancel()
        print("[WorkTweaks] Changes saved - auto-respring in 2 seconds...")
        let item = DispatchWorkItem {
            if !respringDevice() {
                print("[WorkTweaks] Auto-respring unavailable on this iOS - please reboot manually to apply the changes.")
            }
        }
        pendingRespring = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    // MARK: Apply

    /// Applies the current toggle selection.
    ///
    /// Before writing anything, the *current* on-device plist is saved as a
    /// pre-apply snapshot — that snapshot is what the Backup tab shows, so the
    /// exact state at apply time can always be restored afterwards.
    ///
    /// Turning a tweak OFF restores each of its keys from the original
    /// backup: a key that existed originally gets its original value back,
    /// a key that did not exist is removed.
    func apply() {
        do {
            let currentData = try readCurrentData()
            _ = try saveSnapshot(kind: .preApply, data: currentData)

            guard var root = try parseRoot(currentData) else {
                throw GestaltError.invalidPlist
            }
            var extra = (root["CacheExtra"] as? [String: Any]) ?? [:]
            let original = originalCacheExtra() ?? [:]

            for tweak in TweakCatalog.all {
                if enabled.contains(tweak.id) {
                    let valueToApply = effectiveValue(for: tweak)
                    for key in tweak.keys {
                        extra[key] = valueToApply.plistValue
                    }
                } else {
                    for key in tweak.keys {
                        if let originalValue = original[key] {
                            extra[key] = originalValue
                        } else {
                            extra.removeValue(forKey: key)
                        }
                    }
                }
            }

            root["CacheExtra"] = extra
            try writeRoot(root)

            // Verify against ground truth: re-read the file that was just
            // written and confirm each enabled tweak's value is really in
            // there. (A respring/reboot is still needed before the system
            // acts on the new values.)
            do {
                let verifyData = try readCurrentData()
                if let verifyExtra = try parseRoot(verifyData)?["CacheExtra"] as? [String: Any] {
                    for tweak in TweakCatalog.all where enabled.contains(tweak.id) {
                        let expected = effectiveValue(for: tweak)
                        let ok = tweak.keys.allSatisfy { expected.matches(verifyExtra[$0]) }
                        print("[WorkTweaks] \(tweak.title): \(ok ? "OK - value confirmed in MobileGestalt.plist" : "NOT FOUND in file after write!")")
                    }
                }
            } catch {
                print("[WorkTweaks] Post-apply verification failed: \(error.localizedDescription)")
            }

            lastError = nil
            print("[WorkTweaks] Tweaks applied. Pre-apply snapshot saved.")
            scheduleRespring()
        } catch {
            lastError = error.localizedDescription
        }
        refreshSnapshots()
    }

    // MARK: Snapshots

    @discardableResult
    private func saveSnapshot(kind: BackupSnapshot.Kind, data: Data) throws -> URL {
        switch kind {
        case .original:
            if !FileManager.default.fileExists(atPath: originalBackupURL.path) {
                try data.write(to: originalBackupURL, options: .atomic)
            }
            return originalBackupURL
        case .preApply, .manual:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = formatter.string(from: Date())
            var url = backupsDirectory.appendingPathComponent("\(kind.rawValue)-\(stamp).plist")
            var counter = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = backupsDirectory.appendingPathComponent("\(kind.rawValue)-\(stamp)-\(counter).plist")
                counter += 1
            }
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    /// Captures the current on-device state on demand, from the Backup tab.
    func createManualSnapshot() {
        do {
            let data = try readCurrentData()
            _ = try saveSnapshot(kind: .manual, data: data)
            lastError = nil
            print("[WorkTweaks] Manual backup saved.")
        } catch {
            lastError = error.localizedDescription
        }
        refreshSnapshots()
    }

    func refreshSnapshots() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        snapshots = files
            .filter { $0.pathExtension == "plist" }
            .compactMap { makeSnapshot(url: $0) }
            .sorted { a, b in
                if a.kind == .original { return true }
                if b.kind == .original { return false }
                return a.date > b.date
            }
    }

    private func makeSnapshot(url: URL) -> BackupSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let root = try? parseRoot(data),
              let extra = root["CacheExtra"] as? [String: Any] else {
            return nil
        }

        let name = url.lastPathComponent
        let kind: BackupSnapshot.Kind
        let date: Date
        if name == "original.plist" {
            kind = .original
            date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date ?? Date.distantPast
        } else if name.hasPrefix(BackupSnapshot.Kind.preApply.rawValue) {
            kind = .preApply
            date = parseSnapshotDate(name) ?? Date.distantPast
        } else {
            kind = .manual
            date = parseSnapshotDate(name) ?? Date.distantPast
        }

        var entries: [BackupSnapshot.KeyEntry] = []
        var enabledIDs: Set<String> = []
        for tweak in TweakCatalog.all {
            var fullyOn = true
            for key in tweak.keys {
                let present = extra[key] != nil
                if !tweak.value.matches(extra[key]) { fullyOn = false }
                entries.append(.init(
                    key: key,
                    tweakID: tweak.id,
                    tweakTitle: tweak.title,
                    present: present,
                    valueDescription: TweakValue.describe(extra[key])
                ))
            }
            if fullyOn { enabledIDs.insert(tweak.id) }
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

    private func parseSnapshotDate(_ filename: String) -> Date? {
        // Filenames look like: pre-apply-yyyyMMdd-HHmmss(-n).plist
        guard let regex = try? NSRegularExpression(pattern: #"\d{8}-\d{6}"#),
              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
              let range = Range(match.range, in: filename) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: String(filename[range]))
    }

    func deleteSnapshot(_ snapshot: BackupSnapshot) {
        guard snapshot.kind != .original else { return }
        try? FileManager.default.removeItem(at: snapshot.url)
        refreshSnapshots()
    }

    // MARK: Restore — whole snapshot

    func restore(_ snapshot: BackupSnapshot) {
        do {
            let data = try Data(contentsOf: snapshot.url)
            try withExtension { url in
                try data.write(to: url, options: .atomic)
            }
            print("[WorkTweaks] Restored backup \(snapshot.id).")
            load()
            scheduleRespring()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Restores the original backup in full.
    func revert() {
        guard let original = originalSnapshot else { return }
        restore(original)
    }

    // MARK: Restore — per tweak / per key

    /// Restores only one tweak's keys from the given snapshot. A key that is
    /// absent in the snapshot is removed from the device, matching the
    /// snapshot exactly.
    func restoreTweak(_ tweak: GestaltTweak, from snapshot: BackupSnapshot) {
        restoreKeys(tweak.keys, from: snapshot)
    }

    /// Restores a single key from the given snapshot.
    func restoreKey(_ entry: BackupSnapshot.KeyEntry, from snapshot: BackupSnapshot) {
        restoreKeys([entry.key], from: snapshot)
    }

    private func restoreKeys(_ keys: [String], from snapshot: BackupSnapshot) {
        do {
            guard let snapshotRoot = try parseRoot(try Data(contentsOf: snapshot.url)),
                  let snapshotExtra = snapshotRoot["CacheExtra"] as? [String: Any] else {
                throw GestaltError.invalidPlist
            }

            let currentData = try readCurrentData()
            guard var root = try parseRoot(currentData) else {
                throw GestaltError.invalidPlist
            }
            var extra = (root["CacheExtra"] as? [String: Any]) ?? [:]

            for key in keys {
                if let value = snapshotExtra[key] {
                    extra[key] = value
                } else {
                    extra.removeValue(forKey: key)
                }
            }

            root["CacheExtra"] = extra
            try writeRoot(root)
            lastError = nil
            print("[WorkTweaks] Restored \(keys.count) key(s) from \(snapshot.id).")
            load()
            scheduleRespring()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Plist plumbing

    private func originalCacheExtra() -> [String: Any]? {
        guard let data = try? Data(contentsOf: originalBackupURL),
              let root = try? parseRoot(data) else { return nil }
        return root["CacheExtra"] as? [String: Any]
    }

    private func parseRoot(_ data: Data) throws -> [String: Any]? {
        try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    private func readCurrentData() throws -> Data {
        try withExtension { try Data(contentsOf: $0) }
    }

    private func writeRoot(_ root: [String: Any]) throws {
        let out = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try withExtension { url in
            try out.write(to: url, options: .atomic)
        }
    }

    // MARK: Sandbox Extension

    private func withExtension<T>(_ body: (URL) throws -> T) throws -> T {
        let handle = worse_query(gestaltPath, AppGroupResolver.resolvedGroup, false, false)
        guard handle > 0 else { throw GestaltError.sandboxFailed(handle) }
        defer { worse_query_release(handle) }
        return try body(URL(fileURLWithPath: gestaltPath))
    }
}

enum GestaltError: LocalizedError {
    case sandboxFailed(Int64)
    case invalidPlist

    var errorDescription: String? {
        switch self {
        case .sandboxFailed(let code):
            if code == -1 {
                return "Sandbox extension failed (code -1): no accessible App Group. Run App Group Diagnostics in the Sandbox tab, or set the exact group your signer assigned there."
            }
            return "Sandbox extension failed (code \(code))."
        case .invalidPlist:
            return "MobileGestalt.plist is invalid or missing CacheExtra."
        }
    }
}
