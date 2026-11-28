import SwiftUI
import UniformTypeIdentifiers

// MARK: - PosterBoard page
//
// Import .tendies wallpaper packages into PosterBoard's
// data store and remove the wallpapers imported here. All
// work goes through PosterBoardManager (container resolution
// from the shared App Data scan, one sandbox extension on
// the container per operation, verified copies, import
// receipts). Resolution, import, and delete all end in an
// honest status; a successful import or delete offers the
// app's standard respring prompt, because SpringBoard only
// reloads the wallpaper store when it (re)starts.
//
// Three import methods (v8.0): Normal (the v7.0 import),
// Flake (Squair's Flake method — also finds MercuryPoster
// descriptors and keeps their identifiers), and Via Airlift
// (the copy step through the Airlift exploit, pairing + VPN
// transport, iOS 26.0 .. 27.2 beta 2). Normal and Flake run
// on iOS 26.0 .. 27.3 beta 1; on 27.3 beta 2+ the escape is
// patched and the page shows the honest blocked state —
// there is no flake fix for 27.3 beta 2 or later.
//
// The page renders as Liquid Glass cards (WTGlassPage /
// WTSectionCard), like every other page since v3.8.

struct PosterBoardView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var manager = PosterBoardManager()
    @ObservedObject private var appData = AppDataManager.shared

    @State private var method: PosterBoardMethod = .normal
    @State private var transportStatus = TransportGate.check()
    @State private var showImporter = false
    @State private var showRespringChoice = false
    @State private var showManualRestartGuide = false
    @State private var pendingDelete: PosterBoardReceipt?
    @State private var pickerError: String?

    private var packageContentTypes: [UTType] {
        var types: [UTType] = [.zip]
        if let tendies = UTType(filenameExtension: "tendies", conformingTo: .data) {
            types.insert(tendies, at: 0)
        }
        types.append(.data)
        return types
    }

    var body: some View {
        WTGlassPage {
            statusCard

            if let result = manager.lastResult {
                WTSectionCard {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            if case .ready = manager.state {
                methodCard

                if method == .airlift, !transportStatus.isReady {
                    TransportGateCard(status: transportStatus) {
                        transportStatus = TransportGate.check()
                    }
                }

                WTSectionCard(header: wtLang.tr("Import"), footer: wtLang.tr("Each wallpaper in the package is copied into PosterBoard's data store under a fresh identifier, so it can never clash with an existing wallpaper. A respring is required before a new wallpaper appears in the gallery.")) {
                    Button {
                        showImporter = true
                    } label: {
                        HStack(spacing: 10) {
                            Label(wtLang.tr("Import .tendies Package…"), systemImage: "shippingbox")
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            if manager.isBusy {
                                ProgressView()
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isBusy || !methodAvailable || (method == .airlift && !transportStatus.isReady))
                }

                WTSectionCard(header: wtLang.tr("Create"), footer: wtLang.tr("Builds a PosterBoard wallpaper on-device from your photo or video — the same descriptor format as an imported .tendies package, installed and listed exactly like one.")) {
                    NavigationLink {
                        PosterBoardMakerView(manager: manager)
                    } label: {
                        HStack(spacing: 10) {
                            Label(wtLang.tr("Create Wallpaper…"), systemImage: "wand.and.stars")
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isBusy)
                }

                WTSectionCard(header: wtLang.tr("Imported")) {
                    if manager.receipts.isEmpty {
                        Text(wtLang.tr("No wallpapers imported yet. Wallpapers imported here are listed so you can remove them again — wallpapers added any other way are never touched."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(manager.receipts.enumerated()), id: \.element.id) { index, receipt in
                                if index > 0 {
                                    Divider().padding(.leading, 14)
                                }
                                importedRow(receipt)
                            }
                        }
                    }
                }

                WTSectionCard(header: wtLang.tr("Package Format")) {
                    Text(wtLang.tr("A .tendies package is a ZIP archive containing one or more wallpaper descriptors: loose descriptor folders, a descriptors folder, or a container layout mirroring PosterBoard's data store (Library/Application Support/PRBPosterExtensionDataStore/…/Extensions/…/descriptors). Stored and deflated ZIP entries are supported — the same reader Deploy uses; encrypted and ZIP64 archives are rejected."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        }
        // Status, result and receipt rows animate in/out
        // instead of snapping (v8.0 menu motion).
        .animation(.wtMenu, value: manager.lastResult != nil)
        .animation(.wtMenu, value: manager.receipts.count)
        .animation(.wtMenu, value: manager.isBusy)
        .navigationTitle("PosterBoard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.loadReceipts()
            transportStatus = TransportGate.check()
            kickResolution()
        }
        .onChange(of: method) { _, _ in
            transportStatus = TransportGate.check()
        }
        .onChange(of: appData.didScan) { _, done in
            if done { manager.resolve() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: packageContentTypes) { result in
            switch result {
            case .success(let url):
                switch method {
                case .normal:
                    manager.importPackage(url: url, method: .normal) { ok in
                        if ok { showRespringChoice = true }
                    }
                case .flake:
                    manager.importPackage(url: url, method: .flake) { ok in
                        if ok { showRespringChoice = true }
                    }
                case .airlift:
                    manager.importViaAirlift(url: url) { ok in
                        if ok { showRespringChoice = true }
                    }
                }
            case .failure(let error):
                pickerError = error.localizedDescription
            }
        }
        .alert(wtLang.tr("Import Failed"), isPresented: Binding(
            get: { pickerError != nil },
            set: { if !$0 { pickerError = nil } }
        )) {
            Button(wtLang.tr("OK")) { }
        } message: {
            Text(pickerError ?? "")
        }
        .confirmationDialog(wtLang.tr("PosterBoard Updated"), isPresented: $showRespringChoice, titleVisibility: .visible) {
            Button(wtLang.tr("Respring")) { RespringCenter.shared.trigger() }
            Button(wtLang.tr("Restart Device")) { showManualRestartGuide = true }
            Button(wtLang.tr("Later"), role: .cancel) { }
        } message: {
            Text(wtLang.tr("SpringBoard loads the wallpaper store when it starts — respring or restart to see the change in the wallpaper gallery."))
        }
        .alert(ManualRestartGuide.title, isPresented: $showManualRestartGuide) {
            Button(wtLang.tr("OK")) { }
        } message: {
            Text(ManualRestartGuide.message)
        }
        .confirmationDialog(wtLang.tr("Delete Wallpaper?"), isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button(wtLang.tr("Delete"), role: .destructive) {
                if let receipt = pendingDelete {
                    manager.delete(receipt: receipt) { ok in
                        if ok { showRespringChoice = true }
                    }
                }
                pendingDelete = nil
            }
            Button(wtLang.tr("Cancel"), role: .cancel) { }
        } message: {
            Text(wtLang.tr("This removes the wallpaper imported from %@ — its descriptor folder is deleted from PosterBoard's data store.", pendingDelete?.sourcePackage ?? wtLang.tr("the package")))
        }
    }

    // MARK: Status card

    @ViewBuilder
    private var statusCard: some View {
        switch manager.state {
        case .idle, .resolving:
            WTSectionCard(header: wtLang.tr("PosterBoard Data")) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(appData.isScanning ? appData.scanPhase : manager.resolvePhase)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        case .blocked(let reason):
            WTSectionCard(footer: wtLang.tr("Nothing was written.")) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(wtLang.tr("PosterBoard is unavailable"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 14)

                    Button {
                        kickResolution()
                    } label: {
                        Text(wtLang.tr("Try Again"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .ready:
            WTSectionCard(header: wtLang.tr("PosterBoard Data")) {
                VStack(alignment: .leading, spacing: 6) {
                    infoRow(wtLang.tr("Container"), manager.containerPath.map { ($0 as NSString).lastPathComponent } ?? "—")
                    infoRow(wtLang.tr("Data Store"), wtLang.tr("Version %@", manager.storeVersion ?? "—"))
                    infoRow(wtLang.tr("Descriptors"), "\(manager.descriptorCount)")
                    if let containerPath = manager.containerPath {
                        Text(containerPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    /// One label/value line of the status card.
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }

    // MARK: Imported rows

    private func importedRow(_ receipt: PosterBoardReceipt) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.sourcePackage)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(receipt.descriptorUUID)\(receipt.ext == PosterBoardManager.mercuryExtension ? " • MercuryPoster" : "") • \(Self.displayDate(receipt.importedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                pendingDelete = receipt
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(manager.isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private static func displayDate(_ iso8601: String) -> String {
        if let date = ISO8601DateFormatter().date(from: iso8601) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return iso8601
    }

    // MARK: Resolution kick

    /// Start (or wait for) the shared App Data scan, then
    /// resolve — the same pattern Deploy uses: the scan runs
    /// once per app session and its results are shared.
    private func kickResolution() {
        // iOS 27.3 beta 2+ (worse_query patched): neither the
        // escape methods nor Airlift can run — show the honest
        // blocked state instead of a confusing "container not
        // found". There is no flake fix for 27.3 beta 2+.
        if SupportInfo.posterBoardEscapeGate == .aboveMaximum,
           SupportInfo.posterBoardAirliftGate == .aboveMaximum {
            manager.state = .blocked(wtLang.tr("PosterBoard import is blocked on this iOS version — worse_query was patched in iOS 27.3 beta 2, and no Flake fix exists for iOS 27.3 beta 2 or later."))
            return
        }
        if appData.didScan {
            manager.resolve()
        } else {
            manager.noteWaitingForScan()
            if !appData.isScanning {
                appData.rescan()
            }
        }
    }

    // MARK: Method picker

    /// Whether the currently selected method is offered on
    /// this device. The Import button stays disabled otherwise.
    private var methodAvailable: Bool {
        switch method {
        case .normal, .flake:
            return SupportInfo.posterBoardEscapeAvailable
        case .airlift:
            return SupportInfo.posterBoardAirliftAvailable
        }
    }

    private var methodCard: some View {
        WTSectionCard(header: wtLang.tr("PosterBoard Method")) {
            VStack(alignment: .leading, spacing: 0) {
                methodRow(.normal)
                Divider().padding(.leading, 14)
                methodRow(.flake)
                Divider().padding(.leading, 14)
                methodRow(.airlift)
            }
        }
    }

    /// One PosterBoard Method option row: title, supported iOS
    /// range, what it does, and — when the gate closes it —
    /// the honest reason, in orange. Unavailable options
    /// cannot be selected. (DeployView's methodRow pattern.)
    private func methodRow(_ option: PosterBoardMethod) -> some View {
        let gate = option == .airlift ? SupportInfo.posterBoardAirliftGate : SupportInfo.posterBoardEscapeGate
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
                        Text(wtLang.tr(methodTitle(option)))
                            .font(.subheadline.weight(.semibold))
                        if !available {
                            Text(wtLang.tr("Not available on this iOS version"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(methodRange(option))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(wtLang.tr(methodDescription(option)))
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

    private func methodTitle(_ option: PosterBoardMethod) -> String {
        switch option {
        case .normal: return "Normal"
        case .flake: return "Flake (MercuryPoster)"
        case .airlift: return "Via Airlift"
        }
    }

    private func methodRange(_ option: PosterBoardMethod) -> String {
        option == .airlift ? "iOS 26.0 – iOS 27.2 beta 2" : "iOS 26.0 – iOS 27.3 beta 1"
    }

    private func methodDescription(_ option: PosterBoardMethod) -> String {
        switch option {
        case .normal:
            return "The current import — descriptors from any extension in the package, with fresh identifiers."
        case .flake:
            return "Flake's method — also finds MercuryPoster descriptors anywhere in the package and keeps their original identifiers."
        case .airlift:
            return "Writes the descriptors through the Airlift exploit over the pairing + VPN tunnel. The transport below must be ready first. Descriptor folders are staged with their subfolders as-is."
        }
    }

    /// The user-facing reason a PosterBoard method is gated off
    /// on this device.
    private func gateReason(_ option: PosterBoardMethod, _ gate: SupportInfo.DeployGate) -> String {
        switch gate {
        case .available:
            return ""
        case .belowMinimum:
            return wtLang.tr("Requires iOS 26.0 or later.")
        case .aboveMaximum:
            return option == .airlift
                ? wtLang.tr("Blocked above iOS 27.2 beta 2.")
                : wtLang.tr("Blocked above iOS 27.3 beta 1 — worse_query is patched in iOS 27.3 beta 2.")
        case .unknownBuild:
            return wtLang.tr("Could not read this iPhone's iOS build number.")
        }
    }
}
