import SwiftUI
import UIKit
import Combine

// MARK: - Mobile Gestalt.plist viewer + editor (manual Siri AI Cache Patch)
//
// The automatic Siri AI Cache Patch refuses to guess when its
// 51-byte shape matches more than once ("ambiguous"), so the
// patch is manual now: this page shows the on-disk
// MobileGestalt.plist as text — the same lines Filza shows —
// with line numbers, and an editor with a find field so the
// user can jump to line 104 and flip the Siri byte by hand.
//
// Layout is edit-first: the "Open with Text Editor" and
// "Jump to Siri line" actions sit at the TOP of the page, so
// the first thing the user sees is how to edit; the read-only
// lines list lives below them, collapsed behind "View file
// lines". (Before, the editor link sat below a 420pt-tall
// read-only list, so the user never found it and tried typing
// in the read-only lines — which cannot type.)
//
// Typing in the editor is a real UITextView (FindableTextEditor).
// It fills the editor page (.frame maxWidth/maxHeight .infinity —
// a scrolling UITextView reports no intrinsic height, so without
// the frame it can collapse to a strip with nothing to tap) and
// takes focus on open and on "Jump to Siri line", so the
// keyboard is up and the Siri character is selected — the user
// just types over it.
//
// Representation, verified from the engine (GestaltManager):
// the file is read fresh from disk after the session grant
// (MGPaths.gestalt) and serialized to XML with
// PropertyListSerialization — the same serializer the engine's
// own Apply uses (mond serializes as XML), so the lines match
// Filza's view of the same file: CacheData's base64 is wrapped
// at 51 bytes per line and CacheData starts at file line 7, so
// chunk 97 is file line 104. Nothing is assumed, though: the
// viewer COMPUTES the Siri line in its own rendering (the
// base64 line whose 51 bytes match the Siri shape) and
// highlights it, so the line is findable even if the key order
// ever shifts. The flip itself is one base64 character: byte
// 21 of the 51-byte chunk is the first byte of a base64 group,
// so 0x00 -> 0x02 changes the 30th character of that line
// from 'A' to 'g' ("AAAA" -> "AgAA").
//
// Saving parses the edited XML, refuses unless ONLY CacheData
// changed (same length, every other key identical), makes a
// pristine backup before the first save (the hex editor's
// AppDataBackups pattern), then writes through the engine's own
// mgWrite (in-place, verified, rollback on failure) and
// reloads. The on-disk format stays a plist — nothing here
// writes raw text over the file.

/// The manual patch's state, read from the CacheData bytes.
enum SiriPatchState {
    case on, off, ambiguous, moved, notFound, noCacheData

    /// Reads the state from raw CacheData: chunk 97 (the guide's
    /// line 104) first; if its bytes do not match the Siri shape,
    /// the engine's own locator decides whether the patch sits
    /// elsewhere, is ambiguous, or is absent.
    static func current(cacheData: Data?) -> SiriPatchState {
        guard let cacheData else { return .noCacheData }
        let guideOffset = SiriAICachePatch.guideLineChunk * SiriAICachePatch.lineLength
        if guideOffset + SiriAICachePatch.lineLength <= cacheData.count {
            // Data(...) re-bases the slice so chunk[13]/chunk[21]
            // are relative to the chunk, not the whole blob.
            let chunk = Data(cacheData[guideOffset..<(guideOffset + SiriAICachePatch.lineLength)])
            let shapeOK = chunk[13] == 0x01
                && (0..<SiriAICachePatch.lineLength).allSatisfy { $0 == 13 || $0 == 21 || chunk[$0] == 0 }
                && (chunk[21] == 0x00 || chunk[21] == 0x02)
            if shapeOK {
                return chunk[21] == 0x02 ? .on : .off
            }
        }
        let located = SiriAICachePatch.locate(in: cacheData as NSData)
        if located.offset != nil { return .moved }
        if let error = located.error, error.contains("ambiguous") { return .ambiguous }
        return .notFound
    }

