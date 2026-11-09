import SwiftUI
import UIKit

// MARK: - Tweaks tab
//
// Mirrors mond's GestaltView (adnan120hz/mond): same sections, same
// tweak order, same Subtype picker values, same spoofing model list.
// Toggles mutate the in-memory MobileGestalt dictionary immediately
// (mond: mg_tweak_binding); "Apply Tweaks" persists it via mg_apply.

struct TweaksView: View {
    @ObservedObject var console: Console
    @ObservedObject var manager: GestaltManager

    @AppStorage("atomic_write") private var atomicWrite = true

    @State private var infoTitle: String?
    @State private var infoMessage: String = ""
    @State private var showRevertConfirm = false

    private var showInfo: Binding<Bool> {
        Binding(
            get: { infoTitle != nil },
            set: { if !$0 { infoTitle = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection

                if manager.isValid || manager.isEmpty {
                    if !manager.isValid || manager.isEmpty {
                        warningSection
                    }
                }

                actionSection
                artworkSection
                softwareSection
                hardwareSection
                eligibilitySection
                ipadSection
                internalSection
                writeSettingsSection
                footerSection
            }
            .navigationTitle("WorkTweaks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { manager.load() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(manager.isLoading)
                }
            }
            .alert(infoTitle ?? "", isPresented: showInfo) {
                Button("OK") { infoTitle = nil }
            } message: {
                Text(infoMessage)
            }
            .alert("Notice", isPresented: Binding(
                get: { manager.notice != nil },
                set: { if !$0 { manager.notice = nil } }
            )) {
                Button("OK") { manager.notice = nil }
            } message: {
                Text(manager.notice ?? "")
            }
            .confirmationDialog("Revert all tweaks?", isPresented: $showRevertConfirm) {
                Button("Revert", role: .destructive) { manager.revert() }
            } message: {
                Text("This restores the MobileGestalt backup saved on first launch (mond: SavedGestalt.plist).")
            }
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(statusSubtitle)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                if manager.grantingMG || manager.isLoading {
                    Spacer()
                    ProgressView()
                }
            }.padding(.vertical, 4)
        }
    }

    private var statusIcon: String {
        if manager.isEmpty { return "exclamationmark.triangle.fill" }
        if manager.isValid { return "checkmark.seal.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        manager.isValid && !manager.isEmpty ? .green : .orange
    }

    private var statusTitle: String {
        if manager.isEmpty { return "MobileGestalt is empty" }
        if manager.isValid { return "MobileGestalt loaded" }
        if manager.mgGranted == false { return "Sandbox access denied" }
        return "Not loaded"
    }

    private var statusSubtitle: String {
        if let error = manager.lastError { return error }
        if manager.isValid { return "Sandbox extension is ready (directory grant held)." }
        return "Granting sandbox access…"
    }

    // mond: "Do not reboot!" warning block
    private var warningSection: some View {
        Section {
            Label {
                Text("Do not reboot! Your MobileGestalt.plist seems to be \(manager.isEmpty ? "empty" : "invalid").")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
        } header: {
            Label("Warning", systemImage: "exclamationmark.triangle")
        } footer: {
            Text("Rebooting now might cause a bootloop. Try pressing 'Revert Tweaks'.")
        }
    }

    // MARK: Actions (mond: Apply / Revert / Respring)

    private var actionSection: some View {
        Section {
            Button {
                manager.apply()
                console.output += "\n(mg) Apply finished — see the Log for the write result.\n"
            } label: {
                Label("Apply Tweaks", systemImage: "checkmark.circle.fill")
            }
            .disabled(!manager.isValid)

            Button {
                RespringCenter.shared.trigger()
            } label: {
                Label("Respring", systemImage: "restart.circle")
            }

            Button(role: .destructive) {
                showRevertConfirm = true
            } label: {
                Label("Revert Tweaks", systemImage: "arrow.uturn.backward.circle")
            }
            .disabled(!manager.isValid)
        } footer: {
            Text("WARNING: These tweaks can break features on your device or softbrick it if misused. The device resprings automatically after Apply, Revert, and Backup restores.")
        }
    }

    // MARK: Device Artwork (mond: Subtype picker + Custom Device Name)

    private var artworkSection: some View {
        Section {
            Picker(selection: $manager.selectedST) {
                Text("Original (\(manager.ogST))").tag("og")

                if isDeviceGoodForNoDynamicIsland() {
                    Text("Disable Dynamic Island").tag("no_dynamic_island")
                }

                Text("iPhone 14 Pro").tag("14p")
                Text("iPhone 14 Pro Max").tag("14pm")
                Text("iPhone 15 Pro Max").tag("15pm")

                if doubleSystemVersion() >= 18.0 {
                    Text("iPhone 16 Pro").tag("16p")
                    Text("iPhone 16 Pro Max").tag("16pm")
                }

                if doubleSystemVersion() >= 26.0 {
                    Text("iPhone Air").tag("air")
                }

                if hasHomeButton() {
                    Text("iPhone X Gestures").tag("x")
                }
            } label: {
                Text("Subtype")
            }

            Toggle("Custom Device Name", isOn: $manager.enableDeviceName)

            if manager.enableDeviceName {
                TextField("Device Name", text: $manager.deviceName)
                    .autocorrectionDisabled()
            }
        } header: {
            Label("Device Artwork", systemImage: "paintbrush.pointed")
        }
    }

    // MARK: Tweak sections (mond: GestaltView sections, same order)

    private var softwareSection: some View {
        Section {
            TweakToggle(manager: manager, title: "Enable Dynamic Island Capability", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Always-On Display", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "AOD Vibrancy", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Disable Wallpaper Parallax", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Charge Limit Menu", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Boot & Shutdown Chime", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Enable Liquid Glass Low-Performance Mode", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Disable Liquid Glass Low-Performance Mode", onInfo: showInfo(for:))
        } header: {
            Label("Software-Oriented Features", systemImage: "gearshape")
        }
    }

    private var hardwareSection: some View {
        Section {
            TweakToggle(manager: manager, title: "iPhone 16 Camera Control Settings", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Action Button Settings", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Collision SOS", onInfo: showInfo(for:))
            if hasHomeButton() {
                TweakToggle(manager: manager, title: "Tap to Wake", onInfo: showInfo(for:))
            }
            TweakToggle(manager: manager, title: "Pulse Width Modulation", onInfo: showInfo(for:))
        } header: {
            Label("Hardware-Oriented Features", systemImage: "iphone")
        }
    }

    private var eligibilitySection: some View {
        Section {
            TweakToggle(manager: manager, title: "Security Research Device Mode", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Disable Region Restrictions", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Apple Intelligence", onInfo: showInfo(for:))

            HStack(spacing: 10) {
                Picker("Spoofing", selection: $manager.productType) {
                    Text("Default").tag(machineName())
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        if doubleSystemVersion() >= 17.4 {
                            Text("iPad Pro 11-inch (M4)").tag("iPad16,3")
                            Text("iPad Pro 11-inch (M4, Cellular)").tag("iPad16,4")
                        }
                        Text("iPad Pro 11-inch (4th Gen)").tag("iPad14,3")
                        Text("iPad Pro 11-inch (4th Gen, Cellular)").tag("iPad14,4")
                    } else {
                        Text("iPhone 15 Pro").tag("iPhone16,1")
                        Text("iPhone 15 Pro Max").tag("iPhone16,2")
                        if doubleSystemVersion() >= 18.0 {
                            Text("iPhone 16").tag("iPhone17,3")
                            Text("iPhone 16 Plus").tag("iPhone17,4")
                            Text("iPhone 16 Pro").tag("iPhone17,1")
                            Text("iPhone 16 Pro Max").tag("iPhone17,2")
                        }
                        if doubleSystemVersion() >= 19.0 {
                            Text("iPhone 17").tag("iPhone18,3")
                            Text("iPhone 17 Pro").tag("iPhone18,1")
                            Text("iPhone 17 Pro Max").tag("iPhone18,2")
                            Text("iPhone Air").tag("iPhone18,4")
                        }
                    }
                }

                Button {
                    infoTitle = "Device Spoofing Info"
                    infoMessage = "Only spoof your device model if you want to download Apple Intelligence. This may break Face ID. If you decide to unspoof and want to keep Apple Intelligence, do NOT re-enter the Apple Intelligence & Siri menu in Settings."
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
            }
        } header: {
            Label("Eligibility", systemImage: "checklist")
        }
    }

    private var ipadSection: some View {
        Section {
            TweakToggle(manager: manager, title: "Allow iPad Apps", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Apple Pencil Settings", onInfo: showInfo(for:))

            if UIDevice.current.userInterfaceIdiom == .pad {
                TweakToggle(manager: manager, title: "Stage Manager Support", onInfo: showInfo(for:))
            }

            TweakToggle(manager: manager, title: "Enable iPadOS Mode", onInfo: showInfo(for:))
                .disabled({
                    let extra = manager.dictNow["CacheExtra"] as? [String: Any]
                    return extra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone"
                }())
        } header: {
            Label("iPadOS Features", systemImage: "ipad")
        }
    }

    private var internalSection: some View {
        Section {
            TweakToggle(manager: manager, title: "Internal Storage View", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Internal Features", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Apple Internal Install", onInfo: showInfo(for:))
        } header: {
            Label("Internal", systemImage: "ant")
        }
    }

    // mond SettingsView: "Persist after reboot" (atomic_write)
    private var writeSettingsSection: some View {
        Section {
            Toggle("Persist after reboot", isOn: $atomicWrite)
        } header: {
            Label("Write Method", systemImage: "pencil.and.outline")
        } footer: {
            Text("When enabled, MobileGestalt is written in-place on the same inode, which (hopefully) prevents iOS from regenerating the cache on reboot. Disable to use atomic file replacement instead. (mond's default: enabled.)")
        }
    }

    private var footerSection: some View {
        Section {
            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Tweak engine ported from mond (mg.swift); core exploit from work-gestalt (worse_query).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func showInfo(for tweak: GestaltTweak) {
        infoTitle = tweak.title
        infoMessage = tweak.infoMessage ?? ""
    }
}

// MARK: - Toggle row (mond: TweakToggle via mg_tweak_binding)

struct TweakToggle: View {
    @ObservedObject var manager: GestaltManager
    let title: String
    let onInfo: (GestaltTweak) -> Void

    var body: some View {
        if let tweak = TweakCatalog.tweak(title: title) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tweak.title)
                        .font(.subheadline.weight(.medium))
                    if !tweak.supported(), let minv = tweak.minv {
                        Text("Requires iOS \(minv, specifier: "%.1f")+")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if tweak.infoMessage != nil {
                    Button { onInfo(tweak) } label: {
                        Image(systemName: tweak.infoType == .warning || tweak.infoType == .error
                              ? "exclamationmark.triangle"
                              : "info.circle")
                            .foregroundStyle(tweak.infoType == .warning || tweak.infoType == .error ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Toggle("", isOn: manager.toggleBinding(for: tweak))
                    .labelsHidden()
                    .disabled(!manager.isValid || !tweak.supported())
            }
            .padding(.vertical, 2)
        }
    }
}
