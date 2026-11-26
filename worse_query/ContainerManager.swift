import Combine
import Foundation
import Compression

// MARK: - Install IPA on Container (Phase 2 host)
//
// Guest apps ("containers") live in the WorkTweaks App Group,
// mirroring LiveContainer's layout
// (LiveContainerSwiftUI/Utilities/Shared.swift: LCPath):
//   <group>/LiveContainer/Applications/<bundle-id>.app  (guest bundle)
//   <group>/LiveContainer/Data/Application/<uuid>/      (guest data container)
//   <group>/LiveContainer/Tweaks/                      (TweakLoader symlink target)
// The only difference from stock LiveContainer is the group
// itself: LC resolves SideStore/AltStore groups first, WorkTweaks
// resolves its own group via AppGroupResolver.
//
// Phase 2 CAN: list guests, import a decrypted .ipa, patch the
// executable (LCContainerPatch — LCMachOUtils, currentPatchRev 7),
// sign the guest with an imported .p12 certificate (ZSigner,
// called directly), and launch it JIT-less (LiveContainerMain).
// Guests installed before any certificate was stored are
// re-signed on demand (LC parity: validate first, sign only
// when invalid) when a certificate is stored or at launch, so
// they do not need delete + re-import.
// The JIT toggle stays OFF/disabled until the Phase 3 JIT session
// exists; no fake "JIT on" anywhere. A certificate is required
// to launch on iOS 26+ (LCBootstrap refuses without one), so
// launch is honest about that: no cert, no launch.
// Encrypted IPAs are still refused; 32-bit guests are refused
// (they need JIT + classic mode, Phase 3).

/// One installed guest app.
struct ContainerGuest: Identifiable {
    /// LC's current patch revision (LCAppInfo.m): a guest is
    /// patched when its stored revision reaches this.
    static let currentPatchRevision = 7

    let bundleID: String
    let displayName: String
    let version: String
    let executableName: String
    /// Folder name inside Applications/, "<bundle-id>.app".
    let folderName: String
    let bundlePath: String
    let dataUUID: String
    /// -1 = installed but never patched; 7 = patched (current).
    let patchRevision: Int
    /// Set by the patch step (LCAppInfo.plist "is32bit"): 32-bit
    /// guests need JIT + classic mode (Phase 3), so they install
    /// but never launch here.
    let is32bit: Bool
    /// Set when a sign with the stored certificate succeeded
    /// (LCAppInfo.plist "WTSigned").
    let signed: Bool
    let installedAt: Date?

    var id: String { bundleID }
    var isPatched: Bool { patchRevision >= Self.currentPatchRevision }
    /// Launchable JIT-less: patched, 64-bit, and signed. (The
    /// cert gate lives in LCBootstrap: on iOS 26+ launch is
    /// refused outright without a certificate.)
    var isLaunchable: Bool { isPatched && !is32bit && signed }
    /// Launchable with JIT: patched, 64-bit, and (signed OR a
    /// certificate is stored). LiveContainer's iOS 26 gate only
    /// checks a certificate IS stored, not that the guest's
    /// signature validates against the host's team — once the
    /// debugger attaches, init_bypassDyldLibValidation lets the
    /// guest load. JIT-less launch still needs `isLaunchable`.
    var isJITLaunchable: Bool { isPatched && !is32bit && (signed || LCContainerPatch.hasCertificate()) }
}

enum ContainerError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

final class ContainerManager: ObservableObject {
    static let shared = ContainerManager()

    @Published private(set) var guests: [ContainerGuest] = []
    @Published private(set) var isBusy = false
    @Published private(set) var lastResult: String?

    private let fm = FileManager.default

    // MARK: Paths

