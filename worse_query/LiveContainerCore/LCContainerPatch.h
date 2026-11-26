// LCContainerPatch.h
//
// WorkTweaks-side wrapper around the LiveContainer core's patch / sign /
// launch primitives (LCMachOUtils, LCSharedUtils, ZSigner).
//
// The LCAppInfo class itself is NOT vendored — it lives in
// LiveContainer's SwiftUI target (LiveContainerSwiftUI/Models) — so the
// patch sequence here reimplements LCAppInfo.m
// -patchExecAndSignIfNeedWithCompletionHandler (currentPatchRev 7) step
// for step, and patchGuestExtensions. LCUtils.m is NOT compiled: its
// MultitaskSupport + LiveContainerSwiftUI-Swift.h dependencies are not
// vendored, and nothing in the core calls its methods (verified by grep
// — only LCMachOUtils.m imports its header, and calls nothing from it).
// The two LCUtils helpers this feature needs (certificateData,
// setCertificatePassword) are reimplemented here in three lines each.
// Signing calls ZSigner directly: LCUtils.signAppBundleWithZSign first
// dlopens @executable_path/Frameworks/ZSign.dylib, which does not exist
// — ZSigner is compiled into the app binary instead.

#import <Foundation/Foundation.h>

// LiveContainerMain (LCBootstrap.m) — the guest bootstrap. Called from
// WorkTweaksApp init when a guest was selected at launch.
int LiveContainerMain(int argc, char *argv[]);

@interface LCContainerPatch : NSObject

/// Patch one installed guest bundle, exactly like LCAppInfo's patch step:
/// copy-delete-move the executable (avoids codesign SIGKILL), patch every
/// arm64 slice (inject TweakLoader unless there is no space), fix up the
/// arm64e slices, patch .appex extensions, then write LCPatchRevision 7
/// (+ flags) into the guest's LCAppInfo.plist.
/// Returns the new LCAppInfo values (patchRevision, is32bit,
/// tweakLoaderCantInject, segCountMismatch), or nil + an error string.
/// Encrypted executables are refused with LC's exact message.
+ (NSDictionary * _Nullable)patchGuestAppAtPath:(NSString *)appPath
                                 executableName:(NSString *)executableName
                                          error:(NSError * _Nullable * _Nullable)outError;

/// YES when a .p12 certificate is stored (data + password both present).
+ (BOOL)hasCertificate;

/// The stored .p12 blob, if one is stored.
+ (NSData * _Nullable)certificateData;

/// The stored .p12's password, if one is stored. Only ever used
/// in-memory to open the stored blob (signing, export) — never
/// logged, never written anywhere else.
+ (NSString * _Nullable)certificatePassword;

/// Stored certificate info: teamId (OU) + expirationDate, read offline
/// from the stored .p12 via SecPKCS12Import. Nil + error when none stored
/// or the stored data no longer parses.
+ (NSDictionary * _Nullable)certificateInfo:(NSError * _Nullable * _Nullable)outError;

/// Sign a patched guest with the stored certificate, via ZSigner
/// directly (see header note). Completion runs on the main queue.
/// On success the signature is verified with checkCodeSignature first.
+ (void)signGuestAppAtPath:(NSString *)appPath
                  bundleId:(NSString *)bundleId
                completion:(void (^)(BOOL success, NSString * _Nullable error))completion;

/// YES when the guest executable's current signature passes iOS
/// validation (checkCodeSignature — the same F_ADDFILESIGS_RETURN /
/// F_CHECK_LV check signing runs after ZSign). The re-sign path
/// uses this to skip guests that are already validly signed
/// instead of signing them again.
+ (BOOL)isGuestSignatureValidAtPath:(NSString *)appPath
                    executableName:(NSString *)executableName;

/// Validate a picked .p12 with its password (SecPKCS12Import — offline)
/// and store it the LC way: the raw .p12 data under "LCCertificateData"
/// in the App Group defaults, the password under "LCCertificatePassword"
/// in both the standard and the App Group defaults.
+ (BOOL)storeCertificateData:(NSData *)p12Data
                    password:(NSString *)password
                       error:(NSError * _Nullable * _Nullable)outError;

/// Remove the stored certificate (data + password, both defaults).
+ (void)removeCertificate;

/// Select a guest and relaunch the host into it (LCSharedUtils
/// launchToGuestAppWithClassicMode). The next launch runs
/// LiveContainerMain with this guest selected.
+ (void)launchGuestWithFolderName:(NSString *)folderName dataUUID:(NSString *)dataUUID;

/// Completion-taking variant of launchGuestWithFolderName:dataUUID:,
/// for the Swift JIT arm path only (ContainerManager.launch). The
/// completion is invoked at most once, and only when the self-open
/// FAILED (every attempt refused). On success the process SIGKILLs
/// inside the open completion handler, so the completion never runs
/// and a Swift caller awaiting it never resumes — the pending JIT
/// stays armed for the next process. If the open completion never
/// fires at all, the completion never runs either; the Swift side
/// bounds that with its own timeout. Other callers keep using the
/// fire-and-forget variant above, unchanged.
+ (void)launchGuestWithFolderName:(NSString *)folderName dataUUID:(NSString *)dataUUID completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

@end

// MARK: - Persistent JIT diagnostics (WTJITDiag)
//
// One timestamped line per risky step of the JIT relaunch /
// attach path, appended to <AppGroup>/LiveContainer/
// jit-diagnostics.log — a file that survives a SIGKILL /
// force-close, unlike the in-app Log (in-memory only) and
// stderr (never captured). The path is set from Swift
// (WTJITDiag.setPathIfNeeded, the same LiveContainer root
// guests live in); until then the implementation falls back
// to resolving the App Group the LC way. Writes are
// synchronous open / write / fsync / close, so a line
// written in the self-open handler lands on disk BEFORE the
// raise(SIGKILL) that follows it. The file is capped at
// 64 KB — when an append would pass the cap, the oldest
// lines are dropped first (kept tail ~32 KB, cut at a line
// boundary). Never logs passwords, tokens, or cert material
// — step names, bundle IDs, booleans, error descriptions,
// and timings only. Logging only: no gate, timing, or
// launch logic lives here.
void WTJITDiagSetPath(const char *path);
void WTJITDiagAppend(const char *step, const char *detail);
