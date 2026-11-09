# WorkTweaks

### A MobileGestalt tweak app for iOS 26.0 - 26.7.2 / 27.2, built on the worse_query sandbox escape.

WorkTweaks wraps the `worse_query` proof-of-concept below in a native SwiftUI app (no PartyUI):

- **Tweaks** — toggle MobileGestalt tweaks (Dynamic Island, Always-On Display, Charge Limit, Action Button, Stage Manager, and more), ported from [mond](https://github.com/rooootdev/mond).
- **Backup** — the first successful read saves an *original* backup, and every **Apply** first saves a snapshot of the exact state at apply time. The Backup tab shows what is inside each snapshot (active tweaks and every tweak key's value) and can restore a whole snapshot, a single tweak, or a single key. Turning a tweak off also restores its keys from the original backup instead of just deleting them.
- **Sandbox** — the original worse_query escape / path enumeration tools.
- **Log** — the console output, in its own tab.

Notes:

- The Xcode target is still named `worse_query` on purpose (only the display name is WorkTweaks), and the App Group is unchanged (`group.cc.forcequit.worse-query`) — renaming either requires re-provisioning the App Group, otherwise the escape stops working.
- Changes are written to `com.apple.MobileGestalt.plist`; respring after applying or restoring.
- App icon source lives in `Design/AppIcon.svg`; export it to 1024x1024 PNGs for `AppIcon.appiconset`.

---

# worse_query

### A workgestakt for iOS 26.0 - 26.7.2 / 27.2.

This is a proof-of-concept for developers and isn't useful by itself.

worse_query is the direct successor to [bad_query](https://github.com/forcequitOS/bad_query) and essentially replaces it. To use worse_query, you'll have to set up an App Group container for your app.

worse_query can access these paths:

```
/var/containers/Data/System (iOS 27)
/var/containers/Shared/SystemGroup/* (iOS 27)
/var/mobile/Containers/Data/Application/*
/var/mobile/Containers/Data/InternalDaemon/*
/var/mobile/Containers/Data/PluginKitPlugin/*
/var/mobile/Containers/Shared/AppGroup/*
/var/mobile/Containers/Shared/AppGroup (iOS 27)
```

<sub>**This is not relevant to a jailbreak and never will be.** Please don't mislead people into believing otherwise.</sub>