    /// <group>/LiveContainer — nil when the App Group container
    /// does not resolve, in which case every operation refuses
    /// honestly instead of writing somewhere wrong.
    static func liveContainerRoot() -> URL? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupResolver.resolvedGroup) else {
            print("[Container] App Group container unavailable — no LiveContainer root.")
            return nil
        }
        return groupURL.appendingPathComponent("LiveContainer", isDirectory: true)
    }

    private func applicationsDir() -> URL? {
        ContainerManager.liveContainerRoot()?.appendingPathComponent("Applications", isDirectory: true)
    }

    private func dataDir() -> URL? {
        ContainerManager.liveContainerRoot()?.appendingPathComponent("Data/Application", isDirectory: true)
    }

    private func ensureRoots() throws -> (apps: URL, data: URL) {
        guard let root = ContainerManager.liveContainerRoot(),
              let apps = applicationsDir(), let data = dataDir() else {
            throw ContainerError.message("The App Group container could not be opened, so no guest can be stored.")
        }
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Tweaks", isDirectory: true), withIntermediateDirectories: true)
        return (apps, data)
    }

    // MARK: List

    /// Re-read the installed guests from disk.
    func refresh() {
        guard let apps = applicationsDir() else {
            guests = []
            return
        }
        var found: [ContainerGuest] = []
        for folder in (try? fm.contentsOfDirectory(atPath: apps.path)) ?? [] {
            guard folder.hasSuffix(".app") else { continue }
            let bundlePath = apps.appendingPathComponent(folder).path
            guard let plist = NSDictionary(contentsOfFile: (bundlePath as NSString).appendingPathComponent("Info.plist")) as? [String: Any],
                  let bundleID = plist["CFBundleIdentifier"] as? String,
                  let executable = plist["CFBundleExecutable"] as? String else {
                print("[Container] skipping \(folder) — no readable Info.plist.")
                continue
            }
            let info = NSDictionary(contentsOfFile: (bundlePath as NSString).appendingPathComponent("LCAppInfo.plist")) as? [String: Any]
            let displayName = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? executable
            found.append(ContainerGuest(
                bundleID: bundleID,
                displayName: displayName,
                version: (plist["CFBundleShortVersionString"] as? String) ?? "—",
                executableName: executable,
                folderName: folder,
                bundlePath: bundlePath,
                dataUUID: (info?["LCDataUUID"] as? String) ?? "",
                patchRevision: (info?["LCPatchRevision"] as? Int) ?? -1,
                is32bit: (info?["is32bit"] as? Bool) ?? false,
                signed: (info?["WTSigned"] as? Bool) ?? false,
                installedAt: info?["installationDate"] as? Date
            ))
        }
        guests = found.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        print("[Container] listed \(guests.count) guest(s).")
    }

    // MARK: Install

    /// Install one .ipa: unzip, validate, encryption check,
    /// store the bundle, write LCAppInfo.plist, create the data
    /// container. Runs on the calling task; the view wraps it in
    /// a Task and shows isBusy. Throws ContainerError with a
    /// user-facing message on every failure; nothing is left
    /// half-installed (the staging folder and any partial
    /// destination are removed again).
    func installIPA(from url: URL) async throws -> ContainerGuest {
        await MainActor.run { isBusy = true; lastResult = nil }
        defer { Task { @MainActor in self.isBusy = false } }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ContainerError.message("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
        }
        print("[Container] installing \(url.lastPathComponent) (\(data.count) bytes).")

        let staging = fm.temporaryDirectory.appendingPathComponent("container-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        // Set once the bundle has been moved: any later failure
        // removes it again, so a failed install never leaves a
        // broken guest behind.
        var installedDestination: URL?
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try ContainerZip.extract(data: data, to: staging)

            // Payload/*.app — the first .app in Payload, like LC.
            let payload = staging.appendingPathComponent("Payload", isDirectory: true)
            let payloadContents = try fm.contentsOfDirectory(atPath: payload.path)
            guard let appFolderName = payloadContents.first(where: { $0.hasSuffix(".app") }) else {
                throw ContainerError.message("No .app bundle found in the IPA (Payload/*.app is missing).")
            }
            let stagedApp = payload.appendingPathComponent(appFolderName)

            guard let plist = NSDictionary(contentsOfFile: stagedApp.appendingPathComponent("Info.plist").path) as? [String: Any],
                  let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty,
                  let executable = plist["CFBundleExecutable"] as? String, !executable.isEmpty else {
                throw ContainerError.message("The .app bundle has no readable Info.plist (CFBundleIdentifier / CFBundleExecutable missing).")
            }
            let displayName = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? executable
            let version = (plist["CFBundleShortVersionString"] as? String) ?? "—"

            // Encryption check on the executable (LCAppInfo.m:
            // encrypted guests are rejected with exactly this
            // message). A missing arm64 slice is also refused:
            // 32-bit guests need JIT + classic mode (Phase 3).
            let executableURL = stagedApp.appendingPathComponent(executable)
            let machO: ContainerMachO.SliceInfo
            do {
                machO = try ContainerMachO.inspect(executableURL: executableURL)
            } catch {
                throw ContainerError.message("Could not read the app executable: \(error.localizedDescription)")
            }
            guard machO.hasARM64 else {
                throw ContainerError.message("This app has no arm64 slice (32-bit only). 32-bit guests need JIT + classic mode, which lands in Phase 3.")
            }
            if machO.isEncrypted {
                throw ContainerError.message("The app you tried to install is encrypted. Please provide a decrypted app.")
            }

            let (appsDir, dataRoot) = try ensureRoots()
            let folderName = ContainerManager.sanitizedFolderName(bundleID: bundleID)
            let destination = appsDir.appendingPathComponent(folderName)
            guard !fm.fileExists(atPath: destination.path) else {
                throw ContainerError.message("Already installed — \(bundleID) is already in Containers. Delete it first to reinstall.")
            }

            try fm.moveItem(at: stagedApp, to: destination)
            installedDestination = destination

            // LCAppInfo.plist — the metadata invokeAppMain reads.
            // Written with LCPatchRevision -1 first; the patch step
            // below rewrites it to 7 (or the install fails and the
            // catch removes the destination again).
            let dataUUID = UUID().uuidString
            let lcInfo: [String: Any] = [
                "LCPatchRevision": -1,
                "LCDataUUID": dataUUID,
                "LCOrignalBundleIdentifier": bundleID,
                "installationDate": Date(),
            ]
            let lcInfoData = try PropertyListSerialization.data(fromPropertyList: lcInfo, format: .xml, options: 0)
            try lcInfoData.write(to: destination.appendingPathComponent("LCAppInfo.plist"))

            // Patch the executable (LCContainerPatch — LCMachOUtils,
            // currentPatchRev 7, TweakLoader injected). A failure
            // here is a failed install.
            let patchResult = try LCContainerPatch.patchGuestApp(atPath: destination.path, executableName: executable)
            let patchRevision = (patchResult["patchRevision"] as? Int) ?? -1
            let is32bit = (patchResult["is32bit"] as? Bool) ?? false
            print("[Container] patched \(bundleID) — revision \(patchRevision), 32-bit: \(is32bit).")

            // Data container skeleton (LC creates the container
            // lazily on first run; the skeleton is created here so
            // the guest's LCDataUUID already points somewhere).
            let containerDir = dataRoot.appendingPathComponent(dataUUID, isDirectory: true)
            for sub in ["Documents", "Library", "Library/Caches", "Library/Preferences", "tmp"] {
                try fm.createDirectory(at: containerDir.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
            }

            // Sign with the stored certificate when one is imported
            // (ZSigner, direct call). LC skips signing for 32-bit
            // guests; without a cert the guest stays unsigned and
            // unlaunchable. A sign failure does NOT fail the
            // install — the guest lands patched-but-unsigned and
            // the result says so.
            var signed = false
            var signNote = ""
            if is32bit {
                signNote = " This guest is 32-bit — it needs JIT + classic mode (Phase 3) to run."
            } else if LCContainerPatch.hasCertificate() {
                do {
                    signed = try await signGuest(bundlePath: destination.path, bundleID: bundleID)
                    if signed {
                        try setLCAppInfoFlag(bundlePath: destination.path, key: "WTSigned", value: true)
                        signNote = " Signed with your certificate — ready to launch."
                    }
                } catch {
                    signNote = " Signing failed: \(error.localizedDescription)"
                    print("[Container] signing \(bundleID) failed: \(error.localizedDescription)")
                }
            } else {
                signNote = " No certificate imported, so it cannot launch yet."
            }

            let guest = ContainerGuest(
                bundleID: bundleID,
                displayName: displayName,
                version: version,
                executableName: executable,
                folderName: folderName,
                bundlePath: destination.path,
                dataUUID: dataUUID,
                patchRevision: patchRevision,
                is32bit: is32bit,
                signed: signed,
                installedAt: Date()
            )
            print("[Container] installed \(bundleID) (\(displayName) \(version)) — patched revision \(patchRevision), signed: \(signed).")
            await MainActor.run {
                self.lastResult = "Install complete — patched (revision 7).\(signNote)"
                self.refresh()
            }
            return guest
        } catch let error as ContainerError {
            if let installedDestination {
                try? fm.removeItem(at: installedDestination)
            }
            print("[Container] install failed: \(error.localizedDescription)")
            throw error
        } catch {
            if let installedDestination {
                try? fm.removeItem(at: installedDestination)
            }
            print("[Container] install failed: \(error.localizedDescription)")
            throw ContainerError.message("Installing \(url.lastPathComponent) failed: \(error.localizedDescription)")
        }
    }

    /// Folder name for a guest: "<bundle-id>.app", sanitized to
    /// ASCII letters, digits, "." and "-" (LC sanitizes
    /// non-ASCII the same way).
    static func sanitizedFolderName(bundleID: String) -> String {
        // ASCII letters/digits only (Unicode.Scalar.Properties
        // has no isAlphanumeric) plus "." and "-".
        let kept = bundleID.unicodeScalars.filter {
            $0.isASCII && (
                ($0.value >= 48 && $0.value <= 57) ||   // 0-9
                ($0.value >= 65 && $0.value <= 90) ||   // A-Z
                ($0.value >= 97 && $0.value <= 122) ||  // a-z
                $0 == "." || $0 == "-"
            )
        }
        let base = String(String.UnicodeScalarView(kept))
        return (base.isEmpty ? "unknown" : base) + ".app"
    }

    // MARK: Delete

    /// Delete a guest: its bundle folder and its data container
    /// go together, like LC's delete (the receipts for Deploy
    /// are unrelated — guests are not Deploy packages).
    func delete(_ guest: ContainerGuest) {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: guest.bundlePath) {
                try fm.removeItem(atPath: guest.bundlePath)
            }
            if !guest.dataUUID.isEmpty,
               let dataRoot = dataDir() {
                let containerDir = dataRoot.appendingPathComponent(guest.dataUUID)
                if fm.fileExists(atPath: containerDir.path) {
                    try fm.removeItem(at: containerDir)
                }
            }
            print("[Container] deleted \(guest.bundleID).")
            refresh()
        } catch {
            // Failure is Log-only: the message is composed with
            // the guest name, so it has no translation key.
            print("[Container] deleting \(guest.bundleID) failed: \(error.localizedDescription)")
        }
    }
    // MARK: - Sign / launch / certificate

    /// The reason a guest launch failed, set by
    /// ContainerLaunch.checkSelectedGuest() when LiveContainerMain
    /// returns with an "error" key. The Containers page shows it
    /// once and clears it.
    static var launchError: String?

    /// Published cert state for the view (refreshed on appear and
    /// after import/remove).
    @Published private(set) var certificate: ContainerCertificate?

    /// Sign one installed guest with the stored certificate
    /// (ZSigner, direct call — see LCContainerPatch.h).
    private func signGuest(bundlePath: String, bundleID: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            LCContainerPatch.signGuestApp(atPath: bundlePath, bundleId: bundleID) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: ContainerError.message(error ?? "Signing failed."))
                }
            }
        }
    }

    /// Update one key in a guest's LCAppInfo.plist
    /// (read-modify-write, preserving the other keys).
    private func setLCAppInfoFlag(bundlePath: String, key: String, value: Any) throws {
        let url = URL(fileURLWithPath: bundlePath).appendingPathComponent("LCAppInfo.plist")
        var info = (NSDictionary(contentsOfFile: url.path) as? [String: Any]) ?? [:]
        info[key] = value
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url)
    }

    // MARK: - Re-sign on demand (LC parity)
    //
    // Mirrors LiveContainer's LCAppInfo.patchExecAndSignIfNeed
    // (LCAppInfo.m): validate the guest's existing signature first
    // (checkCodeSignature) and skip signing when iOS already
    // considers it valid; otherwise sign with the stored
    // certificate and flip WTSigned. This unblocks guests that
    // were installed before any certificate was stored — they no
    // longer need delete + re-import to become launchable.

    /// Re-sign one guest when needed. Returns true when the guest
    /// ends up validly signed (already valid, or signed now).
    /// Every outcome is logged honestly; a failed re-sign never
    /// claims success, and lastResult carries the user-facing
    /// outcome for the Containers page.
    @discardableResult
    func reSignGuest(_ guest: ContainerGuest) async -> Bool {
        guard guest.isPatched else {
            print("[Container] re-sign skipped for \(guest.bundleID): not patched yet.")
            return false
        }
        guard !guest.is32bit else {
            print("[Container] re-sign skipped for \(guest.bundleID): 32-bit guests need JIT + classic mode.")
            return false
        }
        guard LCContainerPatch.hasCertificate() else {
            print("[Container] re-sign skipped for \(guest.bundleID): no certificate stored.")
            return false
        }
        if LCContainerPatch.isGuestSignatureValid(atPath: guest.bundlePath, executableName: guest.executableName) {
            if !guest.signed {
                try? setLCAppInfoFlag(bundlePath: guest.bundlePath, key: "WTSigned", value: true)
            }
            print("[Container] \(guest.bundleID) signature already valid — skipped re-signing.")
            await MainActor.run { self.refresh() }
            return true
        }
        do {
            let signed = try await signGuest(bundlePath: guest.bundlePath, bundleID: guest.bundleID)
            guard signed else { return false }
            try setLCAppInfoFlag(bundlePath: guest.bundlePath, key: "WTSigned", value: true)
            print("[Container] re-signed \(guest.bundleID) with the stored certificate.")
            await MainActor.run {
                self.lastResult = "Re-signed \(guest.displayName) — ready to launch."
                self.refresh()
            }
            return true
        } catch {
            print("[Container] re-signing \(guest.bundleID) failed: \(error.localizedDescription)")
            await MainActor.run {
                self.lastResult = "Re-signing \(guest.displayName) failed: \(error.localizedDescription)"
            }
            return false
        }
    }

    /// Re-sign every installed guest that is not signed yet,
    /// now that a certificate is stored. Guests whose signature
    /// is already valid keep it (reSignGuest skips the signing
    /// step and just flips WTSigned). Called automatically after
    /// a certificate is stored — manual .p12 import and
    /// Provision alike.
    func reSignAllGuests() async {
        let pending = await MainActor.run {
            guests.filter { $0.isPatched && !$0.is32bit && !$0.signed }
        }
        guard !pending.isEmpty else {
            print("[Container] re-sign: no unsigned guests to re-sign.")
            return
        }
        print("[Container] re-signing \(pending.count) guest(s) with the stored certificate…")
        var signedCount = 0
        for guest in pending {
            if await reSignGuest(guest) { signedCount += 1 }
        }
        print("[Container] re-sign finished: \(signedCount)/\(pending.count) guest(s) signed.")
        await MainActor.run { self.refresh() }
    }

    /// Launch a guest JIT-less: select it and relaunch the host
    /// into it (LCSharedUtils launchToGuestAppWithClassicMode).
    /// The current process is killed by that call; the next launch
    /// runs LiveContainerMain with this guest selected. Before the
    /// signed gate, one automatic re-sign is attempted: a
    /// certificate may have been stored after this guest was
    /// installed, and the guest must not stay unlaunchable for
    /// that. Only launchable guests (patched, 64-bit, signed)
    /// reach the relaunch — the view enforces it and this refuses
    /// again.
    ///
    /// `jit: true` (the JIT arm path only) relaxes the gate to
    /// `isJITLaunchable`: an unsigned guest may relaunch when a
    /// certificate is stored, because the debugger attaches before
    /// the guest runs. JIT-less launch (`jit: false`, the default)
    /// stays signed-gated.
    ///
    /// Throws when the launch didn't take: the gate refused, the
    /// self-open was refused by iOS, or iOS never answered the
    /// self-open within `launchOutcomeTimeout`. On success this
    /// never returns — the process is SIGKILLed once iOS confirms
    /// the self-open, so the caller's continuation never resumes
    /// and (on the JIT path) the pending JIT stays armed for the
    /// next process. The JIT-less caller ignores the error
    /// (`try?`); the JIT caller treats a throw as "the launch
    /// didn't take" and clears the pending JIT.
    func launch(_ guest: ContainerGuest, jit: Bool = false) async throws {
        // Persistent JIT diagnostics: hand the resolved log
        // path to the C helper before any relaunch, so the
        // ObjC self-open handler writes to the same file.
        WTJITDiag.setPathIfNeeded()
        // Validate (and re-sign when needed) before the signed
        // gate, like LC does on every launch: a guest whose
        // signature stopped validating since install gets one
        // automatic re-sign attempt instead of a silent refusal.
        _ = await reSignGuest(guest)
        let current = await MainActor.run {
            self.refresh()
            return guests.first(where: { $0.bundleID == guest.bundleID }) ?? guest
        }
        let launchable = jit ? current.isJITLaunchable : current.isLaunchable
        guard launchable else {
            print("[Container] launch refused for \(guest.bundleID) (jit=\(jit)): patched=\(current.isPatched) 32-bit=\(current.is32bit) signed=\(current.signed).")
            throw ContainerError.message("The guest can't launch right now — it isn't patched, or it still needs a certificate.")
        }
        // Mirror the stdout line to the diagnostics file.
        WTJITDiag.append(step: "launch", detail: "called for \(guest.bundleID) jit=\(jit)")
        print("[Container] launching \(guest.bundleID) — relaunching into the guest.")
        try await launchGuestReportingOutcome(folderName: current.folderName, dataUUID: current.dataUUID)
    }

    /// How long launch() waits for iOS to answer the self-open
    /// before treating the launch as failed (see
    /// launchGuestReportingOutcome). The open completion normally
    /// arrives in milliseconds; 10 s only ever fires when the XPC
    /// round trip itself is dead.
    static let launchOutcomeTimeout: TimeInterval = 10

    /// Awaits the self-open outcome through the completion-taking
    /// launch chain (LCContainerPatch → LCSharedUtils). On success
    /// this never resumes: the process SIGKILLs inside the ObjC
    /// open completion, before the Swift completion block is ever
    /// invoked. On failure the completion resumes with the error
    /// and this throws it. If the open completion never fires at
    /// all, the timeout below resumes with a failure instead, so
    /// the await cannot hang the toggle in "Preparing..." forever.
    /// The gate makes the resume exactly once: the open completion
    /// and the timeout race, and whichever fires first wins (a
    /// checked continuation traps on a second resume).
    private func launchGuestReportingOutcome(folderName: String, dataUUID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let outcome = LaunchOutcomeGate()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(ContainerManager.launchOutcomeTimeout * 1_000_000_000))
                guard outcome.claim() else { return }
                // Diagnostics: the open completion never fired
                // at all — the relaunch request went unanswered.
                WTJITDiag.append(step: "launch", detail: "timeout: no self-open outcome in \(Int(ContainerManager.launchOutcomeTimeout))s")
                continuation.resume(throwing: ContainerError.message("The guest didn't launch — iOS never answered the relaunch request. Try again."))
            }
            LCContainerPatch.launchGuest(withFolderName: folderName, dataUUID: dataUUID) { success, error in
                // Success never reaches here: the process SIGKILLs
                // inside the ObjC open completion before this block
                // is invoked. If it ever did, NOT resuming is still
                // correct — the kill is imminent, and the timeout
                // above reports a failure if it somehow never lands.
                guard !success else {
                    print("[Container] launch open reported success without the process dying — waiting for the SIGKILL (the timeout reports a failure if it never lands).")
                    return
                }
                guard outcome.claim() else { return }
                // Diagnostics: the Swift-side view of the failure.
                // (The ObjC side already wrote its own "self-open
                // FAILED" line with the same error.)
                WTJITDiag.append(step: "launch", detail: "self-open failed: \(error?.localizedDescription ?? "unknown error")")
                continuation.resume(throwing: ContainerError.message(error?.localizedDescription ?? "The guest didn't launch."))
            }
        }
    }

    /// The stored certificate, if one is imported: team ID + expiry.
    struct ContainerCertificate: Equatable {
        let teamID: String
        let expirationDate: Date?
    }

    var hasCertificate: Bool { LCContainerPatch.hasCertificate() }

    func certificateInfo() -> ContainerCertificate? {
        guard let info = try? LCContainerPatch.certificateInfo() else { return nil }
        return ContainerCertificate(
            teamID: (info["teamId"] as? String) ?? "—",
            expirationDate: info["expirationDate"] as? Date
        )
    }

    /// Import a picked .p12 with its password (validated offline
    /// by SecPKCS12Import — wrong password or a non-.p12 throws).
    /// Guests installed before this certificate existed are
    /// re-signed with it right away — no delete + re-import.
    func importCertificate(data: Data, password: String) throws {
        try LCContainerPatch.storeCertificateData(data, password: password)
        print("[Container] certificate imported.")
        refreshCertificate()
        Task { await reSignAllGuests() }
    }

    /// Export the stored signing identity as a fresh .p12 wrapped
    /// with the user's chosen password (empty = no password).
    ///
    /// The stored blob is NEVER handed out as-is: its password is
    /// an unshown random UUID (provisioned) or whatever was typed
    /// at import, so the blob is parsed with its stored password
    /// and re-wrapped (WTPKCS12Export) under the password the user
    /// just chose — the file the user gets opens with that
    /// password. The password is never logged. Works for a
    /// provisioned certificate and a manually imported one alike:
    /// both live in the same stored blob, and the keychain
    /// private key exists only for the provisioned one.
    func exportCertificate(password: String) throws -> Data {
        guard let stored = LCContainerPatch.certificateData(),
              let storedPassword = LCContainerPatch.certificatePassword() else {
            throw ContainerError.message("No certificate stored to export.")
        }
        do {
            return try WTPKCS12Export.rewrapPKCS12(stored, storedPassword: storedPassword, newPassword: password)
        } catch {
            throw ContainerError.message(error.localizedDescription)
        }
    }

    func removeCertificate() {
        LCContainerPatch.removeCertificate()
        print("[Container] certificate removed.")
        refreshCertificate()
    }

    func refreshCertificate() {
        certificate = certificateInfo()
    }
}

