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
// uses the primary icon (nil) and the other three languages
// use alternates:
//   en-US   -> nil (primary, blue)
//   id      -> AppIcon-ID (red #E7000B, white WT)
//   zh-Hans -> AppIcon-CN (deep red #DE2910, gold WT)
//   vi      -> AppIcon-VN (bright red #DA251D, yellow WT)
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
