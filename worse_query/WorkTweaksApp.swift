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
        // Persistent JIT diagnostics: hand the App Group log
        // path to the C helper BEFORE the resume path runs, so
        // the ObjC self-open handler (which SIGKILLs) writes to
        // the same file the Swift side logs to.
        WTJITDiag.setPathIfNeeded()
        // Install IPA on Container (Phase 3, JIT): if JIT was armed
        // for a guest, attach the debugserver session to our own pid
        // BEFORE the guest bootstrap runs — the guest must never make
        // a JIT call before the debugger is attached. On failure the
        // guest still launches, JIT-less, and the failure is recorded.
        ContainerJITManager.resumePendingSessionIfNeeded()
        ContainerLaunch.checkSelectedGuest()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(WTLangStore.shared)
        }
    }
}