    /// One-line state description for the Siri card / viewer.
    func line(wtLang: WTLangStore) -> String {
        switch self {
        case .on:
            return wtLang.tr("The Siri byte is flipped (0x02) — the patch is on.")
        case .off:
            return wtLang.tr("The Siri byte is 0x00 — the patch is off.")
        case .ambiguous:
            return wtLang.tr("The patch pattern matches more than once, so the automatic patch refuses to guess — edit the Siri line by hand.")
        case .moved:
            return wtLang.tr("The patch was found, but not on line 104 — open the viewer to see its line.")
        case .notFound:
            return wtLang.tr("The patch line was not found in this file — check the Mobile Gestalt.plist viewer.")
        case .noCacheData:
            return wtLang.tr("CacheData is missing from MobileGestalt.")
        }
    }

    /// Short badge text for the Siri card.
    func badge(wtLang: WTLangStore) -> String {
        switch self {
        case .on: return wtLang.tr("On")
        case .off: return wtLang.tr("Off")
        default: return wtLang.tr("Manual edit needed")
        }
    }
}

/// The manual guide's steps (English source strings, translated
/// through WTLang like every other user-facing string). Shared
/// by the Siri guide card, the Old UI alert, and Tutorials >
/// Guide C so the three never drift apart.
enum SiriManualGuide {
    static let plistSteps: [String] = [
        "Open \"Mobile Gestalt.plist\" in the Tweaks tab (below the Siri AI Cache Patch card), then tap \"Open with Text Editor\".",
        "Use the find field to jump to line 104 — the viewer shows the exact Siri line number for this device.",
        "On that line, change the 30th base64 character from A to g (this flips CacheData byte 21 from 0x00 to 0x02). To turn the patch off again, change it back from g to A. Then tap Save — a pristine backup is made before the first save.",
    ]

    static let thenLine = "Then turn on Apple Intelligence and the Charge Limit Menu toggle, set Spoofing to iPhone 17 Pro, Apply, respring and restart — Join Waitlist should appear in Settings > Apple Intelligence & Siri."

    /// The full guide as one text (Old UI alert).
    static func fullText(wtLang: WTLangStore) -> String {
        let steps = plistSteps.enumerated()
            .map { "\($0.offset + 1). \(wtLang.tr($0.element))" }
            .joined(separator: "\n")
        return steps + "\n\n" + wtLang.tr(thenLine)
    }
}

// MARK: - Store

final class MobileGestaltPlistStore: ObservableObject {
    @Published var lines: [String] = []
    @Published var isLoading = false
    @Published var loadError: String?
    /// 1-based line number of the Siri chunk in this rendering.
    @Published var siriLine: Int?
    @Published var siriState: SiriPatchState = .noCacheData
    @Published var hasPristineBackup = false
    /// True when the in-memory dict has changes that were never
    /// applied: saving here writes the disk file and drops them.
    @Published var hasUnappliedChanges = false

    private var onDiskDict: NSDictionary?
    private var onDiskCacheData: Data?

    private struct LoadedPlist {
        let dict: NSDictionary
        let cacheData: Data?
        let lines: [String]
        let siriLine: Int?
        let siriState: SiriPatchState
    }

    /// Reads the on-disk file fresh and serializes it to XML
    /// text. The Siri line is the base64 line of CacheData chunk
    /// 97 (line 104 when CacheData starts at file line 7); when
    /// the patch instead sits at another offset, its line is
    /// used, so the highlight is always the real patch line.
    private static func loadFromDisk() throws -> LoadedPlist {
        let raw = try Data(contentsOf: URL(fileURLWithPath: MGPaths.gestalt))
        guard let plist = try PropertyListSerialization.propertyList(from: raw, options: [], format: nil) as? NSDictionary else {
            throw NSError(domain: "mg-plist", code: 1, userInfo: [NSLocalizedDescriptionKey: "The file is not a valid plist."])
        }
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        var text = String(decoding: xml, as: UTF8.self)
        while text.hasSuffix("\n") { text.removeLast() }
        let lines = text.components(separatedBy: "\n")

        // First base64 line of the CacheData block.
        var dataStart: Int?
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "<key>CacheData</key>" {
                var j = i + 1
                while j < lines.count && lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                if j < lines.count && lines[j].trimmingCharacters(in: .whitespaces) == "<data>" {
                    dataStart = j + 1
                }
                break
            }
        }

