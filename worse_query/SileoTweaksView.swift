import SwiftUI
import UIKit

// MARK: - Featured page (Sileo UI)
//
// The Featured tab of the Sileo UI: a faithful copy of Sileo
// 2.5.1's Featured page (repo adnan120hz/ui3-Ui, as shown in
// the user's screen recording) — a horizontal banner carousel
// on top, then the tweak sections stacked with 22pt headers,
// each tweak as a Sileo package row (its own tint icon, three
// lines, a Liquid Glass toggle). The banners are colorful info
// cards now — the version, the supported iOS list, the iPhone
// lineup, and the tweak count — not just the release version.
// The big "Featured" title and the avatar (top right, opens
// settings) live in the navigation bar, like Sileo's — there
// is no second title in the content. No Twitter / Website /
// Discord / Support buttons — the user had those removed.
// The page follows the system appearance (Light or Dark Mode).
// Only the layout differs: every toggle, picker and action
// reads the same GestaltManager state and runs the same
// apply/revert/respring code as the New and Old UIs, and the
// system (engine, backup, resolver, respring) is untouched.

struct SileoTweaksView: View {
    let console: Console
    @ObservedObject var manager: GestaltManager
    /// Shows the Revert confirmation (owned by TweaksView).
    let onRevert: () -> Void
    /// Shows the Device Spoofing info alert (owned by TweaksView).
    let onSpoofingInfo: () -> Void

    @AppStorage("atomic_write") private var atomicWrite = true
    /// The shell's shared state: the search cover is opened by
    /// the floating search circle at the bottom right, the
    /// banner opens the News tab, and the avatar opens the
    /// settings sheet — all through this environment object.
    @EnvironmentObject private var shell: SileoShellState
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var showFixStatusBarGuide = false
    @State private var showFixAppleIntelligenceGuide = false
    /// The changelog sheet, opened by tapping a release banner.
    @State private var showNews = false
    /// The tweak whose detail sheet is open (GET tapped) —
    /// the sheet holds its explanation, its fix if it has
    /// one, and its toggle. It carries the grouped icon color
    /// and group title the row showed, so the sheet matches.
    private struct TweakDetail: Identifiable {
        let tweak: GestaltTweak
        let iconColor: Color
        let groupTitle: String
        var id: String { tweak.id }
    }
    @State private var detailTweak: TweakDetail?
    /// The custom row whose detail sheet is open (GET tapped).
    @State private var detailFollower: FollowerDetail?

    /// One row on the Featured page: a catalog tweak, or one
    /// of the custom rows (pickers, custom name/region,
    /// persist, footnote).
    private enum FeaturedRow: Identifiable {
        case tweak(GestaltTweak)
        case subtype
        case spoofing
        case deviceName
        case regionModel
        case persist
        case footnote
        var id: String {
            switch self {
            case .tweak(let tweak): return tweak.id
            case .subtype: return "subtype"
            case .spoofing: return "spoofing"
            case .deviceName: return "deviceName"
            case .regionModel: return "regionModel"
            case .persist: return "persist"
            case .footnote: return "footnote"
            }
        }
    }

    /// One group on the Featured page: a title and its rows.
    private struct FeaturedGroup {
        let title: String
        let rows: [FeaturedRow]
    }

    /// A custom row whose detail sheet is open.
    private enum FollowerDetail: String, Identifiable {
        case deviceName, regionModel, persist
        var id: String { rawValue }
    }