/// One-shot gate for the relaunch await (ContainerManager.
/// launchGuestReportingOutcome): the LS open completion and the
/// timeout race, and whichever fires first claims the resume —
/// exactly once. A checked continuation traps on a second resume,
/// so the gate, not hope, enforces it. Sendable via its lock.
private final class LaunchOutcomeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    /// True only for the first caller; every later caller is ignored.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return false }
        done = true
        return true
    }
}

// MARK: - Launch-path bootstrap (Phase 2)
//
// LC relaunches the host with a guest selected: it stores the
// guest's folder name under the "selected" key in the standard
// defaults and re-opens itself (LCSharedUtils
// launchToGuestAppWithClassicMode). WorkTweaksApp calls this from
// init(): when a guest is selected, the process hands over to
// LiveContainerMain, which dlopens the guest and jumps to its
// main — on success this never returns. On failure
// LiveContainerMain returns 1 and stores the reason under the
// "error" key; the host UI then opens normally and the error is
// surfaced on the Containers page (ContainerManager.launchError).
// LiveContainerMain is called ONLY when a guest is selected: its
// no-guest tail dlopens LiveContainerSwiftUI.framework, which
// does not exist in WorkTweaks and must never run here.
enum ContainerLaunch {
    static func checkSelectedGuest() {
        guard let selected = UserDefaults.standard.string(forKey: "selected"), !selected.isEmpty else { return }
        // Diagnostics: the guest-launch result is written when
        // LiveContainerMain returns — which is when the guest
        // quits, or when it failed to start. Together with the
        // "self-open success" line (written before the SIGKILL
        // in the old process), this line separates H1 from H2:
        // self-open success + no guest-launch line = the new
        // process died before reaching here.
        WTJITDiag.append(step: "guest-launch", detail: "selected \(selected) — entering LiveContainerMain")
        print("[Container] guest selected at launch: \(selected) — entering LiveContainerMain.")
        let args = CommandLine.arguments
        let argc = Int32(args.count)
        // strdup each arg; the copies are intentionally leaked —
        // they must outlive this call for the guest's lifetime.
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cArgs.append(nil)
        let result = cArgs.withUnsafeMutableBufferPointer { buf in
            LiveContainerMain(argc, buf.baseAddress)
        }
        // Returned: the guest did not launch (or its main returned).
        // LiveContainerMain clears "selected" before attempting, so
        // there is no relaunch loop; the failure reason, if any, is
        // under the "error" key.
        if let error = UserDefaults.standard.string(forKey: "error") {
            UserDefaults.standard.removeObject(forKey: "error")
            ContainerManager.launchError = error
            WTJITDiag.append(step: "guest-launch", detail: "LiveContainerMain returned — failed: \(error)")
            print("[Container] guest launch failed: \(error)")
        } else {
            WTJITDiag.append(step: "guest-launch", detail: "LiveContainerMain returned \(result) with no error recorded — staying in WorkTweaks")
            print("[Container] LiveContainerMain returned \(result) with no error recorded — staying in WorkTweaks.")
        }
    }
}

