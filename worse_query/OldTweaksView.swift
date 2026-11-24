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
    @EnvironmentObject private var wtLang: WTLangStore
    /// Shows the info alert (owned by TweaksView) for a tweak.
    let onInfo: (GestaltTweak) -> Void
    /// Shows the Revert confirmation (owned by TweaksView).
    let onRevert: () -> Void
    /// Shows the Device Spoofing info alert (owned by TweaksView).
    let onSpoofingInfo: () -> Void

    @AppStorage("atomic_write") private var atomicWrite = true
    @State private var showFixStatusBarGuide = false
    @State private var showFixAppleIntelligenceGuide = false
    @State private var showSiriGuide = false

    /// The manual Siri patch's current state (chunk 97 of
    /// CacheData, read from the in-memory dict).
    private var siriPatchState: SiriPatchState {
        SiriPatchState.current(cacheData: manager.dictNow["CacheData"] as? Data)
    }

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
        .alert(wtLang.tr("Fix Status Bar"), isPresented: $showFixStatusBarGuide) {
            Button(wtLang.tr("OK")) { }
        } message: {
            Text(wtLang.tr("1. Use the iPhone 16 Pro subtype.\n2. Settings > Appearance > Display Zoom > Large Text, then go Back and set Text Size to Small (optional)."))
        }
        .alert(wtLang.tr("Fix Apple Intelligence"), isPresented: $showFixAppleIntelligenceGuide) {
            Button(wtLang.tr("OK")) { }
        } message: {
            Text(wtLang.tr("1. Open the Translate app, delete the downloaded English (US) language, then download it again.\n2. Go to Settings > General > Language & Region, change the region from United States to another country, then change it back to United States.\n3. Turn off Low Power Mode (Settings > Battery).\n4. Connect to Wi-Fi (and keep your iPhone charging) while Apple Intelligence finishes downloading."))
        }
        .alert(wtLang.tr("Siri AI Cache Patch"), isPresented: $showSiriGuide) {
            Button(wtLang.tr("OK")) { }
        } message: {
            Text(SiriManualGuide.fullText(wtLang: wtLang))
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
        if manager.isEmpty { return wtLang.tr("MobileGestalt is empty") }
        if manager.isValid { return wtLang.tr("MobileGestalt loaded") }
        if manager.mgGranted == false { return wtLang.tr("Sandbox access denied") }
        return wtLang.tr("Not loaded")
    }

    private var statusSubtitle: String {
        if let error = manager.lastError { return error }
        if manager.isValid { return wtLang.tr("Sandbox extension is ready (directory grant held).") }
        return wtLang.tr("Granting sandbox access…")
    }

    private var warningSection: some View {
        Section {
            Label {
                Text(wtLang.tr("Do not reboot! Your MobileGestalt.plist seems to be %@.", wtLang.tr(manager.isEmpty ? "empty" : "invalid")))
                    .font(.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
        } header: {
            Label(wtLang.tr("Warning"), systemImage: "exclamationmark.triangle")
        } footer: {
            Text(wtLang.tr("Rebooting now might cause a bootloop. Try pressing 'Revert Tweaks'."))
        }
    }

    // MARK: Actions (Apply / Respring / Revert)

    private var actionSection: some View {
        Section {
            Button {
                SoundEffects.playTap()
                manager.apply()
                console.output += "\n(mg) Apply finished — see the Log for the write result.\n"
            } label: {
                Label(wtLang.tr("Apply Tweaks"), systemImage: "checkmark.circle.fill")
            }
            .disabled(!manager.isValid)

            Button {
                SoundEffects.playTap()
                RespringCenter.shared.trigger()
            } label: {
                Label(wtLang.tr("Respring"), systemImage: "restart.circle")
            }

            Button(role: .destructive) {
                SoundEffects.playTap()
                onRevert()
            } label: {
                Label(wtLang.tr("Revert Tweaks"), systemImage: "arrow.uturn.backward.circle")
            }
            .disabled(!manager.isValid)
        } footer: {
            Text(wtLang.tr("WARNING: These tweaks can break features on your device or softbrick it if misused. After Apply you choose Respring or Restart; Revert and Backup restores require a full device restart."))
        }
    }

    // MARK: Device Artwork (Subtype picker + Custom Device Name)

    private var artworkSection: some View {
        Section {
            Picker(selection: $manager.selectedST) {
                Text(wtLang.tr("Original (%d)", manager.ogST)).tag("og")

                if isDeviceGoodForNoDynamicIsland() {
                    Text(wtLang.tr("Disable Dynamic Island")).tag("no_dynamic_island")
                }

                Text("iPhone 14 Pro").tag("14p")
                Text("iPhone 14 Pro Max").tag("14pm")
                Text("iPhone 15 Pro Max").tag("15pm")

                if doubleSystemVersion() >= 18.0 {
                    Text("iPhone 16 Pro").tag("16p")
                    Text("iPhone 16 Pro Max").tag("16pm")
                    Text("iPhone 17 Pro").tag("17p")
                    Text("iPhone 17 Pro Max").tag("17pm")
                    Text("iPhone 18 Pro (iOS 27.0.1+)").tag("18p")
                    Text("iPhone 18 Pro Max (iOS 27.0.1+)").tag("18pm")
                    Text("iPhone Duo (iOS 27.3+)").tag("duo")
                }

                if doubleSystemVersion() >= 26.0 {
                    Text("iPhone Air").tag("air")
                }

                Text("iPhone X Gestures").tag("x")
                Text("iPhone SE").tag("se")
            } label: {
                Text(wtLang.tr("Subtype"))
            }

            Toggle(wtLang.tr("Custom Device Name"), isOn: $manager.enableDeviceName)
                .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })

            if manager.enableDeviceName {
                TextField(wtLang.tr("Device Name"), text: $manager.deviceName)
                    .autocorrectionDisabled()
            }

            Toggle(wtLang.tr("Custom Region Model"), isOn: $manager.enableCustomRegion)
                .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })

            if manager.enableCustomRegion {
                TextField(wtLang.tr("Region suffix (e.g. PA/A)"), text: $manager.customRegionSuffix)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }
        } header: {
            Label(wtLang.tr("Device Artwork"), systemImage: "paintbrush.pointed")
        }
    }

    // MARK: Tweak sections (same catalog as the New UI)

    private var softwareSection: some View {
        Section {
            OldTweakToggle(manager: manager, title: "Enable Dynamic Island Capability", onInfo: onInfo)
            // The status-bar fix guide, next to the Dynamic
            // Island toggle while it is on (same guide as the
            // New UI card's "Fix Status Bar!" button).
            if isDynamicIslandOn {
                Button(wtLang.tr("Fix Status Bar!")) {
                    SoundEffects.playTap()
                    showFixStatusBarGuide = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            OldTweakToggle(manager: manager, title: "Always-On Display", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "AOD Vibrancy", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Disable Wallpaper Parallax", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Charge Limit Menu", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Boot & Shutdown Chime", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Enable Liquid Glass Low-Performance Mode", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Disable Liquid Glass Low-Performance Mode", onInfo: onInfo)
        } header: {
            Label(wtLang.tr("Software-Oriented Features"), systemImage: "gearshape")
        }
    }

    /// Whether the Dynamic Island capability tweak is on —
    /// the Fix Status Bar guide only shows while it is.
    private var isDynamicIslandOn: Bool {
        TweakCatalog.all.first(where: { $0.id == "enable_dynamic_island_capability" })?.isOn(in: manager.dictNow) ?? false
    }

    /// Whether the Apple Intelligence tweak is on —
    /// the Fix Apple Intelligence guide only shows while it is.
    private var isAppleIntelligenceOn: Bool {
        TweakCatalog.all.first(where: { $0.id == "apple_intelligence" })?.isOn(in: manager.dictNow) ?? false
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
            Label(wtLang.tr("Hardware-Oriented Features"), systemImage: "iphone")
        }
    }

    private var eligibilitySection: some View {
        Section {
            OldTweakToggle(manager: manager, title: "Security Research Device Mode", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Disable Region Restrictions", onInfo: onInfo)
            OldTweakToggle(manager: manager, title: "Apple Intelligence", onInfo: onInfo)
            // The Apple Intelligence fix guide, next to the
            // Apple Intelligence toggle while it is on (same
            // guide as the New UI card's
            // "Fix Apple Intelligence Here!" button).
            if isAppleIntelligenceOn {
                Button(wtLang.tr("Fix Apple Intelligence Here!")) {
                    SoundEffects.playTap()
                    showFixAppleIntelligenceGuide = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            // Siri AI Cache Patch is manual now (the automatic
            // pattern is ambiguous on some devices): a Read
            // Tutorial row, and the Mobile Gestalt.plist menu
            // row directly below it.
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Siri AI Cache Patch")
                        .font(.subheadline.weight(.medium))
                    Text(siriPatchState.line(wtLang: wtLang))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(wtLang.tr("Read Tutorial")) {
                    SoundEffects.playTap()
                    showSiriGuide = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
            NavigationLink {
                MobileGestaltPlistView(manager: manager)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                    Text("Mobile Gestalt.plist")
                        .font(.subheadline.weight(.medium))
                }
            }

            HStack(spacing: 10) {
                Picker(wtLang.tr("Spoofing"), selection: $manager.productType) {
                    Text(wtLang.tr("Default")).tag(machineName())
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
                            Text("iPhone Duo (iOS 27.3+)").tag("iPhone19,4")
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
            Label(wtLang.tr("Eligibility"), systemImage: "checklist")
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
            Label(wtLang.tr("iPadOS Features"), systemImage: "ipad")
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
            Label(wtLang.tr("Internal"), systemImage: "ant")
        }
    }

    // MARK: Lock Screen Footnote (post-v1 feature — its own section
    // so it stays reachable in the Old UI)

    private var footnoteSection: some View {
        Section {
            NavigationLink {
                FootnoteView()
            } label: {
                Label(wtLang.tr("Lock Screen Footnote"), systemImage: "text.bubble")
            }
        } header: {
            Label(wtLang.tr("Lock Screen Footnote"), systemImage: "text.bubble")
        } footer: {
            Text(wtLang.tr("Custom text shown at the bottom of the Lock Screen."))
        }
    }

    private var writeSettingsSection: some View {
        Section {
            Toggle(wtLang.tr("Persist after reboot"), isOn: $atomicWrite)
                .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
        } header: {
            Label(wtLang.tr("Write Method"), systemImage: "pencil.and.outline")
        } footer: {
            Text(wtLang.tr("When enabled, MobileGestalt is written in-place on the same inode, which (hopefully) prevents iOS from regenerating the cache on reboot. Disable to use atomic file replacement instead."))
        }
    }

    private var footerSection: some View {
        Section {
            NavigationLink {
                LicenseView()
            } label: {
                Label(wtLang.tr("License & Credits"), systemImage: "doc.text")
            }

            Text(wtLang.tr("Built on the worse_query core system by ForceQuit OS, with CacheExtra key knowledge from mond by rooootdev (AGPL-3.0)."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Toggle row (v1 style)

struct OldTweakToggle: View {
    @ObservedObject var manager: GestaltManager
    @EnvironmentObject private var wtLang: WTLangStore
    let title: String
    let onInfo: (GestaltTweak) -> Void

    var body: some View {
        if let tweak = TweakCatalog.all.first(where: { $0.title == title }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tweak.title)
                        .font(.subheadline.weight(.medium))
                    if !tweak.supported(), let minv = tweak.minv {
                        Text(wtLang.tr("Requires iOS %.1f+", minv))
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
