import SwiftUI

// MARK: - Sandbox tab (v3.0: utilities as their own menus)
//
// The identity header and the "Start Tweaks Feature" master
// switch stay on the Sandbox home. Each utility group — Sandbox
// Escape, Path Enumeration, App Group — is now a menu row that
// opens its own page holding exactly the controls it had when
// they were stacked sections here. The console stays on the
// home, below the menu rows.

struct SandboxView: View {
    @ObservedObject var console: Console
    @State private var path = "/private/var/mobile/Containers/Shared/AppGroup/"
    @State private var sandboxHandle: Int64?
    @State private var groupText = AppGroupResolver.configuredGroup

    /// Master switch for the Tweaks tab (v2.0): the Tweaks tab
    /// stays locked until this is turned on. Shared with the
    /// Tweaks tab gate via the same AppStorage key.
    @AppStorage("wt.tweaksFeatureEnabled") private var tweaksEnabled = false

    /// This build's version as recorded in the bundle
    /// (CFBundleShortVersionString), e.g. "3.7" — the same
    /// source the Tweaks tab's mini identity card reads.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Front door identity: app icon, name, and this
                // device's support status.
                Section {
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
                    .padding(.vertical, 4)

                    // Compact device details, from the same data
                    // the support gate already computes.
                    VStack(alignment: .leading, spacing: 6) {
                        deviceInfoRow("Model", machineName())
                        deviceInfoRow("iOS Version", SupportInfo.deviceVersion)
                        deviceInfoRow("Build", SupportInfo.deviceBuild)
                        deviceInfoRow("Support", SupportInfo.isSupported ? "Supported" : "Unsupported")
                    }
                    .padding(.vertical, 2)
                }

                // Master switch for the Tweaks feature.
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Start Tweaks Feature", isOn: $tweaksEnabled)
                            .font(.subheadline.weight(.semibold))
                        Text("Unlocks the Tweaks tab. Turn this on to start using tweaks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                // Utility menus — each opens its own page.
                Section {
                    NavigationLink {
                        SandboxEscapePage(path: $path, sandboxHandle: $sandboxHandle)
                    } label: {
                        Label("Sandbox Escape", systemImage: "lock.open")
                    }

                    NavigationLink {
                        PathEnumerationPage(path: path)
                    } label: {
                        Label("Path Enumeration", systemImage: "list.bullet.indent")
                    }

                    NavigationLink {
                        AppGroupPage(groupText: $groupText)
                    } label: {
                        Label("App Group", systemImage: "person.2")
                    }

                    NavigationLink {
                        AppDataView()
                    } label: {
                        Label("App Data", systemImage: "folder")
                    }
                } header: {
                    Text("Utilities")
                }

                Section {
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

                    Button("Clear") {
                        console.output = ""
                    }
                } header: {
                    Text("Log")
                }
            }
            .navigationTitle("Sandbox")
        }
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
        Form {
            Section {
                TextField("Target", text: $path)
                    .disabled(isConsumed)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Target Path")
            }

            Section {
                Button("Consume Sandbox Extension") {
                    sandboxHandle = consumeExtension(path)
                }
                .disabled(path.isEmpty || isConsumed)

                Button("Release Sandbox Extension") {
                    if let handle = sandboxHandle {
                        releaseExtension(handle)
                    }
                    sandboxHandle = nil
                }
                .disabled(!isConsumed)
            } header: {
                Text("Escape")
            }

            Section {
                ShareLink(item: URL(fileURLWithPath: path)) {
                    Label("Share Contents", systemImage: "square.and.arrow.up")
                }
                .disabled(path.isEmpty)
            } header: {
                Text("Utilities")
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
        Form {
            Section {
                // Reliable, but insanely slow
                Button("Get Paths (pathleak)") {
                    leakPaths(path)
                }
                // Only works on directories that can get a parent
                // directory extension (AppGroup and System on 27.x)
                Button("Get Paths (parentdir)") {
                    listPaths(path)
                }
            } header: {
                Text("Enumeration")
            }
            .disabled(path.isEmpty)
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
        Form {
            Section {
                TextField("App Group ID", text: $groupText)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)

                Button("Save App Group ID") {
                    AppGroupResolver.configuredGroup = groupText
                    print("[AppGroup] configured group set to: \(groupText)")
                    AppGroupResolver.logDiagnostics()
                }

                Button("App Group Diagnostics") {
                    AppGroupResolver.logDiagnostics()
                }
            } header: {
                Text("App Group")
            } footer: {
                Text("Error -1 means the signed app cannot access its App Group container. Diagnostics reads the groups from your signed provisioning profile and probes them all. If it reports no signed groups, the IPA was signed without an App Group and must be re-signed with one — no name typed here can fix that.")
            }
        }
        .navigationTitle("App Group")
        .navigationBarTitleDisplayMode(.inline)
    }
}
