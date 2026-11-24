import Foundation
import Combine
import SQLite3
import Darwin

// MARK: - SQLite table editor (engine)
//
// Opens a .sqlite/.db file from App Data as editable tables.
// New work — Erosion-CN has no SQLite editor, only read-only
// snapshots — following the same snapshot rules as the
// Battery page:
//
//  - The database is never opened in place. It is cloned
//    (clonefile, copyItem fallback) with its -wal / -shm
//    sidecars into a private temp dir, and the clone is what
//    SQLite opens — read-write, since this is an editor.
//  - A WAL-lock check runs first: a -wal modified within 10
//    seconds means the owning app is still writing — the
//    editor refuses to open, like the Save Vault's hard
//    block. Close the target app first.
//  - Before the first save, a pristine backup of the original
//    file is taken in the shared AppDataBackups store (the
//    same store the hex editor uses — see AppDataManager).
//    Saving refuses to proceed without that backup.
//  - Saving applies the edits to the clone through SQLite,
//    then writes the clone back over the original in place
//    (truncate + write, verified by re-reading) and deletes
//    the original's stale -wal / -shm, which belong to the
//    old generation and must never replay over the new file.
//
// Every step logs with a [SQLite] prefix. At most 200 rows
// per table are loaded — save-game databases can be large,
// and the editor is for targeted edits, not bulk dumps.

struct SQLiteColumn: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let notNull: Bool
    let isPrimaryKey: Bool

    /// SQLite type affinity, from the declared type.
    var affinity: String {
        let t = type.uppercased()
        if t.contains("INT") { return "INTEGER" }
        if t.contains("CHAR") || t.contains("CLOB") || t.contains("TEXT") { return "TEXT" }
        if t.contains("BLOB") || t.isEmpty { return "BLOB" }
        if t.contains("REAL") || t.contains("FLOA") || t.contains("DOUB") { return "REAL" }
        return "NUMERIC"
    }

    var isEditable: Bool { affinity != "BLOB" }
}

struct SQLiteCell: Equatable {
    /// Text representation of the value; nil when NULL.
    var text: String?
    var isNull: Bool { text == nil }
    /// True for BLOB values, which the editor shows but
    /// never lets the user change.
    var isBlob: Bool = false
    var blobSize: Int = 0

    var display: String {
        if let text { return text }
        if isBlob { return "<blob \(blobSize) bytes>" }
        return "NULL"
    }
}

struct SQLiteTableRow: Identifiable, Equatable {
    let id = UUID()
    let rowid: Int64
    /// One cell per column, in column order.
    var values: [SQLiteCell]
}

