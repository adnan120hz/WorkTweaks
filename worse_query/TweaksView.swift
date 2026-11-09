import SwiftUI
import UIKit

// MARK: - Tweaks tab
//
// Mirrors mond's GestaltView (adnan120hz/mond): same sections, same
// tweak order, same Subtype picker values, same spoofing model list.
// Toggles mutate the in-memory MobileGestalt dictionary immediately
// (mond: mg_tweak_binding); "Apply Tweaks" persists it via mg_apply.
//
// Every tweak keeps its own SF Symbol (see TweakCatalog
// .presentation), rendered uniformly as a plain accent-colored
// row icon. The tab starts LOCKED until "Start Tweaks Feature"
// is turned on in the Sandbox tab (wt.tweaksFeatureEnabled).

struct TweaksView: View {
    // Not @ObservedObject on purpose: this view never displays console
    // output (it only appends one line after Apply). Observing it made
    // every log flush re-render the whole tweak list, which re-ran
    // every tweak's read() — a self-sustaining lag/spam loop.
    let console: Console
    @ObservedObject var manager: GestaltManager
    /// Switches the TabView to the Sandbox tab (RootView owns the
    /// selection); used by the locked state's button.
    var onOpenSandbox: () -> Void

    @AppStorage("atomic_write") private var atomicWrite = true
    /// Master switch for this tab, flipped in the Sandbox tab.
    @AppStorage("wt.tweaksFeatureEnabled") private var tweaksEnabled = false

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
            Group {
                if tweaksEnabled {
                    tweakList
                } else {
                    lockedView
                }
            }
            .navigationTitle("WorkTweaks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { manager.load() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(manager.isLoading)
                    NavigationLink {
                        TutorialsView()
                    } label: {
                        Image(systemName: "book")
                    }
                    .accessibilityLabel("Tutorials")
                    NavigationLink {
                        LicenseView()
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel("License & Credits")
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
            .confirmationDialog("Tweaks Applied", isPresented: $manager.showPostApplyChoice, titleVisibility: .visible) {
                Button("Respring") { RespringCenter.shared.trigger() }
                Button("Restart Device") { manager.attemptRestart() }
                Button("Later", role: .cancel) { }
            } message: {
                Text("Some tweaks — especially Apple Intelligence — only take effect after a full restart, not a respring.")
            }
            .confirmationDialog("Restart Required", isPresented: $manager.showRestartRequired, titleVisibility: .visible) {
                Button("Restart Device") { manager.attemptRestart() }
                Button("Later", role: .cancel) { }
            } message: {
                Text("Revert and restore changes only take effect after a full device restart — a respring is not enough. Choosing Later just postpones it; the changes stay pending until you restart.")
            }
            .alert(manager.restartAlertTitle ?? "", isPresented: Binding(
                get: { manager.restartAlertTitle != nil },
                set: { if !$0 { manager.restartAlertTitle = nil } }
            )) {
                Button("OK") { manager.restartAlertTitle = nil }
            } message: {
                Text(manager.restartAlertMessage)
            }
            .confirmationDialog("Revert all tweaks?", isPresented: $showRevertConfirm) {
                Button("Revert", role: .destructive) { manager.revert() }
            } message: {
                Text("This restores the MobileGestalt backup saved on first launch (mond: SavedGestalt.plist).")
            }
        }
    }

    // MARK: Locked state (v2.0)

    private var lockedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Tweaks are locked")
                    .font(.title3.weight(.bold))
                Text("Go to the Sandbox tab and turn on Start Tweaks Feature to unlock the Tweaks tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                onOpenSandbox()
            } label: {
                Label("Go to Sandbox Tab", systemImage: "shippingbox")
                    .font(.headline)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Tweak list

    private var tweakList: some View {
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
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(statusColor)
                    .frame(width: 30)
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
            Text("Warning")
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
                Text("Apply Tweaks")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(!manager.isValid)

            Button {
                RespringCenter.shared.trigger()
            } label: {
                Text("Respring")
                    .font(.subheadline.weight(.semibold))
            }

            Button(role: .destructive) {
                showRevertConfirm = true
            } label: {
                Text("Revert Tweaks")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(!manager.isValid)
        } footer: {
            Text("WARNING: These tweaks can break features on your device or softbrick it if misused. After Apply you choose Respring or Restart; Revert and Backup restores require a full device restart.")
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
                    Text("iPhone 18 Pro Max").tag("18pm")
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
            Text("Device Artwork")
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
            Text("Software-Oriented Features")
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
            Text("Hardware-Oriented Features")
        }
    }

    private var eligibilitySection: some View {
        Section {
            TweakToggle(manager: manager, title: "Security Research Device Mode", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Disable Region Restrictions", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Apple Intelligence", onInfo: showInfo(for:))

            HStack(spacing: 8) {
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
            Text("Eligibility")
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
            Text("iPadOS Features")
        }
    }

    private var internalSection: some View {
        Section {
            TweakToggle(manager: manager, title: "Internal Storage View", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Internal Features", onInfo: showInfo(for:))
            TweakToggle(manager: manager, title: "Apple Internal Install", onInfo: showInfo(for:))
        } header: {
            Text("Internal")
        }
    }

    // mond SettingsView: "Persist after reboot" (atomic_write)
    private var writeSettingsSection: some View {
        Section {
            Toggle("Persist after reboot", isOn: $atomicWrite)
        } header: {
            Text("Write Method")
        } footer: {
            Text("When enabled, MobileGestalt is written in-place on the same inode, which (hopefully) prevents iOS from regenerating the cache on reboot. Disable to use atomic file replacement instead. (mond's default: enabled.)")
        }
    }

    private var footerSection: some View {
        Section {
            NavigationLink {
                TutorialsView()
            } label: {
                Text("Tutorials")
                    .font(.subheadline.weight(.medium))
            }

            NavigationLink {
                LicenseView()
            } label: {
                Text("License & Credits")
                    .font(.subheadline.weight(.medium))
            }

            Text("Tweak engine ported from mond (mg.swift); core exploit from work-gestalt (worse_query).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func showInfo(for tweak: GestaltTweak) {
        infoTitle = tweak.title
        infoMessage = tweak.infoMessage ?? ""
    }
}

// MARK: - Toggle row (mond: TweakToggle via mg_tweak_binding)
//
// Row design: the tweak's own SF Symbol as a plain accent-colored
// icon (uniform size/weight/color for every tweak) + title
// (+ "Requires iOS" subtitle when the tweak needs a newer iOS)
// + optional info button + switch.

struct TweakToggle: View {
    @ObservedObject var manager: GestaltManager
    let title: String
    let onInfo: (GestaltTweak) -> Void

    var body: some View {
        if let tweak = TweakCatalog.tweak(title: title) {
            HStack(spacing: 12) {
                RowIcon(systemImage: tweak.icon)
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
