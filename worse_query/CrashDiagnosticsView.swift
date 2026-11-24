import SwiftUI

// MARK: - Jetsam & crash page
//
// Lists the diagnostic reports iOS writes when it kills or
// crashes an app, with a detail preview, share/export, and a
// Clean All that deletes only the listed report files. All
// strings are English, like the rest of the app.

struct CrashDiagnosticsView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var manager = CrashDiagnostics()
    @State private var selected: CrashReport?
    @State private var showCleanConfirm = false

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: wtLang.tr("About this feature"), footer: wtLang.tr("Only the listed .ips / .crash / .panic files under DiagnosticReports (and Retired) are ever deleted. The folders themselves are kept, and nothing else is touched.")) {
                Text(wtLang.tr("Jetsam & Crash lists the reports iOS writes when it kills an app for memory (Jetsam, bug_type 298), when an app crashes (309), or on a watchdog / kernel panic (210). Open a report to see why it died, share the full file, or clean all reports to free space."))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            WTSectionCard(header: wtLang.tr("Reports (%d)", manager.reports.count)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            SoundEffects.playTap()
                            manager.load()
                        } label: {
                            Label(manager.isLoading ? wtLang.tr("Loading…") : wtLang.tr("Refresh"), systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.isLoading)
                        Spacer(minLength: 0)
                        if manager.isLoading {
                            ProgressView()
                        }
                    }
                    switch manager.state {
                    case .idle:
                        Text(wtLang.tr("Tap Refresh to list the diagnostic reports."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .loading:
                        Text(wtLang.tr("Listing reports…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .ready:
                        if !manager.canWrite {
                            Text(wtLang.tr("Read-only mode — the grant did not include write access, so Clean All is disabled."))
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(wtLang.tr("Write access available — Clean All can delete the listed reports."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    case .blocked(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let result = manager.lastResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if case .ready = manager.state, !manager.reports.isEmpty {
                WTSectionCard(header: wtLang.tr("Clean up")) {
                    Button {
                        SoundEffects.playTap()
                        showCleanConfirm = true
                    } label: {
                        Label(manager.isCleaning ? wtLang.tr("Cleaning…") : wtLang.tr("Clean All Reports"), systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!manager.canWrite || manager.isCleaning)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .alert(wtLang.tr("Clean all reports?"), isPresented: $showCleanConfirm) {
                    Button(wtLang.tr("Delete %d report(s)", manager.reports.count), role: .destructive) {
                        manager.cleanAll { _ in }
                    }
                    Button(wtLang.tr("Cancel"), role: .cancel) {}
                } message: {
                    Text(wtLang.tr("This deletes only the listed .ips / .crash / .panic files. The folders are kept."))
                }

                WTSectionCard(header: wtLang.tr("Reports")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(manager.reports.enumerated()), id: \.element.id) { index, report in
                            Button {
                                SoundEffects.playTap()
                                selected = report
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: report.kind.systemImage)
                                        .foregroundStyle(report.kind == .jetsam ? .orange : report.kind == .crash ? .red : report.kind == .panic ? .purple : .secondary)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(report.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(report.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack(spacing: 8) {
                                            Text(report.date.formatted(date: .abbreviated, time: .shortened))
                                            Text("·")
                                            Text(wtFormatSize(report.size))
                                            if !report.bugType.isEmpty {
                                                Text("·")
                                                Text("bug_type \(report.bugType)")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 4)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            if index < manager.reports.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
            } else if case .ready = manager.state {
                WTSectionCard {
                    Text(wtLang.tr("No diagnostic reports found — nothing has been killed or crashed recently, or the reports were already cleaned."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle(wtLang.tr("Jetsam & Crash"))
        .sheet(item: $selected) { report in
            CrashReportDetailView(report: report, manager: manager)
        }
        .onAppear {
            if case .idle = manager.state {
                manager.load()
            }
        }
    }
}

private struct CrashReportDetailView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    let report: CrashReport
    let manager: CrashDiagnostics
    @Environment(\.dismiss) private var dismiss
    @State private var preview = "Loading preview…"
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WTSectionCard(header: wtLang.tr("Report")) {
                        VStack(alignment: .leading, spacing: 6) {
                            detailRow("File", report.fileName)
                            detailRow("Kind", report.kind.rawValue)
                            if !report.bugType.isEmpty {
                                detailRow("bug_type", report.bugType)
                            }
                            detailRow("Date", report.date.formatted(date: .abbreviated, time: .complete))
                            detailRow("Size", wtFormatSize(report.size))
                            if !report.killedNames.isEmpty {
                                detailRow("Killed", report.killedNames.joined(separator: ", "))
                            }
                            if let detail = report.exceptionDetail {
                                Text(detail)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    WTSectionCard(header: wtLang.tr("Preview (first 128 KB)")) {
                        Text(wtLang.tr(preview))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }

                    if let url = shareURL {
                        ShareLink(item: url) {
                            Label(wtLang.tr("Share Full Report"), systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    } else {
                        Button {
                            SoundEffects.playTap()
                            manager.shareURL(for: report) { url in
                                shareURL = url
                            }
                        } label: {
                            Label(wtLang.tr("Prepare Share"), systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(report.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(wtLang.tr("Close")) { dismiss() }
                }
            }
            .onAppear {
                manager.previewText(for: report) { text in
                    preview = text
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label == "bug_type" ? label : wtLang.tr(label))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
