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
//
// Since v3.8 the pages render as Liquid Glass cards
// (WTGlassPage/WTSectionCard), like every other page —
// presentation only; browsing and editing behave as before.

struct AppDataView: View {
    // The shared, session-persistent manager: its completed
    // scan stays cached across navigation for the whole app
    // session (a per-view manager would forget it on every
    // pop and rescan for a minute each time).
    @ObservedObject private var manager = AppDataManager.shared

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "Containers", footer: "Containers are enumerated with the fork's pathleak scan — the kernel refuses a grant on the container root itself, so there is no faster way to list them.") {
                Group {
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
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if !manager.containers.isEmpty {
                WTSectionCard {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(manager.containers.enumerated()), id: \.element.id) { index, container in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            NavigationLink {
                                AppDataDirectoryView(
                                    manager: manager,
                                    container: container,
                                    path: container.path,
                                    title: container.bundleID
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(container.bundleID)
                                            .font(.subheadline.weight(.semibold))
                                        Text(containerSubtitle(container))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
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
        WTGlassPage {
            if grantFailed {
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Couldn't open this container", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("The sandbox extension for this container's directory was refused — the result code is in the Log.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            } else {
                WTSectionCard(header: "Contents", footer: path) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
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
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    AppDataFileView(
                                        manager: manager,
                                        path: entry.path,
                                        name: entry.name,
                                        isNew: false,
                                        knownSize: entry.size
                                    )
                                } label: {
                                    entryRow(entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
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
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
// editor and saves back in place. Anything else gets an info
// page; a readable non-text file up to 1 MB can also be edited
// byte-by-byte in the hex editor (length-preserving, with a
// pristine backup taken before the first edit). A file reached
// through Add File starts empty and is created on save.

struct AppDataFileView: View {
    @ObservedObject var manager: AppDataManager
    let path: String
    let name: String
    let isNew: Bool
    /// The size from the directory listing, when the listing
    /// could stat the file (0 = not known). Only used by the
    /// read-failure page, where the real size is unavailable.
    var knownSize: Int64 = 0

    @State private var loaded = false
    @State private var fileExists = false
    @State private var isText = false
    @State private var text = ""
    @State private var size: Int64 = 0
    @State private var hexPreview = ""
    @State private var readFailed = false
    @State private var saved = false
    @State private var saveFailed = false
    @State private var hasBackup = false
    @State private var showRestoreConfirm = false
    @State private var restoreFailed = false

    var body: some View {
        WTGlassPage {
            if !loaded {
                WTSectionCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            } else if readFailed {
                WTSectionCard(header: "File", footer: path) {
                    VStack(alignment: .leading, spacing: 0) {
                        LabeledContent("Name", value: name)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        if knownSize > 0 {
                            Divider()
                                .padding(.leading, 14)
                            LabeledContent("Size", value: wtFormatSize(knownSize))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                        }
                    }
                }

                WTSectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Couldn't read this file.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(readFailureNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            } else if isText {
                WTSectionCard(header: "Contents", footer: path) {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 280)
                        .padding(6)
                        .onChange(of: text) { _, _ in
                            saved = false
                        }
                }

                WTSectionCard(footer: "Saving writes the file in place, under the container's sandbox extension.") {
                    Button {
                        if manager.saveText(path: path, text: text, isNew: !fileExists) {
                            fileExists = true
                            saved = true
                        } else {
                            saveFailed = true
                        }
                    } label: {
                        Text(saved ? "Saved" : "Save")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
            } else {
                WTSectionCard(header: "File", footer: path) {
                    VStack(alignment: .leading, spacing: 0) {
                        LabeledContent("Name", value: name)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        Divider()
                            .padding(.leading, 14)
                        LabeledContent("Size", value: wtFormatSize(size))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                }

                if !hexPreview.isEmpty {
                    WTSectionCard(header: "First Bytes") {
                        Text(hexPreview)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }

                WTSectionCard {
                    Text(size <= 1_048_576
                         ? "This file isn't UTF-8 text, so it can't be edited as text. It can be edited byte-by-byte in the hex editor below."
                         : "This file isn't UTF-8 text, so it can't be edited here. Nothing is ever written to it from this page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                if size <= 1_048_576 {
                    WTSectionCard(footer: "Edits replace byte values only — the file's length never changes. A backup of the original is saved before the first edit.") {
                        NavigationLink {
                            AppDataHexEditorView(manager: manager, path: path, name: name)
                        } label: {
                            HStack(spacing: 12) {
                                Text("Edit Bytes")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if hasBackup {
                    WTSectionCard(footer: "Copies the backup taken before the first byte edit back over this file, in place.") {
                        Button(role: .destructive) {
                            showRestoreConfirm = true
                        } label: {
                            Text("Restore Backup")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                    }
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
        .confirmationDialog("Restore the backup?", isPresented: $showRestoreConfirm) {
            Button("Restore Backup", role: .destructive) {
                if manager.restoreHexBackup(path: path) {
                    loaded = false
                    load()
                } else {
                    restoreFailed = true
                }
            }
        } message: {
            Text("The current file is overwritten in place with the backup taken before the first byte edit.")
        }
        .alert("Couldn't Restore", isPresented: $restoreFailed) {
            Button("OK") { }
        } message: {
            Text("Restoring the backup failed — the details are in the Log.")
        }
        .onAppear {
            load()
        }
    }

    /// Why a file may be unreadable, shown on the read-failure
    /// page. The container-manager metadata plist present at
    /// every container root is system-managed: iOS does not let
    /// other processes read its contents at all.
    private var readFailureNote: String {
        if name == ".com.apple.mobile_container_manager.metadata.plist" {
            return "This is the container's system-managed metadata file. iOS doesn't allow other processes to read its contents, so it can't be opened or edited here."
        }
        return "The file couldn't be read under the container's sandbox extension — the details are in the Log. Nothing was written to it."
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
        hasBackup = manager.hexBackupURL(forSourcePath: path) != nil
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

// MARK: - Hex editor
//
// Length-preserving byte editor for files that read fine but
// are not UTF-8 text. Sixteen bytes per row: offset on the
// left, hex pairs in the middle, an ASCII gutter on the right
// (non-printable bytes shown as "·"). Tapping a byte selects
// it and its two hex digits can be edited in the Byte card.
// Edits only ever replace byte values — the file's length can
// never change. Before the first save the manager stores a
// pristine backup in our App Group container and refuses to
// save without one; saving writes in place and verifies by
// re-reading. Same 1 MB ceiling as the text editor.

struct AppDataHexEditorView: View {
    @ObservedObject var manager: AppDataManager
    let path: String
    let name: String

    @State private var loaded = false
    @State private var loadFailed = false
    @State private var original: [UInt8] = []
    @State private var bytes: [UInt8] = []
    @State private var selectedOffset: Int? = nil
    @State private var editHex = ""
    @State private var saved = false
    @State private var saveFailed = false
    @State private var failureMessage = ""

    private var isDirty: Bool { bytes != original }
    private var rowCount: Int { (bytes.count + 15) / 16 }

    var body: some View {
        WTGlassPage {
            if !loaded {
                WTSectionCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            } else if loadFailed {
                WTSectionCard {
                    Label("Couldn't read this file.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            } else {
                WTSectionCard(header: "Hex Editor", footer: path) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(bytes.count) bytes — length-preserving edits only: byte values can change, the file's length never does.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Warning: raw byte edits have no structure validation — a wrong byte can corrupt this file or the owning app's data. A backup of the original is saved before the first edit.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                if let selectedOffset {
                    WTSectionCard(header: "Byte") {
                        HStack(spacing: 12) {
                            Text(String(format: "0x%08X", selectedOffset))
                                .font(.system(.subheadline, design: .monospaced))
                            TextField("HH", text: $editHex)
                                .font(.system(.body, design: .monospaced))
                                .textInputAutocapitalization(.characters)
                                .disableAutocorrection(true)
                                .frame(width: 64)
                                .onChange(of: editHex) { _, newValue in
                                    applyEditHex(newValue, at: selectedOffset)
                                }
                            Spacer()
                            Button("Done") {
                                self.selectedOffset = nil
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }

                WTSectionCard {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(0..<rowCount, id: \.self) { row in
                                hexRow(row)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }

                WTSectionCard(footer: "Saving writes the file in place and verifies the result by re-reading it.") {
                    Button {
                        save()
                    } label: {
                        Text(saved && !isDirty ? "Saved" : "Save")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .disabled(!isDirty)
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't Save", isPresented: $saveFailed) {
            Button("OK") { }
        } message: {
            Text(failureMessage)
        }
        .onAppear {
            load()
        }
    }

    private func hexRow(_ row: Int) -> some View {
        let start = row * 16
        let end = min(start + 16, bytes.count)
        return HStack(spacing: 10) {
            Text(String(format: "%08X", start))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(start..<end, id: \.self) { offset in
                    Text(String(format: "%02X", bytes[offset]))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(byteColor(at: offset))
                        .padding(.horizontal, 2)
                        .background(byteBackground(at: offset))
                        .onTapGesture {
                            selectedOffset = offset
                            editHex = String(format: "%02X", bytes[offset])
                        }
                }
                if end - start < 16 {
                    ForEach(end..<(start + 16), id: \.self) { _ in
                        Text("  ")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 2)
                    }
                }
            }
            Text(asciiGutter(start: start, end: end))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func byteColor(at offset: Int) -> Color {
        if offset == selectedOffset { return .white }
        return bytes[offset] != original[offset] ? .orange : .primary
    }

    private func byteBackground(at offset: Int) -> Color {
        offset == selectedOffset ? Color.accentColor : .clear
    }

    private func asciiGutter(start: Int, end: Int) -> String {
        var result = ""
        for offset in start..<end {
            let byte = bytes[offset]
            if byte >= 32 && byte <= 126 {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result.append("·")
            }
        }
        return result
    }

    private func applyEditHex(_ newValue: String, at offset: Int) {
        let filtered = String(newValue.uppercased().filter { $0.isHexDigit }.prefix(2))
        if filtered != editHex {
            editHex = filtered
        }
        if filtered.count == 2, let value = UInt8(filtered, radix: 16), offset < bytes.count {
            bytes[offset] = value
            saved = false
        }
    }

    private func load() {
        guard !loaded else { return }
        guard let data = manager.readFileData(path), data.count <= 1_048_576 else {
            loadFailed = true
            loaded = true
            return
        }
        original = [UInt8](data)
        bytes = original
        loaded = true
    }

    private func save() {
        guard isDirty else { return }
        guard manager.makeHexBackupIfNeeded(path: path) else {
            failureMessage = "The backup of the original file couldn't be written, so nothing was saved."
            saveFailed = true
            return
        }
        if manager.saveHexData(path: path, data: Data(bytes)) {
            original = bytes
            saved = true
        } else {
            failureMessage = "Writing or verifying the file failed — the details are in the Log."
            saveFailed = true
        }
    }
}
