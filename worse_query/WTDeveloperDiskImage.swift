import Foundation

// MARK: - Developer disk image
//
// Port of the `DeveloperDiskImage` enum in SideInstaller v2.2.0
// `ios-app/LocationView.swift:12-80` (the same mirror StikDebug uses).
// Adapted: logging is `print("[JIT] ...")` (no `Engine`), errors are a
// local type (no `EngineError` / `L()` here — the manager surfaces them
// and the view translates at display time).
//
// The three files of Apple's personalized developer disk image and where
// they are stored. Mounting the image enables DVT services such as
// debugserver — the JIT session needs it mounted before it can attach.
// Downloaded on first use rather than bundled.
//
// Source: doronz88/DeveloperDiskImage. These are Apple's unmodified
// files; the device personalizes the image against its chip ID at mount
// time (see `WTDeviceConnection.mountPersonalizedDeveloperImage`).

enum WTDeveloperDiskImage {

    private static let baseURL =
        "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized"

    /// Files to download (same name remotely and locally).
    private static let files = [
        "BuildManifest.plist",
        "Image.dmg",
        "Image.dmg.trustcache",
    ]

    static var directory: URL {
        URL.documentsDirectory.appendingPathComponent("DDI", isDirectory: true)
    }

    static var imagePath: String { directory.appendingPathComponent("Image.dmg").path }
    static var trustcachePath: String { directory.appendingPathComponent("Image.dmg.trustcache").path }
    static var manifestPath: String { directory.appendingPathComponent("BuildManifest.plist").path }

    /// True when all three files are on disk and non-empty.
    static var isDownloaded: Bool {
        files.allSatisfy { name in
            let path = directory.appendingPathComponent(name).path
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return (attributes?[.size] as? Int ?? 0) > 0
        }
    }

    enum DDIError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let text) = self { return text }
            return nil
        }
    }

    /// Fetch whichever of the three files are missing, reporting 0…1
    /// across the whole set rather than per file.
    static func downloadMissing(progress: @escaping (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let missing = files.filter { name in
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
        guard !missing.isEmpty else { progress(1); return }

        for (index, name) in missing.enumerated() {
            progress(Double(index) / Double(missing.count))
            guard let url = URL(string: "\(baseURL)/\(name)") else {
                throw DDIError.message("Couldn't build the download URL for \(name).")
            }
            let (tmp, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw DDIError.message("Downloading \(name) failed (HTTP \(code)).")
            }
            let destination = directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tmp, to: destination)
            print("[JIT] DDI: downloaded \(name).")
        }
        progress(1)
    }
}
