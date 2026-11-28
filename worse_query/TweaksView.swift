import SwiftUI
import UIKit

// MARK: - Tweaks tab (v8.0 fix: Library-style single column)
//
// The tab is one scrolling column, Library/Sileo-inspired but
// built fresh on the v7.0 material (WTGlassCard surfaces,
// language-theme accent, current fonts): a header block
// (kicker + big title + subtitle), a search capsule, a
// featured Dynamic Island card, category rows that open one
// category's tweaks, then the Apply / Respring / Revert
// actions and a footer note. The old v3.0 two-column split —
// a scrolling tweak column beside a fixed 150pt Sections
// card — is gone: at Large Text it already broke (labels
// truncated, cards sliding behind the tab bar), and the
// v8.0 revamp left it visually unchanged. The new layout is
// single-column at every text size. Toggles mutate the
// in-memory MobileGestalt dictionary immediately; "Apply
// Tweaks" persists it. Every tweak keeps its own SF Symbol
// (see TweakCatalog.presentation), rendered uniformly as a
// plain accent-colored icon. The tab starts LOCKED until
// "Start Tweaks Feature" is turned on in the Sandbox tab
// (wt.tweaksFeatureEnabled).

/// The sections of the Tweaks tab's category rows.
/// All = the full catalog; Apply/Revert holds the action cards
/// instead of tweaks.
enum TweakSection: String, CaseIterable, Identifiable {
    case all, dynamicIsland, tweaks, appleIntelligence, addFeature, applyRevert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("All")
        case .dynamicIsland: return "Dynamic Island"
        case .tweaks: return L("Tweaks")
        case .appleIntelligence: return "Apple Intelligence"
        case .addFeature: return L("Add feature")
        case .applyRevert: return L("Apply/Revert")
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
/// Apple Intelligence / Add feature is the full 24-tweak catalog.
enum TweakCategory {
    static let sectionByID: [String: TweakSection] = [
        // Dynamic Island
        "enable_dynamic_island_capability": .dynamicIsland,
        // Apple Intelligence
        "apple_intelligence": .appleIntelligence,
        "siri_ai_cache_patch": .appleIntelligence,
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
    @EnvironmentObject private var wtLang: WTLangStore
    /// Switches the TabView to the Sandbox tab (RootView owns the
    /// selection); used by the locked state's button.
    var onOpenSandbox: () -> Void

    @AppStorage("atomic_write") private var atomicWrite = true
    /// Master switch for this tab, flipped in the Sandbox tab.
    @AppStorage("wt.tweaksFeatureEnabled") private var tweaksEnabled = false
    /// New UI / Old UI choice, picked in the Sandbox tab
    /// (wt.tweaksUIVersion: "new" or "old"). Applies to this
    /// tab only — every other tab is untouched.
    @AppStorage("wt.tweaksUIVersion") private var uiVersionRaw = "new"

    private var useOldUI: Bool { uiVersionRaw == "old" }

    @State private var infoTitle: String?
    @State private var infoMessage: String = ""
    @State private var showRevertConfirm = false
    /// Search: the toolbar button presents a dedicated
    /// full-screen search cover with its own header and results
    /// list, so the page underneath is never remeasured or
    /// overlapped while searching.
    @State private var searchActive = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

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
                    if useOldUI {
                        OldTweaksView(
                            console: console,
                            manager: manager,
                            onInfo: showInfo(for:),
                            onRevert: { showRevertConfirm = true },
                            onSpoofingInfo: {
                                infoTitle = wtLang.tr("Device Spoofing Info")
                                infoMessage = wtLang.tr("Only spoof your device model if you want to download Apple Intelligence. This may break Face ID. If you decide to unspoof and want to keep Apple Intelligence, do NOT re-enter the Apple Intelligence & Siri menu in Settings.")
                            }
                        )
                    } else {
                        libraryView
                    }
                } else {
                    lockedView
                }
            }
            // Locked ↔ unlocked and New/Old UI switches
            // animate instead of snapping (v8.0 menu motion).
            .animation(.wtMenu, value: tweaksEnabled)
            .animation(.wtMenu, value: uiVersionRaw)
            .navigationTitle("WorkTweaks")
            // Always inline: the page carries its own header
            // block (kicker + big title), so a large navigation
            // title would duplicate it.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Search is a New UI feature — the Old UI (v1)
                // never had it.
                if tweaksEnabled && !useOldUI {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            searchActive = true
                        } label: {
                            Label(wtLang.tr("Search"), systemImage: "magnifyingglass")
                        }
                        .accessibilityLabel(wtLang.tr("Search tweaks"))
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { manager.load() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(manager.isLoading)
                    NavigationLink {
                        TutorialsView()
                    } label: {
                        Image(systemName: "book")
                    }
                    .accessibilityLabel(wtLang.tr("Tutorials"))
                    NavigationLink {
                        LicenseView()
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel(wtLang.tr("License & Credits"))
                }
            }
            .fullScreenCover(isPresented: $searchActive) {
                searchCover
            }
            .alert(infoTitle ?? "", isPresented: showInfo) {
                Button(wtLang.tr("OK")) { infoTitle = nil }
            } message: {
                Text(infoMessage)
            }
            .alert(wtLang.tr("Notice"), isPresented: Binding(
                get: { manager.notice != nil },
                set: { if !$0 { manager.notice = nil } }
            )) {
                Button(wtLang.tr("OK")) { manager.notice = nil }
            } message: {
                Text(manager.notice ?? "")
            }
            // The Respring / Restart dialog waits until the
            // animated success popup is dismissed: both flags
            // are set together on Apply success, and the popup's
            // Continue clears showApplySuccess, which lets this
            // dialog appear. Title, buttons and behavior unchanged.
            .confirmationDialog(wtLang.tr("Tweaks Applied"), isPresented: Binding(
                get: { manager.showPostApplyChoice && !manager.showApplySuccess },
                set: { manager.showPostApplyChoice = $0 }
            ), titleVisibility: .visible) {
                Button(wtLang.tr("Respring")) { RespringCenter.shared.trigger() }
                Button(wtLang.tr("Restart Device")) { manager.presentManualRestartGuide() }
                Button(wtLang.tr("Later"), role: .cancel) { }
            } message: {
                Text(wtLang.tr("Some tweaks — especially Apple Intelligence — only take effect after a full restart, not a respring."))
            }
            .confirmationDialog(wtLang.tr("Restart Required"), isPresented: $manager.showRestartRequired, titleVisibility: .visible) {
                Button(wtLang.tr("Restart Device")) { manager.presentManualRestartGuide() }
                Button(wtLang.tr("Later"), role: .cancel) { }
            } message: {
                Text(wtLang.tr("Revert and restore changes only take effect after a full device restart — a respring is not enough. Choosing Later just postpones it; the changes stay pending until you restart."))
            }
            .alert(manager.restartAlertTitle ?? "", isPresented: Binding(
                get: { manager.restartAlertTitle != nil },
                set: { if !$0 { manager.restartAlertTitle = nil } }
            )) {
                Button(wtLang.tr("OK")) { manager.restartAlertTitle = nil }
            } message: {
                Text(manager.restartAlertMessage)
            }
            .confirmationDialog(wtLang.tr("Revert all tweaks?"), isPresented: $showRevertConfirm) {
                Button(wtLang.tr("Revert"), role: .destructive) { manager.revert() }
            } message: {
                Text(wtLang.tr("This restores the MobileGestalt backup saved on first launch (SavedGestalt.plist)."))
            }
            // Animated Tweaky success popup, shown on Apply
            // success; Continue dismisses it and the Respring /
            // Restart dialog above appears.
            .overlay {
                if manager.showApplySuccess {
                    ApplySuccessPopup {
                        manager.showApplySuccess = false
                    }
                }
            }
        }
    }

    // MARK: Locked state (v2.0)

    private var lockedView: some View {
        VStack(spacing: 18) {
            Spacer()
            // Tweaky greets the user on the locked page
            // (v8.0 revamp) — the lock itself stays below.
            TweakyMascot(size: 64)
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text(wtLang.tr("Tweaks are locked"))
                    .font(.title3.weight(.bold))
                Text(wtLang.tr("Go to the Sandbox tab and turn on Start Tweaks Feature to unlock the Tweaks tab."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                onOpenSandbox()
            } label: {
                Label(wtLang.tr("Go to Sandbox Tab"), systemImage: "shippingbox")
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

    // MARK: Library-style layout (v8.0 fix)
    //
    // One scrolling column at every text size — no fixed side
    // column, so Large Text can never squeeze it: header block,
    // status, search capsule, featured card, category rows,
    // Apply/Revert actions, footer note and links. Same cards,
    // same toggles, same actions; only the arrangement changes.
    // The old v3.0 two-column split (a scrolling tweak column
    // beside a fixed 150pt Sections card) is gone: at Large
    // Text it already broke, and the v8.0 revamp left it
    // visually unchanged.

    private var libraryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WTPageHeader(
                    kicker: "WORKTWEAKS • TWEAK LIBRARY",
                    title: wtLang.tr("Explore tweaks"),
                    subtitle: wtLang.tr("Pick a tweak, turn it on, then apply it."),
                    friend: .tweaky
                )

                statusCard

                if manager.isEmpty || !manager.isValid {
                    warningCard
                }

                searchCapsule

                featuredSection

                browseSection

                actionsSection

                footerNoteCard

                footerLinks

                // Bottom clearance so the last card is never
                // hidden behind the floating tab bar.
                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    /// The search capsule: a glass pill that opens the
    /// full-screen search cover (an empty query shows the full
    /// catalog). The capsule is the "All" entry point now that
    /// the Sections card is gone.
    private var searchCapsule: some View {
        Button {
            SoundEffects.playTap()
            searchActive = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(wtLang.tr("Search tweaks"))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .wtGlassCard(cornerRadius: 999)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(wtLang.tr("Search tweaks"))
    }

    /// A small-caps section label, as in the Library reference.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
    }

    // MARK: Featured card

    /// The Dynamic Island tweak, featured at the top of the
    /// page.
    private var featuredTweak: GestaltTweak? {
        TweakCatalog.all.first { $0.id == "enable_dynamic_island_capability" }
    }

    @ViewBuilder
    private var featuredSection: some View {
        if let tweak = featuredTweak {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(wtLang.tr("Featured"))
                featuredCard(tweak: tweak)
            }
        }
    }

    /// The featured card: the Dynamic Island tweak with its
    /// description, a toggle to turn it on right here, an
    /// arrow that opens its explanation, and the subtype
    /// picker under it.
    private func featuredCard(tweak: GestaltTweak) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                Text(wtLang.tr("Featured"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                // A large Dynamic Island mark as the card's
                // visual, standing in for the reference's chip
                // illustration.
                Image(systemName: "capsule.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
            }
            Text(tweak.title)
                .font(.system(size: 28, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            if let info = tweak.infoMessage {
                Text(info)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if tweak.infoMessage != nil {
                    Button {
                        SoundEffects.playTap()
                        showInfo(for: tweak)
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: manager.toggleBinding(for: tweak))
                    .labelsHidden()
                    .disabled(!manager.isValid || !tweak.supported())
            }
            // The Dynamic Island model picker lives under the
            // featured card, as in the old layout.
            subtypeCard
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 20)
    }

    // MARK: Browse by category

    /// The browsable categories: every section that holds
    /// tweaks. Apply/Revert is an action, not a category, so
    /// it gets its own section below instead of a row here.
    /// "All" lives in the search capsule (an empty query
    /// shows the full catalog).
    private var browseCategories: [TweakSection] {
        [.dynamicIsland, .appleIntelligence, .tweaks, .addFeature]
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(wtLang.tr("Browse by category"))
            ForEach(browseCategories) { section in
                NavigationLink {
                    categoryPage(for: section)
                } label: {
                    categoryRow(section: section)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One category row: icon in a tinted square, title,
    /// tweak count, chevron — as in the reference. The whole
    /// row is the tap target: contentShape(Rectangle()) makes
    /// the Spacer's empty middle tappable too — without it
    /// only the icon, the texts and the chevron receive taps,
    /// so the box only opened from the chevron corner. The
    /// chevron stays as a visual indicator only.
    private func categoryRow(section: TweakSection) -> some View {
        HStack(spacing: 14) {
            Image(systemName: section.icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(wtLang.tr("%d tweaks", visibleTweaks(for: section).count))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .wtGlassCard(cornerRadius: 16)
        .contentShape(Rectangle())
    }

    /// One category's page: the section's tweak cards (with
    /// their follower cards) in a single scrolling column.
    /// Pushed from a category row; the same cards the old
    /// Sections picker showed, now on their own page.
    @ViewBuilder
    private func categoryPage(for section: TweakSection) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                sectionCards(for: section)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Apply & revert

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(TweakSection.applyRevert.title)
            actionsBlock
        }
    }

    /// The safety note at the bottom of the page: the same
    /// warning as the Apply/Revert actions, with a shield
    /// icon — Apply first, then respring or restart.
    private var footerNoteCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "shield.checkmark")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(wtLang.tr("Tweaks change your device"))
                    .font(.system(size: 17, weight: .semibold))
                Text(wtLang.tr("Apply first, then respring or restart. Availability varies by device and iOS version."))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .wtGlassCard(cornerRadius: 16)
    }

    // MARK: Search (dedicated full-screen cover)

    /// The search presentation: a full-screen cover with its
    /// own header — a glass capsule field (magnifier, the text
    /// field, a clear button while there is text) and a Cancel
    /// button — over a single-column, full-width scrolling list
    /// of results. Search is fully isolated from the page
    /// layout: the Tweaks page underneath is never remeasured
    /// or overlapped while searching, and closing returns to
    /// it untouched.
    private var searchCover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(wtLang.tr("Search tweaks"), text: $searchText)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(wtLang.tr("Clear search"))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .wtGlassCard(cornerRadius: 999)

                Button(wtLang.tr("Cancel")) {
                    closeSearch()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 12) {
                    searchResultCards
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { searchFocused = true }
        // The info alert is attached here as well, so a result
        // card's info button presents over the cover (the base
        // page's own alert sits underneath while searching).
        .alert(infoTitle ?? "", isPresented: showInfo) {
            Button(wtLang.tr("OK")) { infoTitle = nil }
        } message: {
            Text(infoMessage)
        }
    }

    private func closeSearch() {
        searchText = ""
        searchActive = false
        searchFocused = false
    }

    /// Tweaks whose names match the query, across the whole
    /// catalog regardless of the selected section — with the
    /// same per-device conditionals as the section lists. An
    /// empty query matches everything: the cover opens on the
    /// full catalog.
    private var searchResults: [GestaltTweak] {
        TweakCatalog.all.filter { tweak in
            if tweak.id == "tap_to_wake" && !hasHomeButton() { return false }
            if tweak.id == "stage_manager_support" && UIDevice.current.userInterfaceIdiom != .pad { return false }
            return searchText.isEmpty || tweak.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    @ViewBuilder
    private var searchResultCards: some View {
        if searchResults.isEmpty {
            Text(wtLang.tr("No tweaks match \"%@\".", searchText))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            ForEach(searchResults) { tweak in
                if tweak.id == "siri_ai_cache_patch" {
                    SiriGuideCard(manager: manager)
                    MobileGestaltPlistMenuRow(manager: manager)
                } else {
                    TweakCard(manager: manager, tweak: tweak, onInfo: showInfo(for:))
                        .disabled(tweak.id == "enable_ipados_mode" && ipadOSModeLocked)
                }

                // The follower cards behave exactly as in the
                // section views: the subtype picker under
                // Dynamic Island, the spoofing picker under
                // Apple Intelligence.
                if tweak.id == "enable_dynamic_island_capability" {
                    subtypeCard
                }
                if tweak.id == "apple_intelligence" {
                    spoofingCard
                }
            }
        }
    }

    // MARK: Status card

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(minWidth: 30)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
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

    // "Do not reboot!" warning card (shown when the loaded
    // MobileGestalt plist is empty or invalid).
    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(wtLang.tr("Do not reboot! Your MobileGestalt.plist seems to be %@.", wtLang.tr(manager.isEmpty ? "empty" : "invalid")))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            Text(wtLang.tr("Rebooting now might cause a bootloop. Try pressing 'Revert Tweaks'."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
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
    private func sectionCards(for section: TweakSection) -> some View {
        ForEach(visibleTweaks(for: section)) { tweak in
            if tweak.id == "siri_ai_cache_patch" {
                // Manual now: the guide card instead of the auto
                // toggle, and the Mobile Gestalt.plist menu row
                // directly below it.
                SiriGuideCard(manager: manager)
                MobileGestaltPlistMenuRow(manager: manager)
            } else {
                TweakCard(manager: manager, tweak: tweak, onInfo: showInfo(for:))
                    .disabled(tweak.id == "enable_ipados_mode" && ipadOSModeLocked)
            }

            // The Dynamic Island model picker lives directly
            // under its tweak's card.
            if tweak.id == "enable_dynamic_island_capability" {
                subtypeCard
            }
            // The spoofing model picker sits next to Apple
            // Intelligence, as before — in the All section and in
            // the Apple Intelligence section itself.
            if tweak.id == "apple_intelligence" && (section == .all || section == .appleIntelligence) {
                spoofingCard
            }
        }

        if section == .tweaks || section == .all {
            deviceNameCard
            regionModelCard
            persistCard
        }

        if section == .addFeature {
            footnoteCard
        }
    }

    /// Lock Screen Footnote: a standalone feature card (not a
    /// catalog tweak) trailing the Add feature section — the
    /// footnote editor's only entry point.
    private var footnoteCard: some View {
        NavigationLink {
            FootnoteView()
        } label: {
            HStack(spacing: 8) {
                RowIcon(systemImage: "text.bubble")
                VStack(alignment: .leading, spacing: 2) {
                    Text(wtLang.tr("Lock Screen Footnote"))
                        .font(.subheadline.weight(.semibold))
                    Text(wtLang.tr("Custom text shown at the bottom of the Lock Screen."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wtGlassCard(cornerRadius: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RowIcon(systemImage: "capsule.fill")
                Text(wtLang.tr("Subtype"))
                    .font(.subheadline.weight(.semibold))
            }
            Picker(wtLang.tr("Subtype"), selection: $manager.selectedST) {
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
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
    }

    /// Device Artwork: Custom Device Name toggle + field.
    private var deviceNameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $manager.enableDeviceName) {
                HStack(spacing: 8) {
                    RowIcon(systemImage: "textformat")
                    Text(wtLang.tr("Custom Device Name"))
                        .font(.subheadline.weight(.semibold))
                }
            }
            .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            if manager.enableDeviceName {
                TextField(wtLang.tr("Device Name"), text: $manager.deviceName)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }
        }
        // The name field slides in/out with the toggle
        // instead of snapping (v8.0 menu motion).
        .animation(.wtMenu, value: manager.enableDeviceName)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
    }

    /// Device Artwork: Custom Region Model toggle + field.
    /// The typed suffix (e.g. PA/A) is the sales region shown
    /// in Settings > General > About as the Model Number
    /// suffix; it is written on Apply, like Custom Device Name.
    private var regionModelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $manager.enableCustomRegion) {
                HStack(spacing: 8) {
                    RowIcon(systemImage: "globe")
                    Text(wtLang.tr("Custom Region Model"))
                        .font(.subheadline.weight(.semibold))
                }
            }
            .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            if manager.enableCustomRegion {
                TextField(wtLang.tr("Region suffix (e.g. PA/A)"), text: $manager.customRegionSuffix)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .textFieldStyle(.roundedBorder)
                Text(wtLang.tr("Type the region suffix as shown in Settings > General > About, e.g. PA/A or LL/A. It changes the Model Number suffix after Apply."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        // The suffix field slides in/out with the toggle
        // instead of snapping (v8.0 menu motion).
        .animation(.wtMenu, value: manager.enableCustomRegion)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
    }

    /// Eligibility: the device-model spoofing picker.
    private var spoofingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RowIcon(systemImage: "iphone.gen3")
                Text(wtLang.tr("Spoofing"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    infoTitle = wtLang.tr("Device Spoofing Info")
                    infoMessage = wtLang.tr("Only spoof your device model if you want to download Apple Intelligence. This may break Face ID. If you decide to unspoof and want to keep Apple Intelligence, do NOT re-enter the Apple Intelligence & Siri menu in Settings.")
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
            }
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
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
    }

    /// Write Method: "Persist after reboot" (atomic_write).
    private var persistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $atomicWrite) {
                HStack(spacing: 8) {
                    RowIcon(systemImage: "externaldrive.fill")
                    Text(wtLang.tr("Persist after reboot"))
                        .font(.subheadline.weight(.semibold))
                }
            }
            .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            Text(wtLang.tr("When enabled, MobileGestalt is written in-place on the same inode, which (hopefully) prevents iOS from regenerating the cache on reboot. Disable to use atomic file replacement instead."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
    }

    // MARK: Actions (Apply / Respring / Revert)

    private var actionsBlock: some View {
        VStack(spacing: 12) {
            actionCardButton(title: wtLang.tr("Apply Tweaks"), systemImage: "checkmark.circle") {
                manager.apply()
                console.output += "\n(mg) Apply finished — see the Log for the write result.\n"
            }
            .disabled(!manager.isValid)

            actionCardButton(title: wtLang.tr("Respring"), systemImage: "arrow.counterclockwise") {
                RespringCenter.shared.trigger()
            }

            actionCardButton(title: wtLang.tr("Revert Tweaks"), systemImage: "arrow.uturn.backward", destructive: true) {
                showRevertConfirm = true
            }
            .disabled(!manager.isValid)

            Text(wtLang.tr("WARNING: These tweaks can break features on your device or softbrick it if misused. After Apply you choose Respring or Restart; Revert and Backup restores require a full device restart."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionCardButton(title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: { SoundEffects.playTap(); action() }) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Color.red : Color.accentColor)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wtGlassCard(cornerRadius: 14)
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
                footerLinkLabel(title: wtLang.tr("Tutorials"), systemImage: "book")
            }
            .buttonStyle(.plain)

            NavigationLink {
                LicenseView()
            } label: {
                footerLinkLabel(title: wtLang.tr("License & Credits"), systemImage: "doc.text")
            }
            .buttonStyle(.plain)

            // English only, like the terms themselves: the
            // standalone TermsView (same content as onboarding
            // page 2) so users can re-read the terms later.
            NavigationLink {
                TermsView()
            } label: {
                footerLinkLabel(title: "Terms & Conditions", systemImage: "doc.plaintext")
            }
            .buttonStyle(.plain)

            Text(wtLang.tr("Built on the worse_query core system by ForceQuit OS, with CacheExtra key knowledge from mond by rooootdev (AGPL-3.0)."))
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
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
    @EnvironmentObject private var wtLang: WTLangStore
    let tweak: GestaltTweak
    let onInfo: (GestaltTweak) -> Void

    @State private var showFixStatusBarGuide = false
    @State private var showFixAppleIntelligenceGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            HStack(spacing: 8) {
                Text(stateLine)
                    .font(.caption).foregroundStyle(.secondary)
                    // Wrap instead of truncating at Large Text.
                    .fixedSize(horizontal: false, vertical: true)
                // The status-bar fix guide lives next to the
                // "On" line of the Dynamic Island card only.
                if tweak.id == "enable_dynamic_island_capability", tweak.isOn(in: manager.dictNow) {
                    Button(wtLang.tr("Fix Status Bar!")) {
                        SoundEffects.playTap()
                        showFixStatusBarGuide = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                }
                // The Apple Intelligence fix guide lives next to
                // the "On" line of the Apple Intelligence card only.
                if tweak.id == "apple_intelligence", tweak.isOn(in: manager.dictNow) {
                    Button(wtLang.tr("Fix Apple Intelligence Here!")) {
                        SoundEffects.playTap()
                        showFixAppleIntelligenceGuide = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
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
    }

    private var stateLine: String {
        if !tweak.supported(), let minv = tweak.minv {
            return wtLang.tr("Requires iOS %.1f+", minv)
        }
        return tweak.isOn(in: manager.dictNow) ? wtLang.tr("On") : wtLang.tr("Off")
    }
}

// MARK: - Apply-success popup (v8.0)
//
// Centered card over a dimmed background: the animated
// Tweaky mascot, the localized success text, and a Continue
// button. Continue only dismisses the popup — the Respring /
// Restart confirmationDialog (still bound to
// showPostApplyChoice) appears right after.
private struct ApplySuccessPopup: View {
    var onContinue: () -> Void

    @EnvironmentObject private var wtLang: WTLangStore

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                AnimatedTweakyMascot(size: 90)
                Text(wtLang.tr("Tweaks applied successfully!"))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button(wtLang.tr("Continue")) {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 16)
            .padding(.horizontal, 32)
        }
    }
}
