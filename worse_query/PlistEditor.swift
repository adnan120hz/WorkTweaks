import Foundation
import Combine

// MARK: - Property list editor (engine)
//
// Opens a .plist from App Data as an editable key/type/value
// table. New work — Erosion-CN has a plist viewer, not this
// editor — following the same safety rules as the other
// editors in this app:
//
//  - Top-level scalar values (String, Integer, Real, Bool,
//    Date) are editable; nested dictionaries and arrays are
//    shown read-only with their item count — the editor never
//    rewrites a structure it cannot show.
//  - Data values are shown read-only (base64 prefix + size).
//  - Before the first save, a pristine backup of the original
//    file is taken in the shared AppDataBackups store (the
//    same store the hex editor uses). Saving refuses to
//    proceed without that backup, and writes in place
//    (truncate + write, verified by re-reading).
//
// Every step logs with a [Plist] prefix.

enum PlistValueKind: String, CaseIterable {
    case string = "String"
    case integer = "Integer"
    case real = "Real"
    case bool = "Bool"
    case date = "Date"
    case data = "Data"
    case dictionary = "Dictionary"
    case array = "Array"
}

struct PlistRow: Identifiable, Equatable {
    let id = UUID()
    /// Dictionary key, or the element index for array roots.
    var key: String
    var kind: PlistValueKind
    /// Text representation for scalar kinds; summary for
    /// containers ("Dictionary (3 items)").
    var display: String
    /// The scalar value (String / NSNumber / Date / Data).
    /// Nil for containers.
    var rawValue: Any?
    /// Index in the original array, for array roots — so a
    /// deleted row before a container never shifts the
    /// container onto the wrong element. Nil for added rows.
    var originalIndex: Int?
    var isEditable: Bool { kind == .string || kind == .integer || kind == .real || kind == .bool || kind == .date }

    static func == (lhs: PlistRow, rhs: PlistRow) -> Bool {
        lhs.key == rhs.key && lhs.kind == rhs.kind && lhs.display == rhs.display
    }
}

