import SwiftUI

// MARK: - Splash Ad Cache Lock page
//
// Lists the ad-cache targets found in app containers and
// App Groups, with per-target Lock / Unlock / Harden and a
// Lock All button, plus whitelist management. All strings
// are English, like the rest of the app.

struct AdCacheBlockerView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var manager = AdCacheBlocker()
    @StateObject private var appData = AppDataManager.shared
    @State private var newBundleRule = ""

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: wtLang.tr("About this feature"), footer: wtLang.tr("This is NOT an adblock: locking only stops ad assets landing on disk. Ads downloaded live over the network when the app opens can still appear.")) {
                Text(wtLang.tr("Splash Ad Cache Lock finds the folders ad SDKs use to cache splash (launch) ads, empties them, and locks them read-only so the app cannot rebuild its splash-ad cache. Locks apply only to third-party app folders — never to system folders, Documents, or the app itself."))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            WTSectionCard(header: wtLang.tr("Scan")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            SoundEffects.playTap()
                            manager.scan()
                        } label: {
                            Label(manager.isScanning ? wtLang.tr("Scanning…") : wtLang.tr("Scan for Ad Targets"), systemImage: "magnifyingglass")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.isScanning)
                        Spacer(minLength: 0)
                        if manager.isScanning {
                            ProgressView()
                        }
                    }
                    if !manager.scanPhase.isEmpty {
                        Text(manager.scanPhase)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let summary = manager.scanSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if appData.isScanning {
                        Text(wtLang.tr("The App Data scan is still running — ad targets appear once it finishes."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if let result = manager.lastResult {
                WTSectionCard {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            WTSectionCard(header: wtLang.tr("Ad Targets (%d)", manager.targets.count), footer: wtLang.tr("Locked folders are read-only (0555) with a sentinel file inside; config files are emptied and locked (0444). A Weak Lock is a locked folder missing its sentinel — tap Harden to add it.")) {
                VStack(alignment: .leading, spacing: 0) {
                    if manager.targets.isEmpty {
                        Text(manager.isScanning ? wtLang.tr("Scanning…") : wtLang.tr("No ad targets found yet. Tap Scan above."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(Array(manager.targets.enumerated()), id: \.element.id) { index, target in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            targetRow(target)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            WTSectionCard(header: wtLang.tr("Lock All"), footer: wtLang.tr("Locks every target below that still needs action. Whitelisted targets are always skipped.")) {
                Button {
                    SoundEffects.playTap()
                    manager.lockAll()
                } label: {
                    HStack(spacing: 10) {
                        Label(wtLang.tr("Lock All"), systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Text(wtLang.tr("%d to lock", manager.targets.filter { $0.needsAction }.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .disabled(manager.isLockingAll || manager.isScanning || manager.targets.allSatisfy { !$0.needsAction })
            }

            WTSectionCard(header: wtLang.tr("Whitelist"), footer: wtLang.tr("A whitelisted bundle id (and its App Groups) or exact path is never locked by Lock All. Newly whitelisted targets are restored writable right away. SMZDM is whitelisted by default — its splash cache is known to crash the app when locked.")) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(manager.rules.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 14)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.value)
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(wtLang.tr("%@ — %@", rule.kind == .bundleID ? wtLang.tr("Bundle ID") : wtLang.tr("Exact path"), rule.note))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Button {
                                SoundEffects.playTap()
                                manager.removeRule(rule)
                            } label: {
                                Text(wtLang.tr("Remove"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                    Divider()
                        .padding(.leading, 14)
                    HStack(spacing: 8) {
                        TextField(wtLang.tr("Bundle ID to whitelist"), text: $newBundleRule)
                            .font(.subheadline)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            SoundEffects.playTap()
                            manager.addBundleRule(newBundleRule)
                            newBundleRule = ""
                        } label: {
                            Text(wtLang.tr("Add"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(newBundleRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(wtLang.tr("Splash Ad Cache Lock"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            appData.scanIfNeeded()
            manager.scanIfNeeded()
        }
    }

    private func targetRow(_ target: AdLockTarget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(target.label)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(target.stateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor(target))
            }
            Text(target.bundleID)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(target.relativePath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(wtFormatSize(target.bytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if target.isWhitelisted {
                    Text(wtLang.tr("Whitelisted"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if target.isWeakLock {
                        Button {
                            SoundEffects.playTap()
                            manager.harden(target)
                        } label: {
                            Text(wtLang.tr("Harden"))
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if target.isLocked {
                        Button {
                            SoundEffects.playTap()
                            manager.setLocked(target, locked: false)
                        } label: {
                            Text(wtLang.tr("Unlock"))
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button {
                            SoundEffects.playTap()
                            manager.setLocked(target, locked: true)
                        } label: {
                            Text(wtLang.tr("Lock"))
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Button {
                        SoundEffects.playTap()
                        manager.addExactPathRule(for: target)
                    } label: {
                        Text(wtLang.tr("Whitelist"))
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .disabled(manager.busyTargetID == target.id || manager.isLockingAll)
    }

    private func stateColor(_ target: AdLockTarget) -> Color {
        if target.isWhitelisted { return .secondary }
        if target.isLocked { return target.isWeakLock ? .orange : .green }
        return .primary
    }
}
