import SwiftUI

struct SandboxView: View {
    @ObservedObject var console: Console
    @State private var path = "/private/var/mobile/Containers/Shared/AppGroup/"
    @State private var sandboxHandle: Int64?
    @State private var groupText = AppGroupResolver.configuredGroup

    /// Master switch for the Tweaks tab (v2.0): the Tweaks tab
    /// stays locked until this is turned on. Shared with the
    /// Tweaks tab gate via the same AppStorage key.
    @AppStorage("wt.tweaksFeatureEnabled") private var tweaksEnabled = false

    private var isConsumed: Bool {
        (sandboxHandle ?? -255) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                // v2.0: master switch for the Tweaks feature.
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            IconChip(systemImage: tweaksEnabled ? "lock.open.fill" : "lock.fill",
                                     color: tweaksEnabled ? .green : .gray)
                            Toggle("Start Tweaks Feature", isOn: $tweaksEnabled)
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Unlocks the Tweaks tab. Turn this on to start using tweaks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.accentColor.opacity(0.07))

                // v2.0: this device's support status.
                Section {
                    Label {
                        Text(SupportInfo.isSupported
                             ? "Supported iOS • \(SupportInfo.deviceSummary)"
                             : "Unsupported iOS • \(SupportInfo.deviceSummary)")
                            .font(.subheadline.weight(.medium))
                    } icon: {
                        Image(systemName: SupportInfo.isSupported ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(SupportInfo.isSupported ? .green : .orange)
                    }
                } header: {
                    Label("Device", systemImage: "iphone")
                }

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
                    Label("App Group", systemImage: "link")
                } footer: {
                    Text("Error -1 means the signed app cannot access its App Group container. Diagnostics reads the groups from your signed provisioning profile and probes them all. If it reports no signed groups, the IPA was signed without an App Group and must be re-signed with one — no name typed here can fix that.")
                }

                Section {
                    TextField("Target", text: $path)
                        .disabled(isConsumed)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                } header: {
                    Label("Target Path", systemImage: "folder")
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
                    Label("Escape", systemImage: "escape")
                }

                Section {
                    ShareLink(item: URL(fileURLWithPath: path)) {
                        Label("Share Contents", systemImage: "square.and.arrow.up")
                    }
                    .disabled(path.isEmpty)
                } header: {
                    Label("Utilities", systemImage: "wrench.and.screwdriver")
                }

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
                    Label("Enumeration", systemImage: "list.bullet.indent")
                }
                .disabled(path.isEmpty)

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
                    Label("Log", systemImage: "terminal")
                }
            }
            .navigationTitle("Sandbox")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
