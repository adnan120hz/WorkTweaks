import SwiftUI

// MARK: - Unsupported iOS screen (v2.0)
//
// Shown when the device's iOS build is not on the v2.0 allowlist
// (SupportInfo). The tab UI is never entered from here — the only
// ways forward are the Tutorials and License & Credits pages, or
// changing the device's iOS version.

struct UnsupportedView: View {
    @State private var showTutorials = false
    @State private var showLicense = false

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color.orange.opacity(0.18), Color.orange.opacity(0.05), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)
            .ignoresSafeArea(edges: .top)

            ScrollView {
                VStack(spacing: 22) {
                    header
                        .padding(.top, 40)

                    SupportedReleasesCard()

                    actions
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showTutorials) {
            NavigationStack {
                TutorialsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close") { showTutorials = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showLicense) {
            NavigationStack {
                LicenseView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close") { showLicense = false }
                        }
                    }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            IconChip(systemImage: "iphone.slash", color: .orange, size: 76)

            VStack(spacing: 8) {
                Text("This iOS Version Isn't Supported")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Your device is running **\(SupportInfo.deviceSummary)**. WorkTweaks v2.0 only runs on the builds listed below, so the app can't open on this version.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("If you update or downgrade to a supported build, WorkTweaks will open normally.")
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
                Label("Open Tutorials", systemImage: "book")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                showLicense = true
            } label: {
                Label("License & Credits", systemImage: "doc.text")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}
