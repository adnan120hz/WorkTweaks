import SwiftUI
import UIKit

// MARK: - Sileo UI (third Tweaks layout)
//
// The Tweaks tab's third layout, styled after the Sileo Featured
// page (repo adnan120hz/ui3-Ui): a dark page with a big title,
// a WorkTweaks banner card, a "Hot Right Now" package list, and a
// floating pill bar — adapted for tweaks. Only the layout differs:
// every toggle, picker and action reads the same GestaltManager
// state and runs the same apply/revert/respring code as the New
// and Old UIs, and the system (engine, backup, resolver, respring)
// is untouched. The Sileo green/teal accent is blue here, the
// packages below are WorkTweaks' own tweaks, and the icon shown
// is the WorkTweaks icon (Image "AppIconDisplay"), not Sileo's.
// Applies to the Tweaks tab only (wt.tweaksUIVersion: "sileo").

struct SileoTweaksView: View {
    let console: Console
    @ObservedObject var manager: GestaltManager
    /// Shows the info alert (owned by TweaksView) for a tweak.
    let onInfo: (GestaltTweak) -> Void
    /// Shows the Revert confirmation (owned by TweaksView).
    let onRevert: () -> Void
    /// Shows the Device Spoofing info alert (owned by TweaksView).
    let onSpoofingInfo: () -> Void

    @AppStorage("atomic_write") private var atomicWrite = true
    @State private var selectedSection: TweakSection = .all
    @State private var searchActive = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var showFixStatusBarGuide = false
    @State private var showFixAppleIntelligenceGuide = false

    /// Sileo's dark page background (#1C1C1E).
    private var sileoBackground: Color {
        Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    /// The list header: the All section keeps Sileo's
    /// "Hot Right Now" name; every other section shows its own.
    private var listTitle: String {
        selectedSection == .all ? "Hot Right Now" : selectedSection.title
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            sileoBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    bannerCard

                    if manager.isEmpty || !manager.isValid {
                        warningRow
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(listTitle)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)

                        if selectedSection == .applyRevert {
                            actionsBlock
                        } else {
                            tweakRows
                        }
                    }

                    footerLinks
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                // Room for the floating pill bar + search button.
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)

