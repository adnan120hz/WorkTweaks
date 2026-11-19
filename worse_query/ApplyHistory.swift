import Foundation

/// One applied change, recorded for the "All data changed" history
/// (Sandbox → Utilities → All data changed). Every menu that writes
/// something to the device records one entry when its apply / flash
/// succeeds: Tweaks (GestaltManager.apply), Airlift Passcode Themes,
/// Airlift Wallet Cards.
struct ApplyHistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let source: String
    let detail: String
}

/// The apply history, persisted in UserDefaults (newest first when
/// read). Kept to the latest 100 entries so it never grows without
/// bound.
enum ApplyHistory {
    private static let key = "wt.applyHistory"
    private static let maxEntries = 100

    static func record(source: String, detail: String) {
        var list = stored()
        list.insert(ApplyHistoryEntry(id: UUID(), date: Date(), source: source, detail: detail), at: 0)
        if list.count > maxEntries {
            list = Array(list.prefix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func entries() -> [ApplyHistoryEntry] {
        stored()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func stored() -> [ApplyHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ApplyHistoryEntry].self, from: data) else {
            return []
        }
        return list
    }
}
