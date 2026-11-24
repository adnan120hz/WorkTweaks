import SwiftUI
import UniformTypeIdentifiers

// MARK: - Save Vault page
//
// Stage an app's user data before its sideload certificate
// expires, then restore it after reinstall — matched by
// bundle id, never the old container UUID. Two mechanisms:
// the APFS staging vault (clonefile, zero extra space, atomic
// restore with rollback) and a ZIP backup (Documents +
// Preferences + Application Support). The staging vault lives
// in this app's Documents and does NOT survive uninstalling
// WorkTweaks.

struct SaveVaultView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject private var appData = AppDataManager.shared
    private let vault = SaveVaultManager()

    @State private var selectedBundleID: String?
    @State private var certText = ""
    @State private var certChecking = false
    @State private var walText = ""
    @State private var weChatText = ""
    @State private var isBusy = false
    @State private var busyLabel = ""
    @State private var resultMessage: String?
    @State private var resultIsError = false
    @State private var snapshots: [SaveVaultManifest] = []
    @State private var zipURLToShare: URL?
    @State private var showZipImporter = false
    @State private var restoringBundleID: String?

    private var thirdPartyContainers: [AppContainer] {
        appData.containers.filter { !$0.bundleID.hasPrefix("com.apple.") }
    }

    private var selectedContainer: AppContainer? {
        guard let id = selectedBundleID else { return nil }
        return appData.containers.first { $0.bundleID == id }
    }

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: wtLang.tr("What this does"), footer: wtLang.tr("The staging vault lives in this app's Documents and does NOT survive uninstalling WorkTweaks. Verify a restore in the app first, then release the vault.")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(wtLang.tr("Stage an app's Documents, Library/Preferences and Library/Application Support (never Caches) before its 7-day certificate expires. After reinstall, the data is restored into the app's new container — matched by bundle id, not the old container UUID."))
                    Text(wtLang.tr("APFS vault: clonefile staging, zero extra space, atomic restore with rollback. ZIP backup: the same three folders as one .zip file, restored by merging in place."))
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            WTSectionCard(header: wtLang.tr("Pick an app")) {
                if appData.isScanning {
                    HStack(spacing: 10) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appData.scanPhase)
                                .font(.subheadline)
                            Text(wtLang.tr("The container scan runs once per session."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else if thirdPartyContainers.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(wtLang.tr("No third-party apps found."))
                            .font(.subheadline)
                        Text(wtLang.tr("Open App Data first so the container scan runs, then come back — or tap Rescan."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(wtLang.tr("Rescan")) {
                            appData.rescan()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(thirdPartyContainers.enumerated()), id: \.element.id) { index, container in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            Button {
                                select(container)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(container.bundleID)
                                            .font(.subheadline.weight(selectedBundleID == container.bundleID ? .semibold : .regular))
                                        Text(container.directoryName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if selectedBundleID == container.bundleID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
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

            if let container = selectedContainer {
                WTSectionCard(header: wtLang.tr("Selected app"), footer: container.path) {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(wtLang.tr("Bundle ID"), value: container.bundleID)
                        Divider()
                        LabeledContent(wtLang.tr("Certificate"), value: certChecking ? wtLang.tr("Checking…") : certText)
                        Divider()
                        LabeledContent(wtLang.tr("Database"), value: walText)
                        if !weChatText.isEmpty {
                            Divider()
                            LabeledContent(wtLang.tr("WeChat accounts"), value: weChatText)
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                WTSectionCard(footer: wtLang.tr("Stage copies into the APFS vault (no extra space). ZIP backup copies first, then zips — for very large apps use the APFS vault. Both refuse while the app is still writing its database.")) {
                    VStack(spacing: 10) {
                        Button {
                            stage(container: container)
                        } label: {
                            Text(wtLang.tr(isBusy && busyLabel == "Staging…" ? "Staging…" : "Stage into APFS Vault"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                        .disabled(isBusy)
                        Button {
                            zipBackup(container: container)
                        } label: {
                            Text(wtLang.tr(isBusy && busyLabel == "Backing up…" ? "Backing up…" : "Back Up as ZIP"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                        .disabled(isBusy)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                if let zipURLToShare {
                    WTSectionCard {
                        ShareLink(item: zipURLToShare) {
                            HStack(spacing: 10) {
                                Text(wtLang.tr("Share %@", zipURLToShare.lastPathComponent))
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isBusy {
                WTSectionCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(wtLang.tr(busyLabel))
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            if let resultMessage {
                WTSectionCard {
                    Text(resultMessage)
                        .font(.subheadline)
                        .foregroundStyle(resultIsError ? .orange : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            WTSectionCard(header: wtLang.tr("Staged snapshots"), footer: wtLang.tr("Restore swaps the staged copy into the app's current container and rolls back if anything fails. Release a snapshot only after you verified the restore in the app.")) {
                if snapshots.isEmpty {
                    Text(wtLang.tr("Nothing staged yet."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(snapshots.enumerated()), id: \.element.sourceBundleID) { index, snap in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(snap.sourceBundleID)
                                    .font(.subheadline.weight(.semibold))
                                Text(wtLang.tr("%d file(s) • %@ • staged %@", snap.fileCount, wtFormatSize(snap.logicalBytes), snap.stagedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    Button {
                                        restore(snapshot: snap, targetBundleID: nil)
                                    } label: {
                                        Text(restoringBundleID == snap.sourceBundleID ? wtLang.tr("Restoring…") : wtLang.tr("Restore"))
                                    }
                                    .disabled(isBusy)
                                    Menu(wtLang.tr("Restore into…")) {
                                        ForEach(thirdPartyContainers.filter { $0.bundleID != snap.sourceBundleID }, id: \.id) { target in
                                            Button(target.bundleID) {
                                                restore(snapshot: snap, targetBundleID: target.bundleID)
                                            }
                                        }
                                    }
                                    .disabled(isBusy)
                                    Button(wtLang.tr("Release"), role: .destructive) {
                                        if vault.releaseSnapshot(bundleID: snap.sourceBundleID) {
                                            refreshSnapshots()
                                        }
                                    }
                                    .disabled(isBusy)
                                }
                                .font(.subheadline)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            WTSectionCard(header: wtLang.tr("Restore a ZIP backup"), footer: wtLang.tr("The ZIP must be a Save Vault backup (it carries a BackupManifest.plist). Files merge in place; system bundle ids are blocked.")) {
                Button {
                    showZipImporter = true
                } label: {
                    Text(wtLang.tr("Import ZIP Backup…"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .disabled(isBusy)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle(wtLang.tr("Save Vault"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showZipImporter, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url):
                // Copy into our temp dir while the security
                // scope is held — the restore reads it later,
                // on a background queue, after access ends.
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("vault-restore-\(UUID().uuidString).zip")
                guard (try? FileManager.default.copyItem(at: url, to: tempURL)) != nil else {
                    resultMessage = wtLang.tr("Could not copy that ZIP for restore.")
                    resultIsError = true
                    return
                }
                isBusy = true
                busyLabel = "Restoring ZIP…"
                resultMessage = nil
                vault.zipRestore(zipURL: tempURL) { outcome in
                    isBusy = false
                    try? FileManager.default.removeItem(at: tempURL)
                    switch outcome {
                    case .success(let message):
                        resultMessage = message
                        resultIsError = false
                    case .failure(let message):
                        resultMessage = message.message
                        resultIsError = true
                    }
                }
            case .failure(let error):
                resultMessage = wtLang.tr("Could not open that file: %@", error.localizedDescription)
                resultIsError = true
            }
        }
        .onAppear {
            appData.scanIfNeeded()
            refreshSnapshots()
        }
    }

    private func refreshSnapshots() {
        snapshots = vault.stagedSnapshots()
    }

    private func select(_ container: AppContainer) {
        selectedBundleID = container.bundleID
        resultMessage = nil
        zipURLToShare = nil
        certChecking = true
        certText = ""
        let wal = SaveVaultManager.activeWALFiles(containerPath: container.path)
        walText = wal.isEmpty ? wtLang.tr("Idle") : wtLang.tr("Still writing (%d active WAL file(s)) — close the app first", wal.count)
        let wc = SaveVaultManager.weChatAccountCount(containerPath: container.path)
        weChatText = wc > 0 ? "\(wc)" : ""
        DispatchQueue.global(qos: .userInitiated).async {
            let state = SaveVaultManager.certState(forBundleID: container.bundleID)
            let text: String
            switch state {
            case .ok(let date):
                text = wtLang.tr("Valid until %@", Self.shortDate(date))
            case .expiringSoon(let date):
                text = wtLang.tr("Expires soon — %@. Stage now, reinstall before it ends.", Self.shortDate(date))
            case .expired(let date):
                text = wtLang.tr("Expired %@ — reinstall the app first.", Self.shortDate(date))
            case .unknown:
                text = wtLang.tr("Could not be read")
            }
            DispatchQueue.main.async {
                if selectedBundleID == container.bundleID {
                    certText = text
                    certChecking = false
                }
            }
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func stage(container: AppContainer) {
        isBusy = true
        busyLabel = "Staging…"
        resultMessage = nil
        vault.stage(container: container) { outcome in
            isBusy = false
            switch outcome {
            case .success(let manifest):
                resultMessage = wtLang.tr("Staged %@: %d file(s), %@. Verified against the source.", manifest.sourceBundleID, manifest.fileCount, wtFormatSize(manifest.logicalBytes))
                resultIsError = false
                refreshSnapshots()
            case .failure(let message):
                resultMessage = message.message
                resultIsError = true
            }
        }
    }

    private func zipBackup(container: AppContainer) {
        isBusy = true
        busyLabel = "Backing up…"
        resultMessage = nil
        zipURLToShare = nil
        vault.zipBackup(container: container) { outcome in
            isBusy = false
            switch outcome {
            case .success(let url):
                resultMessage = wtLang.tr("ZIP backup saved: %@. Share it to Files before you uninstall anything.", url.lastPathComponent)
                resultIsError = false
                zipURLToShare = url
            case .failure(let message):
                resultMessage = message.message
                resultIsError = true
            }
        }
    }

    private func restore(snapshot: SaveVaultManifest, targetBundleID: String?) {
        isBusy = true
        busyLabel = "Restoring…"
        restoringBundleID = targetBundleID ?? snapshot.sourceBundleID
        resultMessage = nil
        vault.restore(manifest: snapshot, targetBundleID: targetBundleID) { outcome in
            isBusy = false
            restoringBundleID = nil
            switch outcome {
            case .success(let message):
                resultMessage = message
                resultIsError = false
            case .failure(let message):
                resultMessage = message.message
                resultIsError = true
            }
        }
    }
}
