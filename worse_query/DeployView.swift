import SwiftUI
import UniformTypeIdentifiers

// MARK: - Deploy page
//
// Import a Deploy package — v5: ONE .zip file from the
// Package Builder (older .deploy archives and plain folders
// still import) — check its manifest, resolve its one
// target app by itself, preview exactly what will happen,
// and apply. No location picking: the target and the
// destinations come from the zip's manifest. The package
// format and the safety rules are documented on this page
// itself, under "Package Format".
//
// The page is composed of two shared sections, so the App
// Data ••• menu's "Package Builder" page can host exactly
// the same machinery: DeployStoreSection (the "My Packages"
// store and its builder) and DeployPreviewSection (the
// manifest / files / target / result preview every loaded
// package lands in, however it was loaded).
//
// Since v3.8 the page renders as Liquid Glass cards
// (WTGlassPage/WTSectionCard), like every other page —
// presentation only; the deploy flow is unchanged.

/// The content types every Deploy package picker accepts:
/// a folder, or a .zip / .deploy archive.
private func deployPackageContentTypes() -> [UTType] {
    var types: [UTType] = [.folder, .zip]
    if let deployType = UTType(filenameExtension: "deploy", conformingTo: .data) {
        types.append(deployType)
    }
    return types
}

struct DeployView: View {
    @ObservedObject var appDataManager: AppDataManager
    @StateObject private var deployManager = DeployManager()

    @State private var package: LoadedDeployPackage?
    @State private var importError: String?
    @State private var showImporter = false
    @State private var resolveRequest = UUID()

