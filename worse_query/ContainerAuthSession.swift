import Combine
import Foundation

// MARK: - Container Apple ID auth: session
//
// The Container's sign-in + provisioning state, modelled on
// Signed Apps' InstallerSession (pinned 61d013e8) but scoped to
// the Container only: sign in -> team -> provision the HOST
// (bundle cc.forcequit.worse-query.<TEAMID> + group
// group.cc.forcequit.worse-query.<TEAMID>) -> export the
// resulting certificate as a .p12 and store it the way a
// manually imported one is stored, so guests sign and launch
// without a manual .p12. Manual .p12 import stays as the
// fallback and is untouched by this session.
//
// What is deliberately NOT ported from InstallerSession:
// - the IPA pick/sign flow (no IPA here; guests are signed by
//   LCContainerPatch from the stored certificate), and with it
//   the importPickedIPA bundle-ID-reset bug — there is no
//   signingBundleIdOverride here to reset.
// - device registration (provision() never did it; the user's
//   device is already registered on the team).
// - nothing is ever revoked on its own: a revoke happens only
//   from the user's confirmed tap in the 7460 recovery UI, and
//   creation is retried once after the slot frees.
//
// Sign-out also removes the stored container certificate: it
// was minted from that account, and a different account's
// guests must not keep signing under it.

@MainActor
final class ContainerAuthSession: ObservableObject {
    enum SignInState: Equatable {
        case signedOut
        case working(String)
        case needsTwoFactor
        case signedIn(email: String)
        case failed(String)
    }

    enum ProvisionState: Equatable {
        case idle
        case working(String)
        case done
        case failed(String)
    }

    @Published var signInState: SignInState = .signedOut
    @Published var appleIDEmail: String = ""
    @Published var teams: [DeveloperTeam] = []
    /// The picked team, by teamId. Nil until teams load; a lone
    /// team is picked automatically (isideload's default).
    @Published var selectedTeamId: String?
    @Published var certificateIdentity: CertificateIdentity?
    @Published var teamCertificates: [DevelopmentCertificate] = []
    @Published var provisionState: ProvisionState = .idle
    @Published var provisionError: String?
    /// True when provisioning failed with 7460 (the free-team
    /// cert slot is full) — the UI then offers revoke->create.
    @Published var showCertRecovery = false
    @Published var savedProfiles: [SavedProfile] = []
    @Published var busy = false

    /// The team provisioning uses: the pick, else the first team.
    var team: DeveloperTeam? {
        if let selectedTeamId {
            return teams.first { $0.teamId == selectedTeamId }
        }
        return teams.first
    }

    private(set) var appleSession: AppleSession?
    private var twoFactorContinuation: CheckedContinuation<String?, Never>?

    init() {
        if let email = ContainerAuthKeychain.load("email"),
           let adsid = ContainerAuthKeychain.load("adsid"),
           let token = ContainerAuthKeychain.load("authToken") {
            appleIDEmail = email
            appleSession = AppleSession(adsid: adsid, authToken: token, email: email)
            signInState = .signedIn(email: email)
            log("restored saved session for \(email) (adsid \(adsid))")
            refreshTeams()
        }
    }

    func log(_ message: String) {
        // The Log tab IS stdout (Console dup2's it at launch),
        // so print is the in-app log path — same as the
        // [Container] lines ContainerManager writes.
        print("[Container] \(message)")
    }

    // MARK: - Sign in

