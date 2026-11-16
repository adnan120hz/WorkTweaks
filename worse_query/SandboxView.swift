import SwiftUI

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
    @State private var path = "/private/var/mobile/Containers/Shared/AppGroup/"
    @State private var sandboxHandle: Int64?
    @State private var groupText = AppGroupResolver.configuredGroup

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

    var body: some View {
        NavigationStack {
            WTGlassPage {
                // Front door identity: app icon, name, and this
                // device's support status.
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 14) {
                            Image("AppIconDisplay")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("WorkTweaks")
                                        .font(.headline)
                                    Text("v\(appVersion)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 5) {
                                    Image(systemName: SupportInfo.isSupported ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(SupportInfo.isSupported ? Color.accentColor : .orange)
                                    Text(SupportInfo.isSupported
                                         ? "Supported iOS • \(SupportInfo.deviceSummary)"
                                         : "Unsupported iOS • \(SupportInfo.deviceSummary)")
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
                            deviceInfoRow("Model", machineName())
                            deviceInfoRow("iOS Version", SupportInfo.deviceVersion)
                            deviceInfoRow("Build", SupportInfo.deviceBuild)
                            deviceInfoRow("Support", SupportInfo.isSupported ? "Supported" : "Unsupported")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }

                // Master switch for the Tweaks feature.
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Start Tweaks Feature", isOn: $tweaksEnabled)
                            .font(.subheadline.weight(.semibold))
                        Text("Unlocks the Tweaks tab. Turn this on to start using tweaks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        // Tweaks UI choice — New UI is the current
                        // two-column layout, Old UI is the v1 list
                        // layout. Applies to the Tweaks tab only.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tweaks UI")
                                .font(.subheadline.weight(.semibold))
                            Picker("Tweaks UI", selection: $tweaksUIVersion) {
                                Text("New UI").tag("new")
                                Text("Old UI").tag("old")
                            }
                            .pickerStyle(.segmented)
                            Text("Applies to the Tweaks tab only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // UI sounds — soft tap on menus and
                        // features, soft swipe on tab switches.
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Sound Effects", isOn: $soundEffectsEnabled)
                                .font(.subheadline.weight(.semibold))
                            Text("Plays a soft sound when you tap menus and features. Respects the silent switch.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                // Utility menus — each opens its own page.
                WTSectionCard(header: "Utilities") {
                    VStack(alignment: .leading, spacing: 0) {
                        utilityRow("Sandbox Escape", systemImage: "lock.open") {
                            SandboxEscapePage(path: $path, sandboxHandle: $sandboxHandle)
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("Path Enumeration", systemImage: "list.bullet.indent") {
                            PathEnumerationPage(path: path)
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("App Group", systemImage: "person.2") {
                            AppGroupPage(groupText: $groupText)
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("App Data", systemImage: "folder") {
                            AppDataView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("PosterBoard", systemImage: "photo") {
                            PosterBoardView()
                        }
                        Divider().padding(.leading, 14)
                        utilityRow("Cache Data Cleaner", systemImage: "trash") {
                            CacheCleanerView()
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
                            Text("Clear")
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
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }
}

// MARK: - Sandbox Escape page
//
// Target Path field + Consume / Release Sandbox Extension, plus
// Share Contents, which acts on the same target path.

struct SandboxEscapePage: View {
    @Binding var path: String
    @Binding var sandboxHandle: Int64?

    private var isConsumed: Bool {
        (sandboxHandle ?? -255) > 0
    }

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "Target Path") {
                TextField("Target", text: $path)
                    .disabled(isConsumed)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }

            WTSectionCard(header: "Escape") {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        sandboxHandle = consumeExtension(path)
                    } label: {
                        Text("Consume Sandbox Extension")
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
                        Text("Release Sandbox Extension")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .disabled(!isConsumed)
                }
            }

            WTSectionCard(header: "Utilities") {
                ShareLink(item: URL(fileURLWithPath: path)) {
                    Label("Share Contents", systemImage: "square.and.arrow.up")
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
    let path: String

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "Enumeration") {
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
        .navigationTitle("Path Enumeration")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - App Group page
//
// App Group ID field + Save + Diagnostics, with the explanation
// of what error -1 means.

struct AppGroupPage: View {
    @Binding var groupText: String

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "App Group", footer: "Error -1 means the signed app cannot access its App Group container. Diagnostics reads the groups from your signed provisioning profile and probes them all. If it reports no signed groups, the IPA was signed without an App Group and must be re-signed with one — no name typed here can fix that.") {
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
                        Text("Save App Group ID")
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
                        Text("App Group Diagnostics")
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
