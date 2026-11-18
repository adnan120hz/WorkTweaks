import SwiftUI

// MARK: - SpringBoard tab (v6.1)
//
// Its own menu, not tucked into Tweaks, and its own system:
// the keys live in `com.apple.springboard.plist` (HomeDomain)
// and in the managed springboard plist (ManagedPreferencesDomain),
// and are applied by the iOS 26 partial restore — not by the
// MobileGestalt/CacheExtra tweak system. Only for iOS 27.

struct SpringBoardView: View {
    let console: Console

    @State private var showBatteryPercentage = false
    @State private var suppressDynamicIsland = false
    @State private var showRisk = false
    @State private var applyMessage: String?
    @State private var isApplying = false
    @State private var showPhotoBackup = false
    @State private var showAllBackups = false

    private var hasAny: Bool { showBatteryPercentage || suppressDynamicIsland }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introCard
                    batteryCard
                    dynamicIslandCard
                    photoBackupCard
                    applyCard
                    if let applyMessage {
                        Text(applyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("SpringBoard")
            .navigationBarTitleDisplayMode(.large)
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
                Text("SpringBoard")
                    .font(.headline)
                Text("SpringBoard options — battery percentage and Dynamic Island suppression. iOS 27 only. Applied by the iOS 26 partial restore — a separate system from the Tweaks tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Battery percentage

    private var batteryCard: some View {
        WTSectionCard(header: "Battery") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Battery Percentage", isOn: $showBatteryPercentage)
                Text("Shows the battery percentage in the status bar. Key: SBShowBatteryPercentage in com.apple.springboard.plist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Dynamic Island

    private var dynamicIslandCard: some View {
        WTSectionCard(header: "Dynamic Island") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Suppress Dynamic Island Completely", isOn: $suppressDynamicIsland)
                Text("Hides the Dynamic Island entirely. Key: SBSuppressDynamicIslandCompletely in the managed com.apple.springboard.plist (set = 1).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Photo backup (safeguard before a restore)

    private var photoBackupCard: some View {
        WTSectionCard(header: "Photos & Videos") {
            VStack(alignment: .leading, spacing: 12) {
                Text("A partial restore can affect photos and videos. Back them up first — optional, you can skip it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Backup Your Photos & Videos Here!") {
                    SoundEffects.playTap()
                    showPhotoBackup = true
                }
                .buttonStyle(.borderedProminent)
                Button("Your All BackUP Files Here!") {
                    SoundEffects.playTap()
                    showAllBackups = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Apply (iOS 26 partial restore)

    private var applyCard: some View {
        WTSectionCard(header: "Apply") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Applies by the iOS 26 partial restore. iOS 27 only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    SoundEffects.playTap()
                    showRisk = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text(isApplying ? "Applying…" : "Apply SpringBoard")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isApplying || !hasAny)
            }
        }
    }

    private func runApply() {
        isApplying = true
        applyMessage = nil
        Task {
            let result = await PartialRestoreEngine.shared.applySpringBoard(
                showBatteryPercentage: showBatteryPercentage,
                suppressDynamicIsland: suppressDynamicIsland,
                console: console
            )
            await MainActor.run {
                isApplying = false
                applyMessage = result
            }
        }
    }
}
