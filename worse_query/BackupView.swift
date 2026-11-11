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
///
/// Since v3.8 the tab renders as Liquid Glass cards (WTGlassPage),
/// like every other page. The List's swipe-to-delete on snapshots
/// becomes a long-press context menu — same delete, same rows.
struct BackupView: View {
    @ObservedObject var manager: GestaltManager

    var body: some View {
        NavigationStack {
            WTGlassPage {
                WTSectionCard(header: "Snapshots", footer: "A snapshot is also created automatically at every Apply, containing the state that Apply just produced. The Original backup is created once, the first time MobileGestalt is read successfully.") {
                    Button {
                        manager.createManualSnapshot()
                    } label: {
                        Text("Back Up Now")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .disabled(!manager.isValid)
                }

                if let original = manager.originalSnapshot {
                    WTSectionCard(header: "Original") {
                        snapshotRow(original)
                    }
                }

                if manager.otherSnapshots.isEmpty {
                    WTSectionCard(header: "Apply Snapshots") {
                        Text("No snapshots yet. Apply some tweaks or tap Back Up Now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                } else {
                    WTSectionCard(header: "Apply Snapshots") {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(manager.otherSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                                snapshotRow(snapshot)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            manager.deleteSnapshot(snapshot)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let error = manager.lastError {
                    WTSectionCard {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
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
                RowIcon(systemImage: snapshot.kind == .original ? "lock.shield" : "clock.arrow.circlepath")

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

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail

struct BackupDetailView: View {
    @ObservedObject var manager: GestaltManager
    let snapshot: BackupSnapshot

    @State private var showRestoreAllConfirm = false

    var body: some View {
        WTGlassPage {
            WTSectionCard {
                VStack(alignment: .leading, spacing: 0) {
                    LabeledContent("Type", value: snapshot.kind.label)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider().padding(.leading, 14)
                    LabeledContent("Date", value: snapshot.date.formatted(date: .abbreviated, time: .standard))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider().padding(.leading, 14)
                    LabeledContent("Total CacheExtra keys", value: "\(snapshot.cacheExtraCount)")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    Divider().padding(.leading, 14)
                    LabeledContent("Active tweaks", value: "\(snapshot.enabledTweakIDs.count) of \(TweakCatalog.all.count)")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
            }

            WTSectionCard(footer: "Rewrites the entire MobileGestalt.plist from this backup. A device restart is required after restoring.") {
                Button(role: .destructive) {
                    showRestoreAllConfirm = true
                } label: {
                    Text("Restore Everything")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .disabled(!manager.isValid)
            }

            WTSectionCard(header: "By Tweak") {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(TweakCatalog.all.enumerated()), id: \.element.id) { index, tweak in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 14)
                        }
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: "By Key") {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(snapshot.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 14)
                        }
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 4)
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
            Button("Restart Device") { manager.presentManualRestartGuide() }
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
