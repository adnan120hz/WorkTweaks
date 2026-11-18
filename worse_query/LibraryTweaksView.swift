import SwiftUI
import UIKit

// MARK: - Library UI (third Tweaks layout, v6.0)
//
// The Tweaks tab's third layout, built from scratch for v6.0 on
// the v5.2.1 base. The design is a REFERENCE, not a copy: the
// photo the user sent (a warm "feature library" — kicker, big
// title, search capsule, a curated featured card, category rows,
// a note card) supplies the layout and the warm palette, but
// every menu, category and tweak is WorkTweaks' own. Only the
// layout differs: every toggle, picker and action reads the
// same GestaltManager state and runs the same apply/revert/
// respring code as the New and Old UIs, and the system (engine,
// backup, resolver, respring) is untouched. Applies to the
// Tweaks tab only (wt.tweaksUIVersion: "library").
//
// Palette (from the reference): warm cream paper, dark navy
// ink, burnt-orange accent. The colors adapt to Dark Mode
// (dark warm paper, warm-white ink) so the page stays readable.

/// Warm cream paper in light mode, dark warm paper in dark mode.
private let libraryBackground = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1)
        : UIColor(red: 0.965, green: 0.945, blue: 0.905, alpha: 1)
})

/// Card surface: warm white in light mode, dark warm in dark mode.
private let libraryCard = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.17, green: 0.155, blue: 0.13, alpha: 1)
        : UIColor(red: 1.0, green: 0.992, blue: 0.965, alpha: 1)
})

/// Ink: dark navy in light mode, warm white in dark mode.
private let libraryInk = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1)
        : UIColor(red: 0.10, green: 0.16, blue: 0.22, alpha: 1)
})

/// Secondary ink: warm gray in both modes.
private let librarySecondary = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.62, green: 0.58, blue: 0.52, alpha: 1)
        : UIColor(red: 0.42, green: 0.40, blue: 0.36, alpha: 1)
})

/// The burnt-orange accent from the reference.
private let libraryAccent = Color(red: 0.91, green: 0.36, blue: 0.15)

/// Soft tinted square behind a category icon.
private let libraryIconTint = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.91, green: 0.36, blue: 0.15, alpha: 0.16)
        : UIColor(red: 0.91, green: 0.36, blue: 0.15, alpha: 0.10)
})

/// Small-caps section label, as in the reference.
private struct LibrarySectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(libraryInk)
    }
}

struct LibraryTweaksView: View {
    let console: Console
    @ObservedObject var manager: GestaltManager
    /// Shows the info alert (owned by TweaksView) for a tweak.
    let onInfo: (GestaltTweak) -> Void
    /// Shows the Revert confirmation (owned by TweaksView).
    let onRevert: () -> Void
    /// Shows the Device Spoofing info alert (owned by TweaksView).
    let onSpoofingInfo: () -> Void

    @AppStorage("atomic_write") private var atomicWrite = true
    @State private var searchActive = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    /// The Dynamic Island tweak, featured under "Curated for you".
    private var featuredTweak: GestaltTweak? {
        TweakCatalog.all.first { $0.id == "enable_dynamic_island_capability" }
    }

    /// The browsable categories: every section that holds tweaks.
    /// Apply/Revert is an action, not a category, so it gets its
    /// own section below instead of a row here.
    private var categories: [TweakSection] {
        [.dynamicIsland, .appleIntelligence, .tweaks, .addFeature]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                searchBar
                curatedSection
                browseSection
                actionsSection
                footerNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(libraryBackground.ignoresSafeArea())
        .fullScreenCover(isPresented: $searchActive) {
            searchCover
        }
    }

