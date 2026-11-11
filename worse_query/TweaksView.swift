import SwiftUI
import UIKit

// MARK: - Tweaks tab (v3.0 two-column layout)
//
// The tab is a two-column page: a scrolling column of tweak cards
// on the left and a fixed "Sections" card on the right (All /
// Dynamic Island / Tweaks / Apple Intelligence / Add feature /
// Apply/Revert); the card is vertically centered in
// the right column. Apply/Revert is a section of its own: its
// column holds the Apply / Respring / Revert action cards.
// Toggles
// mutate the in-memory MobileGestalt dictionary immediately;
// "Apply Tweaks" persists it. Every tweak keeps its own SF Symbol
// (see TweakCatalog.presentation), rendered uniformly as a plain
// accent-colored icon. The tab starts LOCKED until "Start Tweaks
// Feature" is turned on in the Sandbox tab
// (wt.tweaksFeatureEnabled).

/// The sections of the Tweaks tab's right-hand Sections card.
/// All = the full catalog; Apply/Revert holds the action cards
/// instead of tweaks.
enum TweakSection: String, CaseIterable, Identifiable {
    case all, dynamicIsland, tweaks, appleIntelligence, addFeature, applyRevert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .dynamicIsland: return "Dynamic Island"
        case .tweaks: return "Tweaks"
        case .appleIntelligence: return "Apple Intelligence"
        case .addFeature: return "Add feature"
        case .applyRevert: return "Apply/Revert"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .dynamicIsland: return "capsule.fill"
        case .tweaks: return "slider.horizontal.3"
        case .appleIntelligence: return "sparkles"
        case .addFeature: return "plus.circle"
        case .applyRevert: return "checkmark.circle"
        }
    }
}

/// Which section each catalog tweak belongs to — exactly one per
/// tweak, keyed by tweak id. The union of Dynamic Island / Tweaks /
/// Apple Intelligence / Add feature is the full 23-tweak catalog.
enum TweakCategory {
    static let sectionByID: [String: TweakSection] = [
        // Dynamic Island
        "enable_dynamic_island_capability": .dynamicIsland,
        // Apple Intelligence
        "apple_intelligence": .appleIntelligence,
        // Add feature
        "iphone_16_camera_control_settings": .addFeature,
        "action_button_settings": .addFeature,
        "apple_pencil_settings": .addFeature,
        "enable_ipados_mode": .addFeature,
        "allow_ipad_apps": .addFeature,
        "stage_manager_support": .addFeature,
        "charge_limit_menu": .addFeature,
        "tap_to_wake": .addFeature,
        "collision_sos": .addFeature,
        // Tweaks
        "always_on_display": .tweaks,
        "aod_vibrancy": .tweaks,
        "disable_wallpaper_parallax": .tweaks,
        "enable_liquid_glass_low_performance_mode": .tweaks,
        "disable_liquid_glass_low_performance_mode": .tweaks,
        "pulse_width_modulation": .tweaks,
        "boot_shutdown_chime": .tweaks,
        "security_research_device_mode": .tweaks,
        "disable_region_restrictions": .tweaks,
        "internal_storage_view": .tweaks,
        "apple_internal_install": .tweaks,
        "internal_features": .tweaks,
    ]

