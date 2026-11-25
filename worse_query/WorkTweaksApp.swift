import SwiftUI

@main
struct WorkTweaksApp: App {
    init() {
        // mond (mond.swift) registers these defaults; `atomic_write`
        // is mond's "Persist after reboot" — MobileGestalt is rewritten
        // in place on the same inode so iOS does not regenerate the
        // cache (and wipe the tweaks) on reboot/respring.
        UserDefaults.standard.register(defaults: [
            "atomic_write": true,
            // Language default: English (US) is the main language.
            "wt.language": "en-US"
        ])
        // Install IPA on Container (Phase 1): the launch-path
        // decision lives here — if a guest was selected, the
        // bootstrap runs instead of the host UI. In Phase 1
        // the bootstrap is not linked yet (litehook pending),
        // so the check only logs honestly and the host UI
        // opens normally. Phase 2 replaces it with the real
        // LiveContainerMain call.
        ContainerLaunch.checkSelectedGuest()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(WTLangStore.shared)
        }
    }
}
