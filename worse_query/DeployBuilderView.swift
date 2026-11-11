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
            return "A bundle ID is required — it names the one app this package may touch."
        }
        if trimmed.contains("/") || trimmed.contains("..") {
            return "The bundle ID is not a valid identifier."
        }
        return nil
    }

    private func pathProblem(_ file: StoredDeployPackageFile) -> String? {
        DeployManager.cleanRelativePath(file.destinationPath) == nil
            ? "Paths must be relative, non-empty and contain no \"..\" component."
            : nil
    }

    private var saveProblem: String? {
        if let bundleIDProblem { return bundleIDProblem }
        if files.isEmpty {
            return "Add at least one file — a package with no files deploys nothing."
        }
        if files.contains(where: { pathProblem($0) != nil }) {
            return "One of the destination paths is invalid."
        }
        return nil
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            WTGlassPage {
                WTSectionCard(header: "Package") {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text("Name")
                                .font(.subheadline)
                            Spacer()
                            TextField("Optional label", text: $nameText)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)

                        Divider()
                            .padding(.leading, 14)

                        HStack(spacing: 8) {
                            Text("Scope")
                                .font(.subheadline)
                            Spacer()
                            Picker("Scope", selection: $scope) {
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
                    header: "Target",
                    footer: scope == "AppGroup"
                        ? "For AppGroup scope, the target is the App Group identifier (for example group.com.example) — type it here."
                        : "The bundle ID of the one app this package may touch. Pick it from the App Data container scan, or type it."
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text("Bundle ID")
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
                            Label("Pick from App Data scan…", systemImage: "list.bullet.rectangle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                    }
                }

                WTSectionCard(
                    header: "Files (\(files.count))",
                    footer: "Payload files are copied into the package. The destination is where each file lands inside the target container — relative paths only; absolute paths and \"..\" are rejected, exactly like an imported package."
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        if files.isEmpty {
                            Text("No files yet.")
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
                            Label("Add File…", systemImage: "plus")
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
                    WTSectionCard(footer: "Nothing was written — the stored manifest is unchanged.") {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("This package was rejected", systemImage: "exclamationmark.triangle.fill")
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
            }
            .navigationTitle(session.isNew ? "New Package" : "Edit Package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(saveProblem != nil)
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    let taken = Set(files.map(\.payloadName))
                    if let added = DeployManager.addPayload(to: session.package.folderURL, from: url, takenNames: taken) {
                        // The destination defaults to the
                        // payload's name — the picked file's
                        // name, unless it had to be made
                        // unique inside the package.
                        files.append(StoredDeployPackageFile(
                            payloadName: added.name,
                            destinationPath: added.name,
                            size: added.size
                        ))
                        addError = nil
                    } else {
                        addError = "The picked file could not be copied into the package."
                    }
                case .failure(let error):
                    addError = error.localizedDescription
                }
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
                TextField("Destination path", text: $files[index].destinationPath)
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
                             ? "The container scan found no containers."
                             : "No scan yet. The scan starts automatically; if it does not, open App Data once, or type the bundle ID by hand.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                } else {
                    WTSectionCard(
                        header: "Containers (\(appDataManager.containers.count))",
                        footer: "Identifiers from the App Data container scan — the same list Deploy resolves Application targets against."
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
            .navigationTitle("Pick Target App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
    @ObservedObject var appDataManager: AppDataManager
    @StateObject private var deployManager = DeployManager()

    @State private var package: LoadedDeployPackage?
    @State private var importError: String?

    var body: some View {
        WTGlassPage {
            DeployStoreSection(
                appDataManager: appDataManager,
                onDeploy: { presentLoadedPackage($0) },
                onImportError: { importError = $0 }
            )

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
                deployManager: deployManager
            )
        }
        .navigationTitle("Package Builder")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Show a loaded package in the preview/deploy flow
    /// below — the same state a fresh import lands in.
    private func presentLoadedPackage(_ loaded: LoadedDeployPackage) {
        package = loaded
        importError = nil
        deployManager.resolvedContainerPath = nil
        deployManager.resolveError = nil
        deployManager.lastResult = nil
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
