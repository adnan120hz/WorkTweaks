import Foundation
import Combine
import SQLite3
import Darwin

// MARK: - Battery & thermal (read-only)
//
// Reads the system powerlog database and shows battery health,
// cycle count, temperature and thermal history. READ-ONLY by
// design: the database is never opened in place.
//
// Access follows the app's fork pattern: a sandbox extension is
// consumed on the BatteryLife DIRECTORY through the same
// consumeExtension wrapper every other feature uses, the DB and
// its -wal / -shm sidecars are cloned into our own temp dir
// with clonefile(), and the grant is released before the clone
// is opened. The clone is opened SQLITE_OPEN_READONLY; if the
// probe fails, -shm is deleted and the clone is retried
// READWRITE so WAL replay happens on the private clone only,
// never on the original. Fallback is a plain copyItem.
//
// Fail-safe, like the rest of the app: a refused grant or an
// unreadable database produces an honest blocked state with
// the real result code, and nothing is written anywhere.
// Some iOS 26 firmware restricts the powerlog sandbox token;
// iOS 27 reads fully.

struct BatterySample: Identifiable {
    let id = UUID()
    let timestamp: Date?
    let level: Double?
    let rawMaxCapacity: Double?
    let nominalCapacity: Double?
    let designCapacity: Double?
    let cycleCount: Int64?
    let voltage: Double?
    let amperage: Double?
    let temperature: Double?
    let isCharging: Bool?

    /// True health = raw max / design capacity.
    var healthPercent: Double? {
        guard let raw = rawMaxCapacity, let design = designCapacity, design > 0 else { return nil }
        return raw / design * 100
    }

    /// Power in watts (V in mV, A in mA).
    var powerWatts: Double? {
        guard let v = voltage, let a = amperage else { return nil }
        return v * a / 1_000_000
    }
}

struct ThermalEvent: Identifiable {
    let id = UUID()
    let timestamp: Date?
    let level: Int64

    var band: String {
        switch level {
        case ..<1: return "Nominal"
        case 1...10: return "Light"
        case 11...20: return "Moderate"
        case 21...30: return "Heavy"
        default: return "Critical"
        }
    }
}

final class BatteryDiagnostics: ObservableObject {
    static let batteryLifeDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.powerlog/Library/BatteryLife"
    static let databaseName = "CurrentPowerlog.PLSQL"

    enum LoadState {
        case idle
        case loading
        case ready
        case blocked(String)
    }

    @Published var state: LoadState = .idle
    @Published var latest: BatterySample?
    @Published var samples: [BatterySample] = []
    @Published var thermalEvents: [ThermalEvent] = []
    @Published var batteryTableUsed: String?
    @Published var thermalTableUsed: String?
    @Published var isLoading = false

    /// Live thermal state of this process (nominal/fair/serious/critical).
    var liveThermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private var snapshotDir: URL?

    deinit {
        if let dir = snapshotDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: Load

    func load() {
        guard !isLoading else { return }
        isLoading = true
        state = .loading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.performLoad()
            DispatchQueue.main.async { self.isLoading = false }
        }
    }

    private func performLoad() {
        let handle = consumeExtension(Self.batteryLifeDir)
        print("[Battery] grant for \(Self.batteryLifeDir) -> \(handle)")
        guard handle > 0 else {
            finishBlocked("The sandbox extension for the powerlog directory was refused (code \(handle)). Nothing was read or written — the exact grant result is in the Log.")
            return
        }
        defer { releaseExtension(handle) }

        let dbPath = (Self.batteryLifeDir as NSString).appendingPathComponent(Self.databaseName)
        guard FileManager.default.fileExists(atPath: dbPath) else {
            finishBlocked("CurrentPowerlog.PLSQL was not found at \(dbPath). Nothing was read or written.")
            return
        }

        // Snapshot the DB + sidecars into our own temp dir, then
        // release the grant before opening anything.
        guard let clone = snapshotDatabase(dbPath: dbPath) else {
            finishBlocked("The powerlog database could not be cloned for read-only inspection. Nothing was read or written.")
            return
        }
        print("[Battery] snapshot at \(clone.path)")

        var db: OpaquePointer?
        let opened = openDatabase(at: clone, db: &db, readOnly: true)
        guard opened, let db else {
            finishBlocked("The cloned powerlog database could not be opened. Nothing was read or written.")
            return
        }

        // Probe; on failure delete -shm and retry READWRITE on
        // the private clone only (WAL replay on the clone).
        if !probe(db) {
            print("[Battery] readonly probe failed — deleting -shm and retrying read-write on the clone")
            sqlite3_close(db)
            let shm = clone.appendingPathComponent("-shm")
            try? FileManager.default.removeItem(at: shm)
            var db2: OpaquePointer?
            guard openDatabase(at: clone, db: &db2, readOnly: false), let db2 else {
                finishBlocked("The cloned powerlog database failed its probe even after the -shm retry. Nothing was read or written.")
                return
            }
            if !probe(db2) {
                sqlite3_close(db2)
                finishBlocked("The cloned powerlog database failed its probe. Nothing was read or written.")
                return
            }
            readTables(db2)
            sqlite3_close(db2)
            return
        }
        readTables(db)
        sqlite3_close(db)
    }

