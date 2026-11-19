import SwiftUI

/// "All data changed" — the history of every menu that was applied.
/// Every successful apply / flash records one entry (when + which
/// menu + what it did). Nothing is written here; it is a log only.
struct AllDataChangedView: View {
    @State private var entries: [ApplyHistoryEntry] = ApplyHistory.entries()
    @State private var showClearConfirm = false

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "All data changed") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Every menu that was applied, newest first. This is a history log — clearing it only clears the list, it does not undo anything.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    if !entries.isEmpty {
                        Divider().padding(.leading, 14)
                        Button(role: .destructive) {
                            SoundEffects.playTap()
                            showClearConfirm = true
                        } label: {
                            Text("Clear History")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                }
            }

            if entries.isEmpty {
                WTSectionCard(header: "History") {
                    Text("Nothing applied yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            } else {
                WTSectionCard(header: "History") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.source)
                                    .font(.subheadline.weight(.semibold))
                                Text(entry.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                + Text(" ")
                                + Text(entry.date, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            if index < entries.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("All data changed")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entries = ApplyHistory.entries() }
        .confirmationDialog("Clear the apply history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                ApplyHistory.clear()
                entries = []
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This only clears the list. It does not undo anything that was applied.")
        }
    }
}