final class SQLiteDatabaseEditor: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case ready
        case blocked(String)
    }

    static let rowLimit = 200

    @Published var state: LoadState = .idle
    @Published var tables: [String] = []
    @Published var selectedTable: String?
    @Published var columns: [SQLiteColumn] = []
    @Published var rows: [SQLiteTableRow] = []
    @Published var totalRowCount: Int64 = 0
    @Published var isSaving = false
    @Published var saveMessage: String?
    @Published var saveFailed = false

    var filePath: String = ""
    var fileName: String = ""

    private var db: OpaquePointer?
    private var snapshotDir: URL?
    private var clonePath: URL?
    private var originalRows: [SQLiteTableRow] = []

    var isDirty: Bool { rows != originalRows }

    deinit {
        closeDatabase()
        if let dir = snapshotDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: Open

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
        print("[SQLite] opening \(filePath)")

        // WAL-lock check on the file itself and on the
        // container (same 10 s rule as the Save Vault).
        if let wal = activeWALFile() {
            finishBlocked("The database is still being written (\(wal)). Close the owning app first, wait a few seconds, then open it again. Nothing was changed.")
            return
        }
        if let container = Self.containerRoot(ofFilePath: filePath) {
            let wal = SaveVaultManager.activeWALFiles(containerPath: container)
            if !wal.isEmpty {
                finishBlocked("The owning app is still writing its database (\(wal.count) active WAL file(s)). Close it first, wait a few seconds, then open again. Nothing was changed.")
                return
            }
        }

        guard let clone = snapshotDatabase() else {
            finishBlocked("The database could not be cloned for editing. Nothing was read or written.")
            return
        }
        clonePath = clone
        print("[SQLite] editing clone at \(clone.path)")

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        let rc = clone.path.withCString { sqlite3_open_v2($0, &handle, flags, nil) }
        guard rc == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            finishBlocked("The cloned database could not be opened for editing. Nothing was read or written.")
            return
        }
        db = handle
        sqlite3_busy_timeout(handle, 1500)
        if !probe(handle) {
            print("[SQLite] probe failed — deleting -shm and retrying on the clone")
            sqlite3_close(handle)
            db = nil
            let shm = clone.appendingPathComponent("-shm")
            try? FileManager.default.removeItem(at: shm)
            var handle2: OpaquePointer?
            let rc2 = clone.path.withCString { sqlite3_open_v2($0, &handle2, flags, nil) }
            guard rc2 == SQLITE_OK, let handle2, probe(handle2) else {
                if let handle2 { sqlite3_close(handle2) }
                finishBlocked("The cloned database failed its probe. Nothing was read or written.")
                return
            }
            db = handle2
            sqlite3_busy_timeout(handle2, 1500)
        }

        let found = tableNames(handle: db!)
        print("[SQLite] \(found.count) table(s)")
        DispatchQueue.main.async {
            self.tables = found
            self.state = .ready
            if let first = found.first {
                self.selectTable(first)
            }
        }
    }

    private func finishBlocked(_ message: String) {
        print("[SQLite] blocked: \(message)")
        DispatchQueue.main.async { self.state = .blocked(message) }
    }

    // MARK: Snapshot

    /// Clone DB + -wal + -shm into a fresh temp dir. Returns
    /// the cloned DB path, or nil when nothing could be copied.
    private func snapshotDatabase() -> URL? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("sql_edit_\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[SQLite] snapshot dir failed: \(error)")
            return nil
        }
        let dest = dir.appendingPathComponent((filePath as NSString).lastPathComponent)
        var anyCopied = false
        for suffix in ["", "-wal", "-shm"] {
            let src = filePath + suffix
            guard fm.fileExists(atPath: src) else { continue }
            let dst = dest.path + suffix
            let ok = SaveVaultManager.cloneFile(src: src, dst: dst) || (try? fm.copyItem(atPath: src, toPath: dst)) != nil
            if ok { anyCopied = true }
        }
        guard anyCopied, fm.fileExists(atPath: dest.path) else {
            try? fm.removeItem(at: dir)
            return nil
        }
        _ = try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
        snapshotDir = dir
        return dest
    }

    /// The file's own -wal / -shm, when one was modified
    /// within the last 10 seconds — the owning app is still
    /// writing. Nil otherwise.
    private func activeWALFile() -> String? {
        let now = Date().timeIntervalSince1970
        for suffix in ["-wal", "-shm"] {
            let path = filePath + suffix
            var st = stat()
            guard lstat(path, &st) == 0 else { continue }
            let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
            if now - mtime <= 10 { return path }
        }
        return nil
    }

    /// The app container root for a file under
    /// /var/mobile/Containers/Data/Application/<UUID>/…,
    /// or nil when the path is not in a container.
    static func containerRoot(ofFilePath path: String) -> String? {
        let marker = "/Containers/Data/Application/"
        guard let range = path.range(of: marker) else { return nil }
        let after = path[range.upperBound...]
        guard let slash = after.firstIndex(of: "/") else { return nil }
        return String(path[path.startIndex..<slash])
    }

    // MARK: SQLite helpers

    private func probe(_ handle: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT name FROM sqlite_master LIMIT 1", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func tableNames(handle: OpaquePointer) -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return out
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = columnText(stmt, 0) { out.append(text) }
        }
        return out
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let raw = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: UnsafeRawPointer(raw).assumingMemoryBound(to: CChar.self))
    }

    private func closeDatabase() {
        if let handle = db {
            sqlite3_close(handle)
            db = nil
        }
    }

    // MARK: Tables & rows

    func selectTable(_ name: String) {
        guard let handle = db else { return }
        selectedTable = name
        var cols: [SQLiteColumn] = []
        var stmt: OpaquePointer?
        let pragma = "PRAGMA table_info(\"\(name)\")"
        if sqlite3_prepare_v2(handle, pragma, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let colName = columnText(stmt, 1) ?? ""
                let colType = columnText(stmt, 2) ?? ""
                let notNull = sqlite3_column_int(stmt, 3) != 0
                let pk = sqlite3_column_int(stmt, 5) != 0
                cols.append(SQLiteColumn(name: colName, type: colType, notNull: notNull, isPrimaryKey: pk))
            }
        }
        columns = cols
        totalRowCount = rowCount(handle: handle, table: name)
        loadRows(handle: handle, table: name, columns: cols)
    }

    private func rowCount(handle: OpaquePointer, table: String) -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM \"\(table)\"", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(stmt, 0)
    }

    private func loadRows(handle: OpaquePointer, table: String, columns: [SQLiteColumn]) {
        var out: [SQLiteTableRow] = []
        guard !columns.isEmpty else {
            rows = []
            originalRows = []
            return
        }
        let select = columns.map { "\"\($0.name)\"" }.joined(separator: ", ")
        let sql = "SELECT rowid, \(select) FROM \"\(table)\" ORDER BY rowid LIMIT \(Self.rowLimit)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            print("[SQLite] row query failed for \(table)")
            rows = []
            originalRows = []
            return
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            var values: [SQLiteCell] = []
            for i in 0..<columns.count {
                let idx = Int32(i + 1)
                switch sqlite3_column_type(stmt, idx) {
                case SQLITE_NULL:
                    values.append(SQLiteCell(text: nil))
                case SQLITE_INTEGER:
                    values.append(SQLiteCell(text: String(sqlite3_column_int64(stmt, idx))))
                case SQLITE_FLOAT:
                    values.append(SQLiteCell(text: String(sqlite3_column_double(stmt, idx))))
                case SQLITE_BLOB:
                    let bytes = sqlite3_column_bytes(stmt, idx)
                    values.append(SQLiteCell(text: nil, isBlob: true, blobSize: Int(bytes)))
                default:
                    values.append(SQLiteCell(text: columnText(stmt, idx)))
                }
            }
            out.append(SQLiteTableRow(rowid: rowid, values: values))
        }
        rows = out
        originalRows = out
        print("[SQLite] \(out.count) row(s) from \(table) (total \(totalRowCount))")
    }

    /// The cell's value as loaded, for the changed highlight
    /// in the view. Nil when the row is gone (e.g. after an
    /// add/delete reload).
    func originalCell(rowid: Int64, colIndex: Int) -> SQLiteCell? {
        guard let row = originalRows.first(where: { $0.rowid == rowid }),
              colIndex < row.values.count else { return nil }
        return row.values[colIndex]
    }

    // MARK: Editing

    func addRow() {
        guard let handle = db, let table = selectedTable else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO \"\(table)\" DEFAULT VALUES"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            print("[SQLite] add row failed for \(table)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            print("[SQLite] add row step failed for \(table)")
            return
        }
        print("[SQLite] added a row to \(table)")
        selectTable(table)
    }

    func deleteRow(_ row: SQLiteTableRow) {
        guard let handle = db, let table = selectedTable else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM \"\(table)\" WHERE rowid = ?"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            print("[SQLite] delete prepare failed for \(table)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, row.rowid)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            print("[SQLite] delete step failed for \(table)")
            return
        }
        print("[SQLite] deleted row \(row.rowid) from \(table)")
        selectTable(table)
    }

    /// Apply the in-memory edits to the clone through SQLite,
    /// then write the clone back over the original (after a
    /// pristine backup). Runs off the main thread.
    func save(manager: AppDataManager) {
        guard let handle = db, let table = selectedTable, !isSaving else { return }
        isSaving = true
        saveMessage = nil
        saveFailed = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.performSave(handle: handle, table: table, manager: manager)
            DispatchQueue.main.async {
                self.isSaving = false
                switch result {
                case .success(let message):
                    self.saveMessage = message
                    self.originalRows = self.rows
                    print("[SQLite] saved: \(message)")
                case .failure(let error):
                    self.saveMessage = error.message
                    self.saveFailed = true
                    print("[SQLite] save failed: \(error.message)")
                }
            }
        }
    }

    private func performSave(handle: OpaquePointer, table: String, manager: AppDataManager) -> Result<String, VaultError> {
        // Diff in-memory rows against the loaded snapshot.
        let originalByID = Dictionary(uniqueKeysWithValues: originalRows.map { ($0.rowid, $0) })
        var updates: [(rowid: Int64, column: SQLiteColumn, cell: SQLiteCell)] = []
        for row in rows {
            guard let original = originalByID[row.rowid] else { continue }
            for (index, column) in columns.enumerated() {
                guard column.isEditable else { continue }
                if row.values[index] != original.values[index] {
                    updates.append((rowid: row.rowid, column: column, cell: row.values[index]))
                }
            }
        }
        guard !updates.isEmpty else {
            return .success("Nothing changed — nothing was written.")
        }

        // Apply the edits to the clone through SQLite.
        for update in updates {
            var stmt: OpaquePointer?
            let sql = "UPDATE \"\(table)\" SET \"\(update.column.name)\" = ? WHERE rowid = ?"
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                return .failure(VaultError(message: "The UPDATE for \(update.column.name) could not be prepared — nothing was written."))
            }
            defer { sqlite3_finalize(stmt) }
            if let bindError = bindCell(stmt, index: 1, column: update.column, cell: update.cell) {
                return .failure(VaultError(message: bindError))
            }
            sqlite3_bind_int64(stmt, 2, update.rowid)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                return .failure(VaultError(message: "The UPDATE for \(update.column.name) failed — nothing was written."))
            }
        }
        print("[SQLite] applied \(updates.count) cell edit(s) to the clone")

        // Pristine backup before the first save — refuse to
        // proceed without it.
        guard manager.makeHexBackupIfNeeded(path: filePath) else {
            return .failure(VaultError(message: "The backup of the original file couldn't be written, so nothing was saved."))
        }
        // Write the clone back over the original in place
        // (truncate + write, verified by re-reading).
        guard let clone = clonePath,
              let cloneData = try? Data(contentsOf: clone),
              manager.saveHexData(path: filePath, data: cloneData) else {
            return .failure(VaultError(message: "Writing the edited database back failed — the original is untouched and the backup is in AppDataBackups."))
        }
        // The original's -wal / -shm belong to the old
        // generation and must never replay over the new file.
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: filePath + suffix)
        }
        return .success("Saved \(updates.count) edited cell(s) to \(fileName). A backup of the original is in AppDataBackups.")
    }

    /// Bind one edited cell. Returns an error message when
    /// the text cannot convert to the column's affinity.
    private func bindCell(_ stmt: OpaquePointer, index: Int32, column: SQLiteColumn, cell: SQLiteCell) -> String? {
        if cell.text == nil {
            sqlite3_bind_null(stmt, index)
            return nil
        }
        let text = cell.text!
        switch column.affinity {
        case "INTEGER":
            guard let value = Int64(text) else {
                return "\"\(text)\" is not an integer — \(column.name) needs a whole number."
            }
            sqlite3_bind_int64(stmt, index, value)
        case "REAL":
            guard let value = Double(text) else {
                return "\"\(text)\" is not a number — \(column.name) needs a number."
            }
            sqlite3_bind_double(stmt, index, value)
        default:
            text.withCString { ptr in
                sqlite3_bind_text(stmt, index, ptr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
        return nil
    }
}
