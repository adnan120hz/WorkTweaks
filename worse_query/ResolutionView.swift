import SwiftUI
import UIKit
import Combine

// MARK: - Resolution manager (Nugget: CustomResolution / RdarFix)
//
// Screen-resolution changes do NOT go through MobileGestalt. Nugget's
// CustomResolution (a "risky" tweak there) writes canvas_width /
// canvas_height into a different file:
//   /var/Managed Preferences/mobile/com.apple.iokit.IOMobileGraphicsFamily.plist
// canvas_width is the portrait (short-edge) pixel count and
// canvas_height the long-edge count, per Nugget's RdarFix presets.
// Access to that directory is obtained with the same worse_query
// sandbox extension the app uses for the MobileGestalt directory.

@MainActor
final class ResolutionManager: ObservableObject {
    static let directoryPath = "/var/Managed Preferences/mobile"
    static let filePath = directoryPath + "/com.apple.iokit.IOMobileGraphicsFamily.plist"

    @Published var granted = false
    @Published var fileExists = false
    @Published var currentWidth: Int?
    @Published var currentHeight: Int?

    private var handle: Int64 = -1

    var isCustomized: Bool { currentWidth != nil || currentHeight != nil }

    func ensureAccess() {
        if handle <= 0 {
            handle = consumeExtension(Self.directoryPath)
        }
        granted = handle > 0
        if granted {
            reload()
        } else {
            print("(resolution) sandbox grant failed for \(Self.directoryPath)")
        }
    }

    func reload() {
        fileExists = FileManager.default.fileExists(atPath: Self.filePath)
        guard fileExists,
              let dict = NSDictionary(contentsOfFile: Self.filePath) else {
            currentWidth = nil
            currentHeight = nil
            return
        }
        currentWidth = dict["canvas_width"] as? Int
        currentHeight = dict["canvas_height"] as? Int
        print("(resolution) current canvas: \(currentWidth.map(String.init) ?? "nil") x \(currentHeight.map(String.init) ?? "nil")")
    }

    /// Writes canvas_width/canvas_height, preserving any other keys the
    /// file already holds. Returns an error string or nil on success.
    func apply(width: Int, height: Int) -> String? {
        ensureAccess()
        guard granted else {
            return "Could not get sandbox access to \(Self.directoryPath). The resolution file cannot be written."
        }
        let dict = (fileExists ? NSMutableDictionary(contentsOfFile: Self.filePath) : nil) ?? NSMutableDictionary()
        dict["canvas_width"] = width
        dict["canvas_height"] = height
        if let error = writePlist(dict) { return error }
        print("(resolution) wrote canvas \(width) x \(height)")
        reload()
        return nil
    }

    /// Removes the canvas keys again (deleting the file if nothing else
    /// remains in it), returning the device to its native resolution.
    func restoreNative() -> String? {
        ensureAccess()
        guard granted else {
            return "Could not get sandbox access to \(Self.directoryPath)."
        }
        guard fileExists,
              let dict = NSMutableDictionary(contentsOfFile: Self.filePath) else {
            return nil // nothing written — already native
        }
        dict.removeObject(forKey: "canvas_width")
        dict.removeObject(forKey: "canvas_height")
        if dict.count == 0 {
            do {
                try FileManager.default.removeItem(atPath: Self.filePath)
            } catch {
                return "Failed to remove the resolution file: \(error.localizedDescription)"
            }
            print("(resolution) file removed — native resolution")
        } else {
            if let error = writePlist(dict) { return error }
            print("(resolution) canvas keys removed — native resolution")
        }
        reload()
        return nil
    }

    /// Serializes as XML and writes in place when the file already
    /// exists (same inode), like GestaltManager's mg_write.
    private func writePlist(_ dict: NSDictionary) -> String? {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        ) else {
            return "Failed to serialize the resolution plist."
        }
        if FileManager.default.fileExists(atPath: Self.filePath) {
            guard let fh = FileHandle(forWritingAtPath: Self.filePath) else {
                return "Cannot open the resolution file for writing."
            }
            do {
                try fh.truncate(atOffset: 0)
                try fh.write(contentsOf: data)
                try fh.synchronize()
                try fh.close()
            } catch {
                return "Write failed: \(error.localizedDescription)"
            }
        } else {
            do {
                try data.write(to: URL(fileURLWithPath: Self.filePath))
            } catch {
                return "Could not create the resolution file: \(error.localizedDescription)"
            }
        }
        return nil
    }
}

// MARK: - Resolution view

struct ResolutionView: View {
    @ObservedObject var manager: GestaltManager
    @StateObject private var res = ResolutionManager()

    @State private var widthText = ""
    @State private var heightText = ""
    @State private var showApplyConfirm = false
    @State private var showRestoreConfirm = false
    @State private var showRestartChoice = false
    @State private var alertMessage: String?

