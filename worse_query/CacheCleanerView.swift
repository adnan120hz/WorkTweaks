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
    @ObservedObject private var appData = AppDataManager.shared

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "Cache Data Cleaner", footer: "Cache lives in two places inside an app's data container: Library/Caches and tmp. Only the contents of those two folders are deleted — the folders themselves stay, and Documents and the rest of Library are never touched.") {
                Group {
                    if appData.isScanning {
                        HStack(spacing: 10) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(appData.scanPhase)
                                    .font(.subheadline)
                                Text("The container scan is shared with App Data and runs once per app session.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if let summary = appData.scanSummary {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(summary)
                                .font(.subheadline)
                            if appData.containers.isEmpty {
                                Text("No containers were found, so there is nothing to clean.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Pick an app to see its cache and clean it.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Preparing the container scan…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if !appData.containers.isEmpty {
                WTSectionCard(header: "Apps") {
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
        .navigationTitle("Cache Data Cleaner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rescan") {
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
    let container: AppContainer
    @StateObject private var manager = CacheCleanerManager()

    /// The locations a pending confirmation will clean.
    @State private var pendingLocations: [CacheLocation]?

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "App") {
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

            WTSectionCard(header: "Cache Locations", footer: "Sizes are measured by walking each folder. An app recreates cache as it runs, so the size grows back over time.") {
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
                WTSectionCard(header: "Last Clean") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Freed \(wtFormatSize(result.freedBytes))")
                            .font(.subheadline.weight(.semibold))
                        Text("\(result.removedCount) item(s) removed\(result.failedCount > 0 ? ", \(result.failedCount) could not be removed (in use or protected)" : "").")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            WTSectionCard(header: "Clean", footer: "Cleaning is permanent — cache is not backed up. The app itself, its documents, and its settings are not affected.") {
                Button {
                    pendingLocations = CacheLocation.allCases
                } label: {
                    HStack(spacing: 10) {
                        Label("Clean All Cache", systemImage: "trash")
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
                        Text(manager.isCleaning ? "Cleaning…" : "Measuring cache…")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle("Cache")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.measureIfNeeded(container: container)
        }
        .confirmationDialog(
            "Clean cache?",
            isPresented: Binding(
                get: { pendingLocations != nil },
                set: { if !$0 { pendingLocations = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clean", role: .destructive) {
                if let locations = pendingLocations {
                    manager.clean(container: container, locations: locations)
                }
                pendingLocations = nil
            }
            Button("Cancel", role: .cancel) {
                pendingLocations = nil
            }
        } message: {
            if let locations = pendingLocations {
                Text("This permanently deletes the contents of \(locations.map { $0.displayName }.joined(separator: " and ")) in \(container.bundleID) (\(wtFormatSize(manager.totalSize(locations: locations)))). The folders themselves stay in place.")
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
                Button("Clean") {
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
        if manager.isMeasuring { return "Measuring…" }
        guard let stat else { return "Not measured yet" }
        if !stat.exists { return "Not present in this app" }
        if stat.fileCount == 0 { return "Empty" }
        return "\(wtFormatSize(stat.size)) — \(stat.fileCount) file(s)"
    }
}