        let cacheData = plist["CacheData"] as? Data
        let state = SiriPatchState.current(cacheData: cacheData)
        var siriLine: Int?
        if let start = dataStart {
            let structural = start + SiriAICachePatch.guideLineChunk
            if structural < lines.count {
                siriLine = structural + 1 // 1-based
            }
            // When the patch sits elsewhere, highlight its line.
            if state == .moved, let cacheData,
               let offset = SiriAICachePatch.locate(in: cacheData as NSData).offset {
                let moved = start + offset / SiriAICachePatch.lineLength
                if moved < lines.count { siriLine = moved + 1 }
            }
        }
        return LoadedPlist(dict: plist, cacheData: cacheData, lines: lines, siriLine: siriLine, siriState: state)
    }

    func load(manager: GestaltManager) {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Self.loadFromDisk() }
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let loaded):
                    self.applyLoaded(loaded, manager: manager)
                case .failure(let error):
                    self.loadError = error.localizedDescription
                }
            }
        }
    }

    /// Synchronous re-read after a save/restore (the file is
    /// small; called on the main thread from the save path).
    private func refresh(manager: GestaltManager) {
        if let loaded = try? Self.loadFromDisk() {
            applyLoaded(loaded, manager: manager)
        }
    }

    private func applyLoaded(_ loaded: LoadedPlist, manager: GestaltManager) {
        onDiskDict = loaded.dict
        onDiskCacheData = loaded.cacheData
        lines = loaded.lines
        siriLine = loaded.siriLine
        siriState = loaded.siriState
        hasPristineBackup = AppDataManager.shared.hexBackupURL(forSourcePath: MGPaths.gestalt) != nil
        hasUnappliedChanges = !(loaded.dict.isEqual(manager.dictNow))
    }

    /// Saves edited XML text. Returns an error string, or nil on
    /// success. Refuses unless ONLY CacheData changed (same
    /// length, every other key identical) — the editor is for the
    /// Siri byte, not a free-form way to corrupt MobileGestalt.
    func save(editedText: String, manager: GestaltManager) -> String? {
        guard let data = editedText.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil),
              let newDict = plist as? NSDictionary else {
            return "Could not parse the edited text as a plist — nothing was written."
        }
        guard let onDisk = onDiskDict else {
            return "The original file was not loaded — nothing was written."
        }
        guard let newCache = newDict["CacheData"] as? Data,
              let oldCache = onDiskCacheData, newCache.count == oldCache.count else {
            return "CacheData is missing or its length changed — nothing was written. Edits must keep the file the same length."
        }
        for key in onDisk.allKeys {
            guard let k = key as? String, k != "CacheData" else { continue }
            let oldValue = onDisk[k] as? NSObject
            let newValue = newDict[k] as? NSObject
            if oldValue != newValue && !(oldValue?.isEqual(newValue) ?? false) {
                return "Only the CacheData line may change — the '\(k)' value was also edited. Nothing was written."
            }
        }
        for key in newDict.allKeys {
            guard let k = key as? String else { continue }
            if onDisk[k] == nil {
                return "Only the CacheData line may change — a new key '\(k)' was added. Nothing was written."
            }
        }
        guard AppDataManager.shared.makeHexBackupIfNeeded(path: MGPaths.gestalt) else {
            return "Could not make a pristine backup — nothing was written."
        }
        do {
            // mond serializes as XML — the engine's own format.
            let xml = try PropertyListSerialization.data(fromPropertyList: newDict, format: .xml, options: 0)
            try manager.mgWrite(xml)
        } catch {
            return "Write failed: \(error.localizedDescription) — the original file was not changed."
        }
        manager.reloadFromDisk()
        hasPristineBackup = true
        refresh(manager: manager)
        print("(siri-ai) MobileGestalt.plist saved by hand edit; Siri patch is now \(siriState == .on ? "ON" : "OFF")")
        return nil
    }

    /// Writes the pristine backup back through the engine and
    /// reloads. Returns an error string, or nil on success.
    func restorePristineBackup(manager: GestaltManager) -> String? {
        guard let backupURL = AppDataManager.shared.hexBackupURL(forSourcePath: MGPaths.gestalt),
              let data = try? Data(contentsOf: backupURL) else {
            return "No pristine backup found."
        }
        do {
            try manager.mgWrite(data)
        } catch {
            return "Restore failed: \(error.localizedDescription)"
        }
        manager.reloadFromDisk()
        refresh(manager: manager)
        return nil
    }
}

