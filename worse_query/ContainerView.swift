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
                        .padding(.bottom, 10)
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
                        .padding(.bottom, 10)
                    }
                }
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
                                        manager.launch(guest)
                                    } label: {
                                        Label(wtLang.tr("Launch"), systemImage: "play.fill")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.borderedProminent)
                                } else if guest.is32bit {
                                    Text(wtLang.tr("32-bit — needs JIT (Phase 3)"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if !guest.signed {
                                    Text(wtLang.tr("Needs certificate to launch"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }

            WTSectionCard {
                Text(wtLang.tr("JIT is not available yet — it arrives in a later update."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .navigationTitle(wtLang.tr("Install IPA on Container"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.refresh()
            manager.refreshCertificate()
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
}
