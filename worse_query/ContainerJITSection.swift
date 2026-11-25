import SwiftUI

// MARK: - JIT (Install IPA on Container, Phase 3)
//
// The whole JIT card for the Containers page. It REPLACES the
// "JIT is not available yet" card in ContainerView — the parent embeds
// it with one line (see the init + embed line at the bottom of this
// file's header comment; do not edit ContainerView from here).
//
// WHAT THE TOGGLE DOES — and does not do. Turning JIT on for a guest
// arms the session and relaunches into the guest: the guest launch
// kills this process, so the session can only attach on the NEXT
// launch, before the guest runs (`ContainerJITManager
// .resumePendingSessionIfNeeded`, wired in WorkTweaksApp.init by the
// parent). While the guest runs there is no host UI, so the toggle
// CANNOT show a live "JIT is ON" — it shows ARMED, and after the
// guest quits the section shows the last outcome + prepared bytes.
// Anything else would be a fake. The toggle stays OFF when the attach
// fails, with the reason + the external-enabler fallback.
//
// Guest picker: installed guests only. The toggle is disabled for
// guests that can't launch (not patched / not signed / 32-bit) with
// the reason next to it.

struct ContainerJITSection: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var manager: ContainerManager
    @ObservedObject var jitManager: ContainerJITManager

    @State private var selectedGuestID: String?
    @State private var arming = false
    @State private var transport = TransportGate.check()

    private var selectedGuest: ContainerGuest? {
        guard let id = selectedGuestID else { return nil }
        return manager.guests.first { $0.bundleID == id }
    }

    var body: some View {
        WTSectionCard(header: wtLang.tr("JIT")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(wtLang.tr("JIT lets a guest run code it writes itself — emulators and JIT apps need it. One tap arms JIT and relaunches into the guest; the debugger attaches when the guest starts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                transportRows

                if manager.guests.isEmpty {
                    Text(wtLang.tr("No containers installed yet — import an .ipa to add one."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    guestPicker
                    if let guest = selectedGuest {
                        modePicker(for: guest)
                        jitToggle(for: guest)
                    }
                }

                if let error = jitManager.lastError {
                    Text(wtLang.tr(error))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                lastOutcomeCard

                Text(wtLang.tr("If self-attach fails, use the SideInstaller JIT tab or StikDebug — there is no JIT deep link. While the guest runs, keep WorkTweaks in the background: the debugger must stay attached, and closing it ends JIT."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear {
            refreshTransport()
            jitManager.refreshLastOutcome()
            if selectedGuestID == nil {
                selectedGuestID = manager.guests.first(where: \.isLaunchable)?.bundleID
                    ?? manager.guests.first?.bundleID
            }
        }
        .onChange(of: jitManager.isPreparing) { _, preparing in
            if !preparing { arming = false }
        }
        .onChange(of: jitManager.lastError) { _, _ in
            arming = false
        }
    }

    // MARK: - Transport

    private var transportRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            gateRow(ready: transport.hasPairing,
                    label: wtLang.tr("Pairing file"),
                    detail: transport.hasPairing ? wtLang.tr("Saved") : wtLang.tr("Not found — pair this iPhone first"))
            gateRow(ready: transport.vpnUp,
                    label: wtLang.tr("VPN tunnel"),
                    detail: transport.vpnUp ? wtLang.tr("Connected") : wtLang.tr("Not on — open the Local Dev VPN app and connect"))
            gateRow(ready: WTDeviceEnvironment.developerModeIsOn ?? false,
                    label: wtLang.tr("Developer Mode"),
                    detail: developerModeDetail)
            gateRow(ready: WTDeveloperDiskImage.isDownloaded,
                    label: wtLang.tr("Developer disk image"),
                    detail: WTDeveloperDiskImage.isDownloaded
                        ? wtLang.tr("Downloaded")
                        : wtLang.tr("Not downloaded yet — it downloads when you enable JIT"))
            Button {
                SoundEffects.playTap()
                refreshTransport()
                jitManager.refreshLastOutcome()
            } label: {
                Text(wtLang.tr("Refresh Status"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    private var developerModeDetail: String {
        switch WTDeviceEnvironment.developerModeIsOn {
        case true?: return wtLang.tr("On")
        case false?: return wtLang.tr("Off — turn it on under Settings › Privacy & Security › Developer Mode")
        case nil: return wtLang.tr("Unknown — it is checked again when you enable JIT")
        }
    }

    private func refreshTransport() {
        transport = TransportGate.check()
    }

    private func gateRow(ready: Bool, label: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ready ? .green : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Guest + mode

    private var guestPicker: some View {
        Picker(wtLang.tr("Guest"), selection: $selectedGuestID) {
            ForEach(manager.guests) { guest in
                Text(guest.displayName).tag(Optional(guest.bundleID))
            }
        }
        .pickerStyle(.menu)
    }

    private func modePicker(for guest: ContainerGuest) -> some View {
        Picker(wtLang.tr("JIT mode"), selection: Binding(
            get: { jitManager.mode(for: guest) },
            set: { jitManager.setMode($0, for: guest) }
        )) {
            ForEach(WTJITMode.allCases) { mode in
                Text(wtLang.tr(mode.title)).tag(mode)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Toggle

    private func jitToggle(for guest: ContainerGuest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { jitManager.isArmed || arming },
                set: { on in
                    SoundEffects.playTap()
                    if on {
                        arming = true
                        jitManager.enable(guest)
                    } else {
                        arming = false
                        jitManager.disarm()
                    }
                }
            )) {
                Label(wtLang.tr("JIT for %@", guest.displayName), systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(!guest.isLaunchable || jitManager.isBusy)

            if jitManager.isPreparing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(wtLang.tr("Getting JIT ready — Developer Mode, pairing, VPN, disk image…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if jitManager.isArmed {
                Text(wtLang.tr("JIT armed — relaunching into %@…", guest.displayName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !guest.isLaunchable {
                Text(launchBlockerReason(for: guest))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(wtLang.tr("JIT attaches when %@ starts (%@). Turning it on relaunches the app into the guest — the result shows here after the guest quits.", guest.displayName, wtLang.tr(jitManager.jitProtocol(for: guest).title)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func launchBlockerReason(for guest: ContainerGuest) -> String {
        if guest.is32bit {
            return wtLang.tr("32-bit — needs JIT + classic mode, which is not in this build.")
        } else if !guest.isPatched {
            return wtLang.tr("Not patched yet — install it again before enabling JIT.")
        } else {
            return wtLang.tr("Needs certificate to launch — import a .p12 first.")
        }
    }

    // MARK: - Last outcome

    @ViewBuilder
    private var lastOutcomeCard: some View {
        if let outcome = jitManager.lastOutcome, let detail = jitManager.lastOutcomeDetail {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: outcome == "failed" ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(outcome == "failed" ? .red : .green)
                    Text(lastOutcomeTitle(outcome))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Button {
                        SoundEffects.playTap()
                        jitManager.clearLastOutcome()
                    } label: {
                        Text(wtLang.tr("Clear"))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                Text(wtLang.tr(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if jitManager.lastPreparedBytes > 0 {
                    Text(wtLang.tr("%@ of JIT memory prepared", WTJITSession.format(jitManager.lastPreparedBytes)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                if let guest = jitManager.lastGuestName {
                    Text(guest)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func lastOutcomeTitle(_ outcome: String) -> String {
        switch outcome {
        case "detached": return wtLang.tr("JIT was on")
        case "appEnded": return wtLang.tr("Guest quit — JIT session ended")
        case "failed": return wtLang.tr("JIT failed")
        default: return wtLang.tr("JIT session ended")
        }
    }
}

// MARK: - Embed (for the parent)
//
// Exact init:
//
//     ContainerJITSection(manager: manager, jitManager: jitManager)
//
// where `manager` is the ContainerView's `ContainerManager.shared`
// (`@StateObject private var manager = ContainerManager.shared`) and
// `jitManager` is a `@StateObject private var jitManager =
// ContainerJITManager.shared` the parent adds to ContainerView.
//
// One-line embed — replace the "JIT is not available yet" card in
// ContainerView.swift:
//
//     ContainerJITSection(manager: manager, jitManager: jitManager)
//
// Startup wiring (also the parent's — this file does not touch
// WorkTweaksApp): in `WorkTweaksApp.init()`, before
// `ContainerLaunch.checkSelectedGuest()`:
//
//     ContainerJITManager.resumePendingSessionIfNeeded()
//     ContainerLaunch.checkSelectedGuest()
