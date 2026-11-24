import Foundation
import Combine
import Darwin

// MARK: - Splash Ad Cache Lock
//
// Finds the folders ad SDKs use to cache splash (launch)
// ads, empties them, and locks them read-only so the app
// cannot rebuild its splash-ad cache: the folder is chmod
// 0555 with a 0-byte sentinel file inside (chmod 0444).
// Single config files are truncated to a minimal valid
// empty payload and chmod 0444. A bare 0555 folder without
// a sentinel is a "Weak Lock" — one tap hardens it.
//
// This is NOT an adblock: locking only stops ad assets
// landing on disk. Ads downloaded live over the network
// when the app opens can still appear.
//
// Mechanism reference: Erosion-CN (Kianuni), GPLv3 —
// AdCacheBlockerView.swift. This file is an original
// implementation of the same mechanism for WorkTweaks
// (AGPL-3.0); see License & Credits. It reuses only the
// app's existing discovery/grant primitives
// (AppDataManager, wtPathleakChildren,
// wtContainerIdentifier, consumeExtension) and writes
// nothing outside third-party app containers — never
// SystemGroup, Gestalt, daemon, bundle, or container
// roots, and never Documents as a whole.

/// One ad-cache folder or config file that can be locked.
struct AdLockTarget: Identifiable {
    enum Source {
        case curated
        case generic
        case configFile
    }

    /// containerPath + "|" + relativePath — unique per target.
    let id: String
    /// Bundle id of the owning app, or the App Group id.
    let bundleID: String
    let containerPath: String
    let relativePath: String
    let isDirectory: Bool
    let label: String
    let source: Source
    var posixMode: Int
    var bytes: Int64
    var hasSentinel: Bool
    var isWhitelisted: Bool

    var url: URL {
        URL(fileURLWithPath: containerPath).appendingPathComponent(relativePath)
    }

    /// Locked means no write bit for anyone.
    var isLocked: Bool { (posixMode & 0o222) == 0 }

    /// A locked folder without the sentinel can still be
    /// emptied by the app's parent — harden it.
    var isWeakLock: Bool { isDirectory && isLocked && !hasSentinel }

    var needsAction: Bool { !isWhitelisted && (!isLocked || isWeakLock) }

    var stateText: String {
        if isWhitelisted { return "Whitelisted" }
        if isLocked { return isWeakLock ? "Weak Lock" : "Locked" }
        return "Unlocked"
    }
}

/// One whitelist rule: a whole bundle id (also covers its
/// group.<bundleID> App Groups) or one exact target path.
struct AdWhitelistRule: Codable, Identifiable {
    enum Kind: String, Codable {
        case bundleID
        case exactPath
    }

    let id: UUID
    let kind: Kind
    let value: String
    let note: String

    init(kind: Kind, value: String, note: String) {
        self.id = UUID()
        self.kind = kind
        self.value = value
        self.note = note
    }
}

final class AdCacheBlocker: ObservableObject {
    /// Sentinel left inside every locked folder. Named for
    /// this app, not for Erosion.
    static let sentinelFileName = ".worktweaks_adlock"

    // MARK: - Curated per-app paths (verified present only)