// MARK: - Findable text editor (UITextView: go-to-line + find)

private struct FindRequest: Equatable {
    let query: String
    let direction: Int // +1 next, -1 previous
    let nonce: UUID
}

private struct FindableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var jumpToLine: Int?
    /// When set to a line number, jumps to that line AND selects
    /// its 30th base64 character — the single character the Siri
    /// flip changes ('A' -> 'g'). The user just types over it.
    @Binding var jumpToSiriCharLine: Int?
    @Binding var findRequest: FindRequest?
    @Binding var matchInfo: String
    /// Set to true to bring the keyboard up for the text view
    /// (cleared once served). The editor sets it on open so the
    /// user can type immediately instead of hunting for a tap
    /// target.
    @Binding var focusRequest: Bool

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.spellCheckingType = .no
        tv.backgroundColor = .clear
        tv.keyboardDismissMode = .interactive
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        if focusRequest {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
                self.focusRequest = false
            }
        }
        if let line = jumpToLine {
            context.coordinator.goToLine(line, in: uiView)
            DispatchQueue.main.async { self.jumpToLine = nil }
        }
        if let line = jumpToSiriCharLine {
            context.coordinator.selectSiriChar(line, in: uiView)
            // The character is selected so the user can type over
            // it right away — bring the keyboard up with it.
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
                self.jumpToSiriCharLine = nil
            }
        }
        if let request = findRequest, context.coordinator.lastFindNonce != request.nonce {
            context.coordinator.lastFindNonce = request.nonce
            context.coordinator.find(request, in: uiView)
            DispatchQueue.main.async { self.findRequest = nil }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: FindableTextEditor
        var lastFindNonce: UUID?

        init(_ parent: FindableTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func goToLine(_ line: Int, in textView: UITextView) {
            let lines = textView.text.components(separatedBy: "\n")
            guard line >= 1, line <= lines.count else { return }
            var offset = 0
            for i in 0..<(line - 1) { offset += lines[i].count + 1 }
            let range = NSRange(location: min(offset, textView.text.count), length: 0)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
        }

        /// Selects the single character the Siri flip changes:
        /// the 30th base64 character of the line (byte 21 of the
        /// 51-byte chunk is the first byte of a base64 group, so
        /// 0x00 -> 0x02 changes only that character, 'A' -> 'g').
        /// Leading whitespace is skipped; the line must hold at
        /// least 30 base64 characters or nothing is selected.
        func selectSiriChar(_ line: Int, in textView: UITextView) {
            let lines = textView.text.components(separatedBy: "\n")
            guard line >= 1, line <= lines.count else { return }
            let lineText = lines[line - 1]
            let content = lineText.trimmingCharacters(in: .whitespaces)
            guard content.count > 29 else { return }
            var offset = 0
            for i in 0..<(line - 1) { offset += lines[i].count + 1 }
            let leading = lineText.prefix(while: { $0 == " " || $0 == "\t" }).count
            let charOffset = offset + leading + 29
            guard charOffset < textView.text.count else { return }
            let range = NSRange(location: charOffset, length: 1)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
        }

        func find(_ request: FindRequest, in textView: UITextView) {
            guard !request.query.isEmpty else { return }
            let haystack = textView.text as NSString
            var ranges: [NSRange] = []
            var search = NSRange(location: 0, length: haystack.length)
            while search.location < haystack.length {
                let found = haystack.range(of: request.query, options: .caseInsensitive, range: search)
                if found.location == NSNotFound { break }
                ranges.append(found)
                let next = found.location + max(found.length, 1)
                if next >= haystack.length { break }
                search = NSRange(location: next, length: haystack.length - next)
            }
            let current = textView.selectedRange.location
            let target: NSRange?
            if request.direction >= 0 {
                target = ranges.first(where: { $0.location > current }) ?? ranges.first
            } else {
                target = ranges.last(where: { $0.location < current }) ?? ranges.last
            }
            let info: String
            if ranges.isEmpty {
                info = L("No matches")
            } else if let target {
                let index = (ranges.firstIndex(of: target) ?? 0) + 1
                info = String(format: L("%d of %d matches"), index, ranges.count)
            } else {
                info = "\(ranges.count) matches"
            }
            DispatchQueue.main.async { self.parent.matchInfo = info }
            if let target {
                textView.selectedRange = target
                textView.scrollRangeToVisible(target)
            }
        }
    }
}

