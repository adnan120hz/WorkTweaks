import SwiftUI
import UIKit

// MARK: - Packages tab (all tweaks)
//
// Sileo's Packages tab, for WorkTweaks: every tweak in the
// catalog, in one flat alphabetical list, each as a Sileo
// package row. The Featured tab groups them by section; this
// tab is the complete index (and what the Sources tab's
// "All Tweaks" row opens).

struct SileoPackagesView: View {
    @ObservedObject var manager: GestaltManager

    @State private var infoTitle: String?
    @State private var infoMessage: String = ""

    private var showInfo: Binding<Bool> {
        Binding(
            get: { infoTitle != nil },
            set: { if !$0 { infoTitle = nil } }
        )
    }

    /// The whole catalog, alphabetical, with the same
    /// per-device conditionals as the Featured tab.
    private var allTweaks: [GestaltTweak] {
        TweakCatalog.all.filter { tweak in
            if tweak.id == "tap_to_wake" && !hasHomeButton() { return false }
            if tweak.id == "stage_manager_support" && UIDevice.current.userInterfaceIdiom != .pad { return false }
            return true
        }
        .sorted { $0.title < $1.title }
    }

    var body: some View {
        NavigationStack {
            SileoPage {
                ForEach(allTweaks) { tweak in
                    SileoTweakRow(manager: manager, tweak: tweak, onInfo: showInfo(for:))
                }
            }
            .navigationTitle("Packages")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert(infoTitle ?? "", isPresented: showInfo) {
            Button("OK") { infoTitle = nil }
        } message: {
            Text(infoMessage)
        }
    }

    private func showInfo(for tweak: GestaltTweak) {
        infoTitle = tweak.title
        infoMessage = tweak.infoMessage ?? ""
    }
}