    /// bundleID -> (relative path, English label). Taobao
    /// paths are two exact paths, not a bootImage* glob.
    static let curatedPaths: [String: [(relPath: String, label: String)]] = [
        "com.sina.weibo": [
            ("Documents/wb_ad_cache", "Weibo Splash Ad Cache"),
            ("Library/Caches/wb_ad_cache", "Weibo Splash Ad Cache"),
            ("Documents/WBAdCache", "Weibo Ad Asset Cache"),
            ("Library/Caches/WBAdCache", "Weibo Ad Asset Cache"),
            ("Library/Caches/wbad_splash", "Weibo Splash Assets"),
        ],
        "com.sina.weibolite": [
            ("Documents/wb_ad_cache", "Weibo Lite Ad Cache"),
            ("Library/Caches/wb_ad_cache", "Weibo Lite Ad Cache"),
            ("Library/Caches/WBAdCache", "Weibo Ad Cache"),
        ],
        "com.zhihu.ios": [
            ("Library/Caches/ZHAdCache", "Zhihu Splash Ad Cache"),
            ("Library/Caches/ZHSplashAd", "Zhihu Splash Ad"),
            ("Documents/ZHAdCache", "Zhihu Ad Cache"),
            ("Library/Caches/LaunchAdCache", "Zhihu Launch Ad Cache"),
        ],
        "com.netease.cloudmusic": [
            ("Library/Caches/NEAdCache", "NetEase Music Ad Cache"),
            ("Library/Caches/AdCache", "NetEase Ad Cache"),
            ("Documents/AdCache", "NetEase Ad Cache"),
        ],
        "com.tencent.QQMusic": [
            ("Library/Caches/QMAdCache", "QQ Music Ad Cache"),
            ("Documents/QMAdCache", "QQ Music Ad Cache"),
            ("Library/Caches/TADCache", "Tencent Ad Cache (TAD)"),
        ],
        "tv.danmaku.bilianime": [
            ("Library/Caches/SplashAd", "Bilibili Splash Ad"),
            ("Library/Caches/BiliSplashAd", "Bilibili Splash Ad"),
            ("Documents/SplashAd", "Bilibili Splash Ad"),
        ],
        "com.bilibili.app.in": [
            ("Library/Caches/SplashAd", "Bilibili Intl Splash Ad"),
        ],
        "com.xingin.discover": [
            ("Library/Caches/XYAdCache", "Rednote Ad Cache"),
            ("Library/Caches/XHSSplashAd", "Rednote Splash Ad"),
        ],
        "com.taobao.taobao4iphone": [
            ("Documents/TBDocuments/bootImagebiz", "Taobao Boot Splash Config (bootImagebiz)"),
            ("Documents/TBDocuments/bootImageDoc", "Taobao Boot Splash Assets (bootImageDoc)"),
            ("Library/Caches/TanxAd", "Alimama Tanx Ad"),
            ("Library/Caches/TanxSDK", "Alimama Tanx SDK"),
            ("Documents/SplashAd", "Taobao Splash Ad"),
        ],
        "com.taobao.fleamarket": [
            ("Library/Caches/TanxAd", "Idlefish Tanx Ad"),
            ("Library/Caches/SplashAd", "Idlefish Splash Ad"),
        ],
        "com.jingdong.app.mall": [
            ("Library/Caches/JADYun", "JD JADYun Ad SDK"),
            ("Library/Caches/JDAdSDK", "JD Ad SDK"),
        ],
        "com.meituan.imeituan": [
            ("Library/Caches/MTSplashAd", "Meituan Splash Ad"),
            ("Library/Caches/SplashAd", "Meituan Splash Cache"),
        ],
        "com.dianping.dpscope": [
            ("Library/Caches/DPSplashAd", "Dianping Splash Ad"),
            ("Library/Caches/SplashAd", "Dianping Splash Cache"),
        ],
        "com.autonavi.amap": [
            ("Library/Caches/AmapSplashAd", "Amap Splash Ad"),
            ("Library/Caches/SplashAd", "Amap Splash Cache"),
        ],
        "com.baidu.BaiduMobile": [
            ("Library/Caches/BaiduMobAd", "Baidu MobAd"),
            ("Library/Caches/BDAdCache", "Baidu Ad Cache"),
        ],
        "com.baidu.tieba": [
            ("Library/Caches/BaiduMobAd", "Tieba BaiduMobAd"),
            ("Library/Caches/TBAdCache", "Tieba Ad Cache"),
        ],
        "com.baidu.netdisk": [
            ("Library/Caches/BaiduMobAd", "Netdisk BaiduMobAd"),
            ("Library/Caches/BDSplashAd", "Netdisk Splash Ad"),
        ],
        "com.gemd.iting": [
            ("Library/Caches/XMLYAdCache", "Ximalaya Ad Cache"),
            ("Documents/XMLYAdCache", "Ximalaya Ad Cache"),
        ],
        "com.hupu.games": [
            ("Library/Caches/HupuAdCache", "Hupu Ad Cache"),
        ],
        "com.douban.frodo": [
            ("Library/Caches/DoubanAdCache", "Douban Ad Cache"),
        ],
    ]

    // MARK: - Generic scan data

    /// Lowercased exact folder names of mainstream ad SDKs.
    static let exactAdSDKMap: [String: String] = [
        "ksadsdk": "Kuaishou Ad SDK",
        "ksadcache": "Kuaishou Ad Cache",
        "ksad_cache": "Kuaishou Ad Cache",
        "com.kwad.sdk": "Kuaishou Ad SDK",
        "kwadsdk": "Kuaishou Ad SDK",
        "buadsdk": "ByteDance Ad SDK (BUAdSDK)",
        "csjadsdk": "CSJ Ad SDK",
        "csjadcache": "CSJ Ad Cache",
        "pangle_sdk": "Pangle Ad SDK",
        "panglesdk": "Pangle Ad SDK",
        "bytedancead": "ByteDance Ad",
        "ttadsdk": "ByteDance Ad SDK",
        "pangolinad": "Pangle (Pangolin) Ad",
        "gromoread": "GroMore Ad",
        "gdtmobsdk": "Tencent GDT Ad SDK",
        "gdt_splash": "Tencent GDT Splash",
        "gdtsplash": "Tencent GDT Splash",
        "gdtadcache": "Tencent GDT Ad Cache",
        "gdtnetcache": "Tencent GDT Net Cache",
        "tadcache": "Tencent Ad Cache",
        "tencentad": "Tencent Ad",
        "qq_ad_cache": "QQ Ad Cache",
        "ylhadsdk": "Youlianghui Ad SDK",
        "baidumobad": "Baidu MobAd",
        "bd_ad_cache": "Baidu Ad Cache",
        "baidusplashad": "Baidu Splash Ad",
        "bdsplashad": "Baidu Splash Ad",
        "beizisdk": "Beizi Ad SDK",
        "beiziad": "Beizi Ad",
        "octopusad": "Octopus Ad",
        "jadyun": "JD JADYun Ad SDK",
        "jdadsdk": "JD Ad SDK",
        "sigmob": "Sigmob Ad",
        "windadsdk": "Wind Ad SDK",
        "windad": "Wind Ad",
        "anythinksdk": "AnyThink Ad SDK",
        "toponsdk": "TopOn Ad SDK",
        "tradplus": "TradPlus Ad",
        "mintegral": "Mintegral Ad",
        "mtgadcache": "Mintegral Ad Cache",
        "tanxad": "Tanx Ad",
        "tanxsdk": "Tanx SDK",
        "sakuraad": "Sakura Ad",
        "ubixad": "Ubix Ad",
        "qumengad": "Qumeng Ad",
        "googlemobileads": "Google Mobile Ads",
        "gadcache": "Google Ad Cache",
        "unityads": "Unity Ads",
        "unityadscache": "Unity Ads Cache",
        "vunglecache": "Vungle Cache",
        "vungle_cache": "Vungle Cache",
        "applovin": "AppLovin",
        "chartboost": "Chartboost",
        "inmobicache": "InMobi Cache",
        "ironsource": "ironSource",
        "splashad": "Splash Ad",
        "splashads": "Splash Ads",
        "splashadcache": "Splash Ad Cache",
        "splash_ad": "Splash Ad",
        "splash_ads": "Splash Ads",
        "splashscreenad": "Splash Screen Ad",
        "launchad": "Launch Ad",
        "launchads": "Launch Ads",
        "launchadcache": "Launch Ad Cache",
        "launch_ad": "Launch Ad",
        "xhlaunchadcache": "Rednote Launch Ad Cache",
        "xhlaunchad": "Rednote Launch Ad",
        "jwlaunchad": "JW Launch Ad",
        "openscreenad": "Open Screen Ad",
        "open_screen_ad": "Open Screen Ad",
        "adsplash": "Ad Splash",
        "adcache": "Ad Cache",
        "adscache": "Ads Cache",
        "ad_cache": "Ad Cache",
        "ads_cache": "Ads Cache",
        "advertisingcache": "Advertising Cache",
        "startupad": "Startup Ad",
        "startupads": "Startup Ads",
        "bootad": "Boot Ad",
        "wb_ad_cache": "Weibo Ad Cache",
        "wbadcache": "Weibo Ad Cache",
        "zhadcache": "Zhihu Ad Cache",
        "xyadcache": "Rednote Ad Cache",
        "qmadcache": "QQ Music Ad Cache",
        "xmlyadcache": "Ximalaya Ad Cache",
    ]

