import SwiftUI

// MARK: - Adnan.120hz Repository
//
// A built-in catalog of Deploy packages, installable in-app
// through the existing Deploy engine or saved to Files.
//
// The 8 zips live in the app bundle as resources. Display
// data is read from each zip's own manifest.json at runtime
// (via DeployManager.loadPackage) — the manifest is the
// source of truth; nothing about the packages is hardcoded
// here except the bundled file names. Package names and
// descriptions come from the manifests (English) and stay
// untranslated, like CacheExtra stays English.
//
// Install reuses the Deploy flow whole: the detail view
// hosts DeployPreviewSection with the loaded package, so
// resolve, backup, receipt and Deploy History behave exactly
// like importing the same zip through Deploy. Save to Files
// shares the bundled zip through the same share sheet the
// Deploy builder's Export ZIP uses.

// MARK: - Store

enum RepositoryStore {
    /// Bundled zip file names (without extension), in the
    /// order they are listed. The zips sit next to the
    /// sources in worse_query/ and ship in the app bundle.
    static let zipFileNames = [
        "abc-example",
        "collections-sample",
        "editor-app-prefs",
        "free-fire-config",
        "free-fire-max-config",
        "game-config",
        "mobile-legends-config",
        "pubg-mobile-90fps-smooth",
    ]

    struct Entry: Identifiable {
        let fileName: String
        let zipURL: URL
        let zipSize: Int64
        let package: LoadedDeployPackage
        var id: String { fileName }
    }

    /// Load every bundled package. A zip that fails to load
    /// is skipped (and logged) — the list never blocks on
    /// one bad entry.
    static func loadAll() -> [Entry] {
        var entries: [Entry] = []
        for name in zipFileNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "zip") else {
                print("[Repository] missing bundled zip: \(name).zip")
                continue
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            switch DeployManager.loadPackage(from: url) {
            case .success(let package):
                entries.append(Entry(fileName: name, zipURL: url, zipSize: size, package: package))
            case .failure(let error):
                print("[Repository] bundled zip failed to load: \(name).zip — \(error.message)")
            }
        }
        return entries
    }

    /// The Deploy History receipt for this package's target
    /// app, when it was installed before. Matching is by
    /// bundle ID — the one app a package may touch.
    static func installedReceipt(for entry: Entry) -> DeployReceipt? {
        DeployManager.loadHistory().first { $0.receipt.bundleID == entry.package.bundleID }
    }

    /// Human date for a receipt timestamp (ISO8601 in the
    /// receipt; the raw string when it does not parse).
    static func displayDate(_ receipt: DeployReceipt) -> String {
        if let date = ISO8601DateFormatter().date(from: receipt.timestamp) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }
        return receipt.timestamp
    }
}

// MARK: - List

struct RepositoryView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @State private var entries: [RepositoryStore.Entry] = []
    @State private var installedBundleIDs: Set<String> = []

    var body: some View {
        WTGlassPage {
            WTSectionCard {
                Text(wtLang.tr("Packages by Adnan.120hz — tap one to install it into its app, or save its zip in Files."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            if entries.isEmpty {
                WTSectionCard {
                    Text(wtLang.tr("No packages could be loaded from the app bundle."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            } else {
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 14)
                            }
                            NavigationLink {
                                RepositoryDetailView(entry: entry)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(entry.package.name ?? entry.fileName)
                                                .font(.subheadline.weight(.semibold))
                                                .fixedSize(horizontal: false, vertical: true)
                                            if installedBundleIDs.contains(entry.package.bundleID) {
                                                Text(wtLang.tr("Installed"))
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.green)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.green.opacity(0.15), in: Capsule())
                                            }
                                        }
                                        Text(entry.package.bundleID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(wtLang.tr("Files (%d)", entry.package.files.count) + " • " + wtFormatSize(entry.zipSize))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded { _ in SoundEffects.playTap() })
                        }
                    }
                }
            }
        }
        .navigationTitle("Adnan.120hz Repository")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            entries = RepositoryStore.loadAll()
            installedBundleIDs = Set(DeployManager.loadHistory().map { $0.receipt.bundleID })
        }
    }
}

// MARK: - Detail (install via Deploy + save to Files)

struct RepositoryDetailView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    let entry: RepositoryStore.Entry

    @StateObject private var deployManager = DeployManager()
    @State private var package: LoadedDeployPackage?
    @State private var resolveRequest = UUID()
    @State private var shareItem: RepositoryShareItem?

    private struct RepositoryShareItem: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    var body: some View {
        WTGlassPage {
            if let receipt = RepositoryStore.installedReceipt(for: entry) {
                WTSectionCard {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wtLang.tr("Installed"))
                                .font(.subheadline.weight(.semibold))
                            Text(wtLang.tr("Installed on %@", RepositoryStore.displayDate(receipt)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            WTSectionCard {
                Button {
                    SoundEffects.playTap()
                    shareItem = RepositoryShareItem(url: entry.zipURL)
                } label: {
                    Label(wtLang.tr("Save to Files"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // The install itself is the Deploy flow whole:
            // manifest, files, target resolution, Apply and
            // result — same as importing this zip in Deploy.
            DeployPreviewSection(
                appDataManager: AppDataManager.shared,
                package: $package,
                deployManager: deployManager,
                resolveRequest: $resolveRequest
            )
        }
        .navigationTitle(entry.package.name ?? entry.fileName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            DeployShareSheet(items: [item.url])
        }
        .onAppear {
            // Present the bundled package into the Deploy
            // preview exactly the way a fresh import lands
            // there — resolving starts by itself.
            if package == nil {
                package = entry.package
                resolveRequest = UUID()
            }
        }
    }
}
