import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Photo & video backup / restore (v6.1)
//
// "AFC" here is the name of this backup system, not a protocol:
// the backup uses the standard photo picker, and the restore
// uses the standard share sheet.
//
//   Backup Your Photos & Videos Here!  — pick photos/videos,
//     Save -> they are copied into the `BackUP_Data` folder
//     inside the app's local storage. Skippable.
//   Your All BackUP Files Here!        — reads the photos and
//     videos back from `BackUP_Data`, select some, Restore ->
//     opens the share sheet, then Save to Photos.
//
// The folder lives in the app's Documents so it is visible in
// the Files app as the WorkTweaks folder.

enum PhotoBackupStore {
    /// The `BackUP_Data` folder inside the app's Documents.
    static var folderURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("BackUP_Data", isDirectory: true)
    }

    static func ensureFolder() {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    /// Files currently in `BackUP_Data`, newest first.
    static func backedUpFiles() -> [URL] {
        ensureFolder()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return files.sorted {
            let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d0 > d1
        }
    }

    static func isImageOrVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "mov", "mp4", "m4v"].contains(ext)
    }
}

// MARK: - Backup

/// "Backup Your Photos & Videos Here!" — pick photos and videos,
/// then Save copies them into `BackUP_Data`.
struct PhotoBackupView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var picked: [PHPickerResult] = []
    @State private var isSaving = false
    @State private var progress: Double = 0
    @State private var savedCount = 0
    @State private var totalCount = 0
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WTSectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(wtLang.tr("Backup Your Photos & Videos Here!"))
                                .font(.headline)
                            Text(wtLang.tr("Pick the photos and videos you want to keep, then Save. They are copied into the BackUP_Data folder inside the app. Optional — you can skip this."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }

                    WTSectionCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Button(wtLang.tr("Choose Photos & Videos")) {
                                SoundEffects.playTap()
                                showPicker = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving)

                            if totalCount > 0 {
                                Text(wtLang.tr("%d selected", picked.count))
                                    .font(.subheadline)
                            }

                            if isSaving {
                                ProgressView(value: progress)
                                Text(wtLang.tr("Saving %d of %d (%d%%)", savedCount, totalCount, Int(progress * 100)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button(wtLang.tr("Save")) {
                                SoundEffects.playTap()
                                savePicked()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSaving || picked.isEmpty)

                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }

                    WTSectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(wtLang.tr("Where it goes"))
                                .font(.subheadline.weight(.semibold))
                            Text(wtLang.tr("BackUP_Data folder, inside the WorkTweaks folder (Documents). You can browse it in the Files app."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(wtLang.tr("Backup Photos & Videos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(wtLang.tr("Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                PhotoPicker(results: $picked)
            }
        }
    }

    private func savePicked() {
        guard !picked.isEmpty else { return }
        isSaving = true
        progress = 0
        savedCount = 0
        totalCount = picked.count
        statusMessage = nil
        PhotoBackupStore.ensureFolder()

        Task {
            var saved = 0
            for result in picked {
                let provider = result.itemProvider
                let savedURL = await copyItem(provider: provider)
                if savedURL != nil { saved += 1 }
                await MainActor.run {
                    savedCount = saved
                    progress = Double(saved) / Double(max(totalCount, 1))
                }
            }
            await MainActor.run {
                isSaving = false
                statusMessage = wtLang.tr("Saved %d of %d to BackUP_Data.", saved, totalCount)
                picked = []
                totalCount = 0
            }
        }
    }

    /// Copies one picked item into `BackUP_Data`, keeping a unique name.
    private func copyItem(provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            let type = provider.registeredTypeIdentifiers.first ?? UTType.image.identifier
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let dest = uniqueDestination(for: url.lastPathComponent)
                do {
                    // The picker hands us a temp copy; move it into BackUP_Data.
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.copyItem(at: url, to: dest)
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func uniqueDestination(for name: String) -> URL {
        let folder = PhotoBackupStore.folderURL
        var dest = folder.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            dest = folder.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return dest
    }
}

/// The system photo/video picker (PhotosUI).
private struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var results: [PHPickerResult]

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.results = results
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Restore / browse

/// "Your All BackUP Files Here!" — reads the photos and videos
/// from `BackUP_Data`, select some, Restore opens the share
/// sheet, then Save to Photos.
struct PhotoRestoreView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var selected: Set<URL> = []
    @State private var showShare = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WTSectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(wtLang.tr("Your All BackUP Files Here!"))
                                .font(.headline)
                            Text(wtLang.tr("These are the photos and videos in the BackUP_Data folder. Select the ones to restore, then Restore opens the share sheet — tap Save to Photos there."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }

                    if files.isEmpty {
                        WTSectionCard {
                            Text(wtLang.tr("No backed-up photos or videos yet. Use \"Backup Your Photos & Videos Here!\" first."))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        WTSectionCard {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(files, id: \.self) { file in
                                    Button {
                                        if selected.contains(file) {
                                            selected.remove(file)
                                        } else {
                                            selected.insert(file)
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: selected.contains(file) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selected.contains(file) ? Color.accentColor : .secondary)
                                            Image(systemName: file.pathExtension.lowercased() == "mov" || file.pathExtension.lowercased() == "mp4" || file.pathExtension.lowercased() == "m4v" ? "video" : "photo")
                                                .foregroundStyle(.secondary)
                                            Text(file.lastPathComponent)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }

                        Button(wtLang.tr("Restore (%d)", selected.count)) {
                            SoundEffects.playTap()
                            showShare = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selected.isEmpty)
                        .padding(.top, 4)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(wtLang.tr("All BackUP Files"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(wtLang.tr("Done")) { dismiss() }
                }
            }
            .onAppear { reload() }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: Array(selected))
            }
        }
    }

    private func reload() {
        files = PhotoBackupStore.backedUpFiles().filter { PhotoBackupStore.isImageOrVideo($0) }
        selected = selected.intersection(files)
        if files.isEmpty {
            statusMessage = wtLang.tr("BackUP_Data is empty.")
        } else {
            statusMessage = wtLang.tr("%d file(s) in BackUP_Data.", files.count)
        }
    }
}

/// The iOS share sheet (UIActivityViewController). For photos and
/// videos it offers Save to Photos.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