    /// Ad config files (lowercased) that get the
    /// single-file lock instead of the folder lock.
    static let exactAdConfigFiles: Set<String> = [
        "splash_ad.json", "splashad.json", "splash_ads.json",
        "splash_cache.json", "launch_ad.json", "launchad.json",
        "open_screen_ad.json", "ad_splash.json", "wb_splash_ad.json",
        "splash_ad.plist", "splashad.plist", "launch_ad.plist",
        "xhlaunchad.plist", "ad_splash.plist", "wb_ad_cache.plist",
    ]

    /// Never touch or descend into these (lowercased).
    static let neverTouchOrDescend: Set<String> = [
        "splashboard", "webkit", "fscacheddata",
        "com.apple.nsurlsessiond", "cookies", "httpstorages",
        "preferences", "saved application state", "cloudkit",
        "snapshots", "flutter_assets", "downloads", "download",
        "uploads", "upload", "preload", "shaders", "shadercache",
        "metadata", "payload", "avatars", "database", "databases",
    ]

    /// Standard top-level container subdirs, skipped when
    /// scanning an App Group root (they get their own pass).
    static let standardTopSubdirs: Set<String> = [
        "documents", "library", "tmp",
    ]

    static let protectedBundleIDs: Set<String> = [
        "com.apple.PosterBoard",
        "com.apple.springboard",
        "com.apple.Preferences",
        "com.apple.mobilephone",
    ]

    static let ignoredAppGroupPrefixes: [String] = [
        "group.com.apple.",
        "systemgroup.",
        "group.com.jbdotparty.",
        "group.com.nssurge.",
        "group.com.liguangming.",
        "group.com.luo.",
        "group.com.loon",
        "group.ws.stash.",
    ]

    static let appGroupRoot = "/var/mobile/Containers/Shared/AppGroup"

    // MARK: - Published state

    @Published var targets: [AdLockTarget] = []
    @Published var isScanning = false
    @Published var scanPhase = ""
    @Published var scanSummary: String?
    @Published var lastResult: String?
    @Published var busyTargetID: String?
    @Published var isLockingAll = false
    @Published var rules: [AdWhitelistRule] = []

    private let whitelistKey = "wt.adlock.whitelistRules.v1"

    init() {
        loadRules()
    }