// MARK: - Mach-O inspection (encryption + arm64 slice)
//
// LC's LCIsMachOEncrypted (LCMachOUtils.m) walks the load
// commands for LC_ENCRYPTION_INFO(_64) with cryptid != 0.
// Reimplemented here in Swift as the early pre-flight check
// before install — the ObjC core does the authoritative check
// again at patch time. Same rule, same outcome.

enum ContainerMachO {
    struct SliceInfo {
        let hasARM64: Bool
        let isEncrypted: Bool
    }

    private static let cpuTypeARM64: UInt32 = 0x0100_000C
    private static let mhMagic64: UInt32 = 0xFEED_FACF
    private static let fatMagic: UInt32 = 0xCAFE_BABE
    private static let fatMagicSwapped: UInt32 = 0xBEBA_FECA
    private static let lcEncryptionInfo: UInt32 = 0x21
    private static let lcEncryptionInfo64: UInt32 = 0x2C

    static func inspect(executableURL url: URL) throws -> SliceInfo {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ContainerError.message("The app executable could not be opened.")
        }
        defer { try? handle.close() }

        func read(at offset: UInt64, count: Int) throws -> Data {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw ContainerError.message("The app executable is truncated.")
            }
            return data
        }
        func u32LE(_ data: Data, _ offset: Int) -> UInt32 {
            UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
        }
        func u32BE(_ data: Data, _ offset: Int) -> UInt32 {
            (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16)
                | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
        }

        let magicData = try read(at: 0, count: 4)
        let magicBE = u32BE(magicData, 0)

        // Fat binary: walk the arch entries, inspect arm64 slices.
        if magicBE == fatMagic || magicBE == fatMagicSwapped {
            let header = try read(at: 0, count: 8)
            let narch = Int(u32BE(header, 4))
            var hasARM64 = false
            var encrypted = false
            for i in 0..<narch {
                let entry = try read(at: 8 + UInt64(i * 20), count: 20)
                let cputype = u32BE(entry, 0)
                guard cputype == cpuTypeARM64 else { continue }
                let sliceOffset = UInt64(u32BE(entry, 8))
                let slice = try inspectSlice(at: sliceOffset, read: read, u32LE: u32LE)
                hasARM64 = true
                encrypted = encrypted || slice
            }
            return SliceInfo(hasARM64: hasARM64, isEncrypted: encrypted)
        }

        // Thin 64-bit Mach-O.
        let magicLE = u32LE(magicData, 0)
        guard magicLE == mhMagic64 else {
            throw ContainerError.message("The app executable is not a 64-bit Mach-O binary.")
        }
        let encrypted = try inspectSlice(at: 0, read: read, u32LE: u32LE)
        return SliceInfo(hasARM64: true, isEncrypted: encrypted)
    }

    private static func inspectSlice(
        at base: UInt64,
        read: (UInt64, Int) throws -> Data,
        u32LE: (Data, Int) -> UInt32
    ) throws -> Bool {
        let header = try read(base, 32)
        let ncmds = Int(u32LE(header, 16))
        let sizeofcmds = Int(u32LE(header, 20))
        guard sizeofcmds >= 0 else { return false }
        let commands = try read(base + 32, sizeofcmds)
        var offset = 0
        for _ in 0..<ncmds {
            guard offset + 8 <= commands.count else { break }
            let cmd = u32LE(commands, offset)
            let cmdsize = Int(u32LE(commands, offset + 4))
            guard cmdsize >= 8, offset + cmdsize <= commands.count else { break }
            if cmd == lcEncryptionInfo || cmd == lcEncryptionInfo64 {
                // struct encryption_info_command: cmd, cmdsize,
                // cryptoff, cryptsize, cryptid — cryptid at +16.
                guard offset + 20 <= commands.count else { break }
                if u32LE(commands, offset + 16) != 0 { return true }
            }
            offset += cmdsize
        }
        return false
    }
}

