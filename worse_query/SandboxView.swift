import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sandbox tab (v3.0: utilities as their own menus)
//
// The identity header and the "Start Tweaks Feature" master
// switch stay on the Sandbox home. Each utility group — Sandbox
// Escape, Path Enumeration, App Group — is now a menu row that
// opens its own page holding exactly the controls it had when
// they were stacked sections here. The console stays on the
// home, below the menu rows.
//
// Since v3.8 the pages render as free-standing Liquid Glass
// cards over the grouped background (WTGlassPage/WTSectionCard),
// the same construction as the Tweaks tab — presentation only;
// every control behaves exactly as before.

struct SandboxView: View {
    @ObservedObject var console: Console
    @EnvironmentObject private var lang: WTLangStore
    @State private var path = "/private/var/mobile/Containers/Shared/AppGroup/"
    @State private var sandboxHandle: Int64?
    @State private var groupText = AppGroupResolver.configuredGroup
    /// Language picker sheet (v7.0 flag-themed UI).
    @State private var showLanguagePicker = false
    /// Install IPA on Container (Phase 1): JIT toggle + IPA
    /// importer state. The toggle is saved but disabled until
    /// the JIT session lands in Phase 3 — it must never show
    /// a fake "JIT on" state.
    @AppStorage("wt.containerJITEnabled") private var containerJITEnabled = false
    @State private var showContainerImporter = false
    @State private var containerImportError: String?

    /// Master switch for the Tweaks tab (v2.0): the Tweaks tab
    /// stays locked until this is turned on. Shared with the
    /// Tweaks tab gate via the same AppStorage key.
    @AppStorage("wt.tweaksFeatureEnabled") private var tweaksEnabled = false
    /// New UI / Old UI choice for the Tweaks tab only
    /// ("new" = the current two-column layout, "old" = the v1
    /// list layout). Default is the current UI.
    @AppStorage("wt.tweaksUIVersion") private var tweaksUIVersion = "new"
    /// UI sounds on/off (v5.1): soft tap on menus and
    /// features, soft swipe on tab switches. On by default.
    @AppStorage("wt.soundEffectsEnabled") private var soundEffectsEnabled = true

    /// This build's version as recorded in the bundle
    /// (CFBundleShortVersionString), e.g. "3.7" — the same
    /// source the Tweaks tab's mini identity card reads.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Translated support line under the app name, e.g.
    /// "Supported iOS • iOS 27.0.1 (24A446)".
    private var supportLine: String {
        if SupportInfo.isPartiallySupported {
            return lang.tr("Partially Supported iOS • %@", SupportInfo.deviceSummary)
        }
        if SupportInfo.isSupported {
            return lang.tr("Supported iOS • %@", SupportInfo.deviceSummary)
        }
        return lang.tr("Unsupported iOS • %@", SupportInfo.deviceSummary)
    }

    /// Translated support value for the device-details rows.
    private var supportValue: String {
        if SupportInfo.isPartiallySupported { return lang.tr("Partially Supported") }
        if SupportInfo.isSupported { return lang.tr("Supported") }
        return lang.tr("Unsupported")
    }

