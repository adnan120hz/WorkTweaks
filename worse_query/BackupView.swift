import SwiftUI

/// The Backup tab.
///
/// Every Apply first saves a snapshot of the MobileGestalt state at that
/// moment, and the first successful load saves the original backup. This
/// view lists those snapshots with the data inside them (which tweaks were
/// on, and the value of every tweak key), and can restore:
/// - a whole snapshot,
/// - a single tweak from a snapshot,
/// - a single key from a snapshot.
struct BackupView: View {
    @ObservedObject var manager: GestaltManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        manager.createManualSnapshot()
                    } label: {
                        Label("Back Up Now", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(!manager.isValid)
                } footer: {
                    Text("A snapshot is also created automatically at every Apply, containing the state that Apply just produced. The Original backup is created once, the first time MobileGestalt is read successfully.")
                }

                if let original = manager.originalSnapshot {
                    Section("Original") {
                        snapshotRow(original)
                    }
                }

                if manager.otherSnapshots.isEmpty {
                    Section("Apply Snapshots") {
                        Text("No snapshots yet. Apply some tweaks or tap Back Up Now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Apply Snapshots") {
                        ForEach(manager.otherSnapshots) { snapshot in
                            snapshotRow(snapshot)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                manager.deleteSnapshot(manager.otherSnapshots[index])
                            }
                        }
                    }
                }

                if let error = manager.lastError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        manager.refreshSnapshots()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                manager.refreshSnapshots()
            }
        }
    }

    private func snapshotRow(_ snapshot: BackupSnapshot) -> some View {
        NavigationLink {
            BackupDetailView(manager: manager, snapshot: snapshot)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: snapshot.kind == .original ? "lock.shield" : "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.kind.label)
                        .font(.subheadline.weight(.medium))
                    Text(snapshot.date, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(snapshot.enabledTweakIDs.count) active tweaks · \(snapshot.cacheExtraCount) CacheExtra keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Detail

struct BackupDetailView: View {
    @ObservedObject var manager: GestaltManager
    let snapshot: BackupSnapshot

    @State private var showRestoreAllConfirm = false

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: snapshot.kind.label)
                LabeledContent("Date", value: snapshot.date.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Total CacheExtra keys", value: "\(snapshot.cacheExtraCount)")
                LabeledContent("Active tweaks", value: "\(snapshot.enabledTweakIDs.count) of \(TweakCatalog.all.count)")
            }

            Section {
                Button(role: .destructive) {
                    showRestoreAllConfirm = true
                } label: {
                    Label("Restore Everything", systemImage: "arrow.uturn.backward.circle.fill")
                }
                .disabled(!manager.isValid)
            } footer: {
                Text("Rewrites the entire MobileGestalt.plist from this backup. A device restart is required after restoring.")
            }

            Section("By Tweak") {
                ForEach(TweakCatalog.all) { tweak in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tweak.title)
                                .font(.subheadline.weight(.medium))
                            Text(snapshot.enabledTweakIDs.contains(tweak.id) ? "On in this backup" : "Off in this backup")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            manager.restoreTweak(tweak, from: snapshot)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!manager.isValid)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("By Key") {
                ForEach(snapshot.entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.tweakTitle)
                                .font(.caption.weight(.semibold))
                            Text(entry.key)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(entry.present ? "Value: \(entry.valueDescription)" : "Not present in this backup")
                                .font(.caption)
                                .foregroundStyle(entry.present ? .primary : .secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            manager.restoreKey(entry, from: snapshot)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!manager.isValid)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Backup Details")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Restore this entire backup?", isPresented: $showRestoreAllConfirm) {
            Button("Restore Everything", role: .destructive) {
                manager.restore(snapshot)
            }
        } message: {
            Text("The current MobileGestalt will be entirely replaced with this \(snapshot.kind.label) backup.")
        }
        .confirmationDialog("Restart Required", isPresented: $manager.showRestartRequired, titleVisibility: .visible) {
            Button("Restart Device") { manager.attemptRestart() }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Restore changes only take effect after a full device restart — a respring is not enough. Choosing Later just postpones it; the changes stay pending until you restart.")
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
}
