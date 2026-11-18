// MARK: - Airlift Wallet Cards page
//
// SwiftUI page for the Wallet Cards feature (ported from aircard-ios
// WalletCardsTab). Scan for card IDs, attach a skin image per card,
// and flash the skins into the cards' .pkpass folders on-device.
//
// The page is deliberately standalone: it does not add a tab and does
// not touch any other WorkTweaks file. Restart is manual-guide only
// in WorkTweaks, so there is no respring/restart button here —
// after flashing, force-close the Wallet app to see the new art.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct AirliftWalletView: View {
    @StateObject private var engine = AirliftWalletEngine.shared

    @State private var showAddSheet = false
    @State private var newHashText = ""
    @State private var activeTarget: WalletSkinTarget? = nil
    @State private var showSourceDialog = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var showFileImporter = false
    @State private var cropRequest: WalletCropRequest? = nil
    @State private var loadFailed = false

    var body: some View {
        WTGlassPage {
            introCard
            scannerCard

            if engine.cards.isEmpty {
                emptyStateCard
            } else {
                cardsCard
                actionsCard
            }

            flashCard
        }
        .navigationTitle("Wallet Cards")
        .sheet(isPresented: $showAddSheet) {
            AddWalletCardSheet(hashText: $newHashText) {
                engine.addCardHash(newHashText)
                newHashText = ""
                showAddSheet = false
            }
        }
        .confirmationDialog("Choose Image Source", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button {
                showPhotoPicker = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Choose from Files…", systemImage: "folder")
            }
            Button("Cancel", role: .cancel) {
                activeTarget = nil
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem?.itemIdentifier) { _ in
            guard let item = photoItem else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = WalletImageEngine.safeImageFromData(data, maxDimension: 2560) {
                    await MainActor.run {
                        if let target = activeTarget {
                            cropRequest = WalletCropRequest(image: image, target: target)
                        }
                    }
                } else {
                    await MainActor.run { loadFailed = true }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.importContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first,
                      url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url),
                   let image = WalletImageEngine.safeImageFromData(data, maxDimension: 2560),
                   let target = activeTarget {
                    cropRequest = WalletCropRequest(image: image, target: target)
                } else {
                    loadFailed = true
                }
            case .failure:
                loadFailed = true
            }
        }
        .sheet(item: $cropRequest) { request in
            WalletCardCropView(image: request.image) { cropped in
                assignImage(cropped, to: request.target)
                cropRequest = nil
                activeTarget = nil
            }
        }
        .alert("Couldn't Load Photo", isPresented: $loadFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Choose another image or try downloading the photo to your iPhone first.")
        }
    }

    private static var importContentTypes: [UTType] {
        var types: [UTType] = [.image, .png, .jpeg, .heic]
        if let webp = UTType(filenameExtension: "webp") { types.append(webp) }
        if let tiff = UTType(filenameExtension: "tiff") { types.append(tiff) }
        return types
    }

    private func assignImage(_ image: UIImage, to target: WalletSkinTarget) {
        switch target {
        case .singleCard(let cardId):
            engine.setCardImage(for: cardId, image: image)
        case .bulkAll:
            engine.setSkinForAllCards(image: image)
        }
    }

    private func pickSkin(for target: WalletSkinTarget) {
        activeTarget = target
        showSourceDialog = true
    }

    // MARK: - Sections

    private var introCard: some View {
        WTSectionCard(header: "Wallet Cards") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apply custom card art to your Apple Wallet cards on-device. Scan for your cards, attach a skin image to each one, then flash.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Apple Card uses dynamic Metal GPU rendering and cannot have custom static artwork applied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Works on iOS 18.0 – 27.2 beta 2 (iOS 27.2 beta 3 and later patched the exploit).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !engine.hasPairingFile {
                    Text("No pairing file yet. Pair this iPhone first in Sandbox → Utilities → Get Pairing File — scanning and flashing need it.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var scannerCard: some View {
        WTSectionCard(header: "Live Scanner") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        engine.toggleCardScanning()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: engine.isScanningCards ? "stop.circle.fill" : "wave.3.left.circle")
                            Text(engine.isScanningCards ? "Stop Scan" : "Scan Cards")
                        }
                        .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.isScanningCards ? .red : .blue)

                    if engine.isScanningCards {
                        ProgressView()
                    }
                    Spacer()
                    Text("\(engine.cards.count) card\(engine.cards.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !engine.scanStatusText.isEmpty {
                    Text(engine.scanStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var emptyStateCard: some View {
        WTSectionCard {
            VStack(spacing: 14) {
                Image(systemName: "creditcard.viewfinder")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue.opacity(0.8))
                Text("No Cards Detected Yet")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Tap Scan Cards above.")
                    Text("2. On this iPhone, double-click the Side button (Apple Pay), authenticate with Face ID, and tap your card.")
                    Text("3. Your card will appear here automatically!")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Card Manually")
                    }
                    .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var cardsCard: some View {
        WTSectionCard(header: "Cards (\(engine.cards.count))") {
            VStack(spacing: 0) {
                ForEach(engine.cards) { card in
                    WalletCardRow(
                        card: card,
                        onToggleSelected: { engine.setCardSelected(id: card.id, selected: $0) },
                        onPickImage: { pickSkin(for: .singleCard(card.id)) },
                        onClearImage: { engine.clearCardImage(for: card.id) },
                        onDelete: { engine.deleteCard(id: card.id) },
                        onRename: { engine.updateCardName(id: card.id, newName: $0) }
                    )
                    if card.id != engine.cards.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }

    private var actionsCard: some View {
        WTSectionCard(header: "Actions") {
            VStack(spacing: 0) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Card Manually", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider().padding(.leading, 14)

                Button {
                    pickSkin(for: .bulkAll)
                } label: {
                    Label("Set Skin for All Cards…", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider().padding(.leading, 14)

                Button {
                    engine.selectAllCards(true)
                } label: {
                    Label("Select All", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider().padding(.leading, 14)

                Button {
                    engine.selectAllCards(false)
                } label: {
                    Label("Deselect All", systemImage: "circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider().padding(.leading, 14)

                Button(role: .destructive) {
                    engine.clearAllCards()
                } label: {
                    Label("Clear All Cards", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
    }

    private var flashCard: some View {
        WTSectionCard(
            header: "Flash",
            footer: "Force-close the Wallet app from the App Switcher after flashing to see the new card art."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    engine.flashCards()
                } label: {
                    HStack(spacing: 6) {
                        if engine.flashPhase == .running {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.75)
                            Text("Flashing…")
                        } else if engine.flashPhase == .done(ok: false) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Flash")
                        } else {
                            Image(systemName: "bolt.fill")
                            Text("Flash Selected Cards")
                        }
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!engine.canFlashCards || engine.flashPhase == .running)

                if !engine.hasPairingFile {
                    Text("Flashing needs a pairing file. Pair this iPhone first in Sandbox → Utilities → Get Pairing File.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !engine.cards.contains(where: { $0.isSelected && ($0.skinImage != nil || $0.skinData != nil) }) {
                    Text("Select at least one card and attach a skin image to it before flashing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if engine.flashPhase == .running {
                    ProgressView(value: engine.flashProgress)
                }

                if !engine.flashLog.isEmpty {
                    WalletFlashLogView(lines: engine.flashLog) {
                        engine.flashLog.removeAll()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Skin target + crop request

enum WalletSkinTarget: Identifiable {
    case singleCard(String)
    case bulkAll

    var id: String {
        switch self {
        case .singleCard(let id): return id
        case .bulkAll: return "bulk_all"
        }
    }
}

struct WalletCropRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let target: WalletSkinTarget
}

// MARK: - Add card sheet

struct AddWalletCardSheet: View {
    @Binding var hashText: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Card Hash") {
                    TextField("Paste card hash", text: $hashText, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .lineLimit(4...8)
                }
                Section {
                    Text("You can add multiple hashes at once — separate them with spaces, commas, or newlines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd() }
                        .disabled(hashText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Flash log

struct WalletFlashLogView: View {
    let lines: [String]
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Flash Log (\(lines.count) lines)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { onClear() }
                    .font(.caption)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines.indices, id: \.self) { i in
                            Text(lines[i])
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 220)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: lines.count) { _ in
                    if let last = lines.indices.last {
                        withAnimation {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Card row

struct WalletCardRow: View {
    let card: WalletCard
    let onToggleSelected: (Bool) -> Void
    let onPickImage: () -> Void
    let onClearImage: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var renameText: String
    @State private var copied = false

    init(
        card: WalletCard,
        onToggleSelected: @escaping (Bool) -> Void,
        onPickImage: @escaping () -> Void,
        onClearImage: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRename: @escaping (String) -> Void
    ) {
        self.card = card
        self.onToggleSelected = onToggleSelected
        self.onPickImage = onPickImage
        self.onClearImage = onClearImage
        self.onDelete = onDelete
        self.onRename = onRename
        _renameText = State(initialValue: card.displayName ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card art preview (1.586 : 1, same as a real Wallet card)
            ZStack(alignment: .topTrailing) {
                if let img = card.uiImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(1536.0 / 969.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .clear, .black.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        )
                    Button(action: onClearImage) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.95))
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .aspectRatio(1536.0 / 969.0, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        )
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No skin — tap Set Skin below")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        )
                }
            }

            HStack(spacing: 8) {
                Image(systemName: card.network?.iconName ?? "creditcard")
                    .foregroundStyle(.blue)
                Text(card.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { card.isSelected },
                    set: { onToggleSelected($0) }
                ))
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Text(card.id)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    UIPasteboard.general.string = card.id
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.green : Color.secondary)
            }

            TextField("Card name (optional)", text: $renameText, onCommit: {
                onRename(renameText)
            })
            .font(.subheadline)
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button {
                    onPickImage()
                } label: {
                    Label("Set Skin", systemImage: "photo")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Simple card-art cropper
//
// Aircard's CardPhotoCropView source was not available to port, so this
// is a clean-room replacement with the same job: crop the chosen image
// to the 1536:969 card-art aspect (drag to move, pinch to zoom), then
// render exactly 1536x969. No rotation, no aspect change.

struct WalletCardCropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var windowSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: w, height: h)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(magnifyGesture(windowSize: geo.size))
                            .simultaneousGesture(dragGesture(windowSize: geo.size))
                            .onAppear { windowSize = geo.size }
                            .onChange(of: geo.size) { newSize in
                                windowSize = newSize
                            }
                    }
                }
                .aspectRatio(1536.0 / 969.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                )

                Text("Drag to move, pinch to zoom. The skin is saved at 1536×969.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Reset") {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                    .buttonStyle(.bordered)

                    Button("Use Skin") {
                        if let cropped = renderCropped() {
                            onCrop(cropped)
                        } else if let fallback = WalletImageEngine.prepareCardImage(from: image),
                                  let fallbackImage = UIImage(data: fallback) {
                            onCrop(fallbackImage)
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .navigationTitle("Crop Card Skin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func magnifyGesture(windowSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(5.0, max(1.0, lastScale * value))
                offset = clampedOffset(offset, windowSize: windowSize, scale: scale)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
            }
    }

    private func dragGesture(windowSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let next = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(next, windowSize: windowSize, scale: scale)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    /// Keeps the image covering the crop window (no empty edges).
    private func clampedOffset(_ next: CGSize, windowSize: CGSize, scale: CGFloat) -> CGSize {
        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0, windowSize.width > 0, windowSize.height > 0 else { return .zero }
        let cover = max(windowSize.width / imgW, windowSize.height / imgH)
        let dispW = imgW * cover * scale
        let dispH = imgH * cover * scale
        let maxX = max(0, (dispW - windowSize.width) / 2)
        let maxY = max(0, (dispH - windowSize.height) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, next.width)),
            height: min(maxY, max(-maxY, next.height))
        )
    }

    /// Renders exactly what the crop window shows, at 1536x969.
    private func renderCropped() -> UIImage? {
        let w = windowSize.width
        let h = windowSize.height
        let imgW = image.size.width
        let imgH = image.size.height
        guard w > 0, h > 0, imgW > 0, imgH > 0 else { return nil }
        let k: CGFloat = 1536.0 / w
        let cover = max(w / imgW, h / imgH)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1536, height: 969), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: 768 + offset.width * k, y: 484.5 + offset.height * k)
            cg.scaleBy(x: cover * scale * k, y: cover * scale * k)
            image.draw(in: CGRect(x: -imgW / 2, y: -imgH / 2, width: imgW, height: imgH))
        }
    }
}
