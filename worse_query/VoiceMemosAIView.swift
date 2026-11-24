import SwiftUI

// MARK: - Voice Memos & AI Cache page
//
// Two sections on one page: Voice Memos export (recordings
// from CloudRecordings.db, with their original titles, as a
// batch ZIP) and AI cache sizes (translationd /
// mediaanalysisd system groups + Translate / VoiceMemos /
// Shortcuts containers) with a Delete-cache action that only
// ever removes files under Library/Caches.
//
// The recordings load waits for the App Data scan — the
// Voice Memos container is found through it — so opening
// this page before the scan finishes shows a waiting state
// and loads automatically once the scan completes.

struct VoiceMemosAIView: View {
    @StateObject private var engine = VoiceMemosAI()
    @ObservedObject private var appData = AppDataManager.shared
    @State private var showDeleteCacheConfirm = false

    var body: some View {
        WTGlassPage {
            WTSectionCard(
                header: "Voice Memos",
                footer: "Exported as .m4a files with their original titles, zipped to this app's Documents/VoiceMemosExports. The recordings database is only ever read — never written."
            ) {
                switch engine.recordingsState {
                case .idle, .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appData.didScan ? "Reading the recordings database…" : "Waiting for the App Data scan…")
                                .font(.subheadline)
                            Text("The Voice Memos container is found through the App Data scan.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                case .blocked(let message):
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Couldn't load the recordings.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            engine.retryLoadRecordings()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                case .ready:
                    if engine.recordings.isEmpty {
                        Text("No recordings were found in the Voice Memos database.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(engine.recordings.enumerated()), id: \.element.id) { index, recording in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                                Button {
                                    engine.recordings[index].isSelected.toggle()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: recording.isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(recording.isSelected ? Color.accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recording.title)
                                                .font(.subheadline)
                                                .lineLimit(1)
                                            HStack(spacing: 6) {
                                                if let duration = recording.duration {
                                                    Text(formattedDuration(duration))
                                                }
                                                Text(wtFormatSize(recording.size))
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if case .ready = engine.recordingsState, !engine.recordings.isEmpty {
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Button("Select All") {
                                for index in engine.recordings.indices {
                                    engine.recordings[index].isSelected = true
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                            Button("Select None") {
                                for index in engine.recordings.indices {
                                    engine.recordings[index].isSelected = false
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        Divider()
                            .padding(.leading, 14)
                        Button {
                            engine.exportSelected()
                        } label: {
                            Text(engine.isExporting ? "Exporting…" : "Export Selected (\(engine.recordings.filter { $0.isSelected }.count))")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                        .disabled(engine.recordings.filter { $0.isSelected }.isEmpty || engine.isExporting)
                        if let url = engine.exportURL {
                            Divider()
                                .padding(.leading, 14)
                            ShareLink(item: url) {
                                Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }

                if let message = engine.exportMessage {
                    WTSectionCard {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
            }

            WTSectionCard(
                header: "AI Cache",
                footer: "Sizes are probed read-only (depth 4). Delete Cache removes only files under Library/Caches inside these targets — the AI models live elsewhere and are never touched."
            ) {
                if engine.isProbingAI && engine.aiTargets.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Probing cache sizes…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else if engine.aiTargets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No AI cache targets were found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Probe Again") {
                            engine.probeAICache()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(engine.aiTargets.enumerated()), id: \.element.id) { index, target in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                                }
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    if target.probed {
                                        Text("\(target.fileCount) file(s) • \(wtFormatSize(target.bytes)) total • \(wtFormatSize(target.cachesBytes)) in Caches")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Grant refused — size unknown.")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !engine.aiTargets.isEmpty {
                WTSectionCard {
                    Button(role: .destructive) {
                        showDeleteCacheConfirm = true
                    } label: {
                        Text(engine.isDeletingCache ? "Deleting…" : "Delete AI Cache Files")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .disabled(engine.isDeletingCache || !engine.aiTargets.contains(where: { $0.cachesBytes > 0 }))
                }

                if let message = engine.cacheMessage {
                    WTSectionCard {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
        .navigationTitle("Voice Memos & AI Cache")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete the AI cache files?", isPresented: $showDeleteCacheConfirm) {
            Button("Delete Cache Files", role: .destructive) {
                engine.deleteAICaches()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only files under Library/Caches inside the listed targets are deleted. AI models are never touched, and caches regenerate when the apps run again.")
        }
        .onAppear {
            appData.scanIfNeeded()
            if appData.didScan, case .idle = engine.recordingsState {
                engine.loadRecordings()
            }
            if engine.aiTargets.isEmpty {
                engine.probeAICache()
            }
        }
        .onChange(of: appData.didScan) { _, didScan in
            if didScan, case .idle = engine.recordingsState {
                engine.loadRecordings()
            }
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
