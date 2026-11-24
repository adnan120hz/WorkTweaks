import UIKit

// MARK: - Alternate app icons (v7.0)
//
// The app icon color follows the language. The recolored
// variants (worse_query/AppIcon-ID.png, AppIcon-CN.png,
// AppIcon-VN.png — 1024x1024, recolored from the existing
// artwork with Python PIL, WT design intact) are declared
// under CFBundleIcons > CFBundleAlternateIcons by the CI
// PlistBuddy step (see .github/workflows/build-ipa.yml);
// iOS scales the 1024 image as needed.
//
// The current blue icon IS the English (US) look, so en-US
// uses the primary icon (nil) and the other four languages
// use alternates:
//   en-US   -> nil (primary, blue)
//   id      -> AppIcon-ID (red #E7000B, white WT)
//   zh-Hans -> AppIcon-CN (deep red #DE2910, gold WT)
//   vi      -> AppIcon-VN (bright red #DA251D, yellow WT)
//   ru      -> AppIcon-RU (blue #0039A6 field, white W + red T)
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
        case .zhHans: return "AppIcon-CN"
        case .vi: return "AppIcon-VN"
        case .ru: return "AppIcon-RU"
        }
    }

    static func apply(for language: WTLanguage) {
        let desired = alternateName(for: language)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard UIApplication.shared.alternateIconName != desired else { return }
        UIApplication.shared.setAlternateIconName(desired) { error in
            if let error {
                print("[WTIcon] setAlternateIconName failed: \(error)")
            }
        }
    }
}

// MARK: - In-app header icon (v7.0)
//
// The icon box inside the app (Sandbox header card, Welcome
// screen) shows the same artwork as the home-screen icon for
// the current language: the four 1024x1024 PNGs shipped at
// the bundle root. The header reads lang.language, so it
// updates live the moment the language changes, in sync
// with the home-screen icon switch.
enum WTHeaderIcon {
    /// Bundle-root PNG name for the current language's icon.
    static func imageName(for language: WTLanguage) -> String {
        switch language {
        case .enUS: return "AppIcon-US"
        case .id: return "AppIcon-ID"
        case .zhHans: return "AppIcon-CN"
        case .vi: return "AppIcon-VN"
        case .ru: return "AppIcon-RU"
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
