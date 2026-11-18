// MARK: - Airlift Passcode Theme page
//
// Clean rebuild of aircard's PasscodeThemeTab (ContentView.swift) on the
// WorkTweaks page scaffolding (WTGlassPage / WTSectionCard).
// Mode picker (Apply .passthm / Create Theme), .passthm import, key preview
// grid (1-9, *, 0, #), per-digit photo picker in creator mode, Save .passthm
// export, language + bold pickers, flash button with progress + log.
//
// Notes:
// - `*` and `#` appear in the preview grid as plain keys: aircard's staging
//   rules define no filenames for them, so they can never carry a theme image.
// - No respring/restart button anywhere: restart is manual-guide only in
//   WorkTweaks. After a successful flash the user just locks the iPhone.
// - Flash needs a pairing file; without one the page says so honestly and
//   points at Sandbox -> Utilities -> Get Pairing File.

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI

struct AirliftPasscodeView: View {
    @StateObject private var engine = AirliftPasscodeEngine.shared

    @State private var showThemeImporter = false

    @State private var keyPickerDigit: String? = nil
    @State private var showKeySourceDialog = false
    @State private var showKeyPhotosPicker = false
    @State private var keyPickerItems: [PhotosPickerItem] = []
    @State private var showKeyFileImporter = false