    var body: some View {
        WTGlassPage {
            DeployStoreSection(
                appDataManager: appDataManager,
                onDeploy: { presentLoadedPackage($0) },
                onImportError: { importError = $0 }
            )

            WTSectionCard(header: "Deploy Package") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("A Deploy package replaces files inside exactly one app — the app named by its bundle ID. It cannot touch any other app: every target path is relative to that app's container, and packages with absolute or \"..\" paths are rejected whole.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                    Divider()
                        .padding(.leading, 14)

                    Button {
                        showImporter = true
                    } label: {
                        Label(package == nil ? "Choose Package…" : "Choose a Different Package…", systemImage: "shippingbox")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
            }

            if let importError {
                WTSectionCard(footer: "Nothing was written.") {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("This package was rejected", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            DeployPreviewSection(
                appDataManager: appDataManager,
                package: $package,
                deployManager: deployManager,
                resolveRequest: $resolveRequest
            )

            WTSectionCard(header: "Package Format") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A package is ONE .zip file containing a manifest.json at its top level plus the payload files it names. The Package Builder exports that zip (save it in Files); Deploy imports it, resolves the target itself from the manifest, and applies it — no location picking, the destinations come from the zip.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("""
                    {
                      "bundleID": "com.example.app",
                      "scope": "Application",
                      "name": "Optional label",
                      "files": [
                        { "path": "Library/Preferences/com.example.app.plist",
                          "source": "payload/com.example.app.plist" }
                      ]
                    }
                    """)
                    .font(.system(.caption, design: .monospaced))
                    Text("Single-file shorthand: instead of \"files\", give \"relativePath\" and \"file\". \"scope\" is Application (bundleID = the app's bundle ID), AppGroup (bundleID = the group identifier, e.g. group.com.example) or InternalDaemon. ZIP archives may use stored or deflated entries; encrypted and ZIP64 archives are not supported. Older .deploy archives and plain folders still import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle("Deploy")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: deployPackageContentTypes()) { result in
            switch result {
            case .success(let url):
                switch DeployManager.loadPackage(from: url) {
                case .success(let loaded):
                    presentLoadedPackage(loaded)
                case .failure(let error):
                    package = nil
                    importError = error.message
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }

    /// Show a loaded package in the preview/deploy flow
    /// below — the same state a fresh import lands in.
    /// Bumping resolveRequest makes the preview resolve
    /// the target by itself (v5: no location picking).
    private func presentLoadedPackage(_ loaded: LoadedDeployPackage) {
        package = loaded
        importError = nil
        deployManager.resolvedContainerPath = nil
        deployManager.resolveError = nil
        deployManager.lastResult = nil
        resolveRequest = UUID()
    }
}

// MARK: - Package store ("My Packages")
//
// The stored-package list and everything attached to it:
// the New Package / Import Package… actions, the
// builder/editor sheet, the export share sheet and the
// delete confirmation. One implementation, hosted by both
// the Deploy page and the Package Builder page, so both
// entry points show the same live store. Deploying a
// stored package is handed to the host (onDeploy), which
// shows it in its own preview flow.

struct DeployStoreSection: View {
    @ObservedObject var appDataManager: AppDataManager
    /// A stored package's Deploy action, after the package
    /// loaded successfully.
    var onDeploy: (LoadedDeployPackage) -> Void
    /// An import-for-editing failure, for the host to show
    /// in its package-rejected card.
    var onImportError: (String) -> Void

    @State private var storedPackages: [StoredDeployPackage] = []
    @State private var showImporter = false
    @State private var editorSession: DeployEditorSession?
    @State private var packageToDelete: StoredDeployPackage?
    @State private var exportItem: DeployExportItem?
    @State private var storeError: String?

    private struct DeployExportItem: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    var body: some View {
        Group {
            WTSectionCard(header: "My Packages", footer: "Packages you build or import are stored on this device, in WorkTweaks' own container. Tap a package to edit it. Deploy runs it through the same preview, resolve and backup flow as a picked package.") {
                VStack(alignment: .leading, spacing: 0) {
                    if storedPackages.isEmpty {
                        Text("No stored packages yet. Build one with New Package, or import an existing .deploy / .zip / folder package to edit it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    ForEach(Array(storedPackages.enumerated()), id: \.element.id) { index, stored in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 14)
                        }
                        storedPackageRow(stored)
                    }

                    Divider()
                        .padding(.leading, 14)

                    Button {
                        newPackageTapped()
                    } label: {
                        Label("New Package", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }

                    Divider()
                        .padding(.leading, 14)

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Package…", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
            }

            if let storeError {
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Something went wrong", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(storeError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: deployPackageContentTypes()) { result in
            switch result {
            case .success(let url):
                switch DeployManager.importIntoStore(from: url) {
                case .success(let stored):
                    storedPackages = DeployManager.loadStoredPackages()
                    editorSession = DeployEditorSession(package: stored, isNew: false)
                case .failure(let error):
                    onImportError(error.message)
                }
            case .failure(let error):
                onImportError(error.localizedDescription)
            }
        }
        .onAppear {
            storedPackages = DeployManager.loadStoredPackages()
        }
        .sheet(item: $editorSession, onDismiss: {
            storedPackages = DeployManager.loadStoredPackages()
        }) { session in
            DeployBuilderView(appDataManager: appDataManager, session: session)
        }
        .sheet(item: $exportItem) { item in
            DeployShareSheet(items: [item.url])
        }
        .confirmationDialog(
            "Delete Package",
            isPresented: Binding(
                get: { packageToDelete != nil },
                set: { if !$0 { packageToDelete = nil } }
            ),
            presenting: packageToDelete
        ) { stored in
            Button("Delete \"\(stored.displayName)\"", role: .destructive) {
                if DeployManager.deleteStoredPackage(stored) {
                    storedPackages = DeployManager.loadStoredPackages()
                }
                packageToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                packageToDelete = nil
            }
        } message: { _ in
            Text("The stored package is removed. Files it already deployed, and its Deploy History receipts, are not touched.")
        }
    }

    private func storedPackageRow(_ stored: StoredDeployPackage) -> some View {
        HStack(spacing: 10) {
            Button {
                editorSession = DeployEditorSession(package: stored, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stored.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(stored.bundleID) • \(stored.scope) • \(stored.files.count) file\(stored.files.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    editorSession = DeployEditorSession(package: stored, isNew: false)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    deployStoredPackage(stored)
                } label: {
                    Label("Deploy", systemImage: "shippingbox")
                }
                Button {
                    exportStoredPackage(stored)
                } label: {
                    Label("Export ZIP", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    packageToDelete = stored
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func newPackageTapped() {
        if let draft = DeployManager.makeNewStoredPackage() {
            editorSession = DeployEditorSession(package: draft, isNew: true)
        } else {
            storeError = "The package store is unavailable (the App Group container did not resolve)."
        }
    }

    /// Deploy a stored package by feeding its folder through
    /// the regular loader into the host's preview flow — no
    /// second deploy path.
    private func deployStoredPackage(_ stored: StoredDeployPackage) {
        switch DeployManager.loadPackage(from: stored.folderURL) {
        case .success(let loaded):
            storeError = nil
            onDeploy(loaded)
        case .failure(let error):
            storeError = error.message
        }
    }

    private func exportStoredPackage(_ stored: StoredDeployPackage) {
        if let url = DeployManager.exportZipURL(for: stored) {
            storeError = nil
            exportItem = DeployExportItem(url: url)
        } else {
            storeError = "The package could not be exported."
        }
    }
}

// MARK: - Deploy preview (manifest / files / target / result)
//
// The preview every loaded package lands in: its manifest,
// its files, target resolution and the Deploy button, then
// the run's result lines. Hosted by the Deploy page and by
// the Package Builder page; the package itself is the
// host's state, so both pages drive the one preview.

struct DeployPreviewSection: View {
    @ObservedObject var appDataManager: AppDataManager
    @Binding var package: LoadedDeployPackage?
    @ObservedObject var deployManager: DeployManager
    /// Bumped by the host whenever a package is presented,
    /// so the target resolves itself — v5: no location
    /// picking, the manifest names the target and the
    /// destinations.
    @Binding var resolveRequest: UUID

    @State private var wantsResolve = false

    private var isResolving: Bool {
        deployManager.isResolving || (wantsResolve && appDataManager.isScanning)
    }

    /// Identity of the presented package, for change
    /// detection: presenting a different package cancels a
    /// resolve that was still waiting on the container scan.
    private var packageKey: String? {
        package.map { "\($0.bundleID)|\($0.scope)|\($0.files.count)|\($0.name ?? "")" }
    }

    var body: some View {
        Group {
            if let package {
                WTSectionCard(header: "Manifest") {
                    VStack(alignment: .leading, spacing: 0) {
                        if let name = package.name {
                            LabeledContent("Name", value: name)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                            Divider()
                                .padding(.leading, 14)
                        }
                        LabeledContent("Bundle ID", value: package.bundleID)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        Divider()
                            .padding(.leading, 14)
                        LabeledContent("Scope", value: package.scope)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                }

                WTSectionCard(header: "Files (\(package.files.count))") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(package.files.enumerated()), id: \.element.relativePath) { index, file in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.relativePath)
                                    .font(.subheadline)
                                Text("\(wtFormatSize(Int64(file.data.count))) — from \(file.source)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }
                }

                WTSectionCard(header: "Target", footer: "Before anything is written, every file that already exists is backed up (see Deploy History). Existing files are then replaced in place; new files are created.") {
                    VStack(alignment: .leading, spacing: 0) {
                        if isResolving {
                            HStack(spacing: 10) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Resolving the target container…")
                                        .font(.subheadline)
                                    Text(package.scope == "Application" ? appDataManager.scanPhase : "Enumerating containers with pathleak — this can take a while.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        } else if let resolved = deployManager.resolvedContainerPath {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Target container")
                                    .font(.subheadline.weight(.semibold))
                                Text(resolved)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)

                            Divider()
                                .padding(.leading, 14)

                            Button {
                                deployManager.deploy(package: package)
                            } label: {
                                Group {
                                    if deployManager.isDeploying {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                            Text("Applying…")
                                        }
                                    } else {
                                        Text("Apply")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .disabled(deployManager.isDeploying)
                        } else {
                            Button {
                                autoResolve()
                            } label: {
                                Text("Resolve Target")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                            }
                            if let resolveError = deployManager.resolveError {
                                Text(resolveError)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                }
            }

            if let result = deployManager.lastResult {
                WTSectionCard(header: "Result — \(result.succeeded) succeeded, \(result.failed) failed", footer: result.receiptFolderName.map { "Backup and receipt saved under DeployBackups/\($0) — restore it any time from Deploy History." }) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(result.lines.enumerated()), id: \.element.id) { index, line in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            resultLineRow(line)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onChange(of: packageKey) { _, _ in
            wantsResolve = false
        }
        .onChange(of: resolveRequest) { _, _ in
            autoResolve()
        }
        .onChange(of: appDataManager.didScan) { _, done in
            if done, wantsResolve, let package, package.scope == "Application" {
                wantsResolve = false
                deployManager.resolveTarget(package: package, containers: appDataManager.containers)
            }
        }
    }

    /// One line of a deploy/restore result: a status icon and
    /// the file path + outcome message.
    private func resultLineRow(_ line: DeployRunLine) -> some View {
        HStack(spacing: 8) {
            Image(systemName: line.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(line.ok ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                if !line.path.isEmpty {
                    Text(line.path)
                        .font(.subheadline)
                }
                Text(line.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// Resolve the presented package's target by itself:
    /// the manifest names the target, the destinations come
    /// from the zip — v5 has no location picking. The
    /// Application scope waits for the App Data scan when
    /// it has not run yet.
    private func autoResolve() {
        guard let package else { return }
        if package.scope == "Application", appDataManager.containers.isEmpty, !appDataManager.didScan {
            // The Application scope resolves against the App
            // Data scan — run it first, resolve when it lands.
            wantsResolve = true
            if !appDataManager.isScanning {
                appDataManager.rescan()
            }
            return
        }
        deployManager.resolveTarget(package: package, containers: appDataManager.containers)
    }
}

// MARK: - Deploy History page
//
// One entry per deploy, read from the receipts in the backup
// store (newest first). Restore writes each backup back in
// place under a fresh grant; files the deploy created are
// deleted again.

struct DeployHistoryView: View {
    @ObservedObject var appDataManager: AppDataManager
    @StateObject private var deployManager = DeployManager()
    @State private var entries: [DeployHistoryEntry] = []
    @State private var restoringID: String?

    var body: some View {
        WTGlassPage {
            if let result = deployManager.restoreResult {
                WTSectionCard(header: "Restore Result — \(result.succeeded) succeeded, \(result.failed) failed") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(result.lines.enumerated()), id: \.element.id) { index, line in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            HStack(spacing: 8) {
                                Image(systemName: line.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(line.ok ? .green : .red)
                                VStack(alignment: .leading, spacing: 2) {
                                    if !line.path.isEmpty {
                                        Text(line.path)
                                            .font(.subheadline)
                                    }
                                    Text(line.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if entries.isEmpty {
                WTSectionCard {
                    Text("No deploys yet. When a package is deployed, the files it replaced are backed up here with a receipt, ready to restore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            } else {
                WTSectionCard(header: "Deploys", footer: "Restoring writes each backed-up file back in place. Files the deploy created (they did not exist before) are deleted again.") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.receipt.name ?? entry.receipt.bundleID)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(entry.receipt.bundleID) • \(entry.receipt.scope) • \( Self.displayDate(entry.receipt)) • \(entry.receipt.files.count) file\(entry.receipt.files.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    restoringID = entry.id
                                    deployManager.restore(entry: entry, containers: appDataManager.containers)
                                } label: {
                                    if deployManager.isRestoring && restoringID == entry.id {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                            Text("Restoring…")
                                        }
                                    } else {
                                        Text("Restore")
                                    }
                                }
                                .disabled(deployManager.isRestoring)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
        .navigationTitle("Deploy History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    entries = DeployManager.loadHistory()
                }
            }
        }
        .onAppear {
            entries = DeployManager.loadHistory()
        }
    }

    private static func displayDate(_ receipt: DeployReceipt) -> String {
        if let date = ISO8601DateFormatter().date(from: receipt.timestamp) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return receipt.timestamp
    }
}