    /// The groups, stacked in order on the Featured page —
    /// the user's own grouping, not the catalog sections.
    /// Tweaks he did not list (Apple Pencil, Stage Manager,
    /// Charge Limit, Tap to Wake, the Liquid Glass modes,
    /// Boot Chime) sit in "More Tweaks" so nothing is lost,
    /// then Apply / Revert / Respring close the page.
    private var featuredGroups: [FeaturedGroup] {
        let byId = Dictionary(uniqueKeysWithValues: TweakCatalog.all.map { ($0.id, $0) })
        func pick(_ ids: [String]) -> [FeaturedRow] {
            ids.compactMap { byId[$0] }.filter { tweak in
                if tweak.id == "tap_to_wake" && !hasHomeButton() { return false }
                if tweak.id == "stage_manager_support" && UIDevice.current.userInterfaceIdiom != .pad { return false }
                return true
            }.map { .tweak($0) }
        }
        return [
            FeaturedGroup(title: "Dynamic Island", rows: pick(["enable_dynamic_island_capability"]) + [.subtype]),
            FeaturedGroup(title: "Apple Intelligence", rows: pick(["apple_intelligence"]) + [.spoofing] + pick(["siri_ai_cache_patch", "disable_region_restrictions"])),
            FeaturedGroup(title: "Internal", rows: pick(["internal_features", "internal_storage_view", "apple_internal_install"])),
            FeaturedGroup(title: "Always On Display", rows: pick(["always_on_display", "aod_vibrancy"])),
            FeaturedGroup(title: "System", rows: pick(["disable_wallpaper_parallax", "pulse_width_modulation", "security_research_device_mode", "collision_sos"])),
            FeaturedGroup(title: "Buttons", rows: pick(["iphone_16_camera_control_settings", "action_button_settings"])),
            FeaturedGroup(title: "Custom", rows: [.deviceName, .regionModel, .footnote]),
            FeaturedGroup(title: "iPad", rows: pick(["enable_ipados_mode", "allow_ipad_apps"])),
            FeaturedGroup(title: "More Tweaks", rows: pick(["apple_pencil_settings", "stage_manager_support", "charge_limit_menu", "tap_to_wake", "enable_liquid_glass_low_performance_mode", "disable_liquid_glass_low_performance_mode", "boot_shutdown_chime"]) + [.persist]),
        ]
    }

    /// The info banners: the version, the supported iOS list,
    /// the iPhone lineup, and the tweak count — each its own
    /// color, so the carousel is colorful, not one flat blue.
    /// Tap one to open the News tab (the full changelog).
    private struct InfoBanner: Identifiable {
        let id: String
        let title: String
        let headline: String
        let colors: [Color]
        /// SF symbol in a glass circle; nil shows the WT icon.
        let icon: String?
    }

    private var infoBanners: [InfoBanner] {
        [
            InfoBanner(id: "version", title: "WorkTweaks v\(appVersion)",
                       headline: "Liquid Glass everywhere — glass toggles, glass search, light & dark",
                       colors: [.blue, .indigo], icon: nil),
        ]
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        // Extra bottom padding so the last rows clear the
        // floating pill + search circle at the bottom.
        SileoPage(bottomPadding: 120) {
            bannerCarousel

            if manager.isEmpty || !manager.isValid {
                warningRow
            }

            ForEach(Array(featuredGroups.enumerated()), id: \.offset) { groupIndex, group in
                SileoSectionTitle(text: group.title)
                // The icon colors run in one continuous sequence
                // down the page (four blue, four gray, four
                // cyan, four dark), so each group starts where
                // the previous one left off. The offset counts
                // EVERY icon row in the group — not just the
                // tweaks — so the blocks never break where a
                // picker or custom row sits.
                groupRows(group, startingAt: featuredGroups.prefix(groupIndex).reduce(0) { $0 + $1.rows.count })
            }

            // Apply / Revert / Respring close the page, after
            // every group.
            SileoSectionTitle(text: "Actions")
            actionsBlock

            footerCredit
        }
        .toolbar {
            // Backup and Fix Issue sit at the top left, on the
            // same row as the profile avatar (top right).
            // Backup jumps straight to the Backup tab; Fix
            // Issue holds the two fix guides (Apple Intelligence
            // and the status bar) so they are always one tap
            // away instead of only under their tweak's row.
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button {
                    SoundEffects.playTap()
                    shell.backupActive = true
                } label: {
                    Label("Backup", systemImage: "externaldrive.fill")
                }
                .accessibilityLabel("Backup")

                Menu {
                    Button("Fix Apple Intelligence") {
                        SoundEffects.playTap()
                        showFixAppleIntelligenceGuide = true
                    }
                    Button("Fix Status Bar") {
                        SoundEffects.playTap()
                        showFixStatusBarGuide = true
                    }
                } label: {
                    Label("Fix Issue", systemImage: "wrench.and.screwdriver.fill")
                }
                .accessibilityLabel("Fix Issue")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    SoundEffects.playTap()
                    shell.settingsActive = true
                } label: {
                    Image("AppIconDisplay")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("WorkTweaks settings")
            }
        }
        .fullScreenCover(isPresented: $shell.searchActive) {
            searchCover
        }
        .sheet(isPresented: $showNews) {
            SileoNewsView()
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
        .sheet(item: $detailTweak) { detail in
            SileoTweakDetailSheet(manager: manager, detail: detail)
        }
        .sheet(item: $detailFollower) { follower in
            SileoFollowerDetailSheet(manager: manager, follower: follower, atomicWrite: $atomicWrite)
        }
    }

