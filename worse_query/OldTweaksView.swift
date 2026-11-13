import SwiftUI
import UIKit

// MARK: - Old UI (v1 layout) for the Tweaks tab
//
// The Tweaks tab has two layouts, chosen in the Sandbox tab
// ("Tweaks UI" picker under Start Tweaks Feature,
// wt.tweaksUIVersion): New UI is the current two-column card
// layout, Old UI is the v1 layout — a plain native List with
// the original section order (Status, Actions, Device Artwork,
// Software / Hardware / Eligibility / iPadOS / Internal,
// Write Method). Only the layout differs: every toggle, picker
// and action reads the same GestaltManager state and runs the
// same apply/revert/respring code as the New UI, and the
// post-v1 Lock Screen Footnote gets its own small section so
// it stays reachable in the Old UI too. Nothing else in the
// app changes with this setting.

struct OldTweaksView: View {
    let console: Console
    @ObservedObject var manager: GestaltManager
    /// Shows the info alert (owned by TweaksView) for a tweak.
    let onInfo: (GestaltTweak) -> Void
    /// Shows the Revert confirmation (owned by TweaksView).
    let onRevert: () -> Void
    /// Shows the Device Spoofing info alert (owned by TweaksView).
    let onSpoofingInfo: () -> Void

    @AppStorage("atomic_write") private var atomicWrite = true

    var body: some View {
        List {
            statusSection

            if manager.isEmpty || !manager.isValid {
                warningSection
            }

            actionSection
            artworkSection
            softwareSection
            hardwareSection
            eligibilitySection
            ipadSection
            internalSection
            footnoteSection
            writeSettingsSection
            footerSection
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

    // MARK: Actions (Apply / Respring / Revert)

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
                onRevert()
            } label: {
                Label("Revert Tweaks", systemImage: "arrow.uturn.backward.circle")
            }
            .disabled(!manager.isValid)
        } footer: {
            Text("WARNING: These tweaks can break features on your device or softbrick it if misused. After Apply you choose Respring or Restart; Revert and Backup restores require a full device restart.")
        }
    }

    // MARK: Device Artwork (Subtype picker + Custom Device Name)

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
                    Text("iPhone 18 Pro Max (iOS 27.0.1+)").tag("18pm")
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

    // MARK: Tweak sections (same catalog as the New UI)

    private var softwareSection: some View {
        Section {
            OldTweakToggle(manager: manager, title: "Enable Dynamic Island Capability", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Always-On Display", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "AOD Vibrancy", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Disable Wallpaper Parallax", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Charge Limit Menu", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Boot & Shutdown Chime", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Enable Liquid Glass Low-Performance Mode", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Disable Liquid Glass Low-Performance Mode", onInfo: onInfo)
        } header: {
            Label("Software-Oriented Features", systemImage: "gearshape")
        }
    }

    private var hardwareSection: some View {
        Section {
            OldTweakToggle(manager: manager, title: "iPhone 16 Camera Control Settings", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Action Button Settings", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Collision SOS", onInfo: onInfo)
            if hasHomeButton() {
                OldTweakToggle(manager: manager, title: "Tap to Wake", onInfo: onInfo)
            }
            OldTweakToggle(manager: manager, title: "Pulse Width Modulation", onInfo: onInfo)
        } header: {
            Label("Hardware-Oriented Features", systemImage: "iphone")
        }
    }

    private var eligibilitySection: some View {
        Section {
            OldTweakToggle(manager: manager, title: "Security Research Device Mode", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Disable Region Restrictions", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Apple Intelligence", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Siri AI Cache Patch", onInfo: onInfo)

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
                    onSpoofingInfo()
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
            OldTweakToggle(manager: manager, title: "Allow iPad Apps", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Apple Pencil Settings", onInfo: onInfo)

            if UIDevice.current.userInterfaceIdiom == .pad {
                OldTweakToggle(manager: manager, title: "Stage Manager Support", onInfo: onInfo)
            }

            OldTweakToggle(manager: manager, title: "Enable iPadOS Mode", onInfo: onInfo)
                .disabled(ipadOSModeLocked)
        } header: {
            Label("iPadOS Features", systemImage: "ipad")
        }
    }

    /// Enable iPadOS Mode stays locked unless the device class in
    /// CacheExtra still reads "iPhone" (unchanged from v2.0).
    private var ipadOSModeLocked: Bool {
        let extra = manager.dictNow["CacheExtra"] as? [String: Any]
        return extra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone"
    }

    private var internalSection: some View {
        Section {
            OldTweakToggle(manager: manager, title: "Internal Storage View", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Internal Features", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Apple Internal Install", onInfo: onInfo)
        } header: {
            Label("Internal", systemImage: "ant")
        }
    }

    // MARK: Lock Screen Footnote (post-v1 feature — its own section
    // so it stays reachable in the Old UI)

    private var footnoteSection: some View {
        Section {
            NavigationLink {
                FootnoteView()
            } label: {
                Label("Lock Screen Footnote", systemImage: "text.bubble")
            }
        } header: {
            Label("Lock Screen Footnote", systemImage: "text.bubble")
        } footer: {
            Text("Custom text shown at the bottom of the Lock Screen.")
        }
    }

    private var writeSettingsSection: some View {
        Section {
            Toggle("Persist after reboot", isOn: $atomicWrite)
        } header: {
            Label("Write Method", systemImage: "pencil.and.outline")
        } footer: {
            Text("When enabled, MobileGestalt is written in-place on the same inode, which (hopefully) prevents iOS from regenerating the cache on reboot. Disable to use atomic file replacement instead.")
        }
    }

    private var footerSection: some View {
        Section {
            NavigationLink {
                LicenseView()
            } label: {
                Label("License & Credits", systemImage: "doc.text")
            }

            Text("Built on the worse_query core system by ForceQuit OS, with CacheExtra key knowledge from mond by rooootdev (AGPL-3.0).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Toggle row (v1 style)

struct OldTweakToggle: View {
    @ObservedObject var manager: GestaltManager
    let title: String
    let onInfo: (GestaltTweak) -> Void

    var body: some View {
        if let tweak = TweakCatalog.all.first(where: { $0.title == title }) {
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