    var body: some View {
        NavigationStack {
            WTGlassPage {
                modeCard

                if !engine.hasPairingFile {
                    pairingWarningCard
                }

                if engine.passcodeMode == .applyTheme {
                    applySection
                } else {
                    creatorSection
                }

                targetCard
                flashCard
                errorBanner

                // Clear the floating tab bar so the last card
                // is not hidden behind it.
                Color.clear.frame(height: 60)
            }
            .navigationTitle("Passcode Theme")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showThemeImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "passthm") ?? .archive,
                    UTType.zip,
                    UTType.archive
                ],
                allowsMultipleSelection: false
            ) { result in
                importPassthm(result: result)
            }
            .photosPicker(
                isPresented: $showKeyPhotosPicker,
                selection: $keyPickerItems,
                maxSelectionCount: 1,
                matching: .images
            )
            .onChange(of: keyPickerItems) { _, items in
                guard let item = items.first,
                      let digit = keyPickerDigit else {
                    if items.isEmpty { keyPickerDigit = nil }
                    return
                }
                let currentDigit = digit
                Task {
                    if let image = await item.loadUIImage(maxDimension: 1024) {
                        await MainActor.run { engine.setIndividualKey(digit: currentDigit, image: image) }
                    }
                    await MainActor.run {
                        keyPickerItems = []
                        keyPickerDigit = nil
                    }
                }
            }
            .fileImporter(
                isPresented: $showKeyFileImporter,
                allowedContentTypes: [.image, .png, .jpeg, .heic],
                allowsMultipleSelection: false
            ) { result in
                guard let digit = keyPickerDigit else { return }
                defer { keyPickerDigit = nil }
                guard case .success(let urls) = result, let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url),
                   let image = ImageEngine.safeImageFromData(data, maxDimension: 1024) {
                    engine.setIndividualKey(digit: digit, image: image)
                }
            }
            .confirmationDialog(
                "Choose Key \(keyPickerDigit ?? "") Image Source",
                isPresented: $showKeySourceDialog,
                titleVisibility: .visible
            ) {
                Button {
                    showKeyPhotosPicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
                Button {
                    showKeyFileImporter = true
                } label: {
                    Label("Choose from Files…", systemImage: "folder")
                }
                Button("Cancel", role: .cancel) {
                    keyPickerDigit = nil
                }
            }
            .alert("Passcode theme applied", isPresented: $engine.showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(engine.successAlertMessage)
            }
        }
    }

    // MARK: - Import

    private func importPassthm(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        // Copy into tmp while holding the security scope: the reader runs
        // async on a background queue and the Rust extractor needs a plain path.
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("import_\(UUID().uuidString).passthm")
        do {
            try FileManager.default.copyItem(at: url, to: tmpURL)
        } catch {
            return
        }
        engine.loadPassthm(url: tmpURL)
    }

    // MARK: - Cards

    private var modeCard: some View {
        WTSectionCard {
            Picker("Mode", selection: $engine.passcodeMode) {
                ForEach(CreatorMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    /// Error banner, kept as its own view so the main body stays
    /// small enough for the type-checker.
    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage = engine.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
        }
    }

    private var pairingWarningCard: some View {
        WTSectionCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No pairing file")
                        .font(.subheadline.weight(.semibold))
                    Text("Flashing needs a pairing file. Pair first in Sandbox → Utilities → Get Pairing File, then come back here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Apply .passthm

    private var applySection: some View {
        Group {
            WTSectionCard(header: "Browse Files") {
                HStack {
                    Button {
                        showThemeImporter = true
                    } label: {
                        Label(
                            engine.loadedTheme == nil ? "Choose .passthm from Files…" : "Change .passthm…",
                            systemImage: "doc.badge.plus"
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)

                    if engine.loadedTheme != nil {
                        Button("Clear") {
                            engine.clearLoadedTheme()
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if let theme = engine.loadedTheme {
                WTSectionCard(header: "Lock Screen Preview") {
                    KeypadPreviewGrid(keys: theme.keysPreview)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                WTSectionCard(header: "Theme Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Files in theme")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(theme.fileCount)")
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        .font(.subheadline)
                        HStack {
                            Text("Digits styled")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(theme.keysPreview.count) keys")
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        .font(.subheadline)
                        Button {
                            engine.adoptThemeIntoCreator()
                        } label: {
                            Label("Edit in Theme Creator", systemImage: "pencil")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Create Theme

    private var creatorSection: some View {
        Group {
            WTSectionCard(header: "Individual Keys") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap a key to assign a custom image.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)

                    ForEach(KeypadLayout.allButtons) { btn in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(uiColor: .secondarySystemBackground))
                                    .frame(width: 44, height: 44)
                                if let img = engine.customKeys[btn.digit] {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())
                                } else {
                                    Text(btn.digit)
                                        .font(.title3.bold())
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Key \(btn.digit)")
                                    .font(.subheadline.weight(.medium))
                                if !btn.letters.isEmpty {
                                    Text(btn.letters)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if engine.customKeys[btn.digit] != nil {
                                Button(role: .destructive) {
                                    engine.clearIndividualKey(digit: btn.digit)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.title3)
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.title3)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            keyPickerDigit = btn.digit
                            showKeySourceDialog = true
                        }

                        if btn.digit != KeypadLayout.allButtons.last?.digit {
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            WTSectionCard(header: "Lock Screen Preview") {
                KeypadPreviewGrid(keys: engine.effectiveKeys)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            if !engine.effectiveKeys.isEmpty {
                WTSectionCard {
                    VStack(spacing: 10) {
                        Button {
                            _ = engine.exportPassthm()
                        } label: {
                            HStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                Text("Save .passthm")
                                Spacer()
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.bordered)

                        if let url = engine.exportedThemeURL {
                            ShareLink(item: url) {
                                HStack(spacing: 8) {
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up.on.square")
                                    Text("Share \(url.lastPathComponent)")
                                    Spacer()
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button(role: .destructive) {
                            engine.clearAllCreator()
                        } label: {
                            HStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "trash")
                                Text("Clear All")
                                Spacer()
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Target

    private var targetCard: some View {
        WTSectionCard(header: "Flash & Language Target") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Caches")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Picker("System Caches", selection: $engine.targetTelephonyVersion) {
                        Text("TelephonyUI-10 (iOS 18+)").tag("TelephonyUI-10")
                        Text("TelephonyUI-9 (iOS 16–17)").tag("TelephonyUI-9")
                        Text("TelephonyUI-8 (iOS 14–15)").tag("TelephonyUI-8")
                        Text("Universal (All)").tag("all")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("System Language")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Picker("System Language", selection: $engine.passcodeLanguageTarget) {
                        ForEach(PasscodeLanguageTarget.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Font Weight / Style")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Picker("Font Weight / Style", selection: $engine.passcodeBoldTarget) {
                        ForEach(PasscodeBoldTarget.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: engine.passcodeLanguageTarget == .all && engine.passcodeBoldTarget == .both ? "globe" : "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(engine.passcodeLanguageTarget == .all && engine.passcodeBoldTarget == .both ? Color.secondary : Color.orange)
                        .padding(.top, 1)

                    if engine.passcodeLanguageTarget == .all && engine.passcodeBoldTarget == .both {
                        Text("Universal mode flashes ~600 files for all languages & Bold text. Selecting a specific language (e.g. Ukrainian) speeds up flashing dramatically.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Fast mode selected: only targets \(engine.passcodeLanguageTarget.rawValue) with \(engine.passcodeBoldTarget.rawValue).")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Flash

    private var flashCard: some View {
        Group {
            WTSectionCard {
                VStack(spacing: 12) {
                    flashButton

                    if engine.passcodeMode == .applyTheme, engine.loadedTheme != nil {
                        Button(role: .destructive) {
                            engine.clearLoadedTheme()
                        } label: {
                            HStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "trash")
                                Text("Remove / Unload Theme")
                                Spacer()
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if !engine.flashLog.isEmpty {
                WTSectionCard(header: "Flash Log (\(engine.flashLog.count) lines)") {
                    PasscodeFlashLogView(
                        lines: engine.flashLog,
                        onClear: { engine.flashLog.removeAll() }
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder
    private var flashButton: some View {
        if case .running = engine.flashPhase {
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Flashing Theme…").font(.subheadline.bold())
                    ProgressView(value: engine.flashProgress)
                }
            }
            .padding(.vertical, 4)
        } else if case .done(let ok) = engine.flashPhase, !ok {
            Button {
                engine.flashPassthm()
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                    Text("Retry Flash Theme")
                    Spacer()
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!engine.canFlashPassthm)
        } else {
            Button {
                engine.flashPassthm()
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bolt.fill")
                    Text("Flash Theme to iPhone")
                    Spacer()
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!engine.canFlashPassthm)
        }
    }
}

// MARK: - Keypad preview grid (dialer order: 1-9, *, 0, #)
//
// `*` and `#` are plain keys: aircard's staging rules define no filenames
// for them, so no theme image can ever exist for them.

struct KeypadPreviewGrid: View {
    let keys: [String: UIImage]

    private var cells: [(digit: String, letters: String)] {
        var rows: [(String, String)] = []
        for btn in KeypadLayout.allButtons where btn.digit != "0" {
            rows.append((btn.digit, btn.letters))
        }
        rows.append(("*", ""))
        rows.append(("0", KeypadLayout.subtexts["0"] ?? "+"))
        rows.append(("#", ""))
        return rows
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 14
        ) {
            ForEach(cells, id: \.digit) { cell in
                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .frame(width: 64, height: 64)
                        if let img = keys[cell.digit] {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        } else {
                            Text(cell.digit)
                                .font(.title2.bold())
                        }
                    }
                    if !cell.letters.isEmpty {
                        Text(cell.letters)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Flash log (scrolling, auto-follows, copy + clear)

struct PasscodeFlashLogView: View {
    let lines: [String]
    var onClear: (() -> Void)? = nil
    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                if let onClear = onClear, !lines.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    UIPasteboard.general.string = lines.joined(separator: "\n")
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .bold))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(copied ? .green : .blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines.indices, id: \.self) { i in
                            Text(lines[i])
                                .font(.system(size: 12, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                                .id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .onChange(of: lines.count) { _, count in
                    guard count > 0 else { return }
                    withAnimation {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - PhotosPickerItem Universal Image Loader

extension PhotosPickerItem {
    /// Loads a UIImage from the photo picker item, handling HEIC, Live Photos, ProRAW, and iCloud downloads safely.
    func loadUIImage(maxDimension: CGFloat = 2048) async -> UIImage? {
        // 1. Transferable DataRepresentation (automatic conversion to standard format)
        struct ImageTransferable: Transferable {
            let data: Data
            static var transferRepresentation: some TransferRepresentation {
                DataRepresentation(importedContentType: .image) { data in
                    ImageTransferable(data: data)
                }
            }
        }
        if let result = try? await self.loadTransferable(type: ImageTransferable.self) {
            if let img = ImageEngine.safeImageFromData(result.data, maxDimension: maxDimension) {
                return img
            }
        }

        // 2. Direct raw data
        if let data = try? await self.loadTransferable(type: Data.self) {
            if let img = ImageEngine.safeImageFromData(data, maxDimension: maxDimension) {
                return img
            }
        }

        // 3. File representation fallback (ideal for large camera roll photos)
        struct FileImageTransferable: Transferable {
            let url: URL
            static var transferRepresentation: some TransferRepresentation {
                FileRepresentation(importedContentType: .image) { received in
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "_" + received.file.lastPathComponent)
                    try? FileManager.default.copyItem(at: received.file, to: tmp)
                    return FileImageTransferable(url: tmp)
                }
            }
        }
        if let fileResult = try? await self.loadTransferable(type: FileImageTransferable.self) {
            defer { try? FileManager.default.removeItem(at: fileResult.url) }
            if let data = try? Data(contentsOf: fileResult.url),
               let img = ImageEngine.safeImageFromData(data, maxDimension: maxDimension) {
                return img
            }
        }

        return nil
    }
}