    func signIn(password: String) {
        if case .working = signInState { return }
        signInState = .working("Contacting Apple…")
        let email = appleIDEmail
        let anisetteServer = UserDefaults.standard.string(forKey: "wt.container.anisetteURL") ?? ""
        Task {
            let authenticator = GrandSlamAuthenticator()
            // Plain print, not self?.log: the closure runs off the
            // main actor, and print is thread-safe (and the Log
            // tab's Console pipes stdout, so this IS the log).
            authenticator.log = { message in print("[Container] \(message)") }
            do {
                let session = try await authenticator.authenticate(
                    email: email, password: password, anisetteServer: anisetteServer,
                    provideTwoFactorCode: { [weak self] in
                        await self?.awaitTwoFactorCode() ?? nil
                    })
                appleSession = session
                ContainerAuthKeychain.save(session.email, for: "email")
                ContainerAuthKeychain.save(session.adsid, for: "adsid")
                ContainerAuthKeychain.save(session.authToken, for: "authToken")
                signInState = .signedIn(email: session.email)
                log("signed in as \(session.email) — session saved")
                refreshTeams()
            } catch {
                signInState = .failed(error.localizedDescription)
                log("sign-in failed: \(error.localizedDescription)")
            }
        }
    }

    private func awaitTwoFactorCode() async -> String? {
        signInState = .needsTwoFactor
        log("waiting for the two-factor code…")
        return await withCheckedContinuation { continuation in
            twoFactorContinuation = continuation
        }
    }

