import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - PosterBoard wallpaper maker page
//
// Builds a PosterBoard wallpaper on-device from a photo or a
// video and installs it through PosterBoardManager — the same
// grant / copy / verify / receipt path as a .tendies import.
//
//   - Video: the first 12 seconds, sampled at most 30 fps,
//     frames as JPEGs played by a CAKeyframeAnimation. Loop
//     plays the animation forwards and backwards.
//   - Photo: a single still frame. This is the natural
//     adaptation of the video path and has not been
//     device-tested yet — the maker logs that when one is
//     built, so a bad result is reported, not silently kept.
//
// The page renders as Liquid Glass cards (WTGlassPage /
// WTSectionCard), like every other page since v3.8. All strings
// are English, like the rest of the app.

struct PosterBoardMakerView: View {
    @ObservedObject var manager: PosterBoardManager

    @State private var name = "Custom"
    @State private var pickedPhoto: UIImage?
    @State private var pickedVideoURL: URL?
    @State private var pickedVideoDuration: Double?
    @State private var pickerKind: PickerKind?
    @State private var loop = false
    @State private var isBuilding = false
    @State private var progressText = ""
    @State private var errorMessage: String?
    @State private var showRespringChoice = false
    @State private var showManualRestartGuide = false

    private enum PickerKind: Identifiable {
        case photo, video
        var id: Int { self == .photo ? 0 : 1 }
    }

    private var canBuild: Bool {
        !isBuilding && !manager.isBusy && (pickedPhoto != nil || pickedVideoURL != nil)
    }

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "Wallpaper", footer: "Videos use the first 12 seconds. Photos become a single still frame.") {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Wallpaper name", text: $name)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                    Divider().padding(.leading, 14)

                    Button {
                        pickerKind = .photo
                    } label: {
                        HStack(spacing: 10) {
                            Label(pickedPhoto == nil ? "Choose Photo…" : "Photo chosen — tap to change", systemImage: "photo")
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            if let photo = pickedPhoto {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipped()
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBuilding)

                    Divider().padding(.leading, 14)

                    Button {
                        pickerKind = .video
                    } label: {
                        HStack(spacing: 10) {
                            Label(videoButtonTitle, systemImage: "video")
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            if isBuilding || manager.isBusy {
                                ProgressView()
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBuilding)
                }
            }

            if pickedVideoURL != nil {
                WTSectionCard(header: "Video") {
                    Toggle("Loop (forwards and backwards)", isOn: $loop)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .disabled(isBuilding)
                        .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                }
            }

            if !progressText.isEmpty || manager.lastResult != nil {
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 4) {
                        if !progressText.isEmpty {
                            Text(progressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let result = manager.lastResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            WTSectionCard(footer: "A respring is required before a new wallpaper appears in the gallery.") {
                Button {
                    buildAndInstall()
                } label: {
                    HStack(spacing: 10) {
                        Label("Build & Install Wallpaper", systemImage: "wand.and.stars")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        if isBuilding || manager.isBusy {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canBuild)
            }
        }
        .navigationTitle("Create Wallpaper")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pickerKind) { kind in
            PhotoVideoPicker(filter: kind == .photo ? .images : .videos) { result in
                handlePicked(result, kind: kind)
            }
        }
        .alert("Could Not Build", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "")
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
    }

    private var videoButtonTitle: String {
        if let duration = pickedVideoDuration {
            return String(format: "Video chosen (%.1f s) — tap to change", duration)
        }
        return "Choose Video…"
    }

    // MARK: Pick handling

    private func handlePicked(_ result: PHPickerResult, kind: PickerKind) {
        let provider = result.itemProvider
        if kind == .photo {
            guard provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        self.pickedPhoto = image
                        self.pickedVideoURL = nil
                        self.pickedVideoDuration = nil
                    }
                }
            }
        } else {
            guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { return }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else { return }
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("maker-video-\(UUID().uuidString).mov")
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                } catch {
                    DispatchQueue.main.async { self.errorMessage = "Could not read this video: \(error.localizedDescription)" }
                    return
                }
                let duration = CMTimeGetSeconds(AVURLAsset(url: copy).duration)
                DispatchQueue.main.async {
                    self.pickedVideoURL = copy
                    self.pickedVideoDuration = duration.isFinite ? duration : nil
                    self.pickedPhoto = nil
                }
            }
        }
    }

    // MARK: Build + install

    private func buildAndInstall() {
        guard !isBuilding, manager.stateIfReady else { return }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let photo = pickedPhoto
        let videoURL = pickedVideoURL
        let loop = loop
        isBuilding = true
        errorMessage = nil
        progressText = photo != nil ? "Building still wallpaper…" : "Reading video frames…"
        DispatchQueue.global(qos: .userInitiated).async {
            let folder: URL
            do {
                folder = try PosterBoardMaker.buildDescriptor(
                    name: displayName.isEmpty ? "Custom" : displayName,
                    photo: photo,
                    videoURL: videoURL,
                    loop: loop,
                    progress: { text in
                        DispatchQueue.main.async { self.progressText = text }
                    }
                )
            } catch {
                DispatchQueue.main.async {
                    self.isBuilding = false
                    self.progressText = ""
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            DispatchQueue.main.async {
                self.progressText = "Installing into PosterBoard…"
                self.manager.installBuiltDescriptor(folder: folder, name: displayName.isEmpty ? "Custom" : displayName) { ok in
                    self.isBuilding = false
                    self.progressText = ""
                    try? FileManager.default.removeItem(at: folder)
                    if ok { self.showRespringChoice = true }
                }
            }
        }
    }
}

// MARK: - PHPicker wrapper

private struct PhotoVideoPicker: UIViewControllerRepresentable {
    var filter: PHPickerFilter
    var onPick: (PHPickerResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = filter
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPick: (PHPickerResult) -> Void
        init(onPick: @escaping (PHPickerResult) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            if let first = results.first { onPick(first) }
        }
    }
}

// MARK: - Manager readiness helper

private extension PosterBoardManager {
    /// True only when the PosterBoard container is resolved and
    /// the manager is free — the same gate importPackage uses.
    var stateIfReady: Bool {
        if case .ready = state, !isBusy { return true }
        return false
    }
}
