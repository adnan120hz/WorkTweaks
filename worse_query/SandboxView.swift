import SwiftUI

struct SandboxView: View {
    @ObservedObject var console: Console
    @State private var path = "/private/var/mobile/Containers/Shared/AppGroup/"
    @State private var sandboxHandle: Int64?
    @State private var groupText = AppGroupResolver.configuredGroup

    private var isConsumed: Bool {
        (sandboxHandle ?? -255) > 0
    }

    var body: some View {
        NavigationStack {
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
                    Text("Error -1 means the signed app cannot access its App Group container. The app auto-detects any accessible group; if your signer assigned a different one, enter it exactly here, Save, then reload the Tweaks tab.")
                }

                Section("Target Path") {
                    TextField("Target", text: $path)
                        .disabled(isConsumed)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }

                Section("Escape") {
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
                }

                Section("Utilities") {
                    ShareLink(item: URL(fileURLWithPath: path)) {
                        Label("Share Contents", systemImage: "square.and.arrow.up")
                    }
                    .disabled(path.isEmpty)
                }

                Section("Enumeration") {
                    // Reliable, but insanely slow
                    Button("Get Paths (pathleak)") {
                        leakPaths(path)
                    }
                    // Only works on directories that can get a parent
                    // directory extension (AppGroup and System on 27.x)
                    Button("Get Paths (parentdir)") {
                        listPaths(path)
                    }
                }
                .disabled(path.isEmpty)

                Section("Log") {
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
                }
            }
            .navigationTitle("Sandbox")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
