import SwiftUI
import UniformTypeIdentifiers

// MARK: - Deploy page
//
// Import a Deploy package (a folder, or a .zip / .deploy
// archive), check its manifest, resolve its one target app,
// preview exactly what will happen, and deploy. The package
// format and the safety rules are documented on this page
// itself, under "Package Format".
//
// Since v3.8 the page renders as Liquid Glass cards
// (WTGlassPage/WTSectionCard), like every other page —
// presentation only; the deploy flow is unchanged.

struct DeployView: View {
    @ObservedObject var appDataManager: AppDataManager
    @StateObject private var deployManager = DeployManager()

    @State private var package: LoadedDeployPackage?
    @State private var importError: String?
    @State private var showImporter = false
    @State private var wantsResolve = false

    private var packageContentTypes: [UTType] {
        var types: [UTType] = [.folder, .zip]
        if let deployType = UTType(filenameExtension: "deploy", conformingTo: .data) {
            types.append(deployType)
        }
        return types
    }

    private var isResolving: Bool {
        deployManager.isResolving || (wantsResolve && appDataManager.isScanning)
    }

    var body: some View {
        WTGlassPage {
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
                                            Text("Deploying…")
                                        }
                                    } else {
                                        Text("Deploy")
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
                                resolveTapped()
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

            WTSectionCard(header: "Package Format") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A package is a folder, or a .zip / .deploy archive, containing a manifest.json at its top level plus the payload files it names:")
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
                    Text("Single-file shorthand: instead of \"files\", give \"relativePath\" and \"file\". \"scope\" is Application (bundleID = the app's bundle ID), AppGroup (bundleID = the group identifier, e.g. group.com.example) or InternalDaemon. ZIP archives may use stored or deflated entries; encrypted and ZIP64 archives are not supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle("Deploy")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: packageContentTypes) { result in
            switch result {
            case .success(let url):
                switch DeployManager.loadPackage(from: url) {
                case .success(let loaded):
                    package = loaded
                    importError = nil
                    wantsResolve = false
                    deployManager.resolvedContainerPath = nil
                    deployManager.resolveError = nil
                    deployManager.lastResult = nil
                case .failure(let error):
                    package = nil
                    importError = error.message
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
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

    private func resolveTapped() {
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