// MARK: - ZIP extraction (with symlink support)
//
// Same central-directory parser shape as
// DeployManager.zipEntries (stored/deflate only, no ZIP64, no
// encrypted entries, 256 MB per-entry cap) — but it writes to
// disk instead of returning Data, and it recreates symlinks:
// an entry whose external attributes carry Unix mode 0120000
// is a symlink whose content is the link target. Deploy's
// reader drops that bit, and .app bundles rely on symlinks
// (Frameworks, Versions/Current), so installing through it
// would silently produce a broken bundle.

enum ContainerZip {
    static func extract(data: Data, to destination: URL) throws {
        // Index the Data directly — copying a whole IPA into a
        // [UInt8] would double its memory footprint.
        let bytes = data
        func u16(_ offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
                | (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24)
        }
        guard bytes.count >= 22 else {
            throw ContainerError.message("The file is too small to be a ZIP archive.")
        }
        var eocd = -1
        var i = bytes.count - 22
        let windowStart = max(0, bytes.count - 65_558)
        while i >= windowStart {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else {
            throw ContainerError.message("No ZIP end-of-central-directory record was found — this is not a ZIP archive.")
        }
        let entryCount = u16(eocd + 10)
        let cdSize = u32(eocd + 12)
        let cdOffset = u32(eocd + 16)
        if entryCount == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            throw ContainerError.message("ZIP64 archives are not supported.")
        }

        let fm = FileManager.default
        var p = cdOffset
        for _ in 0..<entryCount {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else {
                throw ContainerError.message("The archive's central directory is damaged.")
            }
            let flags = u16(p + 8)
            let method = u16(p + 10)
            let compSize = u32(p + 20)
            let uncompSize = u32(p + 24)
            let nameLength = u16(p + 28)
            let extraLength = u16(p + 30)
            let commentLength = u16(p + 32)
            let externalAttrs = u32(p + 38)
            let localOffset = u32(p + 42)
            guard p + 46 + nameLength <= bytes.count else {
                throw ContainerError.message("The archive's central directory is damaged.")
            }
            let name = String(data: bytes.subdata(in: (p + 46)..<(p + 46 + nameLength)), encoding: .utf8) ?? ""
            p += 46 + nameLength + extraLength + commentLength

            // Path safety: no absolute paths, no ".." components.
            let components = name.split(separator: "/").map(String.init)
            guard !name.hasPrefix("/"), !components.contains("..") else {
                throw ContainerError.message("The archive contains an unsafe path (\(name)) — rejected whole, nothing was installed.")
            }
            if components.isEmpty || name.hasSuffix("/") {
                if !components.isEmpty {
                    let dir = components.reduce(destination) { $0.appendingPathComponent($1) }
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                continue
            }
            if flags & 0x1 != 0 {
                throw ContainerError.message("Encrypted archives are not supported (entry \"\(name)\").")
            }
            if compSize == 0xFFFF_FFFF || uncompSize == 0xFFFF_FFFF {
                throw ContainerError.message("ZIP64 archives are not supported (entry \"\(name)\").")
            }
            guard uncompSize <= 268_435_456 else {
                throw ContainerError.message("The entry \"\(name)\" is too large (\(uncompSize) bytes).")
            }
            guard localOffset + 30 <= bytes.count, u32(localOffset) == 0x0403_4B50 else {
                throw ContainerError.message("The archive's local header for \"\(name)\" is damaged.")
            }
            let localNameLength = u16(localOffset + 26)
            let localExtraLength = u16(localOffset + 28)
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compSize <= bytes.count else {
                throw ContainerError.message("The archive's data for \"\(name)\" is truncated.")
            }
            let compressed = bytes.subdata(in: dataStart..<(dataStart + compSize))
            let content: Data
            switch method {
            case 0:
                guard compressed.count == uncompSize else {
                    throw ContainerError.message("The stored entry \"\(name)\" has a size mismatch.")
                }
                content = compressed
            case 8:
                guard let inflated = inflate(compressed, expectedSize: uncompSize) else {
                    throw ContainerError.message("The deflated entry \"\(name)\" could not be decompressed.")
                }
                content = inflated
            default:
                throw ContainerError.message("Unsupported compression method \(method) for \"\(name)\" — only stored and deflated entries are supported.")
            }

            let dest = components.reduce(destination) { $0.appendingPathComponent($1) }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let unixMode = externalAttrs >> 16
            if unixMode & 0o170000 == 0o120000 {
                // Symlink: the content is the link target.
                let target = String(data: content, encoding: .utf8) ?? ""
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: target)
            } else {
                try content.write(to: dest)
            }
        }
    }

    /// ZIP deflate is a raw deflate stream, which is what the
    /// Compression framework's COMPRESSION_ZLIB decoder reads
    /// (same as DeployManager.inflate).
    private static func inflate(_ compressed: Data, expectedSize: Int) -> Data? {
        if expectedSize == 0 { return Data() }
        guard !compressed.isEmpty else { return nil }
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { dst.deallocate() }
        let written = compressed.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return compression_decode_buffer(
                dst, expectedSize,
                base.assumingMemoryBound(to: UInt8.self), compressed.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written == expectedSize else { return nil }
        return Data(bytes: dst, count: written)
    }
}
