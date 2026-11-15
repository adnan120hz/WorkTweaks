import SwiftUI

// MARK: - Settings sheet (the avatar)
//
// What Sileo opens from the avatar (top right): a settings
// sheet. For WorkTweaks it holds the controls that used to
// live on the Sandbox tab — Start Tweaks Feature, Sound
// Effects, the Tweaks UI picker — plus the Tools (Sandbox
// Escape, Path Enumeration, App Group, App Data, PosterBoard,
// Cache Data Cleaner, CacheExtra, Backup, Log), each pushing
// its own page, and the About rows (Tutorials, License &
// Credits). The footer carries the version + device line,
// like Sileo's device footer.

struct SileoSettingsSheet: View {
    @ObservedObject var console: Console
    @ObservedObject var manager: GestaltManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("wt.tweaksFeatureEnabled") private var tweaksEnabled = false
    @AppStorage("wt.soundEffectsEnabled") private var soundsEnabled = true
    @AppStorage("wt.tweaksUIVersion") private var uiVersionRaw = "sileo"

    @State private var path = ""
    @State private var sandboxHandle: Int64?
    @State private var groupText = ""

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Start Tweaks Feature", isOn: $tweaksEnabled)
                    Toggle("Sound Effects", isOn: $soundsEnabled)
                    Picker("Tweaks UI", selection: $uiVersionRaw) {
                        Text("Sileo UI").tag("sileo")
                        Text("New UI").tag("new")
                        Text("Old UI").tag("old")
                    }
                } footer: {
                    Text("Turn on Start Tweaks Feature to unlock the Featured tab.")
                }

                Section("Tools") {
                    Button("Reload MobileGestalt") {
                        SoundEffects.playTap()
                        manager.load()
                    }
                    NavigationLink("Sandbox Escape") {
                        SandboxEscapePage(path: $path, sandboxHandle: $sandboxHandle)
                    }
                    NavigationLink("Path Enumeration") {
                        PathEnumerationPage(path: path)
                    }
                    NavigationLink("App Group") {
                        AppGroupPage(groupText: $groupText)
                    }
                    NavigationLink("CacheExtra") {
                        CacheExtraView(manager: manager, sileo: true)
                    }
                    NavigationLink("Backup") {
                        BackupView(manager: manager, sileo: true)
                    }
                    NavigationLink("Log") {
                        LogView(console: console, sileo: true)
                    }
                }

                Section("About") {
                    NavigationLink("What's New") {
                        SileoNewsContent()
                            .navigationTitle("News")
                            .navigationBarTitleDisplayMode(.large)
                    }
                    Link("WorkTweaks on GitHub", destination: URL(string: "https://github.com/adnan120hz/WorkTweaks")!)
                    NavigationLink("Tutorials") {
                        TutorialsView()
                    }
                    NavigationLink("License & Credits") {
                        LicenseView()
                    }
                }

                Section {
                    Text("WorkTweaks v\(appVersion) • \(SupportInfo.deviceSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("WorkTweaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.blue)
    }
}