    func submitTwoFactorCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        signInState = .working("Validating two-factor code…")
        twoFactorContinuation?.resume(returning: trimmed)
        twoFactorContinuation = nil
    }

    func cancelTwoFactor() {
        twoFactorContinuation?.resume(returning: nil)
        twoFactorContinuation = nil
    }

    func signOut() {
        cancelTwoFactor()
        appleSession = nil
        teams = []
        selectedTeamId = nil
        certificateIdentity = nil
        teamCertificates = []
        provisionState = .idle
        provisionError = nil
        showCertRecovery = false
        ContainerAuthKeychain.delete("email")
        ContainerAuthKeychain.delete("adsid")
        ContainerAuthKeychain.delete("authToken")
        ContainerAuthKeychain.delete("teamId")
        // The stored container certificate was minted from this
        // account — remove it so a later account doesn't keep
        // signing under it. Manual .p12 import is unaffected
        // (it is the same store, and the user re-imports it).
        ContainerManager.shared.removeCertificate()
        signInState = .signedOut
        log("signed out (stored container certificate removed)")
    }

    // MARK: - Developer portal

    private func makeLog() -> (String) -> Void {
        // Plain print (see signIn): thread-safe, and the Log tab
        // pipes stdout, so this IS the log.
        { message in print("[Container] \(message)") }
    }

    private func makeDeveloperSession() -> DeveloperSession? {
        guard let appleSession else { return nil }
        let dev = DeveloperSession(session: appleSession)
        dev.log = makeLog()
        return dev
    }

    /// List the teams; a lone team is picked automatically.
    func refreshTeams() {
        guard appleSession != nil, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            guard let dev = makeDeveloperSession() else { return }
            do {
                teams = try await dev.listTeams()
                if teams.isEmpty {
                    log("no developer teams available")
                    return
                }
                if teams.count == 1, let only = teams.first {
                    selectedTeamId = only.teamId
                    ContainerAuthKeychain.save(only.teamId, for: "teamId")
                } else if let selectedTeamId, !teams.contains(where: { $0.teamId == selectedTeamId }) {
                    self.selectedTeamId = nil
                }
                if let team {
                    log("team: \(team.name ?? "Personal Team") (\(team.teamId))")
                }
                log("team has \(teams.count) team(s) on this account")
            } catch {
                log("listing teams failed: \(error.localizedDescription)")
            }
        }
    }

    /// Fill the certificate state from the portal: our
    /// certificate if one already matches our key, plus the
    /// team's certificate list (for the 7460 recovery UI).
    /// Nothing is created here.
    func refreshCertificateInfo() {
        savedProfiles = ProfileStore.loadAll()
        guard appleSession != nil, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            guard let dev = makeDeveloperSession(), let email = appleSession?.email,
                  let team = team else { return }
            do {
                teamCertificates = try await dev.listAllDevelopmentCerts(team: team)
                log("team has \(teamCertificates.count) certificate(s)")
                certificateIdentity = await CertificateIdentity.retrieveExisting(dev: dev, team: team, email: email)
                if let certificateIdentity {
                    log("certificate: \(certificateIdentity.displayName)")
                }
            } catch {
                log("certificate refresh failed: \(error.localizedDescription)")
            }
        }
    }

    /// Explicit certificate creation: find ours, or request a
    /// new one via CSR. 7460 surfaces as-is — nothing is
    /// revoked here; the recovery UI does that explicitly.
    func createCertificate() {
        guard appleSession != nil, !busy else { return }
        busy = true
        provisionState = .working("Creating certificate…")
        Task {
            defer { busy = false }
            guard let dev = makeDeveloperSession(), let email = appleSession?.email,
                  let team = team else { return }
            do {
                certificateIdentity = try await CertificateIdentity.retrieve(
                    dev: dev, team: team, email: email, log: makeLog())
                provisionState = .done
                try await exportAndStoreCertificate(email: email)
            } catch {
                provisionState = .failed(error.localizedDescription)
                handleCertificateError(error)
            }
        }
    }

    /// True when this team certificate's subject public key is
    /// the one behind our stored signing identity — the badge
    /// the recovery UI shows instead of a Revoke button.
    func isOurs(_ cert: DevelopmentCertificate) -> Bool {
        guard let identity = certificateIdentity,
              let content = cert.certContent,
              let theirs = try? parseCertificate(content),
              let ours = try? parseCertificate(identity.certificateDER) else { return false }
        return theirs.publicKeyPKCS1 == ours.publicKeyPKCS1
    }

    /// Revoke one of the team's OTHER certificates — only ever
    /// called from the recovery UI's confirmed Revoke action.
    /// When the revoke frees the slot a failed creation needed
    /// (error 7460), creation is retried once.
    func revokeCertificate(_ cert: DevelopmentCertificate) {
        guard appleSession != nil, !busy else { return }
        guard let serial = cert.serialNumber, !serial.isEmpty else {
            log("cannot revoke a certificate with no serial number")
            return
        }
        busy = true
        Task {
            defer { busy = false }
            guard let dev = makeDeveloperSession(), let email = appleSession?.email,
                  let team = team else { return }
            do {
                log("revoking certificate \(cert.name ?? "unnamed certificate") (\(cert.machineName ?? "unknown machine"))…")
                try await dev.revokeDevelopmentCert(team: team, serialNumber: serial)
                log("certificate revoked")
                teamCertificates = try await dev.listAllDevelopmentCerts(team: team)
                showCertRecovery = false
                provisionError = nil
            } catch {
                log("revoke failed: \(error.localizedDescription)")
                return
            }
            if certificateIdentity == nil {
                log("certificate slot freed — creating certificate…")
                do {
                    certificateIdentity = try await CertificateIdentity.retrieve(
                        dev: dev, team: team, email: email, log: makeLog())
                    provisionState = .done
                    try await exportAndStoreCertificate(email: email)
                } catch {
                    provisionState = .failed(error.localizedDescription)
                    handleCertificateError(error)
                }
            }
        }
    }

    /// The full provisioning chain, as isideload runs it: our
    /// certificate, the App ID for the HOST bundle (registered
    /// if missing), the App Group (ensured and assigned, with
    /// the group feature enabled on the App ID), then the team
    /// provisioning profile — then the certificate is exported
    /// as a .p12 and stored, so guests sign and launch.
    func provision() {
        guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty,
              appleSession != nil, !busy else { return }
        let groupId = AppGroupResolver.resolvedGroup
        busy = true
        provisionState = .working("Provisioning…")
        provisionError = nil
        showCertRecovery = false
        Task {
            defer { busy = false }
            guard let dev = makeDeveloperSession(), let email = appleSession?.email,
                  let team = team else { return }
            do {
                log("provisioning \(bundleId)…")
                let identity = try await CertificateIdentity.retrieve(
                    dev: dev, team: team, email: email, log: makeLog())
                certificateIdentity = identity

                let listing = try await dev.listAppIds(team: team)
                var appId: AppId
                if let existing = listing.appIds.first(where: { $0.identifier == bundleId }) {
                    appId = existing
                    log("app ID already registered: \(bundleId)")
                } else {
                    if let available = listing.availableQuantity, available >= 0, available < 1 {
                        throw DeveloperError.message("Not enough available app IDs (0 available).")
                    }
                    log("registering app ID \(bundleId)…")
                    appId = try await dev.addAppId(team: team, name: "WorkTweaks", identifier: bundleId)
                }

                if !groupId.isEmpty {
                    try await dev.ensureGroupFeature(team: team, appId: &appId)
                    let group = try await dev.ensureAppGroup(team: team, name: "WorkTweaks", identifier: groupId)
                    log("assigning app group \(groupId) to the app ID…")
                    try await dev.assignAppGroup(team: team, appGroup: group, appId: appId)
                    log("assigned group \(group.identifier) (portal \(group.applicationGroup)) to app ID \(bundleId)")
                }

                log("downloading team provisioning profile…")
                let profile = try await dev.downloadTeamProvisioningProfile(team: team, appId: appId)
                let url = try ProfileStore.save(profile.encodedProfile, bundleId: bundleId)
                log("profile saved: \(url.lastPathComponent)")
                savedProfiles = ProfileStore.loadAll()
                if let parsed = ProfileStore.parse(profile.encodedProfile, bundleId: bundleId, fileURL: url) {
                    let expiry = parsed.expirationDate.map { Self.dateFormatter.string(from: $0) } ?? "unknown"
                    let groups = parsed.applicationGroups.isEmpty
                        ? "none" : parsed.applicationGroups.joined(separator: ", ")
                    log("profile OK: \(parsed.name), expires \(expiry), groups: \(groups)")
                    if let summary = ProfileStore.entitlementsSummary(profile.encodedProfile) {
                        log("profile entitlements: \(summary)")
                    }
                }

                try await exportAndStoreCertificate(email: email)
                provisionState = .done
            } catch {
                provisionState = .failed(error.localizedDescription)
                log("provisioning failed: \(error.localizedDescription)")
                handleCertificateError(error)
            }
        }
    }

    /// Export the provisioned identity as a .p12 (random UUID
    /// password, never shown or logged) and store it the LC way,
    /// so guests sign and launch without a manual .p12.
    private func exportAndStoreCertificate(email: String) async throws {
        guard let identity = certificateIdentity else {
            throw CertificateError.message("No certificate to store.")
        }
        log("exporting the certificate as a .p12 for the Container…")
        let pkcs1 = try CertificateIdentity.privateKeyPKCS1(email: email)
        let password = UUID().uuidString
        // No guard let: an NSError-convention ObjC method imports
        // as throwing with a non-optional return (a nil return
        // becomes the throw), so the failure path is the catch.
        let p12 = try WTPKCS12Export.exportPKCS12(
            withPrivateKeyPKCS1: pkcs1,
            certificate: identity.certificateDER,
            chain: AppleChain.certificatesDER,
            password: password)
        try LCContainerPatch.storeCertificateData(p12, password: password)
        ContainerManager.shared.refreshCertificate()
        log("certificate stored — guests can now be signed and launched")
        // Guests installed before this certificate existed are
        // re-signed with it right away — no delete + re-import.
        await ContainerManager.shared.reSignAllGuests()
    }

    /// 7460 ("Maximum number of certificates generated") is the
    /// free-team slot being full: surface it honestly with the
    /// revoke->create recovery, and load the team's certs so the
    /// user can pick which one to revoke. Any other error just
    /// stands as the provision error.
    private func handleCertificateError(_ error: Error) {
        guard (error as? DeveloperError)?.serverCode == 7460 else {
            provisionError = error.localizedDescription
            return
        }
        provisionError = error.localizedDescription
        showCertRecovery = true
        log("7460: the free-team certificate slot is full — revoke an old certificate, then create a new one")
        Task {
            guard let dev = makeDeveloperSession(), let team = team else { return }
            do {
                teamCertificates = try await dev.listAllDevelopmentCerts(team: team)
            } catch {
                log("listing team certificates failed: \(error.localizedDescription)")
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
