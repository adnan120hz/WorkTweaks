import SwiftUI
import UniformTypeIdentifiers

// MARK: - Install IPA on Container (Phase 2)
//
// The guest list + IPA import page. Phase 2 installs are patched
// (LCContainerPatch, revision 7) and signed when a certificate is
// imported; launchable guests launch JIT-less. The JIT toggle
// stays OFF/disabled until the Phase 3 JIT session exists.
// Every state on this page says what is true: a guest without a
// certificate is patched but not launchable, and none claims
// otherwise.

struct ContainerView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var manager = ContainerManager.shared
    @StateObject private var auth = ContainerAuthSession()
    @StateObject private var jitManager = ContainerJITManager.shared
    @State private var authPassword = ""
    @State private var twoFactorCode = ""
    @State private var showSignOutConfirm = false
    @State private var certToRevoke: DevelopmentCertificate?
    @State private var showImporter = false
    @State private var importError: String?
    @State private var guestToDelete: ContainerGuest?

    @State private var showCertImporter = false
    @State private var certData: Data?
    @State private var certFileName = ""
    @State private var certPassword = ""
    @State private var showPasswordPrompt = false
    @State private var certError: String?
    @State private var showRemoveCertConfirm = false
    @State private var launchError: String?

    @State private var showExportPasswordPrompt = false
    @State private var exportPassword = ""
    @State private var exportURL: URL?
    @State private var showExportSheet = false
    @State private var exportError: String?

    /// The saved provisioning profile to share: the host bundle's,
    /// else the first saved one. Nil when nothing was ever saved —
    /// the profile row is then hidden, never offered empty.
    private var profileToShare: SavedProfile? {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        return auth.savedProfiles.first { $0.bundleId == bundleId }
            ?? auth.savedProfiles.first
    }

    var body: some View {
        WTGlassPage {
            WTSectionCard {
                Text(wtLang.tr("Guest apps live in the WorkTweaks App Group and run inside this app. Decrypted IPAs are patched and signed here; a certificate is needed to launch on iOS 26+."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            // Apple ID — sign in on-device, pick a team, provision
            // the host (bundle + App Group + profile), and the
            // resulting certificate is stored as a .p12, so guests
            // sign and launch without a manual .p12 import. The
            // password is typed here only: it goes to Apple's
            // servers for sign-in and is never stored or logged.
            WTSectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(wtLang.tr("Apple ID"), systemImage: "person.crop.circle.badge.checkmark")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        if case .signedIn(let email) = auth.signInState {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    switch auth.signInState {
                    case .signedOut, .failed:
                        TextField(wtLang.tr("Apple ID email"), text: $auth.appleIDEmail)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                        SecureField(wtLang.tr("Password"), text: $authPassword)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                        Text(wtLang.tr("Sign in on-device only — your password goes to Apple for sign-in and is never stored."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                        if case .failed(let message) = auth.signInState {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14)
                        }
                        Button {
                            SoundEffects.playTap()
                            let password = authPassword
                            authPassword = ""
                            auth.signIn(password: password)
                        } label: {
                            Label(wtLang.tr("Sign In with Apple ID"), systemImage: "person.crop.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(auth.busy || auth.appleIDEmail.trimmingCharacters(in: .whitespaces).isEmpty || authPassword.isEmpty)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    case .working(let status):
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(wtLang.tr(status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    case .needsTwoFactor:
                        Text(wtLang.tr("Enter the 6-digit code sent to your trusted device."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                        TextField(wtLang.tr("Verification code"), text: $twoFactorCode)
                            .keyboardType(.numberPad)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                        HStack(spacing: 10) {
                            Button {
                                SoundEffects.playTap()
                                let code = twoFactorCode
                                twoFactorCode = ""
                                auth.submitTwoFactorCode(code)
                            } label: {
                                Text(wtLang.tr("Verify"))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(twoFactorCode.trimmingCharacters(in: .whitespaces).isEmpty)
                            Button {
                                SoundEffects.playTap()
                                twoFactorCode = ""
                                auth.cancelTwoFactor()
                            } label: {
                                Text(wtLang.tr("Cancel"))
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    case .signedIn:
                        if let team = auth.team {
                            HStack {
                                Text(wtLang.tr("Team"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Text("\(team.name ?? wtLang.tr("Personal Team")) (\(team.teamId))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                        }
                        if auth.teams.count > 1 {
                            Picker(wtLang.tr("Team"), selection: Binding(
                                get: { auth.selectedTeamId ?? auth.teams.first?.teamId ?? "" },
                                set: { auth.selectedTeamId = $0 }
                            )) {
                                ForEach(auth.teams, id: \.teamId) { team in
                                    Text("\(team.name ?? wtLang.tr("Personal Team")) (\(team.teamId))").tag(team.teamId)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal, 14)
                        }
                        if manager.hasCertificate {
                            Text(wtLang.tr("Certificate ready — guests can be signed and launched."))
                                .font(.caption)
                                .foregroundStyle(.green)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14)
                        } else {
                            Text(wtLang.tr("No certificate yet — provision one below, or import a .p12."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14)
                        }
                        if case .working(let status) = auth.provisionState {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(wtLang.tr(status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                        }
                        if case .failed(let message) = auth.provisionState {
                            Text(auth.provisionError ?? message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14)
                        }
                        Button {
                            SoundEffects.playTap()
                            auth.provision()
                        } label: {
                            Label(wtLang.tr("Provision Certificate"), systemImage: "key.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(auth.busy || auth.team == nil)
                        .padding(.horizontal, 14)
                        if auth.showCertRecovery {
                            Text(wtLang.tr("The free-team certificate slot is full (7460). Revoke an old certificate below, then a new one is created automatically."))
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14)
                            ForEach(auth.teamCertificates) { cert in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cert.name ?? wtLang.tr("Certificate"))
                                            .font(.caption.weight(.semibold))
                                        Text(cert.machineName ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if auth.isOurs(cert) {
                                        Text(wtLang.tr("This device"))
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    } else {
                                        Button(wtLang.tr("Revoke")) {
                                            SoundEffects.playTap()
                                            certToRevoke = cert
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(auth.busy)
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                        }
                        Button {
                            SoundEffects.playTap()
                            showSignOutConfirm = true
                        } label: {
                            Label(wtLang.tr("Sign Out"), systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                }
            }

            // Certificate — the .p12 that signs guests. Without it,
            // installs land patched but unsigned and unlaunchable.
            WTSectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(wtLang.tr("Certificate"), systemImage: "key.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        if manager.hasCertificate, let cert = manager.certificate {
                            Text(wtLang.tr("Team %@", cert.teamID))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    if manager.hasCertificate, let cert = manager.certificate {
                        if let expiry = cert.expirationDate {
                            Text(wtLang.tr("Expires %@", expiry.formatted(date: .abbreviated, time: .omitted)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14)
                        }
                        // Export: the stored identity re-wrapped as
                        // a fresh .p12 under a password the user
                        // chooses — the file they get opens with
                        // that password in another app. On-device
                        // only; the staged temp file is deleted
                        // when the share sheet closes.
                        Button {
                            SoundEffects.playTap()
                            exportPassword = ""
                            showExportPasswordPrompt = true
                        } label: {
                            Label(wtLang.tr("Export Certificate (.p12)"), systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        if let exportURL {
                            Button {
                                SoundEffects.playTap()
                                showExportSheet = true
                            } label: {
                                Label(wtLang.tr("Share %@", exportURL.lastPathComponent), systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                        }
                        Button {
                            SoundEffects.playTap()
                            showRemoveCertConfirm = true
                        } label: {
                            Label(wtLang.tr("Remove Certificate"), systemImage: "trash")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                    } else {
                        Text(wtLang.tr("No certificate imported — import a .p12 to sign and launch guests."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                        Button {
                            SoundEffects.playTap()
                            showCertImporter = true
                        } label: {
                            HStack {
                                Label(wtLang.tr("Import Certificate"), systemImage: "square.and.arrow.down")
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.isBusy)
                        .padding(.horizontal, 14)
                    }
                    // The saved provisioning profile, shared as-is
                    // from ProfileStore. Shown whenever one is
                    // saved — even with no certificate (sign-out
                    // removes the cert but not the profile file) —
                    // and hidden when none is stored.
                    if let profile = profileToShare {
                        ShareLink(item: profile.fileURL) {
                            Label(wtLang.tr("Share Provisioning Profile"), systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.bottom, 10)
            }

            WTSectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        SoundEffects.playTap()
                        showImporter = true
                    } label: {
                        HStack {
                            Label(wtLang.tr("Import IPA"), systemImage: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            if manager.isBusy {
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isBusy)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if let result = manager.lastResult {
                        Text(wtLang.tr(result))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                    if let launchError {
                        Text(wtLang.tr("Launch failed: %@", launchError))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }
            }

            if manager.guests.isEmpty {
                WTSectionCard {
                    Text(wtLang.tr("No containers installed yet — import an .ipa to add one."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            } else {
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(manager.guests.enumerated()), id: \.element.id) { index, guest in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(guest.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(guest.bundleID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack(spacing: 6) {
                                            Text(guest.version)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("•")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(guest.isPatched
                                                 ? wtLang.tr("Patched")
                                                 : wtLang.tr("Not patched yet"))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(guest.isPatched ? .green : .orange)
                                            Text("•")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(guest.signed
                                                 ? wtLang.tr("Signed")
                                                 : wtLang.tr("Not signed"))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(guest.signed ? .green : .orange)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Button {
                                        SoundEffects.playTap()
                                        guestToDelete = guest
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.subheadline)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                if guest.isLaunchable {
                                    Button {
                                        SoundEffects.playTap()
                                        Task { try? await manager.launch(guest) }
                                    } label: {
                                        Label(wtLang.tr("Launch"), systemImage: "play.fill")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.borderedProminent)
                                } else if guest.is32bit {
                                    Text(wtLang.tr("32-bit — needs JIT + classic mode, which is not in this build."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if !guest.signed {
                                    HStack(spacing: 8) {
                                        Text(wtLang.tr("Needs certificate to launch"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if guest.isPatched && manager.hasCertificate {
                                            Button {
                                                SoundEffects.playTap()
                                                Task { await manager.reSignGuest(guest) }
                                            } label: {
                                                Label(wtLang.tr("Re-sign"), systemImage: "arrow.triangle.2.circlepath")
                                                    .font(.caption.weight(.semibold))
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }

            ContainerJITSection(manager: manager, jitManager: jitManager)
        }
        .navigationTitle(wtLang.tr("Install IPA on Container"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.refresh()
            manager.refreshCertificate()
            auth.refreshSavedProfiles()
            if case .signedIn = auth.signInState {
                auth.refreshCertificateInfo()
            }
            if let error = ContainerManager.launchError {
                ContainerManager.launchError = nil
                launchError = error
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "ipa")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        _ = try await manager.installIPA(from: url)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showCertImporter,
            allowedContentTypes: [UTType(filenameExtension: "p12")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    certData = try Data(contentsOf: url)
                    certFileName = url.lastPathComponent
                    certPassword = ""
                    showPasswordPrompt = true
                } catch {
                    certError = error.localizedDescription
                }
            case .failure(let error):
                certError = error.localizedDescription
            }
        }
        .alert(wtLang.tr("Install failed"), isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button(wtLang.tr("OK"), role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert(wtLang.tr("Import failed"), isPresented: Binding(
            get: { certError != nil },
            set: { if !$0 { certError = nil } }
        )) {
            Button(wtLang.tr("OK"), role: .cancel) { certError = nil }
        } message: {
            Text(certError ?? "")
        }
        .alert(
            wtLang.tr("Certificate password"),
            isPresented: $showPasswordPrompt
        ) {
            SecureField(wtLang.tr("Password"), text: $certPassword)
            Button(wtLang.tr("Import Certificate")) {
                guard let data = certData else { return }
                Task {
                    do {
                        try manager.importCertificate(data: data, password: certPassword)
                        certData = nil
                        certPassword = ""
                    } catch {
                        certData = nil
                        certPassword = ""
                        certError = error.localizedDescription
                    }
                }
            }
            Button(wtLang.tr("Cancel"), role: .cancel) {
                certData = nil
                certPassword = ""
            }
        } message: {
            Text(wtLang.tr("Enter the password for %@.", certFileName))
        }
        .alert(
            wtLang.tr("Remove the certificate?"),
            isPresented: $showRemoveCertConfirm
        ) {
            Button(wtLang.tr("Remove Certificate"), role: .destructive) {
                manager.removeCertificate()
            }
            Button(wtLang.tr("Cancel"), role: .cancel) {
                showRemoveCertConfirm = false
            }
        } message: {
            Text(wtLang.tr("This removes the stored .p12 certificate. Guests already signed keep working; new installs will not be signed."))
        }
        .alert(
            wtLang.tr("Export Certificate"),
            isPresented: $showExportPasswordPrompt
        ) {
            SecureField(wtLang.tr("Password"), text: $exportPassword)
            Button(wtLang.tr("Export")) {
                exportCertificateFile()
            }
            Button(wtLang.tr("Cancel"), role: .cancel) {
                exportPassword = ""
            }
        } message: {
            Text(wtLang.tr("Set a password for the exported .p12 — you will need it to import the file in another app. Leave it empty for no password."))
        }
        .alert(wtLang.tr("Export failed"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(wtLang.tr("OK"), role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .sheet(isPresented: $showExportSheet) {
            if let exportURL {
                CertificateExportSheet(url: exportURL) {
                    // Do not mutate presentation state
                    // synchronously inside the sheet's dismissal
                    // completion — defer so the dismissal
                    // finishes first, then clean up the file.
                    DispatchQueue.main.async {
                        deleteExportFile()
                    }
                }
            }
        }
        .alert(
            wtLang.tr("Sign out?"),
            isPresented: $showSignOutConfirm
        ) {
            Button(wtLang.tr("Sign Out"), role: .destructive) {
                auth.signOut()
            }
            Button(wtLang.tr("Cancel"), role: .cancel) {
                showSignOutConfirm = false
            }
        } message: {
            Text(wtLang.tr("This clears the saved Apple ID session and removes the stored container certificate. Guests already signed keep working; new installs will not be signed until you sign in again or import a .p12."))
        }
        .alert(
            wtLang.tr("Revoke this certificate?"),
            isPresented: Binding(
                get: { certToRevoke != nil },
                set: { if !$0 { certToRevoke = nil } }
            ),
            presenting: certToRevoke
        ) { cert in
            Button(wtLang.tr("Revoke"), role: .destructive) {
                auth.revokeCertificate(cert)
            }
            Button(wtLang.tr("Cancel"), role: .cancel) {
                certToRevoke = nil
            }
        } message: { _ in
            Text(wtLang.tr("Revoking frees the certificate slot. The certificate is gone for every app signed with it — installs signed with it stop launching until they are re-signed."))
        }
        .alert(
            wtLang.tr("Delete %@?", guestToDelete?.displayName ?? ""),
            isPresented: Binding(
                get: { guestToDelete != nil },
                set: { if !$0 { guestToDelete = nil } }
            ),
            presenting: guestToDelete
        ) { guest in
            Button(wtLang.tr("Delete"), role: .destructive) {
                manager.delete(guest)
            }
            Button(wtLang.tr("Cancel"), role: .cancel) {
                guestToDelete = nil
            }
        } message: { _ in
            Text(wtLang.tr("This deletes the guest app and its data container."))
        }
    }

    /// Build the fresh .p12 with the user's chosen password and
    /// stage it as a temp file for the share sheet. The password
    /// is cleared the moment it is copied — never stored, never
    /// logged.
    private func exportCertificateFile() {
        let password = exportPassword
        exportPassword = ""
        do {
            let data = try manager.exportCertificate(password: password)
            if let old = exportURL {
                try? FileManager.default.removeItem(at: old)
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("WorkTweaks-Certificate.p12")
            try data.write(to: url, options: .atomic)
            exportURL = url
            // Do NOT present the share sheet synchronously here:
            // this runs from the Export alert's button action,
            // and a modal transition begun while the alert is
            // still dismissing is aborted by UIKit with
            // NSInternalInconsistencyException (force-close).
            // Defer until the alert's dismissal animation has
            // finished; a bare main.async can still land inside
            // it, so use a short fixed delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showExportSheet = true
            }
        } catch {
            let message = error.localizedDescription
            // Same race for the error alert: presenting it
            // synchronously from inside the Export alert's
            // action collides with the dismissal — defer it too.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                exportError = message
            }
        }
    }

    /// Delete the staged export after the share sheet closes —
    /// the .p12 never lingers on disk.
    private func deleteExportFile() {
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportURL = nil
    }
}

// MARK: - Certificate export share sheet
//
// UIActivityViewController with a completion handler: the
// exported .p12 lives in a temp file, and the file is deleted
// once the sheet is dismissed — the .p12 never lingers on disk.
private struct CertificateExportSheet: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onDismiss() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
