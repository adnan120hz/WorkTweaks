import SwiftUI

/// "All data changed" — the history of every menu that was applied.
/// Every successful apply / flash records one entry (when + which
/// menu + what it did). Nothing is written here; it is a log only.
struct AllDataChangedView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @State private var entries: [ApplyHistoryEntry] = ApplyHistory.entries()
    @State private var showClearConfirm = false

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: wtLang.tr("All data changed")) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(wtLang.tr("Every menu that was applied, newest first. This is a history log — clearing it only clears the list, it does not undo anything."))
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
                            Text(wtLang.tr("Clear History"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                }
            }

            if entries.isEmpty {
                WTSectionCard(header: wtLang.tr("History")) {
                    Text(wtLang.tr("Nothing applied yet."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            } else {
                WTSectionCard(header: wtLang.tr("History")) {
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
        .navigationTitle(wtLang.tr("All data changed"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entries = ApplyHistory.entries() }
        .confirmationDialog(wtLang.tr("Clear the apply history?"), isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(wtLang.tr("Clear History"), role: .destructive) {
                ApplyHistory.clear()
                entries = []
            }
            Button(wtLang.tr("Cancel"), role: .cancel) { }
        } message: {
            Text(wtLang.tr("This only clears the list. It does not undo anything that was applied."))
        }
    }
}