final class PlistEditor: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case ready
        case blocked(String)
    }

    enum RootKind {
        case dictionary
        case array
    }

    @Published var state: LoadState = .idle
    @Published var rootKind: RootKind = .dictionary
    @Published var rows: [PlistRow] = []
    @Published var isSaving = false
    @Published var saveMessage: String?
    @Published var saveFailed = false

    var filePath: String = ""
    var fileName: String = ""

    private var originalRows: [PlistRow] = []

    var isDirty: Bool { rows != originalRows }

    // MARK: Load

    func open(path: String, name: String) {
        filePath = path
        fileName = name
        state = .loading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.performOpen()
        }
    }

    private func performOpen() {
        print("[Plist] opening \(filePath)")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            finishBlocked("The file could not be read. Nothing was written.")
            return
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            finishBlocked("The file is not a valid property list. Nothing was written.")
            return
        }
        var loaded: [PlistRow] = []
        var kind: RootKind = .dictionary
        if let dict = plist as? [String: Any] {
            kind = .dictionary
            for key in dict.keys.sorted() {
                loaded.append(Self.row(forKey: key, value: dict[key]!))
            }
        } else if let array = plist as? [Any] {
            kind = .array
            for (index, value) in array.enumerated() {
                var row = Self.row(forKey: "\(index)", value: value)
                row.originalIndex = index
                loaded.append(row)
            }
        } else {
            finishBlocked("The property list root is a single scalar value, not a dictionary or array — this editor only edits containers.")
            return
        }
        print("[Plist] loaded \(loaded.count) top-level entr(ies)")
        DispatchQueue.main.async {
            self.rootKind = kind
            self.rows = loaded
            self.originalRows = loaded
            self.state = .ready
        }
    }

    private func finishBlocked(_ message: String) {
        print("[Plist] blocked: \(message)")
        DispatchQueue.main.async { self.state = .blocked(message) }
    }

    // MARK: Row model

    private static func row(forKey key: String, value: Any) -> PlistRow {
        switch value {
        case let s as String:
            return PlistRow(key: key, kind: .string, display: s, rawValue: s)
        case let n as NSNumber:
            // NSNumber bridges Bool too — distinguish by
            // ObjC type: 'c' is a boolean.
            if String(cString: n.objCType) == "c" {
                return PlistRow(key: key, kind: .bool, display: n.boolValue ? "true" : "false", rawValue: n)
            }
            let isInteger = String(cString: n.objCType) != "d" && String(cString: n.objCType) != "f"
            if isInteger {
                return PlistRow(key: key, kind: .integer, display: "\(n.int64Value)", rawValue: n)
            }
            return PlistRow(key: key, kind: .real, display: "\(n.doubleValue)", rawValue: n)
        case let d as Date:
            return PlistRow(key: key, kind: .date, display: ISO8601DateFormatter().string(from: d), rawValue: d)
        case let data as Data:
            let prefix = data.prefix(16).base64EncodedString()
            return PlistRow(key: key, kind: .data, display: "Data (\(data.count) bytes, \(prefix)…)", rawValue: data)
        case let dict as [String: Any]:
            return PlistRow(key: key, kind: .dictionary, display: "Dictionary (\(dict.count) item(s))", rawValue: nil)
        case let array as [Any]:
            return PlistRow(key: key, kind: .array, display: "Array (\(array.count) item(s))", rawValue: nil)
        default:
            return PlistRow(key: key, kind: .string, display: "\(value)", rawValue: "\(value)")
        }
    }

    /// The scalar value for a row, rebuilt from its display
    /// text. Nil for containers.
    private static func scalarValue(kind: PlistValueKind, text: String) -> Any? {
        switch kind {
        case .string: return text
        case .integer: return NSNumber(value: Int64(text) ?? 0)
        case .real: return NSNumber(value: Double(text) ?? 0)
        case .bool: return NSNumber(value: ["true", "1", "yes"].contains(text.lowercased()))
        case .date:
            if let date = ISO8601DateFormatter().date(from: text) { return date }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.date(from: text)
        default: return nil
        }
    }

    // MARK: Editing

    /// Apply an edited text to a row. Returns an error
    /// message when the text cannot convert to the row's
    /// type, or nil on success.
    func applyEdit(rowID: UUID, text: String) -> String? {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return "That row is gone." }
        let row = rows[index]
        guard row.isEditable else { return "That value cannot be edited here." }
        switch row.kind {
        case .integer:
            guard Int64(text) != nil else { return "\"\(text)\" is not a whole number." }
        case .real:
            guard Double(text) != nil else { return "\"\(text)\" is not a number." }
        case .bool:
            guard ["true", "false", "1", "0", "yes", "no"].contains(text.lowercased()) else {
                return "Use true or false for a Bool."
            }
        case .date:
            guard Self.scalarValue(kind: .date, text: text) != nil else {
                return "Use an ISO date (e.g. 2026-11-24T15:30:00Z) or yyyy-MM-dd HH:mm:ss."
            }
        default:
            break
        }
        rows[index].display = text
        rows[index].rawValue = Self.scalarValue(kind: row.kind, text: text)
        return nil
    }

    /// Add a row. Dictionary roots need a unique key; array
    /// roots append at the end. Returns an error message or
    /// nil on success.
    func addRow(key: String, kind: PlistValueKind, text: String) -> String? {
        switch rootKind {
        case .dictionary:
            let trimmed = key.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return "A key name is required." }
            guard !rows.contains(where: { $0.key == trimmed }) else { return "A key named \"\(trimmed)\" already exists." }
            guard kind != .dictionary && kind != .array && kind != .data else {
                return "New rows must be a scalar value (String, Integer, Real, Bool or Date)."
            }
            if let error = validate(kind: kind, text: text) { return error }
            let row = PlistRow(key: trimmed, kind: kind, display: text, rawValue: Self.scalarValue(kind: kind, text: text))
            rows.append(row)
            rows.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            return nil
        case .array:
            guard kind != .dictionary && kind != .array && kind != .data else {
                return "New rows must be a scalar value (String, Integer, Real, Bool or Date)."
            }
            if let error = validate(kind: kind, text: text) { return error }
            let row = PlistRow(key: "\(rows.count)", kind: kind, display: text, rawValue: Self.scalarValue(kind: kind, text: text))
            rows.append(row)
            return nil
        }
    }

    private func validate(kind: PlistValueKind, text: String) -> String? {
        switch kind {
        case .integer:
            return Int64(text) == nil ? "\"\(text)\" is not a whole number." : nil
        case .real:
            return Double(text) == nil ? "\"\(text)\" is not a number." : nil
        case .bool:
            return ["true", "false", "1", "0", "yes", "no"].contains(text.lowercased()) ? nil : "Use true or false for a Bool."
        case .date:
            return Self.scalarValue(kind: .date, text: text) == nil ? "Use an ISO date (e.g. 2026-11-24T15:30:00Z) or yyyy-MM-dd HH:mm:ss." : nil
        default:
            return nil
        }
    }

    func deleteRow(_ row: PlistRow) {
        rows.removeAll { $0.id == row.id }
        if rootKind == .array {
            // Renumber array indices after a deletion.
            for index in rows.indices {
                rows[index].key = "\(index)"
            }
        }
    }

    // MARK: Save

    /// Rebuild the plist from the rows, take a pristine
    /// backup, and write in place (truncate + write,
    /// verified by re-reading).
    func save(manager: AppDataManager) {
        guard !isSaving else { return }
        isSaving = true
        saveMessage = nil
        saveFailed = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.performSave(manager: manager)
            DispatchQueue.main.async {
                self.isSaving = false
                switch result {
                case .success(let message):
                    self.saveMessage = message
                    self.originalRows = self.rows
                    print("[Plist] saved: \(message)")
                case .failure(let error):
                    self.saveMessage = error.message
                    self.saveFailed = true
                    print("[Plist] save failed: \(error.message)")
                }
            }
        }
    }

    private func performSave(manager: AppDataManager) -> Result<String, VaultError> {
        // Rebuild: containers and Data values come from the
        // ORIGINAL plist (they are read-only in the editor),
        // scalars come from the edited rows.
        guard let originalData = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let original = try? PropertyListSerialization.propertyList(from: originalData, options: [], format: nil) else {
            return .failure(VaultError(message: "The original file could not be re-read — nothing was written."))
        }
        let output: Any
        switch rootKind {
        case .dictionary:
            guard var dict = original as? [String: Any] else {
                return .failure(VaultError(message: "The original file changed shape — nothing was written."))
            }
            let editedKeys = Set(rows.map { $0.key })
            for key in dict.keys where !editedKeys.contains(key) {
                dict.removeValue(forKey: key) // deleted rows
            }
            for row in rows {
                if let value = row.rawValue {
                    dict[row.key] = value
                }
            }
            output = dict
        case .array:
            guard let array = original as? [Any] else {
                return .failure(VaultError(message: "The original file changed shape — nothing was written."))
            }
            // Deleted elements are dropped; edited scalars
            // are replaced in place; appended rows are added.
            // Containers are taken from their ORIGINAL index,
            // so a deletion before one never shifts it onto
            // the wrong element.
            var rebuilt: [Any] = []
            for row in rows {
                if let value = row.rawValue {
                    rebuilt.append(value)
                } else if let idx = row.originalIndex, idx < array.count {
                    rebuilt.append(array[idx]) // container, unchanged
                }
            }
            output = rebuilt
        }
        guard let outData = try? PropertyListSerialization.data(fromPropertyList: output, format: .xml, options: 0) else {
            return .failure(VaultError(message: "The edited plist could not be serialized — nothing was written."))
        }
        guard manager.makeHexBackupIfNeeded(path: filePath) else {
            return .failure(VaultError(message: "The backup of the original file couldn't be written, so nothing was saved."))
        }
        guard manager.saveHexData(path: filePath, data: outData) else {
            return .failure(VaultError(message: "Writing the edited plist failed — the original is untouched and the backup is in AppDataBackups."))
        }
        return .success("Saved \(rows.count) top-level entr(ies) to \(fileName). A backup of the original is in AppDataBackups.")
    }
}
