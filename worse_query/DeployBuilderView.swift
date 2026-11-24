import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Deploy package builder
//
// Create and edit Deploy packages inside the app. A package
// being edited is a StoredDeployPackage: a folder in
// DeployPackages/ (see DeployManager's package store)
// holding payload files plus, once saved, a manifest.json.
//
// v5: the builder's product is ONE .zip file — Export ZIP
// shares manifest.json plus payloads as a single zip the
// user saves (in Files); Deploy imports that zip and
// applies it without location picking. Add File unpacks
// .zip archives (each file inside becomes a payload) and
// accepts .plist files as payloads.
//
// Payload files are copied into the package folder the
// moment they are added, and removed from it the moment
// their entry is removed — those two actions only ever
// touch the package's own folder. The descriptive fields
// (name, scope, bundle ID, destination paths) live in this
// view until Save, which runs DeployManager's own loader
// validation over the whole draft and writes the manifest
// only when the package would be accepted as an import.
//
// Cancelling a brand-new package deletes its draft folder,
// so a half-made package never lingers in the store.

struct DeployEditorSession: Identifiable {
    let package: StoredDeployPackage
    let isNew: Bool
    var id: String { package.id }
}

struct DeployBuilderView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var appDataManager: AppDataManager
    let session: DeployEditorSession

    @Environment(\.dismiss) private var dismiss

    @State private var nameText: String
    @State private var scope: String
    @State private var bundleIDText: String
    @State private var files: [StoredDeployPackageFile]

    @State private var showFilePicker = false
    @State private var showContainerPicker = false
    @State private var saveError: String?
    @State private var addError: String?
    @State private var exportItem: BuilderExportItem?

    private struct BuilderExportItem: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    init(appDataManager: AppDataManager, session: DeployEditorSession) {
        _appDataManager = ObservedObject(wrappedValue: appDataManager)
        self.session = session
        _nameText = State(initialValue: session.package.name ?? "")
        _scope = State(initialValue: session.package.scope)
        _bundleIDText = State(initialValue: session.package.bundleID)
        _files = State(initialValue: session.package.files)
    }

    // MARK: Validation (same rules as the loader)

    private var bundleIDProblem: String? {
        let trimmed = bundleIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return wtLang.tr("A bundle ID is required — it names the one app this package may touch.")
        }
        if trimmed.contains("/") || trimmed.contains("..") {
            return wtLang.tr("The bundle ID is not a valid identifier.")
        }
        return nil
    }

    private func pathProblem(_ file: StoredDeployPackageFile) -> String? {
        DeployManager.cleanRelativePath(file.destinationPath) == nil
            ? wtLang.tr("Paths must be relative, non-empty and contain no \"..\" component.")
            : nil
    }

    private var saveProblem: String? {
        if let bundleIDProblem { return bundleIDProblem }
        if files.isEmpty {
            return wtLang.tr("Add at least one file — a package with no files deploys nothing.")
        }
        if files.contains(where: { pathProblem($0) != nil }) {
            return wtLang.tr("One of the destination paths is invalid.")
        }
        return nil
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            WTGlassPage {
                WTSectionCard(header: wtLang.tr("Package")) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text(wtLang.tr("Name"))
                                .font(.subheadline)
                            Spacer()
                            TextField(wtLang.tr("Optional label"), text: $nameText)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)

                        Divider()
                            .padding(.leading, 14)

                        HStack(spacing: 8) {
                            Text(wtLang.tr("Scope"))
                                .font(.subheadline)
                            Spacer()
                            Picker(wtLang.tr("Scope"), selection: $scope) {
                                ForEach(DeployManager.scopes, id: \.self) { scopeOption in
                                    Text(scopeOption).tag(scopeOption)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }

                WTSectionCard(
                    header: wtLang.tr("Target"),
                    footer: scope == "AppGroup"
                        ? wtLang.tr("For AppGroup scope, the target is the App Group identifier (for example group.com.example) — type it here.")
                        : wtLang.tr("The bundle ID of the one app this package may touch. Pick it from the App Data container scan, or type it.")
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text(wtLang.tr("Bundle ID"))
                                .font(.subheadline)
                            Spacer()
                            TextField("com.example.app", text: $bundleIDText)
                                .multilineTextAlignment(.trailing)
                                .font(.system(.subheadline, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)

                        if let bundleIDProblem {
                            Text(bundleIDProblem)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 9)
                        }

                        Divider()
                            .padding(.leading, 14)

                        Button {
                            showContainerPicker = true
                        } label: {
                            Label(wtLang.tr("Pick from App Data scan…"), systemImage: "list.bullet.rectangle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                    }
                }

                WTSectionCard(
                    header: wtLang.tr("Files (%d)", files.count),
                    footer: wtLang.tr("Payload files are copied into the package. Add File accepts any file — a .plist is added as a payload, and a .zip is unpacked, each file inside becoming a payload with its destination defaulting to its path inside the archive. Destinations are relative paths only; absolute paths and \"..\" are rejected, exactly like an imported package.")
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        if files.isEmpty {
                            Text(wtLang.tr("No files yet."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            fileRow(index: index, file: file)
                        }
                        if !files.isEmpty {
                            Divider()
                                .padding(.leading, 14)
                        }
                        Button {
                            showFilePicker = true
                        } label: {
                            Label(wtLang.tr("Add File…"), systemImage: "plus")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                        if let addError {
                            Text(addError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                        }
                    }
                }

                if let saveError {
                    WTSectionCard(footer: wtLang.tr("Nothing was written — the stored manifest is unchanged.")) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(wtLang.tr("This package was rejected"), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(saveError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                } else if let saveProblem {
                    WTSectionCard {
                        Text(saveProblem)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }

                WTSectionCard(
                    header: wtLang.tr("Export"),
                    footer: wtLang.tr("Saves the package, then shares ONE .zip file — save it in Files. Deploy imports that zip and applies it without asking for locations.")
                ) {
                    Button {
                        exportZIP()
                    } label: {
                        Label(wtLang.tr("Export ZIP"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle(session.isNew ? wtLang.tr("New Package") : wtLang.tr("Edit Package"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(wtLang.tr("Cancel")) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(wtLang.tr("Save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(saveProblem != nil)
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    let taken = Set(files.map(\.payloadName))
                    if url.pathExtension.lowercased() == "zip" {
                        // A .zip is unpacked: each file inside
                        // becomes a payload, its destination
                        // defaulting to its path in the archive.
                        switch DeployManager.addZipPayloads(to: session.package.folderURL, from: url, takenNames: taken) {
                        case .success(let rows):
                            for row in rows {
                                files.append(StoredDeployPackageFile(
                                    payloadName: row.name,
                                    destinationPath: row.destination,
                                    size: row.size
                                ))
                            }
                            addError = nil
                        case .failure(let error):
                            addError = error.message
                        }
                    } else if let added = DeployManager.addPayload(to: session.package.folderURL, from: url, takenNames: taken) {
                        // The destination defaults to the
                        // payload's name — the picked file's
                        // name, unless it had to be made
                        // unique inside the package. A .plist
                        // is added as a payload file, like any
                        // other file.
                        files.append(StoredDeployPackageFile(
                            payloadName: added.name,
                            destinationPath: added.name,
                            size: added.size
                        ))
                        addError = nil
                    } else {
                        addError = wtLang.tr("The picked file could not be copied into the package.")
                    }
                case .failure(let error):
                    addError = error.localizedDescription
                }
            }
            .sheet(item: $exportItem) { item in
                DeployShareSheet(items: [item.url])
            }
            .sheet(isPresented: $showContainerPicker) {
                DeployContainerPickerView(appDataManager: appDataManager) { picked in
                    bundleIDText = picked
                }
            }
        }
    }

    private func fileRow(index: Int, file: StoredDeployPackageFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.payloadName)
                        .font(.subheadline.weight(.semibold))
                    Text(wtFormatSize(Int64(file.size)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    removeFile(file)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(wtLang.tr("Destination path"), text: $files[index].destinationPath)
                    .font(.system(.subheadline, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            if let problem = pathProblem(file) {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func removeFile(_ file: StoredDeployPackageFile) {
        DeployManager.removePayload(from: session.package.folderURL, payloadName: file.payloadName)
        files.removeAll { $0.id == file.id }
    }

    private func save() {
        var draft = session.package
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.name = trimmedName.isEmpty ? nil : trimmedName
        draft.scope = scope
        draft.bundleID = bundleIDText
        draft.files = files
        switch DeployManager.saveStoredPackage(draft) {
        case .success:
            dismiss()
        case .failure(let error):
            saveError = error.message
        }
    }

    /// Save the draft, then share it as ONE .zip file —
    /// the v5 artifact the user saves (in Files) and
    /// Deploy imports.
    private func exportZIP() {
        var draft = session.package
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.name = trimmedName.isEmpty ? nil : trimmedName
        draft.scope = scope
        draft.bundleID = bundleIDText
        draft.files = files
        switch DeployManager.saveStoredPackage(draft) {
        case .failure(let error):
            saveError = error.message
        case .success(let saved):
            saveError = nil
            if let url = DeployManager.exportZipURL(for: saved) {
                exportItem = BuilderExportItem(url: url)
            } else {
                saveError = wtLang.tr("The package could not be exported.")
            }
        }
    }

    private func cancel() {
        // A cancelled new package deletes its draft folder —
        // payloads copied in while building are removed with
        // it, so nothing half-made stays in the store.
        if session.isNew {
            DeployManager.deleteStoredPackage(session.package)
        }
        dismiss()
    }
}

// MARK: - Container picker (bundle ID from the App Data scan)

struct DeployContainerPickerView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var appDataManager: AppDataManager
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WTGlassPage {
                if appDataManager.isScanning {
                    WTSectionCard {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(appDataManager.scanPhase)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                } else if appDataManager.containers.isEmpty {
                    WTSectionCard {
                        Text(appDataManager.didScan
                             ? wtLang.tr("The container scan found no containers.")
                             : wtLang.tr("No scan yet. The scan starts automatically; if it does not, open App Data once, or type the bundle ID by hand."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                } else {
                    WTSectionCard(
                        header: wtLang.tr("Containers (%d)", appDataManager.containers.count),
                        footer: wtLang.tr("Identifiers from the App Data container scan — the same list Deploy resolves Application targets against.")
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(appDataManager.containers.enumerated()), id: \.element.id) { index, container in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                                Button {
                                    onPick(container.bundleID)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(container.bundleID)
                                            .font(.subheadline)
                                        if container.bundleID != container.directoryName {
                                            Text(container.directoryName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(wtLang.tr("Pick Target App"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(wtLang.tr("Cancel")) { dismiss() }
                }
            }
            .onAppear {
                appDataManager.scanIfNeeded()
            }
        }
    }
}

// MARK: - Package Builder page
//
// The App Data ••• menu's direct entry to the package
// store — the menu item is named "Package Builder", so
// this page is too. It hosts the same DeployStoreSection
// as the Deploy page (one store, one builder) plus the
// shared DeployPreviewSection, so a stored package can be
// deployed from here without detouring through the Deploy
// page.

struct PackageBuilderView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var appDataManager: AppDataManager
    @StateObject private var deployManager = DeployManager()

    @State private var package: LoadedDeployPackage?
    @State private var importError: String?
    @State private var resolveRequest = UUID()

    var body: some View {
        WTGlassPage {
            DeployStoreSection(
                appDataManager: appDataManager,
                onDeploy: { presentLoadedPackage($0) },
                onImportError: { importError = $0 }
            )

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
        }
        .navigationTitle(wtLang.tr("Package Builder"))
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Share sheet (package export)

struct DeployShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
