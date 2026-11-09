import SwiftUI

@main
struct WorkTweaksApp: App {
    init() {
        // mond (mond.swift) registers these defaults; `atomic_write`
        // is mond's "Persist after reboot" — MobileGestalt is rewritten
        // in place on the same inode so iOS does not regenerate the
        // cache (and wipe the tweaks) on reboot/respring.
        UserDefaults.standard.register(defaults: [
            "atomic_write": true
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