    private func finishBlocked(_ message: String) {
        print("[Battery] blocked: \(message)")
        DispatchQueue.main.async {
            self.state = .blocked(message)
        }
    }

    // MARK: Snapshot

    /// Clone DB + -wal + -shm into a fresh temp dir. Returns the
    /// cloned DB path, or nil when nothing could be copied.
    private func snapshotDatabase(dbPath: String) -> URL? {
        let fm = FileManager.default
        if let old = snapshotDir {
            try? fm.removeItem(at: old)
            snapshotDir = nil
        }
        let dir = fm.temporaryDirectory.appendingPathComponent("sql_snap_\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[Battery] snapshot dir failed: \(error)")
            return nil
        }
        let dest = dir.appendingPathComponent(Self.databaseName)
        var anyCopied = false
        for suffix in ["", "-wal", "-shm"] {
            let src = dbPath + suffix
            guard fm.fileExists(atPath: src) else { continue }
            let dst = dest.path + suffix
            let ok = cloneFile(src: src, dst: dst) || (try? fm.copyItem(atPath: src, toPath: dst)) != nil
            if ok { anyCopied = true }
        }
        guard anyCopied, fm.fileExists(atPath: dest.path) else {
            try? fm.removeItem(at: dir)
            return nil
        }
        // Private snapshot: owner read/write only.
        _ = try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
        snapshotDir = dir
        return dest
    }

    private func cloneFile(src: String, dst: String) -> Bool {
        src.withCString { s in
            dst.withCString { d in
                wt_clonefile(s, d, 0) == 0
            }
        }
    }

    // MARK: SQLite

    private func openDatabase(at path: URL, db: inout OpaquePointer?, readOnly: Bool) -> Bool {
        let flags = readOnly ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX) : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX)
        let rc = path.path.withCString { sqlite3_open_v2($0, &db, flags, nil) }
        guard rc == SQLITE_OK, db != nil else {
            if let db { sqlite3_close(db) }
            return false
        }
        sqlite3_busy_timeout(db, 1500)
        return true
    }

    private func probe(_ db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master LIMIT 1", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func tableNames(_ db: OpaquePointer) -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table'", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return out
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = columnText(stmt, 0) { out.append(text) }
        }
        return out
    }

    private func columns(of table: String, db: OpaquePointer) -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\"\(table)\")"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return out
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            // PRAGMA table_info: cid, name, type, notnull, dflt_value, pk
            if let text = columnText(stmt, 1) { out.append(text) }
        }
        return out
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let raw = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: UnsafeRawPointer(raw).assumingMemoryBound(to: CChar.self))
    }

    private func columnDouble(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private func columnInt(_ stmt: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, index)
    }

    private func pickColumn(_ candidates: [String], from available: [String]) -> String? {
        let lowered = available.map { $0.lowercased() }
        for candidate in candidates {
            if let idx = lowered.firstIndex(of: candidate.lowercased()) {
                return available[idx]
            }
        }
        return nil
    }

    private func dateFromTimestamp(_ value: Double) -> Date {
        // powerlog timestamps are unix epoch seconds; values
        // far below that are Core Data reference dates.
        value > 1_000_000_000 ? Date(timeIntervalSince1970: value) : Date(timeIntervalSinceReferenceDate: value)
    }

    // MARK: Queries

    private func readTables(_ db: OpaquePointer) {
        let tables = tableNames(db)
        print("[Battery] \(tables.count) table(s) in the clone")
        var foundSamples: [BatterySample] = []
        var foundThermal: [ThermalEvent] = []
        var batteryTable: String?
        var thermalTable: String?

        let batteryCandidates = [
            "PLBatteryAgent_EventBackward_Battery",
            "PLBatteryAgent_EventForward_Battery",
            "PLBatteryAgent_EventBackward_BatteryUI",
        ]
        let batteryTableName = batteryCandidates.first { tables.contains($0) }
            ?? tables.first { $0.contains("PLBatteryAgent") && $0.hasSuffix("_Battery") }
        if let table = batteryTableName {
            batteryTable = table
            foundSamples = queryBatterySamples(table: table, db: db)
            print("[Battery] \(foundSamples.count) sample(s) from \(table)")
        } else {
            print("[Battery] no PLBatteryAgent _Battery table found")
        }

        let thermalCandidates = [
            "PLThermalAgent_EventPoint_ThermalStatus",
            "PLXPCAgent_EventPoint_ThermalLevel",
            "PLThermalMonitorAgent_EventPoint_ThermalLevel",
        ]
        let thermalTableName = thermalCandidates.first { tables.contains($0) }
        if let table = thermalTableName {
            thermalTable = table
            foundThermal = queryThermalEvents(table: table, db: db)
            print("[Battery] \(foundThermal.count) thermal event(s) from \(table)")
        } else {
            print("[Battery] no thermal table found")
        }

        DispatchQueue.main.async {
            self.samples = foundSamples
            self.latest = foundSamples.first
            self.thermalEvents = foundThermal
            self.batteryTableUsed = batteryTable
            self.thermalTableUsed = thermalTable
            self.state = .ready
        }
    }

    private func queryBatterySamples(table: String, db: OpaquePointer) -> [BatterySample] {
        let cols = columns(of: table, db: db)
        let levelCol = pickColumn(["Level", "CurrentCapacity"], from: cols)
        let rawMaxCol = pickColumn(["AppleRawMaxCapacity", "RawMaxCapacity", "MaxCapacity"], from: cols)
        let nominalCol = pickColumn(["NominalChargeCapacity", "MaxCapacity"], from: cols)
        let designCol = pickColumn(["DesignCapacity"], from: cols)
        let cycleCol = pickColumn(["CycleCount"], from: cols)
        let voltageCol = pickColumn(["Voltage"], from: cols)
        let amperageCol = pickColumn(["InstantAmperage", "Amperage"], from: cols)
        let tempCol = pickColumn(["Temperature"], from: cols)
        let chargingCol = pickColumn(["IsCharging"], from: cols)
        let timeCol = pickColumn(["timestamp", "time"], from: cols)

        var select: [String] = []
        if let c = timeCol { select.append("\"\(c)\"") }
        for c in [levelCol, rawMaxCol, nominalCol, designCol, cycleCol, voltageCol, amperageCol, tempCol, chargingCol] {
            if let c { select.append("\"\(c)\"") }
        }
        guard !select.isEmpty else { return [] }
        let order = timeCol != nil ? "\"\(timeCol!)\" DESC" : "rowid DESC"
        let sql = "SELECT \(select.joined(separator: ", ")) FROM \"\(table)\" ORDER BY \(order) LIMIT 25"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            print("[Battery] battery query failed for \(table)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        // Column order mirrors `select`: time first (when present), then the rest in order.
        var out: [BatterySample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var idx: Int32 = 0
            var timestamp: Date?
            if timeCol != nil {
                if let t = columnDouble(stmt, idx) { timestamp = dateFromTimestamp(t) }
                idx += 1
            }
            func nextDouble() -> Double? { defer { idx += 1 }; return columnDouble(stmt, idx) }
            func nextInt() -> Int64? { defer { idx += 1 }; return columnInt(stmt, idx) }
            var level: Double?, rawMax: Double?, nominal: Double?, design: Double?
            var cycle: Int64?, voltage: Double?, amperage: Double?, temp: Double?
            var charging: Bool?
            if levelCol != nil { level = nextDouble() }
            if rawMaxCol != nil { rawMax = nextDouble() }
            if nominalCol != nil { nominal = nextDouble() }
            if designCol != nil { design = nextDouble() }
            if cycleCol != nil { cycle = nextInt() }
            if voltageCol != nil { voltage = nextDouble() }
            if amperageCol != nil { amperage = nextDouble() }
            if tempCol != nil {
                temp = nextDouble()
                if let t = temp, abs(t) > 120 { temp = t / 100 }
            }
            if chargingCol != nil {
                if let v = nextInt() { charging = v != 0 }
            }
            out.append(BatterySample(timestamp: timestamp, level: level, rawMaxCapacity: rawMax, nominalCapacity: nominal, designCapacity: design, cycleCount: cycle, voltage: voltage, amperage: amperage, temperature: temp, isCharging: charging))
        }
        return out
    }

    private func queryThermalEvents(table: String, db: OpaquePointer) -> [ThermalEvent] {
        let cols = columns(of: table, db: db)
        let levelCol = pickColumn(["ThermalLevel", "thermalLevel", "Level", "State"], from: cols)
        let timeCol = pickColumn(["timestamp", "time"], from: cols)
        guard let levelCol else { return [] }
        let order = timeCol != nil ? "\"\(timeCol!)\" DESC" : "rowid DESC"
        var select = "\"\(levelCol)\""
        if let t = timeCol { select = "\"\(t)\", " + select }
        let sql = "SELECT \(select) FROM \"\(table)\" ORDER BY \(order) LIMIT 20"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            print("[Battery] thermal query failed for \(table)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var out: [ThermalEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var idx: Int32 = 0
            var timestamp: Date?
            if timeCol != nil {
                if let t = columnDouble(stmt, idx) { timestamp = dateFromTimestamp(t) }
                idx += 1
            }
            guard let level = columnInt(stmt, idx) else { continue }
            out.append(ThermalEvent(timestamp: timestamp, level: level))
        }
        return out
    }
}
