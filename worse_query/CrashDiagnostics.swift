import Foundation
import Combine
import Darwin

// MARK: - Jetsam & crash diagnostics
//
// Lists the diagnostic reports iOS writes when it kills or
// crashes an app, and deletes them to free space. Read-only
// except for the explicit Clean All action, which deletes
// ONLY the listed report files.
//
// Access follows the app's fork pattern: a sandbox extension
// is consumed on the DiagnosticReports DIRECTORY through the
// same consumeExtension wrapper every other feature uses.
// The grant is taken per operation and released afterwards.
// Writability is checked on the directory itself: when the
// grant does not include write access the page shows
// read-only mode and Clean All stays disabled.
//
// Fail-safe, like the rest of the app: a refused grant
// produces an honest blocked state with the real result
// code, and nothing outside the listed report files is
// ever touched.

enum CrashKind: String {
    case jetsam = "Jetsam"
    case crash = "Crash"
    case panic = "Panic"
    case generic = "System Event"

    var systemImage: String {
        switch self {
        case .jetsam: return "xmark.octagon.fill"
        case .crash: return "exclamationmark.triangle.fill"
        case .panic: return "bolt.fill"
        case .generic: return "doc.fill"
        }
    }
}

struct CrashReport: Identifiable {
    let id: String
    let path: String
    let fileName: String
    let date: Date
    let size: Int64
    let bugType: String
    let kind: CrashKind
    /// App or process name from the .ips header.
    let title: String
    let subtitle: String
    /// Names of the processes Jetsam killed (first 3).
    let killedNames: [String]
    /// Crash detail: procName / exception / signal / indicator.
    let exceptionDetail: String?
}

final class CrashDiagnostics: ObservableObject {
    static let diagRoot = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.osanalytics/Library/Logs/DiagnosticReports"
    static let retiredSubdir = "Retired"

    enum LoadState {
        case idle
        case loading
        case ready
        case blocked(String)
    }

