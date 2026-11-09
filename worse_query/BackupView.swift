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
                        Label("Backup Sekarang", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(!manager.isValid)
                } footer: {
                    Text("Snapshot juga otomatis dibuat setiap kali Apply, berisi data persis sebelum perubahan ditulis. Original backup dibuat sekali, saat pertama kali MobileGestalt berhasil dibaca.")
                }

                if let original = manager.originalSnapshot {
                    Section("Original") {
                        snapshotRow(original)
                    }
                }

                if manager.otherSnapshots.isEmpty {
                    Section("Snapshot Apply") {
                        Text("Belum ada snapshot. Tekan Apply Tweaks atau Backup Sekarang.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Snapshot Apply") {
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
                    Text("\(snapshot.enabledTweakIDs.count) tweak aktif · \(snapshot.cacheExtraCount) key di CacheExtra")
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
                LabeledContent("Jenis", value: snapshot.kind.label)
                LabeledContent("Tanggal", value: snapshot.date.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Total key CacheExtra", value: "\(snapshot.cacheExtraCount)")
                LabeledContent("Tweak aktif", value: "\(snapshot.enabledTweakIDs.count) dari \(TweakCatalog.all.count)")
            }

            Section {
                Button(role: .destructive) {
                    showRestoreAllConfirm = true
                } label: {
                    Label("Restore Semua", systemImage: "arrow.uturn.backward.circle.fill")
                }
                .disabled(!manager.isValid)
            } footer: {
                Text("Menulis ulang seluruh MobileGestalt.plist dari backup ini. Respring setelah restore.")
            }

            Section("Per Tweak") {
                ForEach(TweakCatalog.all) { tweak in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tweak.title)
                                .font(.subheadline.weight(.medium))
                            Text(snapshot.enabledTweakIDs.contains(tweak.id) ? "Aktif di backup ini" : "Mati di backup ini")
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

            Section("Per Key") {
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
                            Text(entry.present ? "Nilai: \(entry.valueDescription)" : "Tidak ada di backup ini")
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
        .navigationTitle("Detail Backup")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Restore seluruh backup ini?", isPresented: $showRestoreAllConfirm) {
            Button("Restore Semua", role: .destructive) {
                manager.restore(snapshot)
            }
        } message: {
            Text("Seluruh MobileGestalt saat ini akan digantikan isi backup \(snapshot.kind.label) ini.")
        }
    }
}
