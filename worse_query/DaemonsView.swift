import SwiftUI

// MARK: - Daemons page
//
// Disable system daemons by writing their launchd labels into
// /var/db/com.apple.xpc.launchd/disabled.plist. Access to that
// root-owned directory is probed fail-safe by DaemonManager:
// if the kernel refuses the escape, this page shows the refusal
// honestly and offers no way to write anything.

struct DaemonsView: View {
    @StateObject private var manager = DaemonManager()
    @State private var showRisky = false

    private var isReady: Bool {
        if case .ready = manager.state { return true }
        return false
    }

    var body: some View {
        Form {
            statusSection

            Section {
                ForEach(DaemonCatalog.main, id: \.id) { category in
                    categoryRow(category)
                }
            } header: {
                Text("Daemons")
            } footer: {
                Text("Turning a category on disables its daemons. Disabled daemons stay off until you turn the category off here and restart again.")
            }
            .disabled(!isReady)

            Section {
                Toggle("Show risky daemons", isOn: $showRisky)

                if showRisky {
                    Text("Disabling thermalmonitord affects the device's thermal management.")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    ForEach(DaemonCatalog.risky, id: \.id) { category in
                        categoryRow(category)
                    }
                    .disabled(!isReady)
                }
            } header: {
                Text("Risky")
            }

            if isReady {
                Section {
                    Button("Apply") {
                        manager.apply()
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Writes the selection to disabled.plist. A full restart is required for changes to take effect.")
                }
            }
        }
        .navigationTitle("Daemons")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { manager.probeIfNeeded() }
        .confirmationDialog("Restart Required", isPresented: $manager.showRestartRequired, titleVisibility: .visible) {
            Button("Restart Device") { manager.attemptRestart() }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Daemon changes only take effect after a full device restart — a respring is not enough. Choosing Later just postpones it; the changes stay pending until you restart.")
        }
        .alert("Couldn't Apply Changes", isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil } }
        )) {
            Button("OK") { manager.errorMessage = nil }
        } message: {
            Text(manager.errorMessage ?? "")
        }
        .alert(manager.restartAlertTitle ?? "", isPresented: Binding(
            get: { manager.restartAlertTitle != nil },
            set: { if !$0 { manager.restartAlertTitle = nil } }
        )) {
            Button("OK") { manager.restartAlertTitle = nil }
        } message: {
            Text(manager.restartAlertMessage)
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch manager.state {
            case .probing:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Probing access to the launchd directory…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .ready:
                VStack(alignment: .leading, spacing: 3) {
                    Label("Access granted", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("\(DaemonManager.directoryPath)/disabled.plist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .blocked(_, let message):
                VStack(alignment: .leading, spacing: 3) {
                    Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Status")
        }
    }

    // MARK: Rows

    private func categoryRow(_ category: DaemonCategory) -> some View {
        Toggle(isOn: toggleBinding(category)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                Text(category.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleBinding(_ category: DaemonCategory) -> Binding<Bool> {
        Binding(
            get: { manager.toggles[category.id] ?? false },
            set: { manager.toggles[category.id] = $0 }
        )
    }
}
