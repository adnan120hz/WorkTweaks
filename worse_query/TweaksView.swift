import SwiftUI

struct TweaksView: View {
    @ObservedObject var console: Console
    @ObservedObject var manager: GestaltManager

    @State private var infoTweak: GestaltTweak?
    @State private var showRevertConfirm = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                actionSection
                tweaksSection
                footerSection
            }
            .navigationTitle("WorkTweaks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        manager.load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(manager.isLoading)
                }
            }
            .alert(item: $infoTweak) { tweak in
                Alert(
                    title: Text(tweak.title),
                    message: Text(tweak.warning ?? "No additional information."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .confirmationDialog("Revert all tweaks?", isPresented: $showRevertConfirm) {
                Button("Revert", role: .destructive) {
                    manager.revert()
                }
            } message: {
                Text("This restores the original MobileGestalt backup.")
            }
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: manager.isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(manager.isValid ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isValid ? "MobileGestalt loaded" : "Not loaded")
                        .font(.subheadline.weight(.semibold))
                    Text(manager.lastError ?? "Sandbox extension is ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                manager.apply()
                console.output += "\n[WorkTweaks] Apply finished. A pre-apply backup was saved — see the Backup tab. Respring required.\n"
            } label: {
                Label("Apply Tweaks", systemImage: "checkmark.circle.fill")
            }
            .disabled(!manager.isValid)

            Button(role: .destructive) {
                showRevertConfirm = true
            } label: {
                Label("Revert Tweaks", systemImage: "arrow.uturn.backward.circle")
            }
            .disabled(!manager.isValid || manager.originalSnapshot == nil)
        } footer: {
            Text("Apply saves a backup of the current state first. Turning a tweak off restores its keys from the original backup. Respring after applying.")
        }
    }

    private var tweaksSection: some View {
        Section {
            ForEach(TweakCatalog.all) { tweak in
                TweakRow(
                    tweak: tweak,
                    isOn: Binding(
                        get: { manager.enabled.contains(tweak.id) },
                        set: { manager.set(tweak, enabled: $0) }
                    ),
                    onInfo: { infoTweak = tweak }
                )
            }
        } header: {
            Label("Tweaks", systemImage: "slider.horizontal.3")
        } footer: {
            Text("These tweaks can break features or soft-brick your device. Use at your own risk.")
        }
    }

    private var footerSection: some View {
        Section {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Ported from rooootdev/mond. UI simplified for WorkTweaks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Row

struct TweakRow: View {
    let tweak: GestaltTweak
    @Binding var isOn: Bool
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tweak.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(tweak.title)
                    .font(.subheadline.weight(.medium))
                Text(tweak.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if tweak.warning != nil {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