    static func section(of tweak: GestaltTweak) -> TweakSection {
        sectionByID[tweak.id] ?? .tweaks
    }
}

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
    /// Switches the TabView to the Extra tab (RootView owns the
    /// selection); used by the Menus card in the right column.
    var onOpenExtra: () -> Void
    /// Switches the TabView to the Backup tab (RootView owns the
    /// selection); used by the Menus card in the right column.
    var onOpenBackup: () -> Void

    @AppStorage("atomic_write") private var atomicWrite = true
    /// Master switch for this tab, flipped in the Sandbox tab.
    @AppStorage("wt.tweaksFeatureEnabled") private var tweaksEnabled = false

    @State private var infoTitle: String?
    @State private var infoMessage: String = ""
    @State private var showRevertConfirm = false
    @State private var selectedSection: TweakSection = .all

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
                    columnsView
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
                Text("This restores the MobileGestalt backup saved on first launch (SavedGestalt.plist).")
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

    // MARK: Two-column layout

    private var columnsView: some View {
        HStack(alignment: .top, spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    statusCard

                    if manager.isEmpty || !manager.isValid {
                        warningCard
                    }

                    // The Apply/Revert section's content is the
                    // action cards; every other section shows its
                    // tweak cards.
                    if selectedSection == .applyRevert {
                        actionsBlock
                    } else {
                        sectionCards
                    }

                    footerLinks
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)

            // The right column is filled top-to-bottom: a mini
            // identity card at the top, the Sections card held in
            // the middle by spacers, and a Menus quick-access card
            // at the bottom. The column spans the full height of
            // the row (driven by the ScrollView beside it) while
            // the left column scrolls.
            VStack(spacing: 0) {
                identityMiniCard
                Spacer(minLength: 0)
                sectionsCard
                Spacer(minLength: 0)
                menusCard
            }
            .frame(width: 150)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 16)
        }
        .padding(.horizontal, 16)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Sections card (right column, always visible)

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sections")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach(TweakSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.icon)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(selectedSection == section ? Color.white : Color.accentColor)
                            .frame(width: 22)
                        Text(section.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(selectedSection == section ? Color.white : Color.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        selectedSection == section ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    // MARK: Right-column companion cards (identity + menus)

    /// This build's version as recorded in the bundle
    /// (CFBundleShortVersionString), e.g. "3.5".
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    // Mini identity card at the top of the right column: app
    // name, version, device model, and iOS version + build.
    // Quiet and display-only — no buttons.
    private var identityMiniCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("WorkTweaks")
                .font(.subheadline.weight(.semibold))
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(machineName())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(SupportInfo.deviceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    // Menus quick-access card at the bottom of the right column:
    // navigation rows styled like the Sections rows, but plain —
    // they switch tabs instead of selecting a section. App Data
    // lives in the Sandbox tab's Utilities menu.
    private var menusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Menus")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            menuRow(title: "App Data", systemImage: "folder") { onOpenSandbox() }
            menuRow(title: "CacheExtra", systemImage: "key") { onOpenExtra() }
            menuRow(title: "Backup", systemImage: "externaldrive.badge.timemachine") { onOpenBackup() }
        }
        .padding(10)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func menuRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Status card

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 20))
                .foregroundStyle(statusColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                Text(statusSubtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if manager.grantingMG || manager.isLoading {
                Spacer()
                ProgressView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
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

    // "Do not reboot!" warning card (shown when the loaded
    // MobileGestalt plist is empty or invalid).
    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Do not reboot! Your MobileGestalt.plist seems to be \(manager.isEmpty ? "empty" : "invalid").")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            Text("Rebooting now might cause a bootloop. Try pressing 'Revert Tweaks'.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    // MARK: Section cards (left column)

    /// The tweaks shown for the selected section, in catalog order.
    private func visibleTweaks(for section: TweakSection) -> [GestaltTweak] {
        TweakCatalog.all.filter { tweak in
            // Same device conditionals as the old list layout.
            if tweak.id == "tap_to_wake" && !hasHomeButton() { return false }
            if tweak.id == "stage_manager_support" && UIDevice.current.userInterfaceIdiom != .pad { return false }
            switch section {
            case .all:
                return true
            default:
                return TweakCategory.section(of: tweak) == section
            }
        }
    }

    @ViewBuilder
    private var sectionCards: some View {
        ForEach(visibleTweaks(for: selectedSection)) { tweak in
            TweakCard(manager: manager, tweak: tweak, onInfo: showInfo(for:))
                .disabled(tweak.id == "enable_ipados_mode" && ipadOSModeLocked)

            // The Dynamic Island model picker lives directly
            // under its tweak's card.
            if tweak.id == "enable_dynamic_island_capability" {
                subtypeCard
            }
            // The spoofing model picker sits next to Apple
            // Intelligence, as before — in the All section and in
            // the Apple Intelligence section itself.
            if tweak.id == "apple_intelligence" && (selectedSection == .all || selectedSection == .appleIntelligence) {
                spoofingCard
            }
        }

        if selectedSection == .tweaks || selectedSection == .all {
            deviceNameCard
            persistCard
        }
    }

    /// Enable iPadOS Mode stays locked unless the device class in
    /// CacheExtra still reads "iPhone" (unchanged from v2.0).
    private var ipadOSModeLocked: Bool {
        let extra = manager.dictNow["CacheExtra"] as? [String: Any]
        return extra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone"
    }

    // MARK: Special cards (non-catalog controls)

    /// Device Artwork: the Dynamic Island subtype (model) picker.
    private var subtypeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RowIcon(systemImage: "capsule.fill")
                Text("Subtype")
                    .font(.subheadline.weight(.semibold))
            }
            Picker("Subtype", selection: $manager.selectedST) {
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
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    /// Device Artwork: Custom Device Name toggle + field.
    private var deviceNameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $manager.enableDeviceName) {
                HStack(spacing: 8) {
                    RowIcon(systemImage: "textformat")
                    Text("Custom Device Name")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if manager.enableDeviceName {
                TextField("Device Name", text: $manager.deviceName)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    /// Eligibility: the device-model spoofing picker.
    private var spoofingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RowIcon(systemImage: "iphone.gen3")
                Text("Spoofing")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    infoTitle = "Device Spoofing Info"
                    infoMessage = "Only spoof your device model if you want to download Apple Intelligence. This may break Face ID. If you decide to unspoof and want to keep Apple Intelligence, do NOT re-enter the Apple Intelligence & Siri menu in Settings."
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
            }
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
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    /// Write Method: "Persist after reboot" (atomic_write).
    private var persistCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $atomicWrite) {
                HStack(spacing: 8) {
                    RowIcon(systemImage: "externaldrive.fill")
                    Text("Persist after reboot")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text("When enabled, MobileGestalt is written in-place on the same inode, which (hopefully) prevents iOS from regenerating the cache on reboot. Disable to use atomic file replacement instead.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    // MARK: Actions (Apply / Respring / Revert)

    private var actionsBlock: some View {
        VStack(spacing: 12) {
            actionCardButton(title: "Apply Tweaks", systemImage: "checkmark.circle") {
                manager.apply()
                console.output += "\n(mg) Apply finished — see the Log for the write result.\n"
            }
            .disabled(!manager.isValid)

            actionCardButton(title: "Respring", systemImage: "arrow.counterclockwise") {
                RespringCenter.shared.trigger()
            }

            actionCardButton(title: "Revert Tweaks", systemImage: "arrow.uturn.backward", destructive: true) {
                showRevertConfirm = true
            }
            .disabled(!manager.isValid)

            Text("WARNING: These tweaks can break features on your device or softbrick it if misused. After Apply you choose Respring or Restart; Revert and Backup restores require a full device restart.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionCardButton(title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Color.red : Color.accentColor)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer links + credits line

    private var footerLinks: some View {
        VStack(spacing: 12) {
            NavigationLink {
                TutorialsView()
            } label: {
                footerLinkLabel(title: "Tutorials", systemImage: "book")
            }
            .buttonStyle(.plain)

            NavigationLink {
                LicenseView()
            } label: {
                footerLinkLabel(title: "License & Credits", systemImage: "doc.text")
            }
            .buttonStyle(.plain)

            Text("Built on the worse_query core system by ForceQuit OS, with CacheExtra key knowledge from mond by rooootdev (AGPL-3.0).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footerLinkLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            RowIcon(systemImage: systemImage)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private func showInfo(for tweak: GestaltTweak) {
        infoTitle = tweak.title
        infoMessage = tweak.infoMessage ?? ""
    }
}

// MARK: - Tweak card
//
// Compact vertical card for the two-column layout: the tweak's
// own SF Symbol as a plain accent-colored icon + an optional info
// button + the switch on the top row, then the tweak name and a
// state line ("On" / "Off", or "Requires iOS …" when the tweak
// needs a newer iOS). The switch stages changes through the same
// manager binding as before.

struct TweakCard: View {
    @ObservedObject var manager: GestaltManager
    let tweak: GestaltTweak
    let onInfo: (GestaltTweak) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                RowIcon(systemImage: tweak.icon)
                Spacer(minLength: 0)
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
            Text(tweak.title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(stateLine)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var stateLine: String {
        if !tweak.supported(), let minv = tweak.minv {
            return String(format: "Requires iOS %.1f+", minv)
        }
        return tweak.isOn(in: manager.dictNow) ? "On" : "Off"
    }
}