    @Published var state: LoadState = .idle
    @Published var reports: [CrashReport] = []
    @Published var canWrite = false
    @Published var isLoading = false
    @Published var isCleaning = false
    @Published var lastResult: String?

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
        let handle = consumeExtension(Self.diagRoot)
        print("[Jetsam] grant for \(Self.diagRoot) -> \(handle)")
        guard handle > 0 else {
            finishBlocked("The sandbox extension for the DiagnosticReports directory was refused (code \(handle)). Nothing was read or written — the exact grant result is in the Log.")
            return
        }
        defer { releaseExtension(handle) }

        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.diagRoot) else {
            finishBlocked("DiagnosticReports was not found at \(Self.diagRoot). Nothing was read or written.")
            return
        }
        let writable = fm.isWritableFile(atPath: Self.diagRoot)
        print("[Jetsam] DiagnosticReports writable: \(writable)")

        var found: [CrashReport] = []
        for dir in [Self.diagRoot, (Self.diagRoot as NSString).appendingPathComponent(Self.retiredSubdir)] {
            guard let children = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for child in children {
                let full = (dir as NSString).appendingPathComponent(child)
                guard Self.isReportFile(name: child, path: full) else { continue }
                guard let attrs = try? fm.attributesOfItem(atPath: full),
                      let size = attrs[.size] as? Int64,
                      let date = attrs[.modificationDate] as? Date else { continue }
                if let report = Self.parseReport(at: full, fileName: child, date: date, size: size) {
                    found.append(report)
                }
            }
        }
        found.sort { $0.date > $1.date }
        print("[Jetsam] \(found.count) report(s) listed")
        DispatchQueue.main.async {
            self.reports = found
            self.canWrite = writable
            self.state = .ready
        }
    }

    private func finishBlocked(_ message: String) {
        print("[Jetsam] blocked: \(message)")
        DispatchQueue.main.async {
            self.state = .blocked(message)
        }
    }

    // MARK: Scan

    private static func isReportFile(name: String, path: String) -> Bool {
        guard name.contains(".ips") || name.hasSuffix(".crash") || name.hasSuffix(".panic") else {
            return false
        }
        // Regular files only (lstat check — no symlinks, no dirs).
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFREG
    }

    // MARK: Parse

    /// Read the first 256 KB of a report and parse its JSON
    /// header (line 1) and body. The body may be truncated, so
    /// body fields are best-effort — a header-only parse still
    /// produces a usable row.
    private static func parseReport(at path: String, fileName: String, date: Date, size: Int64) -> CrashReport? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
        guard !head.isEmpty else { return nil }

        var header: [String: Any] = [:]
        var body: [String: Any] = [:]
        if let newline = head.firstIndex(of: 0x0A) {
            let headerData = head[..<newline]
            header = (try? JSONSerialization.jsonObject(with: headerData) as? [String: Any]) ?? [:]
            let bodyData = head[head.index(after: newline)...]
            body = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
        } else {
            header = (try? JSONSerialization.jsonObject(with: head) as? [String: Any]) ?? [:]
        }

        let bugType = (header["bug_type"] as? String)
            ?? (header["bug_type"] as? NSNumber).map { "\($0.intValue)" }
            ?? ""
        let appName = (header["app_name"] as? String)
            ?? (header["name"] as? String)
            ?? fileName

        let isJetsam = bugType == "298" || fileName.contains("JetsamEvent")
        let isPanic = bugType == "210" || fileName.contains("panic")
        let isCrash = bugType == "309" || bugType == "109"

        if isJetsam {
            var killed: [String] = []
            if let largest = body["largestProcess"] as? String, !largest.isEmpty {
                killed.append(largest)
            }
            if let processes = body["processes"] as? [[String: Any]] {
                for proc in processes {
                    if let name = proc["name"] as? String, !name.isEmpty, !killed.contains(name) {
                        killed.append(name)
                    }
                    if killed.count >= 3 { break }
                }
            }
            let subtitle = killed.isEmpty
                ? "Jetsam (out of memory) — no killed process named in the report"
                : "Jetsam killed: \(killed.joined(separator: ", "))"
            return CrashReport(id: path, path: path, fileName: fileName, date: date, size: size, bugType: bugType, kind: .jetsam, title: "Jetsam event", subtitle: subtitle, killedNames: killed, exceptionDetail: nil)
        }

        if isCrash {
            let procName = body["procName"] as? String ?? appName
            var detailParts: [String] = []
            if let exception = body["exception"] as? [String: Any] {
                if let type = exception["type"] as? String { detailParts.append("Exception: \(type)") }
                if let signal = exception["signal"] as? String { detailParts.append("Signal: \(signal)") }
            }
            if let termination = body["termination"] as? [String: Any],
               let indicator = termination["indicator"] as? String {
                detailParts.append("Termination: \(indicator)")
            }
            return CrashReport(id: path, path: path, fileName: fileName, date: date, size: size, bugType: bugType, kind: .crash, title: procName, subtitle: "Crash (bug_type \(bugType.isEmpty ? "?" : bugType))", killedNames: [], exceptionDetail: detailParts.isEmpty ? nil : detailParts.joined(separator: "\n"))
        }

        if isPanic {
            return CrashReport(id: path, path: path, fileName: fileName, date: date, size: size, bugType: bugType, kind: .panic, title: appName, subtitle: "System / kernel panic or watchdog", killedNames: [], exceptionDetail: nil)
        }

        return CrashReport(id: path, path: path, fileName: fileName, date: date, size: size, bugType: bugType, kind: .generic, title: appName, subtitle: "System event", killedNames: [], exceptionDetail: nil)
    }

    // MARK: Detail preview + share

    /// First 128 KB of the report as text, for the detail sheet.
    func previewText(for report: CrashReport, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = consumeExtension(Self.diagRoot)
            guard handle > 0 else {
                DispatchQueue.main.async { completion("Could not open \(report.fileName) (grant refused, code \(handle)).") }
                return
            }
            defer { releaseExtension(handle) }
            guard let fh = FileHandle(forReadingAtPath: report.path),
                  let data = try? fh.read(upToCount: 128 * 1024) else {
                DispatchQueue.main.async { completion("Could not read \(report.fileName).") }
                return
            }
            try? fh.close()
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// Copy the report into our own temp dir (under a grant) so
    /// the share sheet can export the full file.
    func shareURL(for report: CrashReport, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = consumeExtension(Self.diagRoot)
            guard handle > 0 else {
                print("[Jetsam] share grant refused: \(handle)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            defer { releaseExtension(handle) }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(report.fileName)
            try? FileManager.default.removeItem(at: dest)
            guard (try? FileManager.default.copyItem(atPath: report.path, toPath: dest.path)) != nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(dest) }
        }
    }

    // MARK: Clean All

    /// Delete ONLY the listed report files under
    /// DiagnosticReports + Retired. Keeps the directory
    /// structure and reports count + freed bytes.
    func cleanAll(completion: @escaping (String) -> Void) {
        guard !isCleaning, canWrite else {
            completion("Clean All is not available — the directory is read-only.")
            return
        }
        isCleaning = true
        let targets = reports
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let handle = consumeExtension(Self.diagRoot)
            guard handle > 0 else {
                DispatchQueue.main.async {
                    self.isCleaning = false
                    completion("The sandbox extension was refused (code \(handle)). Nothing was deleted.")
                }
                return
            }
            defer { releaseExtension(handle) }

            var deleted = 0
            var freed: Int64 = 0
            for report in targets {
                do {
                    try FileManager.default.removeItem(atPath: report.path)
                    if !FileManager.default.fileExists(atPath: report.path) {
                        deleted += 1
                        freed += report.size
                    }
                } catch {
                    print("[Jetsam] delete failed for \(report.fileName): \(error)")
                }
            }
            let message = "Deleted \(deleted) report(s), freed \(wtFormatSize(freed)). The folders were kept."
            print("[Jetsam] \(message)")
            DispatchQueue.main.async {
                self.isCleaning = false
                self.lastResult = message
                self.load()
                completion(message)
            }
        }
    }
}
