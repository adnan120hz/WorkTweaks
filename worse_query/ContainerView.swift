import SwiftUI
import UniformTypeIdentifiers

// MARK: - Install IPA on Container (Phase 1)
//
// The guest list + IPA import page. Phase 1 installs are stored
// but NOT patched: the executable patching needs the LC ObjC
// core (blocked on litehook — see
// LiveContainerCore/README.LITEHOOK.md), signing lands in
// Phase 2, and launch needs signing or a JIT session
// (Phases 2–3). Every state on this page says that plainly:
// no guest here is launchable yet, and none claims to be.

struct ContainerView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var manager = ContainerManager.shared
    @State private var showImporter = false
    @State private var importError: String?
    @State private var guestToDelete: ContainerGuest?

    var body: some View {
        WTGlassPage {
            WTSectionCard {
                Text(wtLang.tr("Guest apps live in the WorkTweaks App Group and run inside this app. Phase 1 installs and lists them; patching, signing and launch land in later phases."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }

            WTSectionCard {
                Text(wtLang.tr("Launch needs a certificate (Phase 2) or JIT (Phase 3)."))
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
        .alert(wtLang.tr("Install failed"), isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button(wtLang.tr("OK"), role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
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
