import SwiftUI

// MARK: - Cache Data Cleaner pages
//
// Pick an app from the shared App Data container scan, see
// how much cache it keeps in Library/Caches and tmp, and
// empty those two folders — with a confirmation first.
// Documents and the rest of Library are never touched.
// All measuring and cleaning goes through
// CacheCleanerManager (one short grant per operation, sizes
// measured before and after, failures counted honestly).
//
// The pages render as Liquid Glass cards (WTGlassPage /
// WTSectionCard), like every other page since v3.8.

struct CacheCleanerView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject private var appData = AppDataManager.shared

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: wtLang.tr("Cache Data Cleaner"), footer: wtLang.tr("Cache lives in two places inside an app's data container: Library/Caches and tmp. Only the contents of those two folders are deleted — the folders themselves stay, and Documents and the rest of Library are never touched.")) {
                Group {
                    if appData.isScanning {
                        HStack(spacing: 10) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(appData.scanPhase)
                                    .font(.subheadline)
                                Text(wtLang.tr("The container scan is shared with App Data and runs once per app session."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if let summary = appData.scanSummary {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(summary)
                                .font(.subheadline)
                            if appData.containers.isEmpty {
                                Text(wtLang.tr("No containers were found, so there is nothing to clean."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(wtLang.tr("Pick an app to see its cache and clean it."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(wtLang.tr("Preparing the container scan…"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if !appData.containers.isEmpty {
                WTSectionCard(header: wtLang.tr("Apps")) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(appData.containers.enumerated()), id: \.element.id) { index, container in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            NavigationLink {
                                CacheCleanerDetailView(container: container)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(container.bundleID)
                                            .font(.subheadline.weight(.semibold))
                                        if container.bundleID != container.directoryName {
                                            Text(container.directoryName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(wtLang.tr("Cache Data Cleaner"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(wtLang.tr("Rescan")) {
                    appData.rescan()
                }
                .disabled(appData.isScanning)
            }
        }
        .onAppear {
            appData.scanIfNeeded()
        }
    }
}

// MARK: - One app's cache

struct CacheCleanerDetailView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    let container: AppContainer
    @StateObject private var manager = CacheCleanerManager()

    /// The locations a pending confirmation will clean.
    @State private var pendingLocations: [CacheLocation]?

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: wtLang.tr("App")) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(container.bundleID)
                        .font(.subheadline.weight(.semibold))
                    Text(container.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if let message = manager.statusMessage {
                WTSectionCard {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            WTSectionCard(header: wtLang.tr("Cache Locations"), footer: wtLang.tr("Sizes are measured by walking each folder. An app recreates cache as it runs, so the size grows back over time.")) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(CacheLocation.allCases.enumerated()), id: \.element.id) { index, location in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 14)
                        }
                        locationRow(location)
                    }
                }
                .padding(.vertical, 4)
            }

            if let result = manager.lastResult {
                WTSectionCard(header: wtLang.tr("Last Clean")) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(wtLang.tr("Freed %@", wtFormatSize(result.freedBytes)))
                            .font(.subheadline.weight(.semibold))
                        Text(result.failedCount > 0
                            ? wtLang.tr("%d item(s) removed, %d could not be removed (in use or protected).", result.removedCount, result.failedCount)
                            : wtLang.tr("%d item(s) removed.", result.removedCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            WTSectionCard(header: wtLang.tr("Clean"), footer: wtLang.tr("Cleaning is permanent — cache is not backed up. The app itself, its documents, and its settings are not affected.")) {
                Button {
                    pendingLocations = CacheLocation.allCases
                } label: {
                    HStack(spacing: 10) {
                        Label(wtLang.tr("Clean All Cache"), systemImage: "trash")
                            .font(.subheadline)
                        Spacer(minLength: 0)
                        if manager.didMeasure {
                            Text(wtFormatSize(manager.totalSize(locations: CacheLocation.allCases)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .disabled(manager.isMeasuring || manager.isCleaning || !manager.didMeasure)
            }

            if manager.isMeasuring || manager.isCleaning {
                WTSectionCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(manager.isCleaning ? wtLang.tr("Cleaning…") : wtLang.tr("Measuring cache…"))
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle(wtLang.tr("Cache"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.measureIfNeeded(container: container)
        }
        .confirmationDialog(
            wtLang.tr("Clean cache?"),
            isPresented: Binding(
                get: { pendingLocations != nil },
                set: { if !$0 { pendingLocations = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(wtLang.tr("Clean"), role: .destructive) {
                if let locations = pendingLocations {
                    manager.clean(container: container, locations: locations)
                }
                pendingLocations = nil
            }
            Button(wtLang.tr("Cancel"), role: .cancel) {
                pendingLocations = nil
            }
        } message: {
            if let locations = pendingLocations {
                Text(wtLang.tr("This permanently deletes the contents of %@ in %@ (%@). The folders themselves stay in place.", locations.map { $0.displayName }.joined(separator: wtLang.tr(" and ")), container.bundleID, wtFormatSize(manager.totalSize(locations: locations))))
            }
        }
    }

    private func locationRow(_ location: CacheLocation) -> some View {
        let stat = manager.stats[location]
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(statText(stat))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let stat, stat.exists, stat.size > 0 {
                Button(wtLang.tr("Clean")) {
                    pendingLocations = [location]
                }
                .font(.subheadline)
                .disabled(manager.isMeasuring || manager.isCleaning)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func statText(_ stat: CacheFolderStat?) -> String {
        if manager.isMeasuring { return wtLang.tr("Measuring…") }
        guard let stat else { return wtLang.tr("Not measured yet") }
        if !stat.exists { return wtLang.tr("Not present in this app") }
        if stat.fileCount == 0 { return wtLang.tr("Empty") }
        return wtLang.tr("%@ — %d file(s)", wtFormatSize(stat.size), stat.fileCount)
    }
}