            bottomBar
        }
        .fullScreenCover(isPresented: $searchActive) {
            searchCover
        }
        .alert("Fix Status Bar", isPresented: $showFixStatusBarGuide) {
            Button("OK") { }
        } message: {
            Text("1. Use the iPhone 16 Pro subtype.\n2. Settings > Appearance > Display Zoom > Large Text, then go Back and set Text Size to Small (optional).")
        }
        .alert("Fix Apple Intelligence", isPresented: $showFixAppleIntelligenceGuide) {
            Button("OK") { }
        } message: {
            Text("1. Open the Translate app, delete the downloaded English (US) language, then download it again.\n2. Go to Settings > General > Language & Region, change the region from United States to another country, then change it back to United States.\n3. Turn off Low Power Mode (Settings > Battery).\n4. Connect to Wi-Fi (and keep your iPhone charging) while Apple Intelligence finishes downloading.")
        }
    }

    // MARK: Header (big title + WorkTweaks icon avatar)

    private var header: some View {
        HStack(alignment: .center) {
            Text("Tweaks")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            NavigationLink {
                LicenseView()
            } label: {
                Image("AppIconDisplay")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.blue, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("License & Credits")
        }
    }

    // MARK: Banner card (WorkTweaks featured card, blue)

    private var bannerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image("AppIconDisplay")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("WorkTweaks")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text("MobileGestalt Tweak App for iOS")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.caption.weight(.semibold))
                Text(statusLine)
                    .font(.caption.weight(.medium))
                Text("•")
                Text("Version \(appVersion)")
                Text("•")
                Text(SupportInfo.deviceSummary)
            }
            .foregroundStyle(.white.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.blue, Color(red: 0.0, green: 0.25, blue: 0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var statusIcon: String {
        if manager.isEmpty { return "exclamationmark.triangle.fill" }
        if manager.isValid { return "checkmark.seal.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var statusLine: String {
        if manager.isEmpty { return "MobileGestalt is empty" }
        if manager.isValid { return "MobileGestalt loaded" }
        if manager.mgGranted == false { return "Sandbox access denied" }
        if let error = manager.lastError { return error }
        return "Granting sandbox access…"
    }

    private var warningRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Do not reboot! Your MobileGestalt.plist seems to be \(manager.isEmpty ? "empty" : "invalid").")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            Text("Rebooting now might cause a bootloop. Try pressing 'Revert Tweaks'.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Tweak rows (Sileo package style)

    /// The tweaks shown for the selected section, in catalog order
    /// — the same filter and device conditionals as the New UI.
    private func visibleTweaks(for section: TweakSection) -> [GestaltTweak] {
        TweakCatalog.all.filter { tweak in
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

    private var tweakRows: some View {
        VStack(spacing: 0) {
            ForEach(visibleTweaks(for: selectedSection)) { tweak in
                packageRow(tweak)
                    .disabled(tweak.id == "enable_ipados_mode" && ipadOSModeLocked)

                // The Dynamic Island model picker lives directly
                // under its tweak's row.
                if tweak.id == "enable_dynamic_island_capability" {
                    subtypeRow
                }
                // The spoofing model picker sits next to Apple
                // Intelligence — in the All section and in the
                // Apple Intelligence section itself.
                if tweak.id == "apple_intelligence" && (selectedSection == .all || selectedSection == .appleIntelligence) {
                    spoofingRow
                }
            }

            if selectedSection == .tweaks || selectedSection == .all {
                deviceNameRow
                regionModelRow
                persistRow
            }

            if selectedSection == .addFeature {
                footnoteRow
            }
        }
    }

    /// One tweak as a Sileo package row: the tweak's icon in a
    /// blue rounded square, title + state line, and a toggle
    /// where Sileo puts its GET button.
    private func packageRow(_ tweak: GestaltTweak) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: tweak.icon)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tweak.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        if tweak.infoMessage != nil {
                            Button { onInfo(tweak) } label: {
                                Image(systemName: tweak.infoType == .warning || tweak.infoType == .error
                                      ? "exclamationmark.triangle"
                                      : "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(tweak.infoType == .warning || tweak.infoType == .error ? .orange : .white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(stateLine(for: tweak))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: 8)

                Toggle("", isOn: manager.toggleBinding(for: tweak))
                    .labelsHidden()
                    .tint(.blue)
                    .disabled(!manager.isValid || !tweak.supported())
            }
            .padding(.vertical, 12)

            // The fix guides live under their tweak's row while
            // the tweak is on (same guides as the New UI cards).
            if tweak.id == "enable_dynamic_island_capability", tweak.isOn(in: manager.dictNow) {
                Button("Fix Status Bar!") {
                    SoundEffects.playTap()
                    showFixStatusBarGuide = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.blue)
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
            if tweak.id == "apple_intelligence", tweak.isOn(in: manager.dictNow) {
                Button("Fix Apple Intelligence Here!") {
                    SoundEffects.playTap()
                    showFixAppleIntelligenceGuide = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.blue)
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }

            Divider()
                .background(Color.white.opacity(0.15))
        }
    }

    private func stateLine(for tweak: GestaltTweak) -> String {
        if !tweak.supported(), let minv = tweak.minv {
            return String(format: "Requires iOS %.1f+", minv)
        }
        return tweak.isOn(in: manager.dictNow) ? "On" : "Off"
    }

    /// Enable iPadOS Mode stays locked unless the device class in
    /// CacheExtra still reads "iPhone" (unchanged from v2.0).
    private var ipadOSModeLocked: Bool {
        let extra = manager.dictNow["CacheExtra"] as? [String: Any]
        return extra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone"
    }

    // MARK: Follower rows (pickers + custom name/region + persist)

    /// Device Artwork: the Dynamic Island subtype (model) picker.
    private var subtypeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "capsule.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Subtype")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
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
                        Text("iPhone 17 Pro").tag("17p")
                        Text("iPhone 17 Pro Max").tag("17pm")
                        Text("iPhone 18 Pro (iOS 27.0.1+)").tag("18p")
                        Text("iPhone 18 Pro Max (iOS 27.0.1+)").tag("18pm")
                        Text("iPhone Duo (iOS 27.3+)").tag("duo")
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
                .tint(.white)
            }
            .padding(.vertical, 12)
            Divider().background(Color.white.opacity(0.15))
        }
    }

    /// Eligibility: the device-model spoofing picker.
    private var spoofingRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Spoofing")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
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
                            Text("iPhone Duo (iOS 27.3+)").tag("iPhone19,4")
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.white)
                Button { onSpoofingInfo() } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            Divider().background(Color.white.opacity(0.15))
        }
    }

    /// Device Artwork: Custom Device Name toggle + field.
    private var deviceNameRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "textformat")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Custom Device Name")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Toggle("", isOn: $manager.enableDeviceName)
                    .labelsHidden()
                    .tint(.blue)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            }
            .padding(.vertical, 12)
            if manager.enableDeviceName {
                TextField("Device Name", text: $manager.deviceName)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)
            }
            Divider().background(Color.white.opacity(0.15))
        }
    }

    /// Device Artwork: Custom Region Model toggle + field.
    private var regionModelRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Custom Region Model")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Toggle("", isOn: $manager.enableCustomRegion)
                    .labelsHidden()
                    .tint(.blue)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            }
            .padding(.vertical, 12)
            if manager.enableCustomRegion {
                TextField("Region suffix (e.g. PA/A)", text: $manager.customRegionSuffix)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(10)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.white)
                Text("Type the region suffix as shown in Settings > General > About, e.g. PA/A or LL/A. It changes the Model Number suffix after Apply.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 8)
            }
            Divider().background(Color.white.opacity(0.15))
        }
    }

    /// Write Method: "Persist after reboot" (atomic_write).
    private var persistRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Persist after reboot")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Write MobileGestalt in-place on the same inode.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $atomicWrite)
                    .labelsHidden()
                    .tint(.blue)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            }
            .padding(.vertical, 12)
            Divider().background(Color.white.opacity(0.15))
        }
    }

    /// Lock Screen Footnote: the footnote editor's entry point.
    private var footnoteRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                FootnoteView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock Screen Footnote")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Custom text shown at the bottom of the Lock Screen.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().background(Color.white.opacity(0.15))
        }
    }

    // MARK: Actions (Apply / Respring / Revert)

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow(title: "Apply Tweaks", systemImage: "checkmark.circle") {
                manager.apply()
                console.output += "\n(mg) Apply finished — see the Log for the write result.\n"
            }
            .disabled(!manager.isValid)

            actionRow(title: "Respring", systemImage: "arrow.counterclockwise") {
                RespringCenter.shared.trigger()
            }

            actionRow(title: "Revert Tweaks", systemImage: "arrow.uturn.backward", destructive: true) {
                onRevert()
            }
            .disabled(!manager.isValid)

            Text("WARNING: These tweaks can break features on your device or softbrick it if misused. After Apply you choose Respring or Restart; Revert and Backup restores require a full device restart.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    private func actionRow(title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { SoundEffects.playTap(); action() }) {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(destructive ? Color.red : Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(destructive ? Color.red : Color.white)
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().background(Color.white.opacity(0.15))
        }
    }

    // MARK: Footer links

    private var footerLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                TutorialsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Tutorials")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink {
                LicenseView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("License & Credits")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("Built on the worse_query core system by ForceQuit OS, with CacheExtra key knowledge from mond by rooootdev (AGPL-3.0).")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Floating pill bar (section switcher) + search button

    /// Sileo's floating pill tab bar, adapted: the pill switches
    /// the Tweaks sections, and the blue circle opens search.
    private var bottomBar: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(TweakSection.allCases) { section in
                        Button {
                            SoundEffects.playTap()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedSection = section
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(section.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(selectedSection == section ? .white : .white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                selectedSection == section ? Color.blue : Color.clear,
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .background(.ultraThinMaterial, in: Capsule())

            Button {
                SoundEffects.playTap()
                searchActive = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search tweaks")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: Search (dedicated full-screen cover, Sileo style)

    private var searchCover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.6))
                    TextField("Search tweaks", text: $searchText)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .foregroundStyle(.white)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1), in: Capsule())

                Button("Cancel") {
                    closeSearch()
                }
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if searchResults.isEmpty {
                        Text("No tweaks match \"\(searchText)\".")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(searchResults) { tweak in
                            packageRow(tweak)
                                .disabled(tweak.id == "enable_ipados_mode" && ipadOSModeLocked)
                            if tweak.id == "enable_dynamic_island_capability" {
                                subtypeRow
                            }
                            if tweak.id == "apple_intelligence" {
                                spoofingRow
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(sileoBackground.ignoresSafeArea())
        .onAppear { searchFocused = true }
        .alert("Fix Status Bar", isPresented: $showFixStatusBarGuide) {
            Button("OK") { }
        } message: {
            Text("1. Use the iPhone 16 Pro subtype.\n2. Settings > Appearance > Display Zoom > Large Text, then go Back and set Text Size to Small (optional).")
        }
        .alert("Fix Apple Intelligence", isPresented: $showFixAppleIntelligenceGuide) {
            Button("OK") { }
        } message: {
            Text("1. Open the Translate app, delete the downloaded English (US) language, then download it again.\n2. Go to Settings > General > Language & Region, change the region from United States to another country, then change it back to United States.\n3. Turn off Low Power Mode (Settings > Battery).\n4. Connect to Wi-Fi (and keep your iPhone charging) while Apple Intelligence finishes downloading.")
        }
    }

    private func closeSearch() {
        searchText = ""
        searchActive = false
        searchFocused = false
    }

    /// Tweaks whose names match the query, across the whole
    /// catalog regardless of the selected section — with the
    /// same per-device conditionals as the section lists.
    private var searchResults: [GestaltTweak] {
        TweakCatalog.all.filter { tweak in
            if tweak.id == "tap_to_wake" && !hasHomeButton() { return false }
            if tweak.id == "stage_manager_support" && UIDevice.current.userInterfaceIdiom != .pad { return false }
            return searchText.isEmpty || tweak.title.localizedCaseInsensitiveContains(searchText)
        }
    }
}