// MARK: - Viewer

struct MobileGestaltPlistView: View {
    @ObservedObject var manager: GestaltManager
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var store = MobileGestaltPlistStore()
    @State private var showRestoreConfirm = false
    @State private var restoreMessage: String?

    var body: some View {
        WTGlassPage {
            if store.isLoading && store.lines.isEmpty {
                WTSectionCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(wtLang.tr("Loading MobileGestalt.plist…"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            } else if let error = store.loadError {
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(wtLang.tr("MobileGestalt could not be loaded."))
                            .font(.subheadline.weight(.semibold))
                        Text(error)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(wtLang.tr("Reload MobileGestalt")) {
                            SoundEffects.playTap()
                            manager.load()
                            store.load(manager: manager)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            } else {
                // Edit-first: the actions are the first thing on
                // the page; the read-only lines sit below them,
                // collapsed, so nothing buries the way to type.
                editCard
                stateCard
                linesDisclosure

                if store.hasPristineBackup {
                    Button {
                        SoundEffects.playTap()
                        showRestoreConfirm = true
                    } label: {
                        HStack(spacing: 8) {
                            RowIcon(systemImage: "arrow.counterclockwise")
                            Text(wtLang.tr("Restore Pristine Backup"))
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wtGlassCard(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Mobile Gestalt.plist")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.lines.isEmpty && store.loadError == nil {
                store.load(manager: manager)
            }
        }
        .onChange(of: manager.isValid) { valid in
            if valid && store.lines.isEmpty {
                store.load(manager: manager)
            }
        }
        .confirmationDialog(wtLang.tr("Restore Pristine Backup"), isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button(wtLang.tr("Restore")) {
                if let error = store.restorePristineBackup(manager: manager) {
                    restoreMessage = error
                } else {
                    restoreMessage = wtLang.tr("Pristine backup restored.")
                }
            }
            Button(wtLang.tr("Cancel"), role: .cancel) { }
        } message: {
            Text(wtLang.tr("Restore the pristine backup made before the first save?"))
        }
        .alert(wtLang.tr("Restore Pristine Backup"), isPresented: Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button(wtLang.tr("OK")) { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    /// The edit actions, first on the page. Two full-width
    /// rows, one under the other: side by side they do not fit —
    /// both labels together are ~410pt wide against ~315pt of
    /// card width on his phone, so a row would truncate.
    private var editCard: some View {
        WTSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(wtLang.tr("Edit the Siri line"))
                    .font(.subheadline.weight(.semibold))
                Text(wtLang.tr("Change one character on the Siri line to flip the patch — you don't need to read the whole file."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    MobileGestaltPlistEditorView(store: store, manager: manager)
                } label: {
                    Label(wtLang.tr("Open with Text Editor"), systemImage: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                if let line = store.siriLine {
                    NavigationLink {
                        MobileGestaltPlistEditorView(store: store, manager: manager, jumpToSiriLineOnOpen: line)
                    } label: {
                        Label(wtLang.tr("Jump to Siri line"), systemImage: "arrow.down.to.line")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private var stateCard: some View {
        WTSectionCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(wtLang.tr("Siri AI Cache Patch"))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(store.siriState.badge(wtLang: wtLang))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.siriState == .on ? .green : store.siriState == .off ? .secondary : .orange)
                }
                Text(store.siriState.line(wtLang: wtLang))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = store.siriLine {
                    Text(wtLang.tr("Siri line: line %d", line))
                        .font(.caption.weight(.semibold))
                    if line != SiriAICachePatch.guideLineChunk + 7 {
                        Text(wtLang.tr("On this device the Siri line is line %d, not 104 — the guide's line number varies by device.", line))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if store.hasUnappliedChanges {
                    Text(wtLang.tr("Unapplied changes in the Tweaks tab will be lost when you save here — Apply them first."))
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    /// The read-only lines, collapsed by default: the list is
    /// reference, not the way to edit, so it must not push the
    /// edit actions off the screen. Expanding it scrolls to the
    /// highlighted Siri line, as before.
    private var linesDisclosure: some View {
        WTSectionCard {
            DisclosureGroup {
                Text(wtLang.tr("This is the same text Filza shows for this file. CacheData is the long base64 block; its lines are 51 bytes each. The Siri line is highlighted."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(store.lines.enumerated()), id: \.offset) { index, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                    Text(line.isEmpty ? " " : line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .id(index + 1)
                                .padding(.horizontal, 6)
                                .background(store.siriLine == index + 1 ? Color.accentColor.opacity(0.18) : Color.clear)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 420)
                    .onAppear {
                        if let line = store.siriLine {
                            DispatchQueue.main.async {
                                proxy.scrollTo(line, anchor: .top)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    RowIcon(systemImage: "list.bullet")
                    Text(wtLang.tr("View file lines"))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}

// MARK: - Editor

struct MobileGestaltPlistEditorView: View {
    @ObservedObject var store: MobileGestaltPlistStore
    @ObservedObject var manager: GestaltManager
    @EnvironmentObject private var wtLang: WTLangStore
    @Environment(\.dismiss) private var dismiss

    /// When set, the editor opens already jumped to this line's
    /// Siri character, keyboard up — the viewer passes the Siri
    /// line for its "Jump to Siri line" button. Nil opens the
    /// plain editor (keyboard still comes up: the page is for
    /// typing). No default here: a `let` with a default cannot
    /// be assigned again in init, so the init below (default nil)
    /// is the only place it is set.
    let jumpToSiriLineOnOpen: Int?

    @State private var editedText: String = ""
    @State private var findText = ""
    @State private var lineField = ""
    @State private var jumpToLine: Int?
    @State private var jumpToSiriCharLine: Int?
    @State private var findRequest: FindRequest?
    @State private var matchInfo = ""
    @State private var focusEditor = false
    @State private var showSaveConfirm = false
    @State private var saveMessage: String?
    @State private var saveSucceeded = false

    /// Explicit init: the synthesized memberwise init only takes
    /// the two properties without defaults (store, manager), so
    /// the jump-on-open parameter needs its own init.
    init(store: MobileGestaltPlistStore, manager: GestaltManager, jumpToSiriLineOnOpen: Int? = nil) {
        self.store = store
        self.manager = manager
        self.jumpToSiriLineOnOpen = jumpToSiriLineOnOpen
    }

    var body: some View {
        VStack(spacing: 0) {
            findBar
            Divider()
            FindableTextEditor(text: $editedText, jumpToLine: $jumpToLine, jumpToSiriCharLine: $jumpToSiriCharLine, findRequest: $findRequest, matchInfo: $matchInfo, focusRequest: $focusEditor)
                // A scrolling UITextView reports no intrinsic
                // height, so without this the editor can collapse
                // to a strip with nothing to tap — the fill makes
                // the whole page below the find bar typable.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)
            footerBar
        }
        .navigationTitle("Mobile Gestalt.plist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(wtLang.tr("Save")) {
                    SoundEffects.playTap()
                    showSaveConfirm = true
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .onAppear {
            if editedText.isEmpty {
                editedText = store.lines.joined(separator: "\n")
                if let line = store.siriLine {
                    lineField = "\(line)"
                }
            }
            if let line = jumpToSiriLineOnOpen {
                jumpToSiriCharLine = line
            }
            // The page is for typing: keyboard up on open so the
            // user never has to discover the tap target.
            focusEditor = true
        }
        .confirmationDialog(wtLang.tr("Save the edited file?"), isPresented: $showSaveConfirm, titleVisibility: .visible) {
            Button(wtLang.tr("Save")) {
                if let error = store.save(editedText: editedText, manager: manager) {
                    saveSucceeded = false
                    saveMessage = error
                } else {
                    saveSucceeded = true
                    switch store.siriState {
                    case .on:
                        saveMessage = wtLang.tr("Saved — the Siri patch is now %@.", wtLang.tr("On"))
                    case .off:
                        saveMessage = wtLang.tr("Saved — the Siri patch is now %@.", wtLang.tr("Off"))
                    default:
                        saveMessage = wtLang.tr("Saved — the file was written, but the Siri line does not match the patch shape.")
                    }
                }
            }
            Button(wtLang.tr("Cancel"), role: .cancel) { }
        } message: {
            Text(wtLang.tr("A pristine backup is made before the first save, and only CacheData changes are written."))
        }
        .alert("Mobile Gestalt.plist", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button(wtLang.tr("OK")) {
                saveMessage = nil
                if saveSucceeded { dismiss() }
            }
        } message: {
            Text(saveMessage ?? "")
        }
    }

    private var findBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(wtLang.tr("Find…"), text: $findText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { submitFind(direction: 1) }
                if !matchInfo.isEmpty {
                    Text(matchInfo)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    submitFind(direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                Button {
                    submitFind(direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text(wtLang.tr("Go to line"))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(wtLang.tr("Line number"), text: $lineField)
                    .keyboardType(.numberPad)
                    .font(.subheadline.monospacedDigit())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                Button(wtLang.tr("Go")) {
                    if let line = Int(lineField) {
                        jumpToLine = line
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                if let line = store.siriLine {
                    Button(wtLang.tr("Jump to Siri line")) {
                        lineField = "\(line)"
                        jumpToSiriCharLine = line
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider()
            Text(wtLang.tr("Going back discards unsaved edits."))
                .font(.caption).foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    private func submitFind(direction: Int) {
        guard !findText.isEmpty else { return }
        findRequest = FindRequest(query: findText, direction: direction, nonce: UUID())
    }
}

// MARK: - Siri guide card (New UI) + menu row

/// The Siri AI Cache Patch card, manual now: no toggle (the
/// automatic pattern is ambiguous on some devices), just the
/// current state, the Read Tutorial steps, and a button into
/// the Mobile Gestalt.plist viewer.
struct SiriGuideCard: View {
    @ObservedObject var manager: GestaltManager
    @EnvironmentObject private var wtLang: WTLangStore
    @State private var expanded = false

    private var state: SiriPatchState {
        SiriPatchState.current(cacheData: manager.dictNow["CacheData"] as? Data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                RowIcon(systemImage: "sparkles")
                Spacer(minLength: 0)
                Text(state.badge(wtLang: wtLang))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state == .on ? .green : state == .off ? .secondary : .orange)
            }
            Text("Siri AI Cache Patch")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(state.line(wtLang: wtLang))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SoundEffects.playTap()
                expanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(wtLang.tr("Read Tutorial"))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(SiriManualGuide.plistSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(wtLang.tr(step))
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(wtLang.tr(SiriManualGuide.thenLine))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink {
                        MobileGestaltPlistView(manager: manager)
                    } label: {
                        Label(wtLang.tr("Open Mobile Gestalt.plist"), systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtGlassCard(cornerRadius: 14)
    }
}

/// The "Mobile Gestalt.plist" menu row, placed directly below
/// the Siri AI Cache Patch card (New UI + search results).
struct MobileGestaltPlistMenuRow: View {
    @ObservedObject var manager: GestaltManager
    @EnvironmentObject private var wtLang: WTLangStore

    var body: some View {
        NavigationLink {
            MobileGestaltPlistView(manager: manager)
        } label: {
            HStack(spacing: 8) {
                RowIcon(systemImage: "doc.text")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mobile Gestalt.plist")
                        .font(.subheadline.weight(.semibold))
                    Text(wtLang.tr("View and edit the file with line numbers."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wtGlassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}
