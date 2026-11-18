import SwiftUI

// MARK: - Status Bar tab (v6.1)
//
// Its own menu, not tucked into Tweaks, and its own system:
// the overrides live in HomeDomain (`StatusBarOverrides.archive`)
// and are applied by the iOS 26 partial restore — not by the
// MobileGestalt/CacheExtra tweak system. Only for iOS 27.

struct StatusBarView: View {
    let console: Console

    @State private var overrides = StatusBarOverrides()
    @State private var hideVPN = false
    @State private var hideLocation = false
    @State private var hideAlarm = false
    @State private var showRisk = false
    @State private var applyMessage: String?
    @State private var isApplying = false
    @State private var showPhotoBackup = false
    @State private var showAllBackups = false

    /// Identifiers hidden through the archive's suppressed set.
    /// Hiding is partial — some icons still show.
    private var suppressedIdentifiers: Set<String> {
        var set = Set<String>()
        if hideVPN { set.insert("vpn") }
        if hideLocation { set.insert("location") }
        if hideAlarm { set.insert("alarm") }
        return set
    }

    var body: some View {
        NavigationStack {
            WTGlassPage {
                introCard
                carrierCard
                networkCard
                signalCard
                hideIconsCard
                photoBackupCard
                applyCard
                if let applyMessage {
                    Text(applyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                }
                // Clear the floating tab bar so the last card
                // is not hidden behind it.
                Color.clear.frame(height: 60)
            }
            .navigationTitle("Status Bar")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Apply — read this first", isPresented: $showRisk) {
                Button("Cancel", role: .cancel) { }
                Button("Apply Anyway", role: .destructive) {
                    runApply()
                }
            } message: {
                Text(PartialRestoreEngine.riskText)
            }
            .sheet(isPresented: $showPhotoBackup) {
                PhotoBackupView()
            }
            .sheet(isPresented: $showAllBackups) {
                PhotoRestoreView()
            }
        }
    }

    // MARK: Intro

    private var introCard: some View {
        WTSectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Status Bar")
                    .font(.headline)
                Text("Change the carrier name, network label and signal bars. iOS 27 only. A separate system from the Tweaks tab. LiveContainer is not recommended for this — use a direct install (Signed Apps) instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Carrier name

    private var carrierCard: some View {
        WTSectionCard(header: "Custom Carrier Name") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Carrier name (Primary)", isOn: $overrides.carrierName.set)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                if overrides.carrierName.set {
                    TextField("Carrier name (max 64)", text: $overrides.carrierName.text)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                Toggle("Carrier name (Secondary)", isOn: $overrides.secondaryCarrierName.set)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                if overrides.secondaryCarrierName.set {
                    TextField("Secondary carrier name (max 64)", text: $overrides.secondaryCarrierName.text)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                Text("Dual SIM: primary is the line used for data, secondary is the other line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Network type

    private var networkCard: some View {
        WTSectionCard(header: "Network Type Label") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Network label (Primary)", isOn: $overrides.dataNetworkType.set)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                if overrides.dataNetworkType.set {
                    Picker("Network type", selection: $overrides.dataNetworkType.value) {
                        ForEach(StatusBarNetworkType.options, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Toggle("Network label (Secondary)", isOn: $overrides.secondaryDataNetworkType.set)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                if overrides.secondaryDataNetworkType.set {
                    Picker("Secondary network type", selection: $overrides.secondaryDataNetworkType.value) {
                        ForEach(StatusBarNetworkType.options, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Text("Forces the label shown (5G, 5G+, 5G UC, LTE, …). Limited — the label is display-only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Signal bars

    private var signalCard: some View {
        WTSectionCard(header: "Signal Bars") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Signal bars (Primary)", isOn: $overrides.signalBars.set)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                if overrides.signalBars.set {
                    Stepper("Bars: \(overrides.signalBars.value)", value: $overrides.signalBars.value, in: 0...4)
                }
                Toggle("Signal bars (Secondary)", isOn: $overrides.secondarySignalBars.set)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                if overrides.secondarySignalBars.set {
                    Stepper("Secondary bars: \(overrides.secondarySignalBars.value)", value: $overrides.secondarySignalBars.value, in: 0...4)
                }
                Text("Sets how many bars are drawn. Static — it does not follow the real signal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Hide icons

    private var hideIconsCard: some View {
        WTSectionCard(header: "Hide Status Bar Icons") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Hide VPN icon", isOn: $hideVPN)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                Toggle("Hide Location icon", isOn: $hideLocation)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                Toggle("Hide Alarm icon", isOn: $hideAlarm)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                Text("Partial — some icons may still show. Hidden through the archive's suppressed identifiers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Photo backup & restore (its own menu)

    private var photoBackupCard: some View {
        WTSectionCard(header: "Photos & Videos") {
            VStack(alignment: .leading, spacing: 0) {
                Text("A partial restore can affect photos and videos. Back them up first — optional, you can skip it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                Divider()
                    .padding(.leading, 14)
                Button {
                    SoundEffects.playTap()
                    showPhotoBackup = true
                } label: {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                            .foregroundStyle(.secondary)
                        Text("Backup Your Photos & Videos Here!")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
                    .padding(.leading, 14)
                Button {
                    SoundEffects.playTap()
                    showAllBackups = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.secondary)
                        Text("Your All BackUP Files Here!")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Apply (iOS 26 partial restore)

    private var applyCard: some View {
        WTSectionCard(header: "Apply") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    SoundEffects.playTap()
                    showRisk = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text(isApplying ? "Applying…" : "Apply Status Bar")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isApplying || (!overrides.hasAny && suppressedIdentifiers.isEmpty))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func runApply() {
        isApplying = true
        applyMessage = nil
        Task {
            let result = await PartialRestoreEngine.shared.applyStatusBar(
                overrides: overrides,
                suppressedIdentifiers: suppressedIdentifiers,
                console: console
            )
            await MainActor.run {
                isApplying = false
                applyMessage = result
            }
        }
    }
}
