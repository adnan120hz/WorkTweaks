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
    @EnvironmentObject private var wtLang: WTLangStore
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

            WTSectionCard(header: wtLang.tr("Deploy Package")) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(wtLang.tr("A Deploy package replaces files inside exactly one app — the app named by its bundle ID. It cannot touch any other app: every target path is relative to that app's container, and packages with absolute or \"..\" paths are rejected whole."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                    Divider()
                        .padding(.leading, 14)

                    Button {
                        showImporter = true
                    } label: {
                        Label(package == nil ? wtLang.tr("Choose Package…") : wtLang.tr("Choose a Different Package…"), systemImage: "shippingbox")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
            }

            if let importError {
                WTSectionCard(footer: wtLang.tr("Nothing was written.")) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(wtLang.tr("This package was rejected"), systemImage: "exclamationmark.triangle.fill")
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

            WTSectionCard(header: wtLang.tr("Package Format")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(wtLang.tr("A package is ONE .zip file containing a manifest.json at its top level plus the payload files it names. The Package Builder exports that zip (save it in Files); Deploy imports it, resolves the target itself from the manifest, and applies it — no location picking, the destinations come from the zip."))
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
                    Text(wtLang.tr("Single-file shorthand: instead of \"files\", give \"relativePath\" and \"file\". \"scope\" is Application (bundleID = the app's bundle ID), AppGroup (bundleID = the group identifier, e.g. group.com.example) or InternalDaemon. ZIP archives may use stored or deflated entries; encrypted and ZIP64 archives are not supported. Older .deploy archives and plain folders still import."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        // Package preview and rejection card animate in/out
        // instead of snapping (v8.0 menu motion).
        .animation(.wtMenu, value: package != nil)
        .animation(.wtMenu, value: importError != nil)
        .navigationTitle(wtLang.tr("Deploy"))
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
    @EnvironmentObject private var wtLang: WTLangStore
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
            WTSectionCard(header: wtLang.tr("My Packages"), footer: wtLang.tr("Packages you build or import are stored on this device, in WorkTweaks' own container. Tap a package to edit it. Deploy runs it through the same preview, resolve and backup flow as a picked package.")) {
                VStack(alignment: .leading, spacing: 0) {
                    if storedPackages.isEmpty {
                        Text(wtLang.tr("No stored packages yet. Build one with New Package, or import an existing .deploy / .zip / folder package to edit it here."))
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
                        Label(wtLang.tr("New Package"), systemImage: "plus")
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
                        Label(wtLang.tr("Import Package…"), systemImage: "square.and.arrow.down")
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
                        Label(wtLang.tr("Something went wrong"), systemImage: "exclamationmark.triangle.fill")
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
            wtLang.tr("Delete Package"),
            isPresented: Binding(
                get: { packageToDelete != nil },
                set: { if !$0 { packageToDelete = nil } }
            ),
            presenting: packageToDelete
        ) { stored in
            Button(wtLang.tr("Delete \"%@\"", stored.displayName), role: .destructive) {
                if DeployManager.deleteStoredPackage(stored) {
                    storedPackages = DeployManager.loadStoredPackages()
                }
                packageToDelete = nil
            }
            Button(wtLang.tr("Cancel"), role: .cancel) {
                packageToDelete = nil
            }
        } message: { _ in
            Text(wtLang.tr("The stored package is removed. Files it already deployed, and its Deploy History receipts, are not touched."))
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
                    Text(wtLang.tr(stored.files.count == 1 ? "%@ • %@ • %d file" : "%@ • %@ • %d files", stored.bundleID, stored.scope, stored.files.count))
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
                    Label(wtLang.tr("Edit"), systemImage: "pencil")
                }
                Button {
                    deployStoredPackage(stored)
                } label: {
                    Label(wtLang.tr("Deploy"), systemImage: "shippingbox")
                }
                Button {
                    exportStoredPackage(stored)
                } label: {
                    Label(wtLang.tr("Export ZIP"), systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    packageToDelete = stored
                } label: {
                    Label(wtLang.tr("Delete"), systemImage: "trash")
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
            storeError = wtLang.tr("The package store is unavailable (the App Group container did not resolve).")
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
            storeError = wtLang.tr("The package could not be exported.")
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
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var appDataManager: AppDataManager
    @Binding var package: LoadedDeployPackage?
    @ObservedObject var deployManager: DeployManager
    /// Bumped by the host whenever a package is presented,
    /// so the target resolves itself — v5: no location
    /// picking, the manifest names the target and the
    /// destinations.
    @Binding var resolveRequest: UUID

    @State private var wantsResolve = false

    /// The chosen deploy method. Defaults to Normal when it is
    /// available on this device, otherwise Airlift.
    @State private var method: DeployMethod = DeployMethod.defaultMethod
    /// Pairing + VPN status, for the Airlift transport gate.
    @State private var transportStatus = TransportGate.check()

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
                // MARK: Deploy method (v8.0)
                //
                // Exactly two options, each with its supported
                // iOS range and gated to that range. Normal is
                // the existing worse_query flow; Airlift runs
                // the same package flow through the Airlift
                // exploit over the pairing + VPN tunnel.
                WTSectionCard(header: wtLang.tr("Deploy Method")) {
                    VStack(alignment: .leading, spacing: 0) {
                        methodRow(.normal)
                        Divider()
                            .padding(.leading, 14)
                        methodRow(.airlift)
                    }
                }

                if method == .airlift {
                    if !transportStatus.isReady {
                        TransportGateCard(status: transportStatus) {
                            SoundEffects.playTap()
                            transportStatus = TransportGate.check()
                        }
                    }
                    WTSectionCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(wtLang.tr("Airlift cannot back up files it replaces on iOS 17/18 — the exploit writes but cannot read them back. On iOS 26/27 a backup is made first when the container can be read. Files replaced without a backup cannot be restored from Deploy History."))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(wtLang.tr("Files in subfolders are staged with their folders. Only flat (top-level) payloads are proven over Airlift so far."))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(wtLang.tr("AppGroup and InternalDaemon targets resolve from the local container scan; on iOS 17/18 only Application targets can be found over the tunnel."))
                                .fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(SupportInfo.airliftIOS17Releases) { rel in
                                        HStack(spacing: 8) {
                                            Text(rel.version)
                                            Spacer()
                                            Text(rel.build)
                                                .font(.system(.caption, design: .monospaced))
                                        }
                                    }
                                }
                                .padding(.top, 6)
                                Text(wtLang.tr("iOS 18, 26 and 27 follow the SupportInfo table (iOS 27 up to 27.2 beta 2)."))
                                    .padding(.top, 6)
                                    .fixedSize(horizontal: false, vertical: true)
                            } label: {
                                Text(wtLang.tr("Airlift — supported iOS 17 versions"))
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }

                WTSectionCard(header: wtLang.tr("Manifest")) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let name = package.name {
                            LabeledContent(wtLang.tr("Name"), value: name)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                            Divider()
                                .padding(.leading, 14)
                        }
                        LabeledContent(wtLang.tr("Bundle ID"), value: package.bundleID)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        Divider()
                            .padding(.leading, 14)
                        LabeledContent(wtLang.tr("Scope"), value: package.scope)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                }

                WTSectionCard(header: wtLang.tr("Files (%d)", package.files.count)) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(package.files.enumerated()), id: \.element.relativePath) { index, file in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.relativePath)
                                    .font(.subheadline)
                                Text(wtLang.tr("%@ — from %@", wtFormatSize(Int64(file.data.count)), file.source))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }
                }

                WTSectionCard(header: wtLang.tr("Target"), footer: method == .airlift
                    ? wtLang.tr("Files are written through the Airlift exploit. A backup is made first only when the container can be read (iOS 26/27).")
                    : wtLang.tr("Before anything is written, every file that already exists is backed up (see Deploy History). Existing files are then replaced in place; new files are created.")) {
                    VStack(alignment: .leading, spacing: 0) {
                        if isResolving {
                            HStack(spacing: 10) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(wtLang.tr("Resolving the target container…"))
                                        .font(.subheadline)
                                    Text(package.scope == "Application" ? appDataManager.scanPhase : wtLang.tr("Enumerating containers with pathleak — this can take a while."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        } else if let resolved = deployManager.resolvedContainerPath {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(wtLang.tr("Target container"))
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
                                SoundEffects.playTap()
                                if method == .airlift {
                                    deployManager.deployViaAirlift(package: package)
                                } else {
                                    deployManager.deploy(package: package)
                                }
                            } label: {
                                Group {
                                    if deployManager.isDeploying {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                            Text(wtLang.tr(method == .airlift ? "Deploying via Airlift…" : "Applying…"))
                                        }
                                    } else {
                                        Text(wtLang.tr("Apply"))
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .disabled(deployManager.isDeploying || !methodAvailable || (method == .airlift && !transportStatus.isReady))
                        } else {
                            Button {
                                autoResolve()
                            } label: {
                                Text(wtLang.tr("Resolve Target"))
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
                WTSectionCard(header: wtLang.tr("Result — %d succeeded, %d failed", result.succeeded, result.failed), footer: resultFooter(result)) {
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
            transportStatus = TransportGate.check()
        }
        .onChange(of: method) { _, _ in
            // The target resolves differently per method
            // (Airlift can fall back to the tunnel lookup),
            // so switching methods re-resolves from scratch.
            deployManager.resolvedContainerPath = nil
            deployManager.resolveError = nil
            deployManager.lastResult = nil
            autoResolve()
        }
        .onChange(of: resolveRequest) { _, _ in
            autoResolve()
        }
        .onChange(of: appDataManager.didScan) { _, done in
            if done, wantsResolve, let package, package.scope == "Application" {
                wantsResolve = false
                deployManager.resolveTarget(package: package, containers: appDataManager.containers, viaAirlift: method == .airlift)
            }
        }
    }

    /// Whether the currently selected method is offered on
    /// this device. The Apply button stays disabled otherwise.
    private var methodAvailable: Bool {
        method == .normal ? SupportInfo.normalDeployAvailable : SupportInfo.airliftDeployAvailable
    }

    /// One Deploy Method option row: title, supported iOS
    /// range, what it does, and — when the gate closes it —
    /// the honest reason, in orange. Unavailable options
    /// cannot be selected.
    private func methodRow(_ option: DeployMethod) -> some View {
        let gate = option == .normal ? SupportInfo.normalDeployGate : SupportInfo.airliftDeployGate
        let available = gate == .available
        let selected = method == option
        return Button {
            guard available else { return }
            SoundEffects.playTap()
            method = option
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .font(.title3)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(wtLang.tr(option == .normal ? "Normal Deploy" : "Deploy via Airlift"))
                            .font(.subheadline.weight(.semibold))
                        if !available {
                            Text(wtLang.tr("Not available on this iOS version"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(option == .normal ? "iOS 26.0 – iOS 27.3 beta 1" : "iOS 17 / 18 / 26 / 27 · iOS 27 up to 27.2 beta 2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(wtLang.tr(option == .normal
                        ? "Uses the sandbox escape (worse_query) to write files directly. No pairing file or VPN needed."
                        : "Writes the package through the Airlift exploit over the pairing + VPN tunnel. The transport below must be ready first."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !available {
                        Text(gateReason(option, gate))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .opacity(available ? 1 : 0.75)
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    /// The user-facing reason a Deploy method is gated off on
    /// this device.
    private func gateReason(_ option: DeployMethod, _ gate: SupportInfo.DeployGate) -> String {
        switch gate {
        case .available:
            return ""
        case .belowMinimum:
            return option == .normal
                ? wtLang.tr("Requires iOS 26.0 or later.")
                : wtLang.tr("Requires iOS 17 or later.")
        case .aboveMaximum:
            return option == .normal
                ? wtLang.tr("Blocked above iOS 27.3 beta 1 — worse_query is patched in iOS 27.3 beta 2.")
                : wtLang.tr("Blocked above iOS 27.2 beta 2.")
        case .unknownBuild:
            return wtLang.tr("Could not read this iPhone's iOS build number.")
        }
    }

    /// The result card footer: where the backup/receipt went,
    /// plus any honest Airlift caveats (translated from the
    /// result's note keys). When no backup was made, the folder
    /// holds only the receipt — the footer says so instead of
    /// promising a restore.
    private func resultFooter(_ result: DeployRunResult) -> String? {
        var parts: [String] = []
        if let folder = result.receiptFolderName {
            if result.noteKeys.contains("No backup was made — the target container could not be read, so files this deploy replaced cannot be restored from Deploy History.") {
                parts.append(wtLang.tr("Receipt saved under DeployBackups/%@ — no backup was made, so this deploy cannot be restored.", folder))
            } else {
                parts.append(wtLang.tr("Backup and receipt saved under DeployBackups/%@ — restore it any time from Deploy History.", folder))
            }
        }
        parts.append(contentsOf: result.noteKeys.map { wtLang.tr($0) })
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
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
        deployManager.resolveTarget(package: package, containers: appDataManager.containers, viaAirlift: method == .airlift)
    }
}

// MARK: - Deploy History page
//
// One entry per deploy, read from the receipts in the backup
// store (newest first). Restore writes each backup back in
// place under a fresh grant; files the deploy created are
// deleted again.

struct DeployHistoryView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var appDataManager: AppDataManager
    @StateObject private var deployManager = DeployManager()
    @State private var entries: [DeployHistoryEntry] = []
    @State private var restoringID: String?

    var body: some View {
        WTGlassPage {
            if let result = deployManager.restoreResult {
                WTSectionCard(header: wtLang.tr("Restore Result — %d succeeded, %d failed", result.succeeded, result.failed)) {
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
                    Text(wtLang.tr("No deploys yet. When a package is deployed, the files it replaced are backed up here with a receipt, ready to restore."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            } else {
                WTSectionCard(header: wtLang.tr("Deploys"), footer: wtLang.tr("Restoring writes each backed-up file back in place. Files the deploy created (they did not exist before) are deleted again.")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.receipt.name ?? entry.receipt.bundleID)
                                    .font(.subheadline.weight(.semibold))
                                Text(wtLang.tr(entry.receipt.files.count == 1 ? "%@ • %@ • %@ • %d file" : "%@ • %@ • %@ • %d files", entry.receipt.bundleID, entry.receipt.scope, Self.displayDate(entry.receipt), entry.receipt.files.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    restoringID = entry.id
                                    deployManager.restore(entry: entry, containers: appDataManager.containers)
                                } label: {
                                    if deployManager.isRestoring && restoringID == entry.id {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                            Text(wtLang.tr("Restoring…"))
                                        }
                                    } else {
                                        Text(wtLang.tr("Restore"))
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
        .navigationTitle(wtLang.tr("Deploy History"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(wtLang.tr("Refresh")) {
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
