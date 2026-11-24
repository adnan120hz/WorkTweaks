import Foundation
import Network
import Darwin

// MARK: - Wi-Fi file sharing
//
// A small HTTP file server on the local network, following
// the shape Erosion-CN's WiFiShareServer uses (see License &
// Credits): NWListener, preferred port 8080 with an ephemeral
// fallback, en0 IPv4 auto-detect, HTTP Basic Auth with
// username "worktweaks" and a per-session random 6-digit PIN
// (constant-time check), 64 KB chunked downloads, folder
// .zip download capped at 2 GB, PUT upload streamed to a
// .part file then renamed, never overwrites (collisions
// auto-rename "name 2.ext"), and auto-stop on dismiss or
// background (the view owns the lifecycle).
//
// The served root is this app's own Documents folder —
// SaveVaultBackups, staged vaults and uploads live there —
// so no sandbox extension is needed at all. Nothing outside
// that root is ever served: every requested path is resolved
// under the root and rejected when it escapes it.
//
// Endpoints: GET / (web UI), GET /api/files?path= (list),
// GET /api/download?path= (streaming), GET /api/zip?path=
// (folder as .zip), POST /api/delete?path=, PUT
// /api/upload?path=&name= (streaming PUT). The web UI is a
// small dark page served from a string (well under 1 MB).
// Original Swift code written for WorkTweaks.

final class WiFiShareServer: ObservableObject {
    static let username = "worktweaks"
    static let preferredPort: UInt16 = 8080
    static let folderZipCap: Int64 = 2_147_483_648 // 2 GB

    @Published var isRunning = false
    @Published var addressText = ""
    @Published var pin = ""
    @Published var statusMessage = ""
    @Published var requestLog: [String] = []

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var connStates: [ObjectIdentifier: WiFiConnState] = [:]
    private let queue = DispatchQueue(label: "wt.wifishare", qos: .userInitiated)

    var rootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var rootPath: String { rootURL.path }

    // MARK: Lifecycle

