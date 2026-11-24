import SwiftUI

// MARK: - Unsupported iOS screen (v2.0)
//
// Shown when the device's iOS build is not on the v2.0 allowlist
// (SupportInfo). The tab UI is never entered from here — the only
// ways forward are the Tutorials and License & Credits pages, or
// changing the device's iOS version.

struct UnsupportedView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @State private var showTutorials = false
    @State private var showLicense = false

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(SupportInfo.supportedReleases) { release in
                    SupportedReleaseRow(release: release)
                }
            } header: {
                Text(wtLang.tr("Supported iOS Versions"))
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            actions
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showTutorials) {
            NavigationStack {
                TutorialsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(wtLang.tr("Close")) { showTutorials = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showLicense) {
            NavigationStack {
                LicenseView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(wtLang.tr("Close")) { showLicense = false }
                        }
                    }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 52))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text(wtLang.tr("This iOS Version Isn't Supported"))
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(LocalizedStringKey(wtLang.tr("Your device is running **%@**. WorkTweaks v2.0 only runs on the builds listed below, so the app can't open on this version.", SupportInfo.deviceSummary)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(wtLang.tr("If you update or downgrade to a supported build, WorkTweaks will open normally."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                showTutorials = true
            } label: {
                Label(wtLang.tr("Open Tutorials"), systemImage: "book")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                showLicense = true
            } label: {
                Label(wtLang.tr("License & Credits"), systemImage: "doc.text")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}