    // MARK: Header (kicker + big title + subtitle)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKTWEAKS • TWEAK LIBRARY")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(libraryInk)
            Text("Explore tweaks")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(libraryInk)
            Text("Pick a tweak, turn it on, then apply it.")
                .font(.system(size: 17))
                .foregroundStyle(librarySecondary)
        }
    }

    // MARK: Search bar (opens the search cover)

    private var searchBar: some View {
        Button {
            SoundEffects.playTap()
            searchActive = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(librarySecondary)
                Text("Search tweaks")
                    .foregroundStyle(librarySecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(libraryCard, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search tweaks")
    }

    // MARK: Curated for you (featured tweak)

    private var curatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionLabel(text: "CURATED FOR YOU")
            if let tweak = featuredTweak {
                featuredCard(tweak: tweak)
            }
        }
    }

    /// The featured card: the Dynamic Island tweak with its
    /// description, a toggle to turn it on right here, and an
    /// orange arrow that opens its explanation.
    private func featuredCard(tweak: GestaltTweak) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(libraryAccent)
                    .frame(width: 8, height: 8)
                Text("FEATURED")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(libraryInk)
                Spacer(minLength: 0)
                // A large Dynamic Island mark as the card's visual,
                // standing in for the reference's chip illustration.
                Image(systemName: "capsule.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(libraryAccent.opacity(0.85))
            }
            Text(tweak.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(libraryInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(tweak.infoMessage ?? "Turn on Dynamic Island on your iPhone.")
                .font(.system(size: 15))
                .foregroundStyle(librarySecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    onInfo(tweak)
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(libraryAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(tweak.title)")
                Spacer(minLength: 0)
                Toggle("", isOn: manager.toggleBinding(for: tweak))
                    .labelsHidden()
                    .disabled(!manager.isValid || !tweak.supported())
            }
            // The Dynamic Island model picker lives under the
            // featured card, as in the New UI.
            subtypeCard
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    // MARK: Browse by category

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by category")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(libraryInk)
            ForEach(categories) { section in
                NavigationLink {
                    LibraryCategoryView(
                        section: section,
                        console: console,
                        manager: manager,
                        onInfo: onInfo,
                        onRevert: onRevert,
                        onSpoofingInfo: onSpoofingInfo
                    )
                } label: {
                    categoryRow(section: section)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One category row: icon in a tinted square, title,
    /// tweak count, chevron — as in the reference.
    private func categoryRow(section: TweakSection) -> some View {
        HStack(spacing: 14) {
            Image(systemName: section.icon)
                .font(.system(size: 20))
                .foregroundStyle(libraryAccent)
                .frame(width: 44, height: 44)
                .background(libraryIconTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(libraryInk)
                Text("\(visibleTweaks(for: section).count) tweaks")
                    .font(.system(size: 14))
                    .foregroundStyle(librarySecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(librarySecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: Apply & revert

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionLabel(text: "APPLY & REVERT")
            VStack(spacing: 12) {
                libraryActionButton(title: "Apply Tweaks", systemImage: "checkmark.circle") {
                    manager.apply()
                    console.output += "\n(mg) Apply finished — see the Log for the write result.\n"
                }
                .disabled(!manager.isValid)

                libraryActionButton(title: "Respring", systemImage: "arrow.counterclockwise") {
                    RespringCenter.shared.trigger()
                }

                libraryActionButton(title: "Revert Tweaks", systemImage: "arrow.uturn.backward", destructive: true) {
                    onRevert()
                }
                .disabled(!manager.isValid)

                Text("WARNING: These tweaks can break features on your device or softbrick it if misused. After Apply you choose Respring or Restart; Revert and Backup restores require a full device restart.")
                    .font(.caption)
                    .foregroundStyle(librarySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func libraryActionButton(title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: { SoundEffects.playTap(); action() }) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Color.red : libraryAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(libraryCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer note

    private var footerNote: some View {
        HStack(spacing: 14) {
            Image(systemName: "shield.checkmark")
                .font(.system(size: 22))
                .foregroundStyle(libraryAccent)
                .frame(width: 44, height: 44)
                .background(libraryIconTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Tweaks change your device")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(libraryInk)
                Text("Apply first, then respring or restart. Availability varies by device and iOS version.")
                    .font(.system(size: 14))
                    .foregroundStyle(librarySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: Search cover

    private var searchCover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(librarySecondary)
                    TextField("Search tweaks", text: $searchText)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(librarySecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(libraryCard, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )

                Button("Cancel") {
                    searchText = ""
                    searchActive = false
                    searchFocused = false
                }
                .foregroundStyle(libraryAccent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(searchResults) { tweak in
                        TweakCard(manager: manager, tweak: tweak, onInfo: onInfo)
                            .disabled(tweak.id == "enable_ipados_mode" && ipadOSModeLocked)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(libraryBackground)
        .onAppear { searchFocused = true }
    }

    /// Tweaks whose names match the query, across the whole
    /// catalog regardless of section — with the same per-device
    /// conditionals as the section lists. An empty query matches
    /// everything: the cover opens on the full catalog.
    private var searchResults: [GestaltTweak] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return TweakCatalog.all.filter { tweak in
            if tweak.id == "tap_to_wake" && !hasHomeButton() { return false }
            if tweak.id == "stage_manager_support" && UIDevice.current.userInterfaceIdiom != .pad { return false }
            if q.isEmpty { return true }
            return tweak.title.lowercased().contains(q)
                || tweak.id.lowercased().contains(q)
        }
    }

    // MARK: Shared tweak-list helpers

    /// The tweaks visible in a section — same device conditionals
    /// as the New UI's list.
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    onSpoofingInfo()
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
                        Text("iPhone Duo (iOS 27.3+)").tag("iPhone19,4")
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            if manager.enableDeviceName {
                TextField("Device Name", text: $manager.deviceName)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Persist after reboot (atomic write) toggle.
    private var persistCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $atomicWrite) {
                HStack(spacing: 8) {
                    RowIcon(systemImage: "externaldrive.fill")
                    Text("Persist after reboot")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            Text("When enabled, MobileGestalt is written in-place on the same inode, which (hopefully) prevents iOS from regenerating the cache on reboot. Disable to use atomic file replacement instead.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    Text("Lock Screen Footnote")
                        .font(.subheadline.weight(.semibold))
                    Text("Custom text shown at the bottom of the Lock Screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - One category's tweaks (pushed from a category row)

private struct LibraryCategoryView: View {
    let section: TweakSection
    let console: Console
    @ObservedObject var manager: GestaltManager
    let onInfo: (GestaltTweak) -> Void
    let onRevert: () -> Void
    let onSpoofingInfo: () -> Void

    @AppStorage("atomic_write") private var atomicWrite = true

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

    private var ipadOSModeLocked: Bool {
        let extra = manager.dictNow["CacheExtra"] as? [String: Any]
        return extra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(visibleTweaks(for: section)) { tweak in
                    TweakCard(manager: manager, tweak: tweak, onInfo: onInfo)
                        .disabled(tweak.id == "enable_ipados_mode" && ipadOSModeLocked)

                    if tweak.id == "enable_dynamic_island_capability" {
                        LibraryTweaksView.subtypeCard(manager: manager)
                    }
                    if tweak.id == "apple_intelligence" {
                        LibraryTweaksView.spoofingCard(manager: manager, onSpoofingInfo: onSpoofingInfo)
                    }
                }

                if section == .tweaks {
                    LibraryTweaksView.deviceNameCard(manager: manager)
                    LibraryTweaksView.persistCard(atomicWrite: $atomicWrite)
                }

                if section == .addFeature {
                    LibraryTweaksView.footnoteCard
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(libraryBackground)
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Shared special cards, reused by the category view

private extension LibraryTweaksView {
    static func subtypeCard(manager: GestaltManager) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RowIcon(systemImage: "capsule.fill")
                Text("Subtype")
                    .font(.subheadline.weight(.semibold))
            }
            Picker("Subtype", selection: Binding(get: { manager.selectedST }, set: { manager.selectedST = $0 })) {
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static func spoofingCard(manager: GestaltManager, onSpoofingInfo: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RowIcon(systemImage: "iphone.gen3")
                Text("Spoofing")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    onSpoofingInfo()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
            }
            Picker("Spoofing", selection: Binding(get: { manager.productType }, set: { manager.productType = $0 })) {
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static func deviceNameCard(manager: GestaltManager) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { manager.enableDeviceName }, set: { manager.enableDeviceName = $0 })) {
                HStack(spacing: 8) {
                    RowIcon(systemImage: "textformat")
                    Text("Custom Device Name")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            if manager.enableDeviceName {
                TextField("Device Name", text: Binding(get: { manager.deviceName }, set: { manager.deviceName = $0 }))
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static func persistCard(atomicWrite: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: atomicWrite) {
                HStack(spacing: 8) {
                    RowIcon(systemImage: "externaldrive.fill")
                    Text("Persist after reboot")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
            Text("When enabled, MobileGestalt is written in-place on the same inode, which (hopefully) prevents iOS from regenerating the cache on reboot. Disable to use atomic file replacement instead.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static var footnoteCard: some View {
        NavigationLink {
            FootnoteView()
        } label: {
            HStack(spacing: 8) {
                RowIcon(systemImage: "text.bubble")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock Screen Footnote")
                        .font(.subheadline.weight(.semibold))
                    Text("Custom text shown at the bottom of the Lock Screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(libraryCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