    func start() {
        guard listener == nil else { return }
        let newPin = String(format: "%06d", Int.random(in: 0...999_999))
        queue.async { [weak self] in
            guard let self else { return }
            self.pin = newPin
            do {
                let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.preferredPort)!)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        let port = listener.port?.rawValue ?? 0
                        let ip = Self.localIPv4Address() ?? "?"
                        DispatchQueue.main.async {
                            self.isRunning = true
                            self.addressText = "http://\(ip):\(port)"
                            self.statusMessage = "Serving this app's Documents folder."
                            print("[WiFiShare] listening on \(ip):\(port)")
                        }
                    case .failed(let error):
                        print("[WiFiShare] listener failed: \(error)")
                        DispatchQueue.main.async {
                            self.statusMessage = "The listener failed: \(error.localizedDescription)"
                            self.isRunning = false
                        }
                        self.stop()
                    case .cancelled:
                        DispatchQueue.main.async { self.isRunning = false }
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start(queue: self.queue)
            } catch {
                // Port 8080 taken — fall back to an ephemeral port.
                print("[WiFiShare] port 8080 failed (\(error)) — trying an ephemeral port")
                do {
                    let listener = try NWListener(using: .tcp, on: 0)
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            let port = listener.port?.rawValue ?? 0
                            let ip = Self.localIPv4Address() ?? "?"
                            DispatchQueue.main.async {
                                self.isRunning = true
                                self.addressText = "http://\(ip):\(port)"
                                self.statusMessage = "Port 8080 was busy — serving on an ephemeral port."
                                print("[WiFiShare] listening on \(ip):\(port) (ephemeral)")
                            }
                        case .failed(let error):
                            print("[WiFiShare] ephemeral listener failed: \(error)")
                            DispatchQueue.main.async {
                                self.statusMessage = "The listener failed: \(error.localizedDescription)"
                                self.isRunning = false
                            }
                            self.stop()
                        case .cancelled:
                            DispatchQueue.main.async { self.isRunning = false }
                        default:
                            break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        self?.accept(connection)
                    }
                    listener.start(queue: self.queue)
                } catch {
                    print("[WiFiShare] could not start a listener: \(error)")
                    DispatchQueue.main.async {
                        self.statusMessage = "Could not start the server: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for (_, connection) in self.connections {
                connection.cancel()
            }
            self.connections.removeAll()
            self.connStates.removeAll()
            DispatchQueue.main.async {
                self.isRunning = false
                self.addressText = ""
                print("[WiFiShare] stopped")
            }
        }
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connStates[id] = WiFiConnState()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receiveLoop(connection)
            case .failed, .cancelled:
                self.queue.async { [weak self] in
                    self?.connections.removeValue(forKey: id)
                    self?.connStates.removeValue(forKey: id)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let id = ObjectIdentifier(connection)
            guard let state = self.connStates[id] else {
                // The connection is already being torn down.
                connection.cancel()
                return
            }
            if let data, !data.isEmpty {
                self.processReceived(connection, state: state, data: data)
                // A finished upload/download already closed the
                // connection; only keep receiving while it lives.
                if self.connections[id] != nil && !state.responded {
                    self.receiveLoop(connection)
                }
                return
            }
            if isComplete || error != nil || data == nil {
                self.queue.async { [weak self] in
                    self?.connections.removeValue(forKey: id)
                    self?.connStates.removeValue(forKey: id)
                }
                connection.cancel()
            } else {
                self.receiveLoop(connection)
            }
        }
    }

    // MARK: Request handling

    private func processReceived(_ connection: NWConnection, state: WiFiConnState, data: Data) {
        if state.request == nil {
            state.buffer.append(data)
            guard let headerEnd = state.buffer.range(of: Data([13, 10, 13, 10])) else { return }
            let headerData = state.buffer.subdata(in: state.buffer.startIndex..<headerEnd.lowerBound)
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                sendText(connection, status: 400, text: "Bad request.")
                state.responded = true
                return
            }
            let lines = headerText.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else {
                sendText(connection, status: 400, text: "Bad request.")
                state.responded = true
                return
            }
            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else {
                sendText(connection, status: 400, text: "Bad request.")
                state.responded = true
                return
            }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                if let colon = line.firstIndex(of: ":") {
                    let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    headers[key] = value
                }
            }
            let request = WiFiHTTPRequest(method: String(parts[0]), rawTarget: String(parts[1]), headers: headers)
            state.request = request
            // Body bytes that already arrived with the headers.
            let bodyStart = headerEnd.upperBound
            let pendingBody = state.buffer.subdata(in: bodyStart..<state.buffer.endIndex)
            state.buffer.removeAll()
            if !authorize(request) {
                sendUnauthorized(connection)
                state.responded = true
                return
            }
            if request.method == "PUT" {
                guard let lengthString = request.headers["content-length"],
                      let length = Int(lengthString), length >= 0 else {
                    sendText(connection, status: 411, text: "PUT requires a Content-Length.")
                    state.responded = true
                    return
                }
                state.expectedBody = length
                guard beginUpload(connection, state: state, request: request) else {
                    state.responded = true
                    return
                }
                if !pendingBody.isEmpty {
                    appendUploadBody(connection, state: state, data: pendingBody)
                }
                return
            }
            // GET / POST have no body — answer now.
            handleRequest(connection, state: state, request: request)
            state.responded = true
        } else if state.request?.method == "PUT" {
            appendUploadBody(connection, state: state, data: data)
        }
    }

    private func authorize(_ request: WiFiHTTPRequest) -> Bool {
        guard let auth = request.headers["authorization"],
              auth.hasPrefix("Basic ") else { return false }
        let encoded = String(auth.dropFirst("Basic ".count))
        guard let decoded = Data(base64Encoded: encoded),
              let expected = "Self.username:\(pin)".data(using: .utf8) else { return false }
        return Self.constantTimeEqual(decoded, expected)
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    // MARK: Upload (PUT, streamed to .part)

    private func beginUpload(_ connection: NWConnection, state: WiFiConnState, request: WiFiHTTPRequest) -> Bool {
        let query = Self.queryItems(request.rawTarget)
        guard let dirRel = query["path"] ?? "",
              let name = query["name"]?.removingPercentEncoding,
              !name.isEmpty, !name.contains("/"), name != ".", name != "..",
              let dirURL = resolvePath(dirRel), isDirectory(dirURL.path) else {
            sendText(connection, status: 400, text: "PUT needs ?path=<folder>&name=<filename>.")
            return false
        }
        let finalURL = autoRename(in: dirURL, name: name)
        let partURL = finalURL.appendingPathExtension("part")
        FileManager.default.createFile(atPath: partURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: partURL.path) else {
            sendText(connection, status: 500, text: "Could not create the upload file.")
            return false
        }
        state.uploadHandle = handle
        state.uploadPartURL = partURL
        state.uploadFinalURL = finalURL
        state.receivedBody = 0
        return true
    }

    private func appendUploadBody(_ connection: NWConnection, state: WiFiConnState, data: Data) {
        guard let handle = state.uploadHandle else { return }
        handle.write(data)
        state.receivedBody += data.count
        if state.receivedBody >= state.expectedBody {
            try? handle.close()
            state.uploadHandle = nil
            var ok = false
            if let part = state.uploadPartURL, let final = state.uploadFinalURL {
                do {
                    try FileManager.default.moveItem(at: part, to: final)
                    ok = true
                    print("[WiFiShare] upload: \(final.lastPathComponent) (\(state.receivedBody) bytes)")
                    logRequest("PUT \(final.lastPathComponent) — \(state.receivedBody) bytes")
                } catch {
                    print("[WiFiShare] upload rename failed: \(error)")
                    try? FileManager.default.removeItem(at: part)
                }
            }
            sendJSON(connection, status: ok ? 200 : 500, dict: ok
                ? ["ok": true, "name": state.uploadFinalURL?.lastPathComponent ?? "", "bytes": state.receivedBody]
                : ["ok": false, "error": "The upload could not be saved."])
            state.responded = true
        }
    }

    // MARK: Routing

    private func handleRequest(_ connection: NWConnection, state: WiFiConnState, request: WiFiHTTPRequest) {
        let path = request.path
        logRequest("\(request.method) \(request.rawTarget)")
        switch (request.method, path) {
        case ("GET", "/"):
            sendText(connection, status: 200, text: Self.webUI, contentType: "text/html; charset=utf-8")
        case ("GET", "/api/files"):
            handleList(connection, request: request)
        case ("GET", "/api/download"):
            handleDownload(connection, request: request)
        case ("GET", "/api/zip"):
            handleZip(connection, request: request)
        case ("POST", "/api/delete"):
            handleDelete(connection, request: request)
        default:
            sendText(connection, status: 404, text: "Not found.")
        }
    }

    private func handleList(_ connection: NWConnection, request: WiFiHTTPRequest) {
        let query = Self.queryItems(request.rawTarget)
        guard let dirURL = resolvePath(query["path"] ?? "") else {
            sendJSON(connection, status: 400, dict: ["ok": false, "error": "Invalid path."])
            return
        }
        guard isDirectory(dirURL.path) else {
            sendJSON(connection, status: 400, dict: ["ok": false, "error": "Not a folder."])
            return
        }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dirURL.path) else {
            sendJSON(connection, status: 500, dict: ["ok": false, "error": "Could not list that folder."])
            return
        }
        var entries: [[String: Any]] = []
        for name in names.sorted() {
            let full = dirURL.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full.path, isDirectory: &isDir) else { continue }
            var size: Int64 = 0
            if !isDir.boolValue,
               let attrs = try? fm.attributesOfItem(atPath: full.path),
               let s = attrs[.size] as? NSNumber {
                size = s.int64Value
            }
            entries.append(["name": name, "isDirectory": isDir.boolValue, "size": size])
        }
        sendJSON(connection, status: 200, dict: [
            "ok": true,
            "path": query["path"] ?? "",
            "entries": entries,
        ])
    }

    private func handleDownload(_ connection: NWConnection, request: WiFiHTTPRequest) {
        let query = Self.queryItems(request.rawTarget)
        guard let rel = query["path"], let fileURL = resolvePath(rel), isRegularFile(fileURL.path) else {
            sendText(connection, status: 404, text: "File not found.")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        sendStreamedFile(connection, path: fileURL.path, contentType: "application/octet-stream",
                         downloadName: fileURL.lastPathComponent, contentLength: size)
    }

    private func handleZip(_ connection: NWConnection, request: WiFiHTTPRequest) {
        let query = Self.queryItems(request.rawTarget)
        guard let dirURL = resolvePath(query["path"] ?? ""), isDirectory(dirURL.path) else {
            sendText(connection, status: 404, text: "Folder not found.")
            return
        }
        // Cap: refuse folders over 2 GB before zipping.
        let total = totalSize(of: dirURL.path)
        guard total <= Self.folderZipCap else {
            sendText(connection, status: 413, text: "That folder is over the 2 GB zip cap.")
            return
        }
        let tmpZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("wifishare-\(UUID().uuidString).zip")
        let writer = WTStoredZipWriter(url: tmpZip)
        guard writer.open() else {
            sendText(connection, status: 500, text: "Could not create the zip.")
            return
        }
        let base = dirURL.lastPathComponent
        var zipOK = true
        var entries: [String] = []
        collectZipEntries(dir: dirURL.path, base: dirURL.path, into: &entries)
        for name in entries {
            let full = (dirURL.path as NSString).appendingPathComponent(name)
            if isDirectory(full) {
                if !writer.addDirectory(name: base + "/" + name) { zipOK = false; break }
            } else if isRegularFile(full) {
                if !writer.addFile(name: base + "/" + name, path: full) { zipOK = false; break }
            }
        }
        writer.close(success: zipOK)
        guard zipOK else {
            try? FileManager.default.removeItem(at: tmpZip)
            sendText(connection, status: 500, text: "Zipping failed partway.")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: tmpZip.path)[.size] as? NSNumber)?.int64Value ?? 0
        sendStreamedFile(connection, path: tmpZip.path, contentType: "application/zip",
                         downloadName: base + ".zip", contentLength: size, deleteAfter: true)
    }

    private func handleDelete(_ connection: NWConnection, request: WiFiHTTPRequest) {
        let query = Self.queryItems(request.rawTarget)
        guard let rel = query["path"], !rel.isEmpty, let target = resolvePath(rel) else {
            sendJSON(connection, status: 400, dict: ["ok": false, "error": "Invalid path."])
            return
        }
        guard target.path != rootPath else {
            sendJSON(connection, status: 400, dict: ["ok": false, "error": "The root folder itself cannot be deleted."])
            return
        }
        do {
            try FileManager.default.removeItem(at: target)
            print("[WiFiShare] deleted: \(rel)")
            sendJSON(connection, status: 200, dict: ["ok": true])
        } catch {
            sendJSON(connection, status: 500, dict: ["ok": false, "error": error.localizedDescription])
        }
    }

    // MARK: Responses

    private func sendUnauthorized(_ connection: NWConnection) {
        let body = Data("Authorization required.".utf8)
        var header = "HTTP/1.1 401 Unauthorized\r\n"
        header += "WWW-Authenticate: Basic realm=\"WorkTweaks\"\r\n"
        header += "Content-Type: text/plain; charset=utf-8\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendText(_ connection: NWConnection, status: Int, text: String, contentType: String = "text/plain; charset=utf-8") {
        let body = Data(text.utf8)
        sendBytes(connection, status: status, contentType: contentType, body: body)
    }

    private func sendJSON(_ connection: NWConnection, status: Int, dict: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
        sendBytes(connection, status: status, contentType: "application/json; charset=utf-8", body: body)
    }

    private func sendBytes(_ connection: NWConnection, status: Int, contentType: String, body: Data) {
        var header = "HTTP/1.1 \(status) \(statusReason(status))\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusReason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 411: return "Length Required"
        case 413: return "Content Too Large"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }

    /// Stream a file in 64 KB chunks, then close the
    /// connection (and delete the temp file when asked).
    private func sendStreamedFile(_ connection: NWConnection, path: String, contentType: String, downloadName: String, contentLength: Int64, deleteAfter: Bool = false) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            sendText(connection, status: 500, text: "Could not open the file.")
            return
        }
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Disposition: attachment; filename=\"\(downloadName)\"\r\n"
        header += "Content-Length: \(contentLength)\r\n"
        header += "Connection: close\r\n\r\n"
        let headerData = Data(header.utf8)
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if error != nil {
                try? handle.close()
                if deleteAfter { try? FileManager.default.removeItem(atPath: path) }
                connection.cancel()
                return
            }
            guard let self else {
                try? handle.close()
                if deleteAfter { try? FileManager.default.removeItem(atPath: path) }
                connection.cancel()
                return
            }
            self.sendFileChunks(connection, handle: handle, path: path, deleteAfter: deleteAfter)
        })
    }

    private func sendFileChunks(_ connection: NWConnection, handle: FileHandle, path: String, deleteAfter: Bool) {
        guard let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty else {
            try? handle.close()
            if deleteAfter { try? FileManager.default.removeItem(atPath: path) }
            connection.cancel()
            return
        }
        let isLast = chunk.count < 65_536
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil || isLast {
                try? handle.close()
                if deleteAfter { try? FileManager.default.removeItem(atPath: path) }
                connection.cancel()
                return
            }
            self.sendFileChunks(connection, handle: handle, path: path, deleteAfter: deleteAfter)
        })
    }

    // MARK: Path helpers

    /// Resolve a relative path ("" = root) under the served
    /// root. Nil when the path escapes the root.
    private func resolvePath(_ rel: String) -> URL? {
        let decoded = rel.removingPercentEncoding ?? rel
        guard !decoded.hasPrefix("/") else { return nil }
        let joined = decoded.isEmpty ? rootPath : (rootPath as NSString).appendingPathComponent(decoded)
        let standardized = (joined as NSString).standardizingPath
        guard standardized == rootPath || standardized.hasPrefix(rootPath + "/") else { return nil }
        return URL(fileURLWithPath: standardized)
    }

    /// "name 2.ext" auto-rename for uploads that would
    /// overwrite an existing file — never overwrites.
    private func autoRename(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let renamed = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            candidate = dir.appendingPathComponent(renamed)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func isRegularFile(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFREG
    }

    private func totalSize(of dir: String) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: dir),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return 0 }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isDirectory == false {
                var st = stat()
                if lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG {
                    total += Int64(st.st_size)
                }
            }
        }
        return total
    }

    private func collectZipEntries(dir: String, base: String, into out: inout [String]) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for name in names.sorted() {
            let full = (dir as NSString).appendingPathComponent(name)
            let rel = String(full.dropFirst(base.count + 1))
            var st = stat()
            guard lstat(full, &st) == 0 else { continue }
            let mode = st.st_mode & S_IFMT
            if mode == S_IFLNK { continue }
            if mode == S_IFDIR {
                out.append(rel + "/")
                collectZipEntries(dir: full, base: base, into: &out)
            } else if mode == S_IFREG {
                out.append(rel)
            }
        }
    }

    private func logRequest(_ line: String) {
        print("[WiFiShare] \(line)")
        DispatchQueue.main.async {
            self.requestLog.insert(line, at: 0)
            if self.requestLog.count > 5 { self.requestLog.removeLast() }
        }
    }

    // MARK: URL helpers

    private static func queryItems(_ rawTarget: String) -> [String: String] {
        guard let qIndex = rawTarget.firstIndex(of: "?") else { return [:] }
        let query = String(rawTarget[rawTarget.index(after: qIndex)...])
        var out: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            out[String(kv[0])] = String(kv[1])
        }
        return out
    }

    private static func localIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let ifa = current.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: ifa.ifa_name) == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            ptr = ifa.ifa_next
        }
        return nil
    }

    // MARK: Web UI

    /// Small dark file-browser page (well under 1 MB).
    private static let webUI = """
    <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>WorkTweaks Files</title>
    <style>body{background:#111;color:#eee;font-family:-apple-system,Helvetica,Arial,sans-serif;margin:0;padding:16px}
    h1{font-size:18px;margin:0 0 4px} p{color:#999;font-size:13px;margin:0 0 16px}
    table{width:100%;border-collapse:collapse} td,th{padding:8px 6px;border-bottom:1px solid #333;text-align:left;font-size:14px}
    a{color:#6ab0ff;text-decoration:none} button{background:#222;color:#eee;border:1px solid #444;border-radius:6px;padding:6px 10px;font-size:13px}
    input[type=file]{color:#eee} .crumb{margin-bottom:12px;font-size:14px}
    .row{display:flex;gap:8px;align-items:center;margin:12px 0;flex-wrap:wrap}</style></head>
    <body><h1>WorkTweaks Files</h1><p>Files in this app's Documents folder. Uploads never overwrite — a name clash becomes "name 2.ext".</p>
    <div class="crumb" id="crumb"></div>
    <div class="row"><input type="file" id="file"><button onclick="upload()">Upload here</button>
    <button onclick="zipCurrent()">Download folder as .zip</button></div>
    <table><thead><tr><th>Name</th><th>Size</th><th></th></tr></thead><tbody id="list"></tbody></table>
    <script>
    let current = "";
    function fmt(n){if(n<1024)return n+" B";if(n<1048576)return (n/1024).toFixed(1)+" KB";if(n<1073741824)return (n/1048576).toFixed(1)+" MB";return (n/1073741824).toFixed(2)+" GB";}
    async function load(path){
      current = path || "";
      const r = await fetch("/api/files?path=" + encodeURIComponent(current));
      const j = await r.json();
      if(!j.ok){document.getElementById("list").innerHTML = "<tr><td colspan=3>"+(j.error||"Failed to list.")+"</td></tr>";return;}
      const parts = current ? current.split("/") : [];
      let crumb = '<a href="#" onclick="load(\\'\\');return false">Documents</a>';
      let acc = "";
      parts.forEach((p,i)=>{acc += (i?"/":"")+p; crumb += " / <a href=\\"#\\" onclick=\\"load('"+acc.replace(/'/g,"\\\\'")+"');return false\\">"+p+"</a>";});
      document.getElementById("crumb").innerHTML = crumb;
      let html = "";
      if(current){const parent = parts.slice(0,-1).join("/"); html += "<tr><td><a href=\\"#\\" onclick=\\"load('"+parent.replace(/'/g,"\\\\'")+"');return false\\">..</a></td><td></td><td></td></tr>";}
      for(const e of j.entries){
        const p = current ? current + "/" + e.name : e.name;
        if(e.isDirectory){html += "<tr><td><a href=\\"#\\" onclick=\\"load('"+p.replace(/'/g,"\\\\'")+"');return false\\">"+e.name+"/</a></td><td></td><td></td></tr>";}
        else{html += "<tr><td><a href=\\"/api/download?path="+encodeURIComponent(p)+"\\">"+e.name+"</a></td><td>"+fmt(e.size)+"</td><td><button onclick=\\"delFile('"+p.replace(/'/g,"\\\\'")+"')\\">Delete</button></td></tr>";}
      }
      document.getElementById("list").innerHTML = html;
    }
    async function delFile(p){if(!confirm("Delete "+p+"?"))return; await fetch("/api/delete?path="+encodeURIComponent(p),{method:"POST"}); load(current);}
    function zipCurrent(){window.location = "/api/zip?path=" + encodeURIComponent(current);}
    async function upload(){
      const f = document.getElementById("file").files[0];
      if(!f){alert("Choose a file first.");return;}
      const r = await fetch("/api/upload?path="+encodeURIComponent(current)+"&name="+encodeURIComponent(f.name),{method:"PUT",body:f});
      const j = await r.json();
      if(!j.ok){alert(j.error||"Upload failed.");return;}
      document.getElementById("file").value = ""; load(current);
    }
    load("");
    </script></body></html>
    """
}

// MARK: - Per-connection state

private final class WiFiConnState {
    var buffer = Data()
    var request: WiFiHTTPRequest?
    var expectedBody = 0
    var receivedBody = 0
    var uploadHandle: FileHandle?
    var uploadPartURL: URL?
    var uploadFinalURL: URL?
    var responded = false

    deinit {
        try? uploadHandle?.close()
        if let part = uploadPartURL {
            try? FileManager.default.removeItem(at: part)
        }
    }
}

private struct WiFiHTTPRequest {
    let method: String
    let rawTarget: String
    let headers: [String: String]

    var path: String {
        let target = rawTarget.removingPercentEncoding ?? rawTarget
        if let q = target.firstIndex(of: "?") { return String(target[target.startIndex..<q]) }
        return target
    }
}