    var body: some View {
        NavigationStack {
            WTGlassPage {
                // Front door identity: app icon, name, and this
                // device's support status — v7.0 themed header:
                // "{Language} Version" under the name (name text
                // only, no flag graphic), version in the theme
                // color, and the language picker row at the bottom.
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 14) {
                            // The real icon artwork for the
                            // current language — the same PNGs
                            // as the home-screen alternate
                            // icons, so the box follows the
                            // language live, in sync with the
                            // home-screen icon switch.
                            Image(uiImage: WTHeaderIcon.image(for: lang.language))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                // One Text with mixed fonts, so
                                // "v7.0" sits exactly on the
                                // "WorkTweaks" baseline (an HStack
                                // lets the smaller text float).
                                Text("WorkTweaks")
                                    .font(.headline)
                                + Text(" v\(appVersion)")
                                    .font(.caption)
                                    .foregroundStyle(lang.theme.accent)
                                Text(lang.language.versionLabel)
                                    // Wraps to two lines at large
                                    // Dynamic Type sizes instead
                                    // of truncating.
                                    .fixedSize(horizontal: false, vertical: true)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                // Badge centered against the FULL
                                // two-line support text, not
                                // pinned to its first line.
                                HStack(alignment: .center, spacing: 5) {
                                    Image(systemName: SupportInfo.isSupported ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(SupportInfo.isSupported ? Color.accentColor : .orange)
                                    Text(supportLine)
                                        // Wraps to two lines at large
                                        // Dynamic Type sizes instead
                                        // of truncating.
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider()
                            .padding(.leading, 14)

                        // Compact device details, from the same data
                        // the support gate already computes.
                        VStack(alignment: .leading, spacing: 6) {
                            deviceInfoRow(lang.tr("Model"), machineName())
                            deviceInfoRow(lang.tr("iOS Version"), SupportInfo.deviceVersion)
                            deviceInfoRow(lang.tr("Build"), SupportInfo.deviceBuild)
                            deviceInfoRow(lang.tr("Support"), supportValue)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                        Divider()
                            .padding(.leading, 14)

                        // Language picker row: language name
                        // only, no flag; tapping opens the
                        // 5-language sheet.
                        Button {
                            showLanguagePicker = true
                        } label: {
                            HStack(spacing: 10) {
                                Text(lang.tr("Language"))
                                    .font(.subheadline)
                                Spacer(minLength: 0)
                                Text(lang.language.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                    }
                }
                .sheet(isPresented: $showLanguagePicker) {
                    LanguagePickerSheet()
                }

                // Master switch for the Tweaks feature.
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(lang.tr("Start Tweaks Feature"), isOn: $tweaksEnabled)
                            .font(.subheadline.weight(.semibold))
                            .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                        Text(lang.tr("Unlocks the Tweaks tab. Turn this on to start using tweaks."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        // Tweaks UI choice — New UI is the current
                        // two-column layout, Old UI is the v1 list
                        // layout. Applies to the Tweaks tab only.
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lang.tr("Tweaks UI"))
                                .font(.subheadline.weight(.semibold))
                            Picker(lang.tr("Tweaks UI"), selection: $tweaksUIVersion) {
                                Text(lang.tr("New UI")).tag("new")
                                Text(lang.tr("Old UI")).tag("old")
                            }
                            .pickerStyle(.segmented)
                            Text(lang.tr("Applies to the Tweaks tab only."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // UI sounds — soft tap on menus and
                        // features, soft swipe on tab switches.
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(lang.tr("Sound Effects"), isOn: $soundEffectsEnabled)
                                .font(.subheadline.weight(.semibold))
                                .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                            Text(lang.tr("Plays a soft sound when you tap menus and features. Respects the silent switch."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                // Utility menus — each opens its own page.
                // v7.0: grouped into labeled sections instead
                // of one long list; every row is still here.
                WTSectionCard(header: lang.tr("Diagnostics")) {
                    VStack(alignment: .leading, spacing: 0) {
                        utilityRow("Battery & Thermal", systemImage: "battery.100") {
                            BatteryDiagnosticsView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("Jetsam & Crash", systemImage: "doc.text.magnifyingglass") {
                            CrashDiagnosticsView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow(lang.tr("Configuration Profiles"), systemImage: "person.badge.key") {
                            ProfileViewerView()
                        }
                    }
                }

                WTSectionCard(header: lang.tr("Files & Sharing")) {
                    VStack(alignment: .leading, spacing: 0) {
                        utilityRow(lang.tr("App Data"), systemImage: "folder") {
                            AppDataView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("Adnan.120hz Repository", systemImage: "shippingbox") {
                            RepositoryView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("Save Vault", systemImage: "archivebox") {
                            SaveVaultView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("Wi-Fi File Sharing", systemImage: "wifi") {
                            WiFiShareView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("Voice Memos & AI Cache", systemImage: "waveform") {
                            VoiceMemosAIView()
                        }
                    }
                }

                // Install IPA on Container (Phase 1 host
                // skeleton): the guest list + IPA import live in
                // ContainerView; the JIT toggle sits here so it
                // is visible on the Sandbox home. The toggle is
                // disabled until the JIT session lands in
                // Phase 3 — it is saved, but nothing runs yet.
                WTSectionCard(header: lang.tr("Install IPA on Container")) {
                    VStack(alignment: .leading, spacing: 0) {
                        utilityRow(lang.tr("Containers"), systemImage: "shippingbox") {
                            ContainerView()
                        }
                        Divider().padding(.leading, 14)
                        Button {
                            SoundEffects.playTap()
                            showContainerImporter = true
                        } label: {
                            HStack(spacing: 10) {
                                Label(lang.tr("Import IPA"), systemImage: "square.and.arrow.down")
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "plus")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 14)
                        HStack(spacing: 10) {
                            Label("JIT", systemImage: "bolt.fill")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Toggle("", isOn: $containerJITEnabled)
                                .labelsHidden()
                                .disabled(true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        Text(lang.tr("JIT is not available yet — it arrives in a later update."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }
                .fileImporter(
                    isPresented: $showContainerImporter,
                    allowedContentTypes: [UTType(filenameExtension: "ipa")!],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        Task {
                            do {
                                _ = try await ContainerManager.shared.installIPA(from: url)
                            } catch {
                                containerImportError = error.localizedDescription
                            }
                        }
                    case .failure(let error):
                        containerImportError = error.localizedDescription
                    }
                }
                .alert(lang.tr("Install failed"), isPresented: Binding(
                    get: { containerImportError != nil },
                    set: { if !$0 { containerImportError = nil } }
                )) {
                    Button(lang.tr("OK"), role: .cancel) { containerImportError = nil }
                } message: {
                    Text(containerImportError ?? "")
                }

                WTSectionCard(header: lang.tr("System")) {
                    VStack(alignment: .leading, spacing: 0) {
                        utilityRow("Sandbox Escape", systemImage: "lock.open") {
                            SandboxEscapePage(path: $path, sandboxHandle: $sandboxHandle)
                        }
                        Divider().padding(.leading, 14)
                        utilityRow(lang.tr("Path Enumeration"), systemImage: "list.bullet.indent") {
                            PathEnumerationPage(path: path)
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("App Group", systemImage: "person.2") {
                            AppGroupPage(groupText: $groupText)
                        }
                    }
                }

                WTSectionCard(header: lang.tr("Media")) {
                    VStack(alignment: .leading, spacing: 0) {
                        utilityRow("PosterBoard", systemImage: "photo") {
                            PosterBoardView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow(lang.tr("Cache Data Cleaner"), systemImage: "trash") {
                            CacheCleanerView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("Splash Ad Cache Lock", systemImage: "megaphone.slash") {
                            AdCacheBlockerView()
                        }
                    }
                }

                WTSectionCard(header: lang.tr("Pairing & Airlift")) {
                    VStack(alignment: .leading, spacing: 0) {
                        utilityRow(lang.tr("Get Pairing File + VPN Status"), systemImage: "key.fill") {
                            PairingView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("Airlift", systemImage: "airplane") {
                            AirliftView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow(lang.tr("All data changed"), systemImage: "clock.arrow.circlepath") {
                            AllDataChangedView()
                        }
                    }
                }

                WTSectionCard(header: "Log") {
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(console.output)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("bottom")
                            }
                            .frame(height: 240)
                            .onChange(of: console.output) { _, _ in
                                withAnimation {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                        Divider()
                            .padding(.leading, 14)

                        Button {
                            console.output = ""
                        } label: {
                            Text(lang.tr("Clear"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Sandbox")
        }
    }

    /// One Sandbox home utility row: the row's label on the
    /// left, a chevron on the right, the whole row tappable.
    private func utilityRow<Destination: View>(_ title: String, systemImage: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                    // Wrap the label instead of truncating it at
                    // Large Text.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
    }

    /// One label/value line of the identity card's device-details
    /// block.
    private func deviceInfoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                // Long values (build strings) wrap instead of
                // truncating at Large Text.
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

// MARK: - Sandbox Escape page
//
// Target Path field + Consume / Release Sandbox Extension, plus
// Share Contents, which acts on the same target path.

struct SandboxEscapePage: View {
    @EnvironmentObject private var lang: WTLangStore
    @Binding var path: String
    @Binding var sandboxHandle: Int64?

    private var isConsumed: Bool {
        (sandboxHandle ?? -255) > 0
    }

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: lang.tr("Target Path")) {
                TextField(lang.tr("Target"), text: $path)
                    .disabled(isConsumed)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }

            WTSectionCard(header: lang.tr("Escape")) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        sandboxHandle = consumeExtension(path)
                    } label: {
                        Text(lang.tr("Consume Sandbox Extension"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .disabled(path.isEmpty || isConsumed)

                    Divider()
                        .padding(.leading, 14)

                    Button {
                        if let handle = sandboxHandle {
                            releaseExtension(handle)
                        }
                        sandboxHandle = nil
                    } label: {
                        Text(lang.tr("Release Sandbox Extension"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .disabled(!isConsumed)
                }
            }

            WTSectionCard(header: lang.tr("Utilities")) {
                ShareLink(item: URL(fileURLWithPath: path)) {
                    Label(lang.tr("Share Contents"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .disabled(path.isEmpty)
            }
        }
        .navigationTitle("Sandbox Escape")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Path Enumeration page
//
// Enumerates the paths under the Sandbox tab's target path.

struct PathEnumerationPage: View {
    @EnvironmentObject private var lang: WTLangStore
    let path: String

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: lang.tr("Enumeration")) {
                VStack(alignment: .leading, spacing: 0) {
                    // Reliable, but insanely slow
                    Button {
                        leakPaths(path)
                    } label: {
                        Text("Get Paths (pathleak)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }

                    Divider()
                        .padding(.leading, 14)

                    // Only works on directories that can get a parent
                    // directory extension (AppGroup and System on 27.x)
                    Button {
                        listPaths(path)
                    } label: {
                        Text("Get Paths (parentdir)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
                .disabled(path.isEmpty)
            }
        }
        .navigationTitle(lang.tr("Path Enumeration"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - App Group page
//
// App Group ID field + Save + Diagnostics, with the explanation
// of what error -1 means.

struct AppGroupPage: View {
    @EnvironmentObject private var lang: WTLangStore
    @Binding var groupText: String

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "App Group", footer: lang.tr("Error -1 means the signed app cannot access its App Group container. Diagnostics reads the groups from your signed provisioning profile and probes them all. If it reports no signed groups, the IPA was signed without an App Group and must be re-signed with one — no name typed here can fix that.")) {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("App Group ID", text: $groupText)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                    Divider()
                        .padding(.leading, 14)

                    Button {
                        AppGroupResolver.configuredGroup = groupText
                        print("[AppGroup] configured group set to: \(groupText)")
                        AppGroupResolver.logDiagnostics()
                    } label: {
                        Text(lang.tr("Save App Group ID"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }

                    Divider()
                        .padding(.leading, 14)

                    Button {
                        AppGroupResolver.logDiagnostics()
                    } label: {
                        Text(lang.tr("App Group Diagnostics"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .navigationTitle("App Group")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Language picker sheet (v7.0)
//
// The five languages, shown by name text only (no flag
// graphics). Tapping one switches the language
// immediately — the whole app re-translates and
// re-themes with no restart.

struct LanguagePickerSheet: View {
    @EnvironmentObject private var lang: WTLangStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(WTLanguage.allCases) { language in
                    Button {
                        lang.setLanguage(language.rawValue)
                        SoundEffects.playTap()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(language.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if lang.language == language {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(lang.theme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle(lang.tr("Language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.tr("Done")) { dismiss() }
                }
            }
        }
    }
}
