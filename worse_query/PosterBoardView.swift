import SwiftUI
import UniformTypeIdentifiers

// MARK: - PosterBoard page
//
// Import .tendies wallpaper packages into PosterBoard's
// data store and remove the wallpapers imported here. All
// work goes through PosterBoardManager (container resolution
// from the shared App Data scan, one sandbox extension on
// the container per operation, verified copies, import
// receipts). Resolution, import, and delete all end in an
// honest status; a successful import or delete offers the
// app's standard respring prompt, because SpringBoard only
// reloads the wallpaper store when it (re)starts.
//
// The page renders as Liquid Glass cards (WTGlassPage /
// WTSectionCard), like every other page since v3.8.

struct PosterBoardView: View {
    @StateObject private var manager = PosterBoardManager()
    @ObservedObject private var appData = AppDataManager.shared

    @State private var showImporter = false
    @State private var showRespringChoice = false
    @State private var showManualRestartGuide = false
    @State private var pendingDelete: PosterBoardReceipt?
    @State private var pickerError: String?

    private var packageContentTypes: [UTType] {
        var types: [UTType] = [.zip]
        if let tendies = UTType(filenameExtension: "tendies", conformingTo: .data) {
            types.insert(tendies, at: 0)
        }
        types.append(.data)
        return types
    }

    var body: some View {
        WTGlassPage {
            statusCard

            if let result = manager.lastResult {
                WTSectionCard {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            if case .ready = manager.state {
                WTSectionCard(header: "Import", footer: "Each wallpaper in the package is copied into PosterBoard's data store under a fresh identifier, so it can never clash with an existing wallpaper. A respring is required before a new wallpaper appears in the gallery.") {
                    Button {
                        showImporter = true
                    } label: {
                        HStack(spacing: 10) {
                            Label("Import .tendies Package…", systemImage: "shippingbox")
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            if manager.isBusy {
                                ProgressView()
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isBusy)
                }

                WTSectionCard(header: "Create", footer: "Builds a PosterBoard wallpaper on-device from your photo or video — the same descriptor format as an imported .tendies package, installed and listed exactly like one.") {
                    NavigationLink {
                        PosterBoardMakerView(manager: manager)
                    } label: {
                        HStack(spacing: 10) {
                            Label("Create Wallpaper…", systemImage: "wand.and.stars")
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isBusy)
                }

                WTSectionCard(header: "Imported") {
                    if manager.receipts.isEmpty {
                        Text("No wallpapers imported yet. Wallpapers imported here are listed so you can remove them again — wallpapers added any other way are never touched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(manager.receipts.enumerated()), id: \.element.id) { index, receipt in
                                if index > 0 {
                                    Divider().padding(.leading, 14)
                                }
                                importedRow(receipt)
                            }
                        }
                    }
                }

                WTSectionCard(header: "Package Format") {
                    Text("A .tendies package is a ZIP archive containing one or more wallpaper descriptors: loose descriptor folders, a descriptors folder, or a container layout mirroring PosterBoard's data store (Library/Application Support/PRBPosterExtensionDataStore/…/Extensions/…/descriptors). Stored and deflated ZIP entries are supported — the same reader Deploy uses; encrypted and ZIP64 archives are rejected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle("PosterBoard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.loadReceipts()
            kickResolution()
        }
        .onChange(of: appData.didScan) { _, done in
            if done { manager.resolve() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: packageContentTypes) { result in
            switch result {
            case .success(let url):
                manager.importPackage(url: url) { ok in
                    if ok { showRespringChoice = true }
                }
            case .failure(let error):
                pickerError = error.localizedDescription
            }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { pickerError != nil },
            set: { if !$0 { pickerError = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(pickerError ?? "")
        }
        .confirmationDialog("PosterBoard Updated", isPresented: $showRespringChoice, titleVisibility: .visible) {
            Button("Respring") { RespringCenter.shared.trigger() }
            Button("Restart Device") { showManualRestartGuide = true }
            Button("Later", role: .cancel) { }
        } message: {
            Text("SpringBoard loads the wallpaper store when it starts — respring or restart to see the change in the wallpaper gallery.")
        }
        .alert(ManualRestartGuide.title, isPresented: $showManualRestartGuide) {
            Button("OK") { }
        } message: {
            Text(ManualRestartGuide.message)
        }
        .confirmationDialog("Delete Wallpaper?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let receipt = pendingDelete {
                    manager.delete(receipt: receipt) { ok in
                        if ok { showRespringChoice = true }
                    }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the wallpaper imported from \(pendingDelete?.sourcePackage ?? "the package") — its descriptor folder is deleted from PosterBoard's data store.")
        }
    }

    // MARK: Status card

    @ViewBuilder
    private var statusCard: some View {
        switch manager.state {
        case .idle, .resolving:
            WTSectionCard(header: "PosterBoard Data") {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(appData.isScanning ? appData.scanPhase : manager.resolvePhase)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        case .blocked(let reason):
            WTSectionCard(footer: "Nothing was written.") {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("PosterBoard is unavailable", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 14)

                    Button {
                        kickResolution()
                    } label: {
                        Text("Try Again")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .ready:
            WTSectionCard(header: "PosterBoard Data") {
                VStack(alignment: .leading, spacing: 6) {
                    infoRow("Container", manager.containerPath.map { ($0 as NSString).lastPathComponent } ?? "—")
                    infoRow("Data Store", "Version \(manager.storeVersion ?? "—")")
                    infoRow("Descriptors", "\(manager.descriptorCount)")
                    if let containerPath = manager.containerPath {
                        Text(containerPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    /// One label/value line of the status card.
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }

    // MARK: Imported rows

    private func importedRow(_ receipt: PosterBoardReceipt) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.sourcePackage)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(receipt.descriptorUUID) • \(Self.displayDate(receipt.importedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                pendingDelete = receipt
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .regular))
            }
            .buttonStyle(.plain)
            .disabled(manager.isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private static func displayDate(_ iso8601: String) -> String {
        if let date = ISO8601DateFormatter().date(from: iso8601) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return iso8601
    }

    // MARK: Resolution kick

    /// Start (or wait for) the shared App Data scan, then
    /// resolve — the same pattern Deploy uses: the scan runs
    /// once per app session and its results are shared.
    private func kickResolution() {
        if appData.didScan {
            manager.resolve()
        } else {
            manager.noteWaitingForScan()
            if !appData.isScanning {
                appData.rescan()
            }
        }
    }
}