    // MARK: - Whitelist

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: whitelistKey),
           let decoded = try? JSONDecoder().decode([AdWhitelistRule].self, from: data) {
            rules = decoded
            return
        }
        // Seed once: SMZDM is known to crash when its splash
        // cache is locked. The rule is removable.
        rules = [AdWhitelistRule(kind: .bundleID, value: "com.smzdm.client.ios", note: "Known splash lock crash")]
        saveRules()
        print("[AdLock] seeded whitelist with com.smzdm.client.ios (known splash lock crash)")
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: whitelistKey)
        }
    }

    func isWhitelisted(bundleID: String, containerPath: String, relativePath: String) -> Bool {
        for rule in rules {
            switch rule.kind {
            case .bundleID:
                if bundleID == rule.value { return true }
                if bundleID == "group." + rule.value { return true }
            case .exactPath:
                if (containerPath as NSString).appendingPathComponent(relativePath) == rule.value {
                    return true
                }
            }
        }
        return false
    }

    func addBundleRule(_ bundleID: String) {
        let value = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard !rules.contains(where: { $0.kind == .bundleID && $0.value == value }) else { return }
        rules.append(AdWhitelistRule(kind: .bundleID, value: value, note: "Added manually"))
        saveRules()
        print("[AdLock] whitelisted bundle id \(value)")
        refreshWhitelistFlags()
        restoreWhitelistedTargets()
    }

    func addExactPathRule(for target: AdLockTarget) {
        let value = target.url.path
        guard !rules.contains(where: { $0.kind == .exactPath && $0.value == value }) else { return }
        rules.append(AdWhitelistRule(kind: .exactPath, value: value, note: target.label))
        saveRules()
        print("[AdLock] whitelisted exact path \(value)")
        refreshWhitelistFlags()
        restoreWhitelistedTargets()
    }

    func removeRule(_ rule: AdWhitelistRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
        print("[AdLock] removed whitelist rule \(rule.kind) \(rule.value)")
        refreshWhitelistFlags()
    }

    /// Recompute the whitelisted flag on every listed target.
    private func refreshWhitelistFlags() {
        for index in targets.indices {
            targets[index].isWhitelisted = isWhitelisted(
                bundleID: targets[index].bundleID,
                containerPath: targets[index].containerPath,
                relativePath: targets[index].relativePath
            )
        }
    }

    /// A newly whitelisted target is restored writable right
    /// away (sentinel removed) — whitelisting is a rescue,
    /// not just a skip for Lock All.
    private func restoreWhitelistedTargets() {
        let toRestore = targets.filter { $0.isWhitelisted && $0.isLocked }
        guard !toRestore.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            for target in toRestore {
                let outcome = Self.applyLock(target: target, locked: false)
                print("[AdLock] auto-restore whitelisted \(target.relativePath) -> \(outcome.ok ? "writable" : "failed: \(outcome.error ?? "?")")")
                self.refreshTarget(target)
            }
            DispatchQueue.main.async {
                self.lastResult = "Restored \(toRestore.count) whitelisted target(s) to writable."
            }
        }
    }

    // MARK: - Scan

    func scanIfNeeded() {
        if targets.isEmpty && !isScanning {
            scan()
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanSummary = nil
        scanPhase = "Waiting for the App Data scan…"
        print("[AdLock] scan started")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.runScan()
        }
    }

    private func runScan() {
        // The App Data scan is session-cached and takes about
        // a minute; wait for it instead of scanning twice.
        if !AppDataManager.shared.didScan {
            DispatchQueue.main.sync { AppDataManager.shared.scanIfNeeded() }
            var waited = 0.0
            while !AppDataManager.shared.didScan && waited < 180 {
                Thread.sleep(forTimeInterval: 0.5)
                waited += 0.5
            }
            if !AppDataManager.shared.didScan {
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.scanPhase = ""
                    self.lastResult = "The App Data scan did not finish — try Scan again."
                    print("[AdLock] scan aborted: App Data scan did not finish")
                }
                return
            }
        }

        var found: [AdLockTarget] = []
        var seen = Set<String>()
        let containers = AppDataManager.shared.containers
        print("[AdLock] scanning \(containers.count) app container(s)")

        for container in containers {
            if Self.isProtectedContainer(bundleID: container.bundleID) { continue }
            DispatchQueue.main.async { self.scanPhase = "Scanning \(container.bundleID)…" }
            self.scanContainer(
                containerPath: container.path,
                bundleID: container.bundleID,
                isAppGroup: false,
                into: &found,
                seen: &seen
            )
        }

        if let groupPaths = wtPathleakChildren(Self.appGroupRoot) {
            print("[AdLock] scanning \(groupPaths.count) App Group container(s)")
            for path in groupPaths {
                guard let groupID = wtContainerIdentifier(atPath: path) else { continue }
                if Self.isIgnoredAppGroup(groupID) { continue }
                if groupID == AppGroupResolver.resolvedGroup { continue }
                DispatchQueue.main.async { self.scanPhase = "Scanning \(groupID)…" }
                self.scanContainer(
                    containerPath: path,
                    bundleID: groupID,
                    isAppGroup: true,
                    into: &found,
                    seen: &seen
                )
            }
        } else {
            print("[AdLock] App Group enumeration returned nothing")
        }

        found.sort {
            if $0.needsAction != $1.needsAction { return $0.needsAction }
            if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            return $0.relativePath < $1.relativePath
        }
        let lockedCount = found.filter { $0.isLocked }.count
        DispatchQueue.main.async {
            self.targets = found
            self.isScanning = false
            self.scanPhase = ""
            self.scanSummary = "\(found.count) ad target(s) found, \(lockedCount) locked."
            print("[AdLock] scan finished: \(found.count) target(s), \(lockedCount) locked")
        }
    }

    private static func isProtectedContainer(bundleID: String) -> Bool {
        if bundleID.hasPrefix("com.apple.") { return true }
        if protectedBundleIDs.contains(bundleID) { return true }
        if let ownID = Bundle.main.bundleIdentifier, bundleID == ownID { return true }
        return false
    }

    private static func isIgnoredAppGroup(_ groupID: String) -> Bool {
        ignoredAppGroupPrefixes.contains { groupID.hasPrefix($0) }
    }

    /// Pass A (curated paths) + Pass B (generic shallow
    /// scan) for one container, under one grant.
    private func scanContainer(
        containerPath: String,
        bundleID: String,
        isAppGroup: Bool,
        into results: inout [AdLockTarget],
        seen: inout Set<String>
    ) {
        let handle = consumeExtension(containerPath)
        guard handle > 0 else {
            print("[AdLock] grant refused for \(containerPath) — skipped")
            return
        }
        defer { releaseExtension(handle) }

        // Pass A — curated per-app paths, only when the path
        // is really on disk.
        let curatedKey: String
        if isAppGroup, bundleID.hasPrefix("group.") {
            curatedKey = String(bundleID.dropFirst("group.".count))
        } else {
            curatedKey = bundleID
        }
        if let entries = Self.curatedPaths[curatedKey] {
            for entry in entries {
                let fullPath = (containerPath as NSString).appendingPathComponent(entry.relPath)
                addTargetIfPresent(
                    fullPath: fullPath,
                    containerPath: containerPath,
                    bundleID: bundleID,
                    relativePath: entry.relPath,
                    label: entry.label,
                    source: .curated,
                    into: &results,
                    seen: &seen
                )
            }
        }

        // Pass B — generic shallow scan.
        if isAppGroup {
            Self.scanDirectoryShallow(
                dirURL: URL(fileURLWithPath: containerPath),
                containerPath: containerPath,
                bundleID: bundleID,
                currentDepth: 1,
                maxDepth: 2,
                skipStandardTopSubdirs: true,
                into: &results,
                seen: &seen,
                whitelist: { [weak self] b, c, r in
                    self?.isWhitelisted(bundleID: b, containerPath: c, relativePath: r) ?? false
                }
            )
        }
        for rootRel in ["Documents", "Library/Caches", "Library/Application Support", "tmp"] {
            let rootURL = URL(fileURLWithPath: containerPath).appendingPathComponent(rootRel)
            var rootSt = stat()
            guard lstat(rootURL.path, &rootSt) == 0,
                  (rootSt.st_mode & S_IFMT) == S_IFDIR else {
                continue
            }
            Self.scanDirectoryShallow(
                dirURL: rootURL,
                containerPath: containerPath,
                bundleID: bundleID,
                currentDepth: 1,
                maxDepth: 3,
                skipStandardTopSubdirs: false,
                into: &results,
                seen: &seen,
                whitelist: { [weak self] b, c, r in
                    self?.isWhitelisted(bundleID: b, containerPath: c, relativePath: r) ?? false
                }
            )
        }
    }

    /// Add a target when the path exists on disk and passes
    /// the safety checks. Deduplicated by canonical path.
    private func addTargetIfPresent(
        fullPath: String,
        containerPath: String,
        bundleID: String,
        relativePath: String,
        label: String,
        source: AdLockTarget.Source,
        into results: inout [AdLockTarget],
        seen: inout Set<String>
    ) {
        let canonical = Self.normalizedPath(fullPath)
        guard seen.insert(canonical).inserted else { return }
        guard let state = Self.inspectTarget(atPath: fullPath) else { return }
        guard Self.canSafelyModifyPermissions(path: fullPath) else {
            print("[AdLock] blocked by safety policy: \(fullPath)")
            return
        }
        results.append(AdLockTarget(
            id: containerPath + "|" + relativePath,
            bundleID: bundleID,
            containerPath: containerPath,
            relativePath: relativePath,
            isDirectory: state.isDir,
            label: label,
            source: source,
            posixMode: state.mode,
            bytes: state.bytes,
            hasSentinel: state.hasSentinel,
            isWhitelisted: isWhitelisted(bundleID: bundleID, containerPath: containerPath, relativePath: relativePath)
        ))
        print("[AdLock] found \(source) target \(bundleID) \(relativePath) mode \(String(format: "%04o", state.mode))")
    }

    /// Shallow POSIX scan (opendir/readdir, never follows
    /// symlinks) of one directory tree to maxDepth.
    private static func scanDirectoryShallow(
        dirURL: URL,
        containerPath: String,
        bundleID: String,
        currentDepth: Int,
        maxDepth: Int,
        skipStandardTopSubdirs: Bool,
        into results: inout [AdLockTarget],
        seen: inout Set<String>,
        whitelist: (String, String, String) -> Bool
    ) {
        guard let dir = opendir(dirURL.path) else { return }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
            let name = direntName(entry)
            guard name != "." && name != ".." else { continue }
            let lower = name.lowercased()
            if neverTouchOrDescend.contains(lower) { continue }
            if skipStandardTopSubdirs && standardTopSubdirs.contains(lower) { continue }
            let childPath = (dirURL.path as NSString).appendingPathComponent(name)
            var st = stat()
            guard lstat(childPath, &st) == 0 else { continue }
            let fmt = st.st_mode & S_IFMT
            if fmt == S_IFLNK { continue }
            let relativePath = String(childPath.dropFirst(containerPath.count + 1))
            if fmt == S_IFDIR {
                if let label = classifyAdFolder(name: name) {
                    let canonical = normalizedPath(childPath)
                    if seen.insert(canonical).inserted,
                       let state = inspectTarget(atPath: childPath),
                       canSafelyModifyPermissions(path: childPath) {
                        results.append(AdLockTarget(
                            id: containerPath + "|" + relativePath,
                            bundleID: bundleID,
                            containerPath: containerPath,
                            relativePath: relativePath,
                            isDirectory: true,
                            label: label,
                            source: .generic,
                            posixMode: state.mode,
                            bytes: state.bytes,
                            hasSentinel: state.hasSentinel,
                            isWhitelisted: whitelist(bundleID, containerPath, relativePath)
                        ))
                        print("[AdLock] found generic target \(bundleID) \(relativePath)")
                    }
                }
                if currentDepth < maxDepth {
                    scanDirectoryShallow(
                        dirURL: URL(fileURLWithPath: childPath),
                        containerPath: containerPath,
                        bundleID: bundleID,
                        currentDepth: currentDepth + 1,
                        maxDepth: maxDepth,
                        skipStandardTopSubdirs: false,
                        into: &results,
                        seen: &seen,
                        whitelist: whitelist
                    )
                }
            } else if fmt == S_IFREG, exactAdConfigFiles.contains(lower) {
                let canonical = normalizedPath(childPath)
                if seen.insert(canonical).inserted,
                   let state = inspectTarget(atPath: childPath),
                   canSafelyModifyPermissions(path: childPath) {
                    results.append(AdLockTarget(
                        id: containerPath + "|" + relativePath,
                        bundleID: bundleID,
                        containerPath: containerPath,
                        relativePath: relativePath,
                        isDirectory: false,
                        label: "Ad Config (\(name))",
                        source: .configFile,
                        posixMode: state.mode,
                        bytes: state.bytes,
                        hasSentinel: false,
                        isWhitelisted: whitelist(bundleID, containerPath, relativePath)
                    ))
                    print("[AdLock] found config file \(bundleID) \(relativePath)")
                }
            }
        }
    }

    // MARK: - Lock / unlock

    /// Lock (or unlock) one target on a background queue,
    /// then refresh its published state.
    func setLocked(_ target: AdLockTarget, locked: Bool) {
        guard busyTargetID == nil else { return }
        busyTargetID = target.id
        print("[AdLock] \(locked ? "locking" : "unlocking") \(target.bundleID) \(target.relativePath)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let outcome = Self.applyLock(target: target, locked: locked)
            DispatchQueue.main.async {
                self.busyTargetID = nil
                if outcome.ok {
                    self.lastResult = "\(locked ? "Locked" : "Unlocked") \(target.label) (\(target.relativePath))."
                    print("[AdLock] \(locked ? "locked" : "unlocked") \(target.relativePath) mode \(String(format: "%04o", outcome.mode))")
                } else {
                    self.lastResult = "Failed: \(outcome.error ?? "unknown error")"
                    print("[AdLock] failed \(target.relativePath): \(outcome.error ?? "?")")
                }
                self.refreshTarget(target)
            }
        }
    }

    /// Harden is a lock for a weak lock: same folder lock,
    /// which adds the missing sentinel.
    func harden(_ target: AdLockTarget) {
        setLocked(target, locked: true)
    }

    /// Lock every non-whitelisted target that still needs
    /// action, one by one, refreshing each as it finishes.
    func lockAll() {
        guard !isLockingAll else { return }
        let pending = targets.filter { $0.needsAction }
        guard !pending.isEmpty else {
            lastResult = "Nothing left to lock."
            return
        }
        isLockingAll = true
        print("[AdLock] Lock All: \(pending.count) target(s)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var okCount = 0
            var failCount = 0
            for target in pending {
                let outcome = Self.applyLock(target: target, locked: true)
                if outcome.ok { okCount += 1 } else { failCount += 1 }
                print("[AdLock] Lock All \(target.relativePath) -> \(outcome.ok ? "locked" : "failed: \(outcome.error ?? "?")")")
                self.refreshTarget(target)
            }
            DispatchQueue.main.async {
                self.isLockingAll = false
                self.lastResult = "Lock All finished: \(okCount) locked, \(failCount) failed."
                print("[AdLock] Lock All finished: \(okCount) locked, \(failCount) failed")
            }
        }
    }

    /// Re-read one target's live state (mode, size,
    /// sentinel) and update its published row.
    private func refreshTarget(_ target: AdLockTarget) {
        guard let state = Self.inspectTarget(atPath: target.url.path) else { return }
        DispatchQueue.main.async {
            guard let index = self.targets.firstIndex(where: { $0.id == target.id }) else { return }
            self.targets[index].posixMode = state.mode
            self.targets[index].bytes = state.bytes
            self.targets[index].hasSentinel = state.hasSentinel
        }
    }

    /// The whole lock/unlock operation for one target:
    /// grant container + target, check the safety policy,
    /// then apply the folder or single-file lock.
    private static func applyLock(target: AdLockTarget, locked: Bool) -> (ok: Bool, mode: Int, error: String?) {
        let targetPath = target.url.path
        let containerHandle = consumeExtension(target.containerPath)
        defer { if containerHandle > 0 { releaseExtension(containerHandle) } }
        let targetHandle = consumeExtension(targetPath)
        defer { if targetHandle > 0 { releaseExtension(targetHandle) } }
        guard containerHandle > 0 || targetHandle > 0 else {
            return (false, target.posixMode, "Sandbox grant failed for the container.")
        }

        var st = stat()
        guard lstat(targetPath, &st) == 0 else {
            return (false, target.posixMode, "Target no longer exists.")
        }
        let fmt = st.st_mode & S_IFMT
        guard fmt == S_IFDIR || fmt == S_IFREG else {
            return (false, target.posixMode, "Unsupported file type (symlinks blocked).")
        }
        guard canSafelyModifyPermissions(path: targetPath) else {
            return (false, target.posixMode, "Blocked by system container safety policy.")
        }

        if fmt == S_IFDIR {
            return applyDirectorySentinelLock(targetPath: targetPath, locked: locked, fallbackMode: target.posixMode)
        } else {
            return applySingleFileReadOnlyLock(targetURL: target.url, locked: locked, fallbackMode: target.posixMode)
        }
    }

    /// Folder lock: chmod 0755, purge contents safely, put a
    /// 0-byte sentinel inside (0444), chmod the folder 0555,
    /// then lstat-verify the mode is exactly 0555. Unlock
    /// reverses it: chmod 0755, sentinel back to 0644 and
    /// unlinked.
    private static func applyDirectorySentinelLock(
        targetPath: String,
        locked: Bool,
        fallbackMode: Int
    ) -> (ok: Bool, mode: Int, error: String?) {
        let sentinelPath = (targetPath as NSString).appendingPathComponent(sentinelFileName)

        if locked {
            guard Darwin.chmod(targetPath, 0o755) == 0 else {
                return (false, fallbackMode, "chmod 0755 failed: \(errnoString())")
            }
            purgeDirectoryContentsSafely(atPath: targetPath)

            // The sentinel keeps the folder non-empty so the
            // app cannot rmdir it and rebuild the cache there.
            let fd = Darwin.open(sentinelPath, O_CREAT | O_TRUNC | O_WRONLY | O_NOFOLLOW, mode_t(0o644))
            var sentinelCreated = false
            if fd >= 0 {
                Darwin.close(fd)
                _ = Darwin.chmod(sentinelPath, 0o444)
                var sSt = stat()
                sentinelCreated = (lstat(sentinelPath, &sSt) == 0) && ((sSt.st_mode & S_IFMT) == S_IFREG)
            }
            if !sentinelCreated {
                print("[AdLock] warning: sentinel not created at \(sentinelPath)")
            }

            guard Darwin.chmod(targetPath, 0o555) == 0 else {
                return (false, fallbackMode, "chmod 0555 failed: \(errnoString())")
            }
            var verifySt = stat()
            guard lstat(targetPath, &verifySt) == 0 else {
                return (false, fallbackMode, "Failed to verify permissions via lstat.")
            }
            let verifiedMode = Int(verifySt.st_mode) & 0o777
            guard verifiedMode == 0o555 else {
                return (false, verifiedMode, "Mode mismatch: got \(String(format: "%04o", verifiedMode)).")
            }
            return (true, verifiedMode, nil)
        } else {
            guard Darwin.chmod(targetPath, 0o755) == 0 else {
                return (false, fallbackMode, "chmod 0755 failed: \(errnoString())")
            }
            var sSt = stat()
            if lstat(sentinelPath, &sSt) == 0 && (sSt.st_mode & S_IFMT) == S_IFREG {
                _ = Darwin.chmod(sentinelPath, 0o644)
                _ = Darwin.unlink(sentinelPath)
            }
            var verifySt = stat()
            guard lstat(targetPath, &verifySt) == 0 else {
                return (false, fallbackMode, "Failed to verify permissions via lstat.")
            }
            return (true, Int(verifySt.st_mode) & 0o777, nil)
        }
    }

    /// Single-file lock: chmod 0644, truncate and write a
    /// minimal valid empty payload ({} for JSON, empty plist
    /// XML for .plist) with F_FULLFSYNC, chmod 0444, verify.
    /// Unlock restores 0644.
    private static func applySingleFileReadOnlyLock(
        targetURL: URL,
        locked: Bool,
        fallbackMode: Int
    ) -> (ok: Bool, mode: Int, error: String?) {
        let targetPath = targetURL.path

        if locked {
            guard Darwin.chmod(targetPath, 0o644) == 0 else {
                return (false, fallbackMode, "chmod 0644 failed: \(errnoString())")
            }
            let emptyData = emptyPayloadData(for: targetURL)
            let fd = Darwin.open(targetPath, O_WRONLY | O_TRUNC | O_NOFOLLOW)
            guard fd >= 0 else {
                return (false, fallbackMode, "Failed to truncate config file: \(errnoString())")
            }
            if !emptyData.isEmpty {
                _ = emptyData.withUnsafeBytes { ptr -> Int in
                    guard let base = ptr.baseAddress else { return 0 }
                    return Darwin.write(fd, base, emptyData.count)
                }
            }
            _ = Darwin.fcntl(fd, F_FULLFSYNC)
            Darwin.close(fd)

            guard Darwin.chmod(targetPath, 0o444) == 0 else {
                return (false, fallbackMode, "chmod 0444 failed: \(errnoString())")
            }
            var verifySt = stat()
            guard lstat(targetPath, &verifySt) == 0 else {
                return (false, fallbackMode, "Failed to verify permissions via lstat.")
            }
            let verifiedMode = Int(verifySt.st_mode) & 0o777
            return (verifiedMode == 0o444, verifiedMode,
                    verifiedMode == 0o444 ? nil : "Mode verification mismatch.")
        } else {
            guard Darwin.chmod(targetPath, 0o644) == 0 else {
                return (false, fallbackMode, "chmod 0644 failed: \(errnoString())")
            }
            var verifySt = stat()
            let verifiedMode = (lstat(targetPath, &verifySt) == 0) ? (Int(verifySt.st_mode) & 0o777) : 0o644
            return (true, verifiedMode, nil)
        }
    }

    private static func emptyPayloadData(for url: URL) -> Data {
        switch url.pathExtension.lowercased() {
        case "json":
            return Data("{}".utf8)
        case "plist":
            if let data = try? PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .xml, options: 0) {
                return data
            }
            return Data()
        default:
            return Data()
        }
    }

    /// Empties all entries inside dirPath via POSIX
    /// lstat/unlink/rmdir, without removing dirPath itself
    /// and without ever following a symlink.
    private static func purgeDirectoryContentsSafely(atPath dirPath: String) {
        guard let dir = opendir(dirPath) else { return }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
            let name = direntName(entry)
            guard name != "." && name != ".." else { continue }
            let child = (dirPath as NSString).appendingPathComponent(name)
            var st = stat()
            guard lstat(child, &st) == 0 else { continue }
            if (st.st_mode & S_IFMT) == S_IFDIR {
                purgeDirectoryContentsSafely(atPath: child)
                _ = rmdir(child)
            } else {
                // Files, symlinks, anything else: unlink
                // never follows a symlink.
                _ = unlink(child)
            }
        }
    }

    /// Bounded recursive size walk: regular files only,
    /// symlinks skipped.
    private static func folderSize(atPath path: String, maxDepth: Int) -> Int64 {
        guard maxDepth >= 0 else { return 0 }
        var total: Int64 = 0
        guard let dir = opendir(path) else { return 0 }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
            let name = direntName(entry)
            guard name != "." && name != ".." else { continue }
            let child = (path as NSString).appendingPathComponent(name)
            var st = stat()
            guard lstat(child, &st) == 0 else { continue }
            let fmt = st.st_mode & S_IFMT
            if fmt == S_IFREG {
                total += max(0, Int64(st.st_size))
            } else if fmt == S_IFDIR, maxDepth > 0 {
                total += folderSize(atPath: child, maxDepth: maxDepth - 1)
            }
        }
        return total
    }

    /// Live state of one target: mode, size, sentinel.
    /// Nil when the path is gone or not a file/folder.
    private static func inspectTarget(atPath path: String) -> (mode: Int, bytes: Int64, hasSentinel: Bool, isDir: Bool)? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let fmt = st.st_mode & S_IFMT
        guard fmt == S_IFDIR || fmt == S_IFREG else { return nil }
        let isDir = fmt == S_IFDIR
        let mode = Int(st.st_mode) & 0o777
        if isDir {
            let bytes = folderSize(atPath: path, maxDepth: 6)
            var sSt = stat()
            let sentinel = (path as NSString).appendingPathComponent(sentinelFileName)
            let hasSentinel = lstat(sentinel, &sSt) == 0 && (sSt.st_mode & S_IFMT) == S_IFREG
            return (mode, bytes, hasSentinel, true)
        }
        return (mode, max(0, Int64(st.st_size)), false, false)
    }

    // MARK: - Classification

    /// Exact SDK-map hit, else tokenize the name and require
    /// an "ad"/"ads" token plus a modifier token.
    private static func classifyAdFolder(name: String) -> String? {
        let lower = name.lowercased()
        if neverTouchOrDescend.contains(lower) { return nil }
        if let exact = exactAdSDKMap[lower] { return exact }
        let tokens = splitBoundaryTokens(name)
        guard tokens.contains("ad") || tokens.contains("ads") else { return nil }
        let modifiers: Set<String> = ["sdk", "splash", "launch", "cache", "banner", "interstitial", "mob"]
        if tokens.contains(where: { modifiers.contains($0) }) {
            return "Ad Cache (\(name))"
        }
        return nil
    }

    /// Splits a folder name on `_`, `-`, `.`, spaces, and
    /// ASCII camelCase boundaries.
    private static func splitBoundaryTokens(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        let scalars = Array(raw.unicodeScalars)
        for i in scalars.indices {
            let s = scalars[i]
            if s == "_" || s == "-" || s == "." || s == " " {
                if !current.isEmpty {
                    tokens.append(current.lowercased())
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            let isUpper = s.value >= 65 && s.value <= 90
            if isUpper && !current.isEmpty {
                let prev = scalars[i - 1]
                let prevIsLower = prev.value >= 97 && prev.value <= 122
                let nextIsLower = (i + 1 < scalars.count) && (scalars[i + 1].value >= 97 && scalars[i + 1].value <= 122)
                if prevIsLower || nextIsLower {
                    tokens.append(current.lowercased())
                    current.removeAll(keepingCapacity: true)
                }
            }
            current.unicodeScalars.append(s)
        }
        if !current.isEmpty {
            tokens.append(current.lowercased())
        }
        return tokens
    }

    // MARK: - Safety policy

    /// chmod is only ever used on third-party app subpaths:
    /// owner must be "mobile", symlinks rejected, and the
    /// path must sit at least two components below an app
    /// container or App Group root (never the root itself),
    /// or inside this app's own Documents. SystemGroup,
    /// Gestalt, daemon, bundle, and system paths are
    /// forbidden. Both the standardized path and the
    /// symlink-resolved path must pass.
    static func canSafelyModifyPermissions(path: String) -> Bool {
        guard ownerName(atPath: path) == "mobile" else { return false }
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else { return false }
        let candidates = [normalizedPath(path), resolvedPath(path)].compactMap { $0 }
        guard !candidates.isEmpty else { return false }
        for p in candidates {
            if forbiddenPrefixes.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) {
                return false
            }
            let appPrefix = "/var/mobile/Containers/Data/Application/"
            let groupPrefix = "/var/mobile/Containers/Shared/AppGroup/"
            if p.hasPrefix(appPrefix) || p.hasPrefix(groupPrefix) {
                let prefix = p.hasPrefix(appPrefix) ? appPrefix : groupPrefix
                let rest = String(p.dropFirst(prefix.count))
                let components = rest.split(separator: "/")
                guard components.count >= 2 else { return false }
            } else if let ownDocs = ownDocumentsPath, p.hasPrefix(ownDocs + "/") {
                // This app's own Documents subpaths are allowed.
                continue
            } else {
                return false
            }
        }
        return true
    }

    static let forbiddenPrefixes: [String] = [
        "/var/containers/Shared/SystemGroup",
        "/var/containers/Bundle",
        "/var/mobile/Containers/Data/InternalDaemon",
        "/var/mobile/Containers/Data/PluginKitPlugin",
        "/var/containers/Data/System",
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library",
        "/etc",
    ]

    private static var ownDocumentsPath: String? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
    }

    private static func ownerName(atPath path: String) -> String? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.ownerAccountName] as? String) ?? nil
    }

    /// Standardized path with the /private mount prefix
    /// stripped, so /private/var/... and /var/... compare
    /// the same.
    static func normalizedPath(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        if p.hasPrefix("/private/") {
            p = String(p.dropFirst("/private".count))
        }
        return p
    }

    private static func resolvedPath(_ path: String) -> String? {
        normalizedPath(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }

    private static func errnoString() -> String {
        String(cString: strerror(errno))
    }

    private static func direntName(_ entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: &entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
    }
}
