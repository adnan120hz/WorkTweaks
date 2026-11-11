import Foundation
import Combine
import Darwin

// MARK: - Lock Screen Footnote
//
// The Lock Screen footnote is an official Apple
// device-management setting (domain
// com.apple.shareddeviceconfiguration): the string key
// "LockScreenFootnote" in SharedDeviceConfiguration.plist,
// which SpringBoard shows in small text at the bottom of the
// Lock Screen. It is NOT a MobileGestalt key.
//
// Access follows the app's fork pattern: a sandbox extension
// is consumed on the Library/ConfigurationProfiles DIRECTORY
// (never on the file itself) through the same consumeExtension
// wrapper every other feature uses, the work happens under
// that one grant, and the grant is released afterwards.
//
// Fail-safe, like the rest of the app: if the grant or the
// read fails, the feature reports an honest blocked state
// with the real result code and writes NOTHING. If the plist
// does not exist yet but the directory grant works, Apply
// creates it. Writes are read-modify-write (every other key
// is preserved) and happen IN PLACE on the same inode —
// FileHandle truncate + write, never an atomic replacement.

final class FootnoteManager: ObservableObject {
    static let directoryPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
    static let filePath = directoryPath + "/SharedDeviceConfiguration.plist"
    static let footnoteKey = "LockScreenFootnote"

    enum LoadState {
        case loading
        case ready
        case blocked(String)
    }

    @Published var state: LoadState = .loading
    /// The footnote currently in the plist ("" when unset).
    @Published var footnote: String = ""
    @Published var hasFootnote = false
    @Published var fileExists = false
    @Published var isWriting = false

    // MARK: Load

    func load() {
        state = .loading
        let handle = consumeExtension(Self.directoryPath)
        print("[Footnote] grant for \(Self.directoryPath) -> \(handle)")
        guard handle > 0 else {
            state = .blocked("The sandbox extension for the ConfigurationProfiles directory was refused (code \(handle)). Nothing was read or written — the exact grant result is in the Log.")
            return
        }
        defer { releaseExtension(handle) }

        fileExists = FileManager.default.fileExists(atPath: Self.filePath)
        guard fileExists else {
            footnote = ""
            hasFootnote = false
            state = .ready
            print("[Footnote] SharedDeviceConfiguration.plist does not exist yet — the editor starts empty and Apply will create it.")
            return
        }
        guard let dict = Self.readPlist() else {
            state = .blocked("SharedDeviceConfiguration.plist exists but could not be read as a property list. Nothing was written.")
            return
        }
        footnote = dict[Self.footnoteKey] as? String ?? ""
        hasFootnote = dict[Self.footnoteKey] != nil
        state = .ready
        print("[Footnote] loaded — footnote \(hasFootnote ? "is set (\(footnote.count) character(s))" : "is not set").")
    }

    private static func readPlist() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            print("[Footnote] read failed: \(filePath)")
            return nil
        }
        let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = parsed as? [String: Any] else {
            print("[Footnote] parse failed: \(filePath) is not a dictionary plist")
            return nil
        }
        return dict
    }

    // MARK: Write

    /// Apply the editor text. Empty text removes the key.
    func apply(text: String) -> Bool {
        writeFootnote(text.isEmpty ? nil : text)
    }

    /// Remove the footnote key entirely.
    func removeFootnote() -> Bool {
        writeFootnote(nil)
    }

    private func writeFootnote(_ newValue: String?) -> Bool {
        isWriting = true
        defer { isWriting = false }

        let handle = consumeExtension(Self.directoryPath)
        print("[Footnote] grant for write -> \(handle)")
        guard handle > 0 else {
            print("[Footnote] write aborted — the directory grant was refused (code \(handle)). Nothing was written.")
            return false
        }
        defer { releaseExtension(handle) }

        // Read-modify-write: every other key is preserved.
        var dict: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: Self.filePath) {
            guard let existing = Self.readPlist() else {
                print("[Footnote] write aborted — the existing plist could not be read, so it was left untouched.")
                return false
            }
            dict = existing
        }
        if let newValue {
            dict[Self.footnoteKey] = newValue
        } else {
            dict.removeValue(forKey: Self.footnoteKey)
        }

        guard let out = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else {
            print("[Footnote] write aborted — the plist could not be serialized.")
            return false
        }

        // Create the file first when it does not exist yet,
        // then write in place on the same inode.
        if !FileManager.default.fileExists(atPath: Self.filePath) {
            guard FileManager.default.createFile(atPath: Self.filePath, contents: nil) else {
                print("[Footnote] write aborted — could not create \(Self.filePath).")
                return false
            }
            print("[Footnote] created \(Self.filePath)")
        }
        guard let handle = FileHandle(forWritingAtPath: Self.filePath) else {
            print("[Footnote] write aborted — could not open \(Self.filePath) for writing.")
            return false
        }
        do {
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: out)
            try handle.synchronize()
            try handle.close()
        } catch {
            print("[Footnote] write failed for \(Self.filePath): \(error)")
            try? handle.close()
            return false
        }

        // Verify by re-reading and comparing the key.
        guard let back = Self.readPlist() else {
            print("[Footnote] verify failed — the plist could not be re-read after writing.")
            return false
        }
        let nowValue = back[Self.footnoteKey] as? String
        let verified = (newValue == nil) ? (nowValue == nil) : (nowValue == newValue)
        print("[Footnote] write \(verified ? "verified" : "FAILED verification") — footnote is now \(nowValue.map { "\"\($0)\"" } ?? "not set").")
        guard verified else { return false }

        footnote = newValue ?? ""
        hasFootnote = newValue != nil
        fileExists = true
        return true
    }

}