    /// Presets from Nugget's RdarFix (canvas_width x canvas_height).
    private static let presets: [(label: String, width: Int, height: Int)] = [
        ("iPhone XR / XS / 11 (RDAR fix)", 828, 1791),
        ("iPhone SE (RDAR fix)", 1000, 1779),
        ("iPhone 14 / 15 / 16", 1179, 2556),
        ("iPhone 14 Pro Max / 15 Pro Max", 1290, 2796),
        ("iPhone 16 Pro", 1206, 2622),
        ("iPhone 16 Pro Max", 1320, 2868),
        ("iPhone 16 Plus", 1260, 2736),
    ]

    private var parsedWidth: Int? { Int(widthText) }
    private var parsedHeight: Int? { Int(heightText) }

    private var inputValid: Bool {
        guard let w = parsedWidth, let h = parsedHeight else { return false }
        return (100...4000).contains(w) && (100...4000).contains(h)
    }

    private var nativeText: String {
        let b = UIScreen.main.nativeBounds
        return "\(Int(b.width)) x \(Int(b.height))"
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                presetSection
                customSection
                restoreSection
                warningSection
            }
            .navigationTitle("Resolution")
            .onAppear { res.ensureAccess() }
            .alert("Resolution", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog("Apply custom resolution?", isPresented: $showApplyConfirm, titleVisibility: .visible) {
                Button("Write \(widthText) x \(heightText)", role: .destructive) { applyResolution() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This writes canvas_width / canvas_height to the IOMobileGraphicsFamily preferences (Nugget's Custom Resolution method, marked risky there). A full device restart is required before it takes effect.")
            }
            .confirmationDialog("Restore native resolution?", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
                Button("Restore Native", role: .destructive) {
                    if let error = res.restoreNative() {
                        alertMessage = error
                    } else {
                        showRestartChoice = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes the canvas_width / canvas_height override. A full device restart is required before it takes effect.")
            }
            .confirmationDialog("Resolution Written", isPresented: $showRestartChoice, titleVisibility: .visible) {
                Button("Restart Device") { manager.attemptRestart() }
                Button("Later", role: .cancel) { }
            } message: {
                Text("Resolution changes need a full restart — a respring is not enough.")
            }
            .alert(manager.restartAlertTitle ?? "", isPresented: Binding(
                get: { manager.restartAlertTitle != nil },
                set: { if !$0 { manager.restartAlertTitle = nil } }
            )) {
                Button("OK") { manager.restartAlertTitle = nil }
            } message: {
                Text(manager.restartAlertMessage)
            }
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: res.granted ? "checkmark.shield" : "exclamationmark.shield")
                    .font(.title3)
                    .foregroundStyle(res.granted ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(res.granted ? "Graphics preferences reachable" : "No access yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Native panel: \(nativeText) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if res.isCustomized {
                        Text("Current override: \(res.currentWidth.map(String.init) ?? "?") x \(res.currentHeight.map(String.init) ?? "?")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No override set — native resolution in use")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !res.granted {
                    Button("Grant") { res.ensureAccess() }
                        .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Method: Nugget's Custom Resolution — writes canvas_width / canvas_height to /var/Managed Preferences/mobile/com.apple.iokit.IOMobileGraphicsFamily.plist. This is not a MobileGestalt tweak.")
        }
    }

    private var presetSection: some View {
        Section {
            ForEach(Self.presets, id: \.label) { preset in
                Button {
                    widthText = String(preset.width)
                    heightText = String(preset.height)
                } label: {
                    HStack {
                        Text(preset.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(preset.width) x \(preset.height)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Presets (tap to fill the custom fields)")
        }
    }

    private var customSection: some View {
        Section {
            HStack {
                Text("canvas_width")
                Spacer()
                TextField("width", text: $widthText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
            }
            HStack {
                Text("canvas_height")
                Spacer()
                TextField("height", text: $heightText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
            }
            Button {
                showApplyConfirm = true
            } label: {
                Label("Apply Custom Resolution", systemImage: "rectangle.expand.vertical")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!inputValid || !res.granted)
        } header: {
            Text("Custom Resolution")
        } footer: {
            Text("Fully custom: enter any pixel size (100–4000 per side). Width is normally the short edge, height the long edge.")
        }
    }

    private var restoreSection: some View {
        Section {
            Button(role: .destructive) {
                showRestoreConfirm = true
            } label: {
                Label("Restore Native Resolution", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!res.isCustomized)
        }
    }

    private var warningSection: some View {
        Section {
            Label {
                Text("Risky: an unusable canvas size can make the UI too small, too large, or misaligned until you restore. If the screen becomes unusable, the override can be removed from this tab after a restart, or by deleting the IOMobileGraphicsFamily.plist file. Nugget classifies this tweak as risky — apply carefully.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Actions

    private func applyResolution() {
        guard let w = parsedWidth, let h = parsedHeight else { return }
        if let error = res.apply(width: w, height: h) {
            alertMessage = error
        } else {
            showRestartChoice = true
        }
    }
}
