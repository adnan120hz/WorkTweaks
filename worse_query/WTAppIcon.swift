import UIKit

// MARK: - Alternate app icons (v7.0)
//
// The app icon color follows the language. The recolored
// variants (worse_query/AppIcon-{ID,CN,VN,RU,AR,BR,ES,FR}.png
// — 1024x1024, recolored from the existing artwork with
// Python PIL, WT design intact) are declared under
// CFBundleIcons > CFBundleAlternateIcons by the CI
// PlistBuddy step (see .github/workflows/build-ipa.yml);
// iOS scales the 1024 image as needed.
//
// The current blue icon IS the English (US) look, so en-US
// uses the primary icon (nil) and the other eight languages
// use alternates:
//   en-US   -> nil (primary, blue)
//   id      -> AppIcon-ID (red #E7000B, white WT)
//   vi      -> AppIcon-VN (bright red #DA251D, yellow WT)
//   ru      -> AppIcon-RU (blue #0039A6 field, white W + red T)
//   zh-Hans -> AppIcon-CN (deep red #DE2910, gold WT)
//   ar      -> AppIcon-AR (green #006C35, white WT)
//   pt-BR   -> AppIcon-BR (green #009C3B, yellow WT)
//   es      -> AppIcon-ES (red #AA151B, yellow WT)
//   fr      -> AppIcon-FR (blue #0055A4 field, white W + red T;
//             lighter blue than RU, so the two never read
//             as the same)
//
// iOS shows a small system alert when the icon changes —
// that is stock iOS behavior, not something the app
// controls. apply() no-ops when the desired icon is
// already active, so there is no alert on launch.

enum WTAppIcon {
    static func alternateName(for language: WTLanguage) -> String? {
        switch language {
        case .enUS: return nil
        case .id: return "AppIcon-ID"
        case .vi: return "AppIcon-VN"
        case .ru: return "AppIcon-RU"
        case .zhHans: return "AppIcon-CN"
        case .ar: return "AppIcon-AR"
        case .ptBR: return "AppIcon-BR"
        case .es: return "AppIcon-ES"
        case .fr: return "AppIcon-FR"
        }
    }

    static func apply(for language: WTLanguage) {
        apply(desired: alternateName(for: language), retried: false)
    }

    /// `desired` is the icon for the language that was current
    /// when the change was asked for. On failure iOS is usually
    /// refusing a rapid successive change (the user switching
    /// languages quickly, or the previous change's system alert
    /// still up), so one retry a second later covers it — never
    /// more than one. The retry re-reads the CURRENT language
    /// first: if the user switched again inside that second,
    /// the stale retry must not resurrect the old icon.
    private static func apply(desired: String?, retried: Bool) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard UIApplication.shared.alternateIconName != desired else { return }
        UIApplication.shared.setAlternateIconName(desired) { error in
            if let error {
                // The Log tab IS stdout (Console dup2's it at
                // launch), so print is the in-app log path — the
                // same one the [Container] lines use. The failure
                // used to print only the bare error; the wanted
                // icon is what says which switch failed.
                print("[WTIcon] setAlternateIconName failed (want \(desired ?? "primary")): \(error)")
                guard !retried else {
                    print("[WTIcon] icon change failed after retry — icon stays \(UIApplication.shared.alternateIconName ?? "primary").")
                    return
                }
                print("[WTIcon] retrying icon change in 1s…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let current = WTLanguage(rawValue: UserDefaults.standard.string(forKey: WTLangStore.defaultsKey) ?? "en-US") ?? .enUS
                    guard alternateName(for: current) == desired else {
                        print("[WTIcon] language changed again — skipping the stale icon retry.")
                        return
                    }
                    apply(desired: desired, retried: true)
                }
            } else {
                print("[WTIcon] icon changed to \(desired ?? "primary").")
            }
        }
    }
}

// MARK: - In-app header icon (v7.0)
//
// The icon box inside the app (Sandbox header card, Welcome
// screen) shows the same artwork as the home-screen icon for
// the current language: the eight 1024x1024 PNGs shipped at
// the bundle root. The header reads lang.language, so it
// updates live the moment the language changes, in sync
// with the home-screen icon switch.
enum WTHeaderIcon {
    /// Bundle-root PNG name for the current language's icon.
    static func imageName(for language: WTLanguage) -> String {
        switch language {
        case .enUS: return "AppIcon-US"
        case .id: return "AppIcon-ID"
        case .vi: return "AppIcon-VN"
        case .ru: return "AppIcon-RU"
        case .zhHans: return "AppIcon-CN"
        case .ar: return "AppIcon-AR"
        case .ptBR: return "AppIcon-BR"
        case .es: return "AppIcon-ES"
        case .fr: return "AppIcon-FR"
        }
    }

    /// Loads the header icon artwork from the bundle.
    /// UIImage(named:) finds loose bundle-root PNGs; the
    /// explicit path lookup is the fallback. Falls back to
    /// the AppIconDisplay asset so the header never renders
    /// blank if a PNG is ever missing.
    static func image(for language: WTLanguage) -> UIImage {
        let name = imageName(for: language)
        if let image = UIImage(named: name) { return image }
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) { return image }
        return UIImage(named: "AppIconDisplay") ?? UIImage()
    }
}
