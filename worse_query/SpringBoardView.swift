import SwiftUI

// MARK: - SpringBoard tab (v6.1)
//
// Its own menu, not tucked into Tweaks, and its own system:
// the keys live in `com.apple.springboard.plist` (HomeDomain)
// and in the managed springboard plist (ManagedPreferencesDomain),
// and are applied by the iOS 26 partial restore — not by the
// MobileGestalt/CacheExtra tweak system. Only for iOS 27.

struct SpringBoardView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    let console: Console

    @State private var showBatteryPercentage = false
    @State private var disableDynamicIsland = false
    @State private var showRisk = false
    @State private var applyMessage: String?
    @State private var isApplying = false
    @State private var showPhotoBackup = false
    @State private var showAllBackups = false
    @State private var transport = TransportGate.check()

    private var hasAny: Bool { showBatteryPercentage || disableDynamicIsland }

    var body: some View {
        NavigationStack {
            WTGlassPage {
                if !transport.isReady {
                    TransportGateCard(status: transport) {
                        transport = TransportGate.check()
                    }
                }
                introCard
                batteryCard
                dynamicIslandCard
                photoBackupCard
                applyCard
                ApplyDangerWarning()
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
            .navigationTitle("SpringBoard")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { transport = TransportGate.check() }
            .alert(wtLang.tr("Apply — read this first"), isPresented: $showRisk) {
                Button(wtLang.tr("Cancel"), role: .cancel) { }
                Button(wtLang.tr("Apply Anyway"), role: .destructive) {
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
                Text("SpringBoard")
                    .font(.headline)
                Text(wtLang.tr("SpringBoard options — battery percentage and Dynamic Island. iOS 27 only. A separate system from the Tweaks tab. LiveContainer is not recommended for this — use a direct install (Signed Apps) instead."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Battery percentage

    private var batteryCard: some View {
        WTSectionCard(header: wtLang.tr("Battery")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(wtLang.tr("Battery Percentage"), isOn: $showBatteryPercentage)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                Text(wtLang.tr("Shows the battery percentage in the status bar. Key: SBShowBatteryPercentage in com.apple.springboard.plist."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Dynamic Island

    private var dynamicIslandCard: some View {
        WTSectionCard(header: wtLang.tr("Dynamic Island")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(wtLang.tr("Disable Dynamic Island System"), isOn: $disableDynamicIsland)
                    .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                Text(wtLang.tr("Disables the Dynamic Island system completely — not just hiding it. Key: SBSuppressDynamicIslandCompletely in the managed com.apple.springboard.plist (set = 1)."))
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
        WTSectionCard(header: wtLang.tr("Photos & Videos")) {
            VStack(alignment: .leading, spacing: 0) {
                Text(wtLang.tr("A partial restore can affect photos and videos. Back them up first — optional, you can skip it."))
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
                        Text(wtLang.tr("Backup Your Photos & Videos Here!"))
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
                        Text(wtLang.tr("Your All BackUP Files Here!"))
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
        WTSectionCard(header: wtLang.tr("Apply")) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    SoundEffects.playTap()
                    showRisk = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text(isApplying ? wtLang.tr("Applying…") : wtLang.tr("Apply SpringBoard"))
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isApplying || !hasAny || !transport.isReady)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func runApply() {
        isApplying = true
        applyMessage = nil
        Task {
            let result = await PartialRestoreEngine.shared.applySpringBoard(
                showBatteryPercentage: showBatteryPercentage,
                suppressDynamicIsland: disableDynamicIsland,
                console: console
            )
            await MainActor.run {
                isApplying = false
                applyMessage = result
            }
        }
    }
}
