import SwiftUI

// MARK: - App Data page
//
// Browse the app data containers under
// /var/mobile/Containers/Data/Application, open their files,
// edit text files in place, and add new files and folders.
// All access goes through the Gestalt-Tweak fork's machinery
// (ContainerSupport.swift + SandboxBridge): the container list
// is a pathleak scan, and each opened container is browsed
// under a single consumeExtension grant on its directory.

struct AppDataView: View {
    @StateObject private var manager = AppDataManager()

    var body: some View {
        Form {
            Section {
                if manager.isScanning {
                    HStack(spacing: 10) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(manager.scanPhase)
                                .font(.subheadline)
                            Text("The pathleak scan reads inodes one by one — this can take a few minutes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let summary = manager.scanSummary {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary)
                            .font(.subheadline)
                        if manager.containers.isEmpty {
                            Text("The scan of \(AppDataManager.rootPath) found no containers. The scan's baseline and counts are in the Log.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Preparing the container scan…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Containers")
            } footer: {
                Text("Containers are enumerated with the fork's pathleak scan — the kernel refuses a grant on the container root itself, so there is no faster way to list them.")
            }

            if !manager.containers.isEmpty {
                Section {
                    ForEach(manager.containers) { container in
                        NavigationLink {
                            AppDataDirectoryView(
                                manager: manager,
                                container: container,
                                path: container.path,
                                title: container.bundleID
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(container.bundleID)
                                    .font(.subheadline.weight(.semibold))
                                Text(containerSubtitle(container))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("App Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rescan") {
                    manager.rescan()
                }
                .disabled(manager.isScanning)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        DeployView(appDataManager: manager)
                    } label: {
                        Label("Deploy Package…", systemImage: "shippingbox")
                    }
                    NavigationLink {
                        DeployHistoryView(appDataManager: manager)
                    } label: {
                        Label("Deploy History", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // Back at the list: any browsing grant is released.
            manager.leaveContainer()
            manager.scanIfNeeded()
        }
    }

    private func containerSubtitle(_ container: AppContainer) -> String {
        var parts: [String] = []
        if container.bundleID != container.directoryName {
            parts.append(container.directoryName)
        }
        if let count = container.itemCount {
            parts.append("\(count) item\(count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Directory browser
//
// One page per directory under the opened container, all under
// the container's single grant. Folders push another page of
// the same view; files push the file view.

struct AppDataDirectoryView: View {
    @ObservedObject var manager: AppDataManager
    let container: AppContainer
    let path: String
    let title: String

    @State private var entries: [AppDataEntry] = []
    @State private var grantFailed = false
    @State private var showAddFile = false
    @State private var showAddFolder = false
    @State private var newName = ""
    @State private var newFilePath: String?

    var body: some View {
        Form {
            if grantFailed {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Couldn't open this container", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("The sandbox extension for this container's directory was refused — the result code is in the Log.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        if entry.isDirectory {
                            NavigationLink {
                                AppDataDirectoryView(
                                    manager: manager,
                                    container: container,
                                    path: entry.path,
                                    title: entry.name
                                )
                            } label: {
                                entryRow(entry)
                            }
                        } else {
                            NavigationLink {
                                AppDataFileView(
                                    manager: manager,
                                    path: entry.path,
                                    name: entry.name,
                                    isNew: false
                                )
                            } label: {
                                entryRow(entry)
                            }
                        }
                    }
                } header: {
                    Text("Contents")
                } footer: {
                    Text(path)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = ""
                        showAddFile = true
                    } label: {
                        Label("Add File", systemImage: "doc.badge.plus")
                    }
                    Button {
                        newName = ""
                        showAddFolder = true
                    } label: {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(grantFailed)
            }
        }
        .alert("Add File", isPresented: $showAddFile) {
            TextField("Filename", text: $newName)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard isValidName(name) else { return }
                newFilePath = (path as NSString).appendingPathComponent(name)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Opens an empty editor; the file is created when you save.")
        }
        .alert("Add Folder", isPresented: $showAddFolder) {
            TextField("Folder name", text: $newName)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard isValidName(name) else { return }
                if manager.createFolder(path: (path as NSString).appendingPathComponent(name)) {
                    reload()
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .navigationDestination(item: $newFilePath) { filePath in
            AppDataFileView(
                manager: manager,
                path: filePath,
                name: (filePath as NSString).lastPathComponent,
                isNew: true
            )
        }
        .onAppear {
            if manager.enterContainer(container) {
                grantFailed = false
                reload()
            } else {
                grantFailed = true
            }
        }
    }

    private func entryRow(_ entry: AppDataEntry) -> some View {
        HStack(spacing: 10) {
            RowIcon(systemImage: entry.isDirectory ? "folder" : "doc")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if !entry.isDirectory {
                    Text(wtFormatSize(entry.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func isValidName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
    }

    private func reload() {
        entries = manager.listDirectory(path)
    }
}

// MARK: - File view / editor
//
// A file that decodes as UTF-8 text (up to 1 MB) opens in the
// editor and saves back in place. Anything else gets a
// read-only info page — it is never written to. A file reached
// through Add File starts empty and is created on save.

struct AppDataFileView: View {
    @ObservedObject var manager: AppDataManager
    let path: String
    let name: String
    let isNew: Bool

    @State private var loaded = false
    @State private var fileExists = false
    @State private var isText = false
    @State private var text = ""
    @State private var size: Int64 = 0
    @State private var hexPreview = ""
    @State private var readFailed = false
    @State private var saved = false
    @State private var saveFailed = false

    var body: some View {
        Form {
            if !loaded {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if readFailed {
                Section {
                    Label("Couldn't read this file.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else if isText {
                Section {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 280)
                        .onChange(of: text) { _, _ in
                            saved = false
                        }
                } header: {
                    Text("Contents")
                } footer: {
                    Text(path)
                }

                Section {
                    Button(saved ? "Saved" : "Save") {
                        if manager.saveText(path: path, text: text, isNew: !fileExists) {
                            fileExists = true
                            saved = true
                        } else {
                            saveFailed = true
                        }
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Saving writes the file in place, under the container's sandbox extension.")
                }
            } else {
                Section {
                    LabeledContent("Name", value: name)
                    LabeledContent("Size", value: wtFormatSize(size))
                } header: {
                    Text("File")
                } footer: {
                    Text(path)
                }

                if !hexPreview.isEmpty {
                    Section {
                        Text(hexPreview)
                            .font(.system(.caption, design: .monospaced))
                    } header: {
                        Text("First Bytes")
                    }
                }

                Section {
                    Text("This file isn't UTF-8 text, so it can't be edited here. Nothing is ever written to it from this page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't Save", isPresented: $saveFailed) {
            Button("OK") { }
        } message: {
            Text("Writing the file failed — the details are in the Log.")
        }
        .onAppear {
            load()
        }
    }

    private func load() {
        guard !loaded else { return }
        if isNew {
            // Add File: nothing exists yet; the editor starts
            // empty and Save creates the file.
            fileExists = false
            isText = true
            loaded = true
            return
        }
        fileExists = true
        guard let data = manager.readFileData(path) else {
            readFailed = true
            loaded = true
            return
        }
        size = Int64(data.count)
        if data.count <= 1_048_576, let decoded = String(data: data, encoding: .utf8) {
            text = decoded
            isText = true
        } else {
            hexPreview = data.prefix(64)
                .map { String(format: "%02x", $0) }
                .joined(separator: " ")
            isText = false
        }
        loaded = true
    }
}