    // MARK: Banner carousel (info cards)

    /// Sileo's banner carousel: full-width cards, swiped
    /// sideways. Each card is one piece of information — the
    /// version, the supported iOS list, the iPhone lineup, the
    /// tweak count — in its own color, and tapping one opens
    /// the News tab (the full changelog). The text sits in the
    /// middle of the card, centered, so a long list (the iOS
    /// versions) reads as a centered block instead of spilling
    /// down the left edge.
    private var bannerCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(infoBanners) { banner in
                    Button {
                        SoundEffects.playTap()
                        showNews = true
                    } label: {
                        ZStack(alignment: .center) {
                            LinearGradient(
                                colors: banner.colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            VStack(alignment: .center, spacing: 8) {
                                if let icon = banner.icon {
                                    Image(systemName: icon)
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 56, height: 56)
                                        // A plain translucent circle, not
                                        // glassEffect: the icon sits inside
                                        // a Button label, and glassEffect on
                                        // a button broke taps in v5.8.
                                        .background(.white.opacity(0.25), in: Circle())
                                } else {
                                    Image("AppIconDisplay")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                VStack(alignment: .center, spacing: 2) {
                                    Text(banner.title)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                    Text(banner.headline)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                        }
                        .frame(width: UIScreen.main.bounds.width - 32, height: 196)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var warningRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Do not reboot! Your MobileGestalt.plist seems to be \(manager.isEmpty ? "empty" : "invalid").")
                    .font(.subheadline)
                    .foregroundStyle(Sileo.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            Text("Rebooting now might cause a bootloop. Try pressing 'Revert Tweaks'.")
                .font(.caption).foregroundStyle(Sileo.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Groups

    @ViewBuilder
    /// The rows of one group, in order. `startingAt` is the
    /// group's first row's position in the page's whole row
    /// sequence, so the icon colors run continuously down
    /// the page instead of restarting per group.
    private func groupRows(_ group: FeaturedGroup, startingAt offset: Int) -> some View {
        ForEach(Array(group.rows.enumerated()), id: \.element.id) { rowIndex, row in
            let color = groupedIconColor(at: offset + rowIndex)
            switch row {
            case .tweak(let tweak):
                SileoTweakRow(manager: manager, tweak: tweak, onOpen: { detailTweak = TweakDetail(tweak: $0, iconColor: color, groupTitle: group.title) }, iconTileColor: color, author: group.title)
                // The fix guides live in the tweak's detail
                // sheet now (GET opens it), not under the row.
            case .subtype:
                subtypeRow(color: color)
            case .spoofing:
                spoofingRow(color: color)
            case .deviceName:
                deviceNameRow(color: color)
            case .regionModel:
                regionModelRow(color: color)
            case .persist:
                persistRow(color: color)
            case .footnote:
                footnoteRow(color: color)
            }
        }
    }

    /// The tweak icon tile colors, in blocks of four down the
    /// page — four blue, four gray, four cyan, four dark, then
    /// blue again — so the colors are grouped, never random.
    /// The symbol is always white. The dark tile is the
    /// palette's dark (near-black); light is not in the cycle.
    private func groupedIconColor(at index: Int) -> Color {
        switch (index / 4) % 4 {
        case 0: return .blue
        case 1: return .gray
        case 2: return .cyan
        default: return Color(red: 0.16, green: 0.16, blue: 0.18)
        }
    }

    // MARK: Follower rows (pickers + custom name/region + persist)

    /// One follower row: the package icon + three lines, with
    /// the picker on the right (a menu picker shows its current
    /// value, like Sileo's rows show their state).
    private func followerRow(icon: String, iconColor: Color, title: String, author: String) -> some View {
        HStack(spacing: 16) {
            SileoIcon(systemImage: icon, color: iconColor, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Sileo.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(author)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Sileo.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("WorkTweaks")
                    .font(.system(size: 11))
                    .foregroundStyle(Sileo.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Device Artwork: the Dynamic Island subtype (model) picker.
    /// The icon color comes from the page's grouped sequence,
    /// so it continues the block its tweak sits in.
    private func subtypeRow(color: Color) -> some View {
        HStack(spacing: 16) {
            followerRow(icon: "capsule.fill", iconColor: color, title: "Subtype", author: "Dynamic Island")
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
            .tint(Sileo.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sileo.separator).frame(height: 1)
        }
    }

    /// Eligibility: the device-model spoofing picker.
    /// The icon color comes from the page's grouped sequence,
    /// so it continues the block its tweak sits in.
    private func spoofingRow(color: Color) -> some View {
        HStack(spacing: 16) {
            followerRow(icon: "iphone.gen3", iconColor: color, title: "Spoofing", author: "Device model")
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
            .tint(Sileo.accent)
            Button { onSpoofingInfo() } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Sileo.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sileo.separator).frame(height: 1)
        }
    }

    /// Sileo's GET pill: opens the row's detail sheet. It reads
    /// ON in green when the row is on, GET in blue when off.
    private func getPill(isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            SoundEffects.playTap()
            action()
        } label: {
            Text(isOn ? "ON" : "GET")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isOn ? Color.green : Sileo.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The GET pill as a label (not a button) — for rows that
    /// navigate, where the whole row is the tap target.
    private func getPillLabel(isOn: Bool) -> some View {
        Text(isOn ? "ON" : "GET")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isOn ? Color.green : Sileo.accent, in: Capsule())
    }

    /// Device Artwork: Custom Device Name. The row carries a
    /// GET pill now (no toggle on the row) — GET opens its
    /// detail sheet, where the toggle and the name field live.
    /// The icon color comes from the page's grouped sequence.
    private func deviceNameRow(color: Color) -> some View {
        SileoPackageRow(icon: "textformat", iconColor: color, title: "Custom Device Name", author: "Shown in Settings > General > About", version: "WorkTweaks", onTap: { detailFollower = .deviceName }) {
            getPill(isOn: manager.enableDeviceName) { detailFollower = .deviceName }
        }
    }

    /// Device Artwork: Custom Region Model. The row carries a
    /// GET pill now — GET opens its detail sheet, where the
    /// toggle and the region field live.
    private func regionModelRow(color: Color) -> some View {
        SileoPackageRow(icon: "globe", iconColor: color, title: "Custom Region Model", author: "Type the sales-region suffix", version: "WorkTweaks", onTap: { detailFollower = .regionModel }) {
            getPill(isOn: manager.enableCustomRegion) { detailFollower = .regionModel }
        }
    }

    /// Write Method: "Persist after reboot" (atomic_write).
    /// The row carries a GET pill now — GET opens its detail
    /// sheet, where the toggle lives.
    private func persistRow(color: Color) -> some View {
        SileoPackageRow(icon: "externaldrive.fill", iconColor: color, title: "Persist after reboot", author: "Write MobileGestalt in-place on the same inode.", version: "WorkTweaks", onTap: { detailFollower = .persist }) {
            getPill(isOn: atomicWrite) { detailFollower = .persist }
        }
    }

    /// Lock Screen Footnote: the footnote editor's entry point.
    /// The row carries a GET pill now — tapping it (or the row)
    /// opens the footnote editor.
    private func footnoteRow(color: Color) -> some View {
        NavigationLink {
            FootnoteView()
        } label: {
            HStack(spacing: 16) {
                SileoIcon(systemImage: "text.bubble", color: color, size: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock Screen Footnote")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Sileo.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Custom text at the bottom of the Lock Screen")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Sileo.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("WorkTweaks")
                        .font(.system(size: 11))
                        .foregroundStyle(Sileo.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                getPillLabel(isOn: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sileo.separator).frame(height: 1)
        }
    }

    // MARK: Actions (Apply / Respring / Revert)

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow(title: "Apply Tweaks", author: "Write staged tweaks", systemImage: "checkmark.circle", pill: "APPLY", destructive: false) {
                manager.apply()
                console.output += "\n(mg) Apply finished — see the Log for the write result.\n"
            }
            .disabled(!manager.isValid)

            actionRow(title: "Respring", author: "Reload SpringBoard", systemImage: "arrow.counterclockwise", pill: "RESPRING", destructive: false) {
                RespringCenter.shared.trigger()
            }

            actionRow(title: "Revert Tweaks", author: "Restore the original", systemImage: "arrow.uturn.backward", pill: "REVERT", destructive: true) {
                onRevert()
            }
            .disabled(!manager.isValid)

            Text("WARNING: These tweaks can break features on your device or softbrick it if misused. After Apply you choose Respring or Restart; Revert and Backup restores require a full device restart.")
                .font(.caption).foregroundStyle(Sileo.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
    }

    private func actionRow(title: String, author: String, systemImage: String, pill: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            SileoIcon(systemImage: systemImage, color: destructive ? .red : .blue, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(destructive ? Color.red : Sileo.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(author)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Sileo.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("WorkTweaks")
                    .font(.system(size: 11))
                    .foregroundStyle(Sileo.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                SoundEffects.playTap()
                action()
            } label: {
                Text(pill)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(destructive ? Color.red : Sileo.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            SoundEffects.playTap()
            action()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sileo.separator).frame(height: 1)
        }
    }

    // MARK: Footer

    private var footerCredit: some View {
        Text("Built on the worse_query core system by ForceQuit OS, with CacheExtra key knowledge from mond by rooootdev (AGPL-3.0).")
            .font(.caption).foregroundStyle(Sileo.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
    }

    // MARK: Search (dedicated full-screen cover, Sileo style)

    private var searchCover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Sileo.secondary)
                    TextField("Search for Tweaks", text: $searchText)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .foregroundStyle(Sileo.primary)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Sileo.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())

                // Sileo's search closes with an X circle — glass,
                // like the search circle on the pill — the
                // native glass button, so it stays tappable.
                Button {
                    closeSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close search")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if searchResults.isEmpty {
                        Text("No tweaks match \"\(searchText)\".")
                            .font(.subheadline)
                            .foregroundStyle(Sileo.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { searchIndex, tweak in
                            SileoTweakRow(manager: manager, tweak: tweak, onOpen: { detailTweak = TweakDetail(tweak: $0, iconColor: groupedIconColor(at: searchIndex), groupTitle: TweakCategory.section(of: $0).title) }, iconTileColor: groupedIconColor(at: searchIndex), author: TweakCategory.section(of: tweak).title)
                            if tweak.id == "enable_dynamic_island_capability" {
                                subtypeRow(color: groupedIconColor(at: searchIndex + 1))
                            }
                            if tweak.id == "apple_intelligence" {
                                spoofingRow(color: groupedIconColor(at: searchIndex + 1))
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Sileo.background.ignoresSafeArea())
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
        shell.searchActive = false
        searchFocused = false
    }

    /// Tweaks whose names match the query, across the whole
    /// catalog regardless of section — with the same per-device
    /// conditionals as the section lists.
    private var searchResults: [GestaltTweak] {
        TweakCatalog.all.filter { tweak in
            if tweak.id == "tap_to_wake" && !hasHomeButton() { return false }
            if tweak.id == "stage_manager_support" && UIDevice.current.userInterfaceIdiom != .pad { return false }
            return searchText.isEmpty || tweak.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: Detail sheets (GET)

    /// A tweak's detail sheet, opened by its GET pill: the
    /// package icon and title, the explanation, the fix if
    /// it has one (shown while the tweak is on), and then
    /// the toggle — the only place the toggle lives now.
    private struct SileoTweakDetailSheet: View {
        @ObservedObject var manager: GestaltManager
        let detail: TweakDetail
        @Environment(\.dismiss) private var dismiss

        private var tweak: GestaltTweak { detail.tweak }

        private var ipadOSModeLocked: Bool {
            let extra = manager.dictNow["CacheExtra"] as? [String: Any]
            return extra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone"
        }

        private var toggleDisabled: Bool {
            !manager.isValid || !tweak.supported()
                || (tweak.id == "enable_ipados_mode" && ipadOSModeLocked)
        }

        /// The fix guide, when this tweak has one.
        private var fix: (title: String, text: String)? {
            if tweak.id == "enable_dynamic_island_capability" {
                return ("Fix Status Bar", "1. Use the iPhone 16 Pro subtype.\n2. Settings > Appearance > Display Zoom > Large Text, then go Back and set Text Size to Small (optional).")
            }
            if tweak.id == "apple_intelligence" {
                return ("Fix Apple Intelligence", "1. Open the Translate app, delete the downloaded English (US) language, then download it again.\n2. Go to Settings > General > Language & Region, change the region from United States to another country, then change it back to United States.\n3. Turn off Low Power Mode (Settings > Battery).\n4. Connect to Wi-Fi (and keep your iPhone charging) while Apple Intelligence finishes downloading.")
            }
            return nil
        }

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        HStack(spacing: 16) {
                            SileoIcon(systemImage: tweak.icon, color: detail.iconColor, size: 60)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tweak.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Sileo.primary)
                                Text(detail.groupTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Sileo.secondary)
                                Text((tweak.isOn(in: manager.dictNow) ? "On" : "Off") + " · WorkTweaks")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Sileo.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let info = tweak.infoMessage {
                            Text(info)
                                .font(.subheadline)
                                .foregroundStyle(Sileo.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !tweak.supported(), let minv = tweak.minv {
                            Text(String(format: "Requires iOS %.1f or newer.", minv))
                                .font(.subheadline)
                                .foregroundStyle(Color.red)
                        }
                    }
                    if let fix, tweak.isOn(in: manager.dictNow) {
                        Section("Fix") {
                            Text(fix.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Sileo.primary)
                            Text(fix.text)
                                .font(.subheadline)
                                .foregroundStyle(Sileo.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Section {
                        Toggle("Enable \(tweak.title)", isOn: manager.toggleBinding(for: tweak))
                            .disabled(toggleDisabled)
                    } footer: {
                        Text("Apply Tweaks to write the change, then Respring or Restart.")
                    }
                }
                .navigationTitle(tweak.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    /// A custom row's detail sheet, opened by its GET pill:
    /// the explanation, then the toggle (and the field, for
    /// the name and region rows).
    private struct SileoFollowerDetailSheet: View {
        @ObservedObject var manager: GestaltManager
        let follower: FollowerDetail
        @Binding var atomicWrite: Bool
        @Environment(\.dismiss) private var dismiss

        private var title: String {
            switch follower {
            case .deviceName: return "Custom Device Name"
            case .regionModel: return "Custom Region Model"
            case .persist: return "Persist after reboot"
            }
        }

        private var icon: String {
            switch follower {
            case .deviceName: return "textformat"
            case .regionModel: return "globe"
            case .persist: return "externaldrive.fill"
            }
        }

        private var iconColor: Color {
            switch follower {
            case .deviceName: return .blue
            case .regionModel: return .cyan
            case .persist: return .gray
            }
        }

        private var explanation: String {
            switch follower {
            case .deviceName: return "Shown in Settings > General > About. Turn it on, type a name, then Apply Tweaks."
            case .regionModel: return "Type the sales-region suffix as shown in Settings > General > About, e.g. PA/A or LL/A. It changes the Model Number suffix after Apply."
            case .persist: return "Write MobileGestalt in-place on the same inode, so the tweak survives a reboot."
            }
        }

        private var isOn: Bool {
            switch follower {
            case .deviceName: return manager.enableDeviceName
            case .regionModel: return manager.enableCustomRegion
            case .persist: return atomicWrite
            }
        }

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        HStack(spacing: 16) {
                            SileoIcon(systemImage: icon, color: iconColor, size: 60)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Sileo.primary)
                                Text("Custom")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Sileo.secondary)
                                Text((isOn ? "On" : "Off") + " · WorkTweaks")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Sileo.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(explanation)
                            .font(.subheadline)
                            .foregroundStyle(Sileo.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Section {
                        switch follower {
                        case .deviceName:
                            Toggle("Enable \(title)", isOn: $manager.enableDeviceName)
                            if manager.enableDeviceName {
                                TextField("Device Name", text: $manager.deviceName)
                                    .autocorrectionDisabled()
                            }
                        case .regionModel:
                            Toggle("Enable \(title)", isOn: $manager.enableCustomRegion)
                            if manager.enableCustomRegion {
                                TextField("Region suffix (e.g. PA/A)", text: $manager.customRegionSuffix)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.characters)
                            }
                        case .persist:
                            Toggle("Enable \(title)", isOn: $atomicWrite)
                        }
                    } footer: {
                        Text("Apply Tweaks to write the change, then Respring or Restart.")
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}
