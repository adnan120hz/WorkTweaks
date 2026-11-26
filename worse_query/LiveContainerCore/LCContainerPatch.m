// LCContainerPatch.m
//
// See LCContainerPatch.h. Patch sequence mirrors LCAppInfo.m
// (LiveContainerSwiftUI/Models, upstream) — currentPatchRev 7 — and
// patchGuestExtensions; certificate storage mirrors LCUtils.m
// certificateData / setCertificatePassword (LCUtils.m itself is not
// compiled — see the header note).

#import "LCContainerPatch.h"
#import "LiveContainer/LCMachOUtils.h"
#import "LiveContainer/LCSharedUtils.h"
#import "ZSign/zsigner.h"
#import <Security/Security.h>
#import <fcntl.h>
#import <limits.h>
#import <sys/stat.h>
#import <time.h>
#import <unistd.h>

static NSString * const kLCCertificateDataKey = @"LCCertificateData";
static NSString * const kLCCertificatePasswordKey = @"LCCertificatePassword";
static const int kCurrentPatchRevision = 7;

@implementation LCContainerPatch

+ (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:@"LCContainerPatch" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

// MARK: - Patch

+ (NSDictionary *)patchGuestAppAtPath:(NSString *)appPath
                      executableName:(NSString *)executableName
                               error:(NSError **)outError {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *plistPath = [appPath stringByAppendingPathComponent:@"LCAppInfo.plist"];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!info) {
        if (outError) *outError = [self errorWithMessage:@"LCAppInfo.plist not found"];
        return nil;
    }
    NSString *execPath = [appPath stringByAppendingPathComponent:executableName];

    // copy-delete-move to avoid EXC_BAD_ACCESS (SIGKILL - CODESIGNING)
    NSString *backupPath = [NSString stringWithFormat:@"%@/%@_LiveContainerPatchBackUp", appPath, executableName];
    NSError *err = nil;
    [fm copyItemAtPath:execPath toPath:backupPath error:&err];
    [fm removeItemAtPath:execPath error:&err];
    [fm moveItemAtPath:backupPath toPath:execPath error:&err];

    __block BOOL dontInjectTweakLoader = [info[@"dontInjectTweakLoader"] boolValue];
    __block BOOL has64bitSlice = NO;
    __block BOOL isEncrypted = NO;
    __block BOOL tweakLoaderCantInject = NO;
    __block BOOL segCountMismatch = NO;
    NSString *error = LCParseMachO(execPath.UTF8String, false, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
        if (header->cputype == CPU_TYPE_ARM64) {
            has64bitSlice = YES;
            int patchResult = LCPatchExecSlice(path, header, !dontInjectTweakLoader);
            if (patchResult & PATCH_EXEC_RESULT_NO_SPACE_FOR_TWEAKLOADER) {
                tweakLoaderCantInject = YES;
                dontInjectTweakLoader = YES;
            }
            if (patchResult & (PATCH_EXEC_RESULT_SEG_COUNT_MISMATCH | PATCH_EXEC_RESULT_MISALIGNED_LINKEDIT_STRING_POOL)) {
                segCountMismatch = YES;
            }
        }
        isEncrypted |= LCIsMachOEncrypted(header);
    });
    BOOL is32bit = !has64bitSlice;
    if (isEncrypted) {
        error = @"The app you tried to install is encrypted. Please provide a decrypted app.";
    }
    if (error) {
        if (outError) *outError = [self errorWithMessage:error];
        return nil;
    }
    if (!is32bit) {
        LCPatchAppBundleFixupARM64eSlice([NSURL fileURLWithPath:appPath]);
    }
    error = [self patchGuestExtensionsAtBundlePath:appPath];
    if (error) {
        if (outError) *outError = [self errorWithMessage:error];
        return nil;
    }
    info[@"LCPatchRevision"] = @(kCurrentPatchRevision);
    info[@"is32bit"] = @(is32bit);
    if (tweakLoaderCantInject) {
        info[@"LCTweakLoaderCantInject"] = @YES;
        info[@"dontInjectTweakLoader"] = @YES;
    }
    if (segCountMismatch) {
        info[@"segCountMismatch"] = @YES;
    }
    if (is32bit) {
        info[@"isJITNeeded"] = @YES;
        info[@"classicMode"] = @YES;
        info[@"spoofSDKVersion"] = @YES;
    }
    [info writeToFile:plistPath atomically:YES];
    return @{
        @"patchRevision": @(kCurrentPatchRevision),
        @"is32bit": @(is32bit),
        @"tweakLoaderCantInject": @(tweakLoaderCantInject),
        @"segCountMismatch": @(segCountMismatch),
    };
}

/// Mirrors LCAppInfo.m patchGuestExtensions: every .appex in PlugIns gets
/// copy-to-.lcpatch, LCPatchExecSlice with no TweakLoader injection,
/// replace-in-place, and an LCAppExtension.plist recording seg mismatch.
+ (NSString *)patchGuestExtensionsAtBundlePath:(NSString *)bundlePath {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *pluginsPath = [bundlePath stringByAppendingPathComponent:@"PlugIns"];
    NSArray *plugins = [fm contentsOfDirectoryAtPath:pluginsPath error:nil];
    for (NSString *name in plugins) {
        if (![name.pathExtension isEqualToString:@"appex"]) continue;
        NSString *extBundlePath = [pluginsPath stringByAppendingPathComponent:name];
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[extBundlePath stringByAppendingPathComponent:@"Info.plist"]];
        NSString *executable = plist[@"CFBundleExecutable"];
        NSString *path = [extBundlePath stringByAppendingPathComponent:executable];
        NSString *temporaryPath = [path stringByAppendingString:@".lcpatch"];
        NSError *fileError = nil;
        [fm removeItemAtPath:temporaryPath error:nil];
        if (![fm copyItemAtPath:path toPath:temporaryPath error:&fileError]) return fileError.localizedDescription;

        __block BOOL hasARM64 = NO;
        __block BOOL encrypted = NO;
        __block BOOL mismatch = NO;
        NSString *error = LCParseMachO(temporaryPath.fileSystemRepresentation, false, ^(const char *slicePath, struct mach_header_64 *header, int fd, void *filePtr) {
            if (header->cputype != CPU_TYPE_ARM64) return;
            hasARM64 = YES;
            encrypted |= LCIsMachOEncrypted(header);
            if (!encrypted) {
                int patchResult = LCPatchExecSlice(path.fileSystemRepresentation, header, false);
                mismatch |= (patchResult & (PATCH_EXEC_RESULT_SEG_COUNT_MISMATCH | PATCH_EXEC_RESULT_MISALIGNED_LINKEDIT_STRING_POOL)) != 0;
            }
        });
        if (!error && (!hasARM64 || encrypted)) {
            error = [NSString stringWithFormat:@"%@ requires a decrypted arm64 executable", name];
        }
        if (!error && ![fm replaceItemAtURL:[NSURL fileURLWithPath:path] withItemAtURL:[NSURL fileURLWithPath:temporaryPath] backupItemName:nil options:0 resultingItemURL:nil error:&fileError]) {
            error = fileError.localizedDescription;
        }
        [fm removeItemAtPath:temporaryPath error:nil];
        if (error) return error;
        [@{@"segCountMismatch": @(mismatch)} writeToFile:[extBundlePath stringByAppendingPathComponent:@"LCAppExtension.plist"] atomically:YES];
    }
    return nil;
}

// MARK: - Certificate

+ (NSUserDefaults *)groupDefaults {
    NSString *groupID = [LCSharedUtils appGroupID];
    if (groupID) {
        NSUserDefaults *group = [[NSUserDefaults alloc] initWithSuiteName:groupID];
        if (group) return group;
    }
    return NSUserDefaults.standardUserDefaults;
}

+ (NSData *)certificateData {
    return [[self groupDefaults] objectForKey:kLCCertificateDataKey];
}

+ (NSString *)certificatePassword {
    return [LCSharedUtils certificatePassword];
}

+ (BOOL)hasCertificate {
    return [self certificateData] != nil && [LCSharedUtils certificatePassword] != nil;
}

+ (NSDictionary *)certificateInfo:(NSError **)outError {
    NSData *p12Data = [self certificateData];
    NSString *password = [LCSharedUtils certificatePassword];
    if (!p12Data || !password) {
        if (outError) *outError = [self errorWithMessage:@"No certificate imported"];
        return nil;
    }
    // NOTE: the first version of this method used SecCertificateCopyValues
    // + kSecOIDOrganizationalUnitName / kSecOIDX509V1ValidityNotAfter /
    // kSecPropertyKeyValue. All of those are macOS-only: in the iOS SDK
    // SecCertificate.h they are declared __OSX_AVAILABLE_STARTING(
    // __MAC_10_7, __IPHONE_NA), so no import fixes the build on iOS.
    // Parse the stored .p12 offline via ZSign/OpenSSL instead — same
    // OU + notAfter extraction checkCert uses, minus its live OCSP call.
    NSDictionary *info = [ZSigner certificateInfoWithCert:p12Data pass:password];
    if (!info) {
        if (outError) *outError = [self errorWithMessage:@"The stored certificate no longer parses — remove it and import it again."];
        return nil;
    }
    return info;
}

+ (BOOL)storeCertificateData:(NSData *)p12Data
                    password:(NSString *)password
                       error:(NSError **)outError {
    // Validate offline: the .p12 must open with this password and hold
    // an identity. (ZSign's checkCert does a live OCSP check on top of
    // this; that runs at signing time, not at import.)
    NSDictionary *query = @{(__bridge id)kSecImportExportPassphrase: password};
    CFArrayRef items = NULL;
    OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)query, &items);
    BOOL valid = (status == errSecSuccess && items && CFArrayGetCount(items) > 0);
    if (items) CFRelease(items);
    if (!valid) {
        if (outError) *outError = [self errorWithMessage:@"That .p12 could not be opened with this password — wrong password, or not a .p12 file."];
        return NO;
    }
    // Store the LC way: raw .p12 in the App Group defaults (ZSign reads
    // it from there at signing time), password in both defaults.
    NSUserDefaults *group = [self groupDefaults];
    [group setObject:p12Data forKey:kLCCertificateDataKey];
    [NSUserDefaults.standardUserDefaults setObject:password forKey:kLCCertificatePasswordKey];
    [group setObject:password forKey:kLCCertificatePasswordKey];
    return YES;
}

+ (void)removeCertificate {
    NSUserDefaults *group = [self groupDefaults];
    [group removeObjectForKey:kLCCertificateDataKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kLCCertificatePasswordKey];
    [group removeObjectForKey:kLCCertificatePasswordKey];
}

// MARK: - Sign

+ (void)signGuestAppAtPath:(NSString *)appPath
                  bundleId:(NSString *)bundleId
                completion:(void (^)(BOOL success, NSString *error))completion {
    NSData *cert = [self certificateData];
    NSString *pass = [LCSharedUtils certificatePassword];
    if (!cert || !pass) {
        if (completion) completion(NO, @"No certificate imported — import a .p12 certificate first.");
        return;
    }
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *executable = plist[@"CFBundleExecutable"];
    NSString *executablePath = [appPath stringByAppendingPathComponent:executable ?: @""];
    [ZSigner signWithAppPath:appPath bundleId:bundleId cert:cert pass:pass completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) {
                if (completion) completion(NO, error.localizedDescription ?: @"Signing failed.");
                return;
            }
            if (!checkCodeSignature(executablePath.UTF8String)) {
                if (completion) completion(NO, @"The guest was signed, but iOS does not consider the signature valid — the certificate may be expired or revoked.");
                return;
            }
            if (completion) completion(YES, nil);
        });
    }];
}

// MARK: - Launch

/// Validate one guest's current signature without signing it
/// (LCAppInfo.patchExecAndSignIfNeed's skip-if-valid step).
+ (BOOL)isGuestSignatureValidAtPath:(NSString *)appPath
                    executableName:(NSString *)executableName {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *executable = plist[@"CFBundleExecutable"];
    if (!executable) return NO;
    NSString *executablePath = [appPath stringByAppendingPathComponent:executable];
    return checkCodeSignature(executablePath.UTF8String);
}

+ (void)launchGuestWithFolderName:(NSString *)folderName dataUUID:(NSString *)dataUUID {
    [self launchGuestWithFolderName:folderName dataUUID:dataUUID completion:nil];
}

+ (void)launchGuestWithFolderName:(NSString *)folderName dataUUID:(NSString *)dataUUID completion:(void (^)(BOOL success, NSError *error))completion {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:folderName forKey:@"selected"];
    [defaults setObject:dataUUID forKey:@"selectedContainer"];
    [LCSharedUtils launchToGuestAppWithClassicMode:0 completion:completion];
}

@end

// MARK: - Persistent JIT diagnostics (WTJITDiag)
//
// See LCContainerPatch.h. One lock serializes all writers
// (the main queue, Swift Tasks, and the self-open handler
// can all append); every write is synchronous, so a line
// appended before raise(SIGKILL) is on disk before the
// process dies. The trim keeps the file bounded without
// ever growing an unbounded in-memory copy: the file is at
// most ~64 KB + one line when it is read for trimming.

/// Max file size (64 KB); when an append would pass it, the
/// oldest lines are dropped first, keeping ~32 KB.
static const off_t kWTJITDiagMaxBytes = 64 * 1024;
static const off_t kWTJITDiagKeepBytes = 32 * 1024;
/// One line never carries more detail than this (error
/// descriptions are cut, not wrapped, so the file stays
/// one event per line).
static const size_t kWTJITDiagMaxDetail = 500;

static char gWTJITDiagPath[PATH_MAX] = "";

void WTJITDiagSetPath(const char *path) {
    if (!path || !path[0]) return;
    @synchronized([LCContainerPatch class]) {
        strlcpy(gWTJITDiagPath, path, sizeof(gWTJITDiagPath));
    }
}

/// The log path. Assumes the caller holds the
/// WTJITDiagAppend lock (via @synchronized below): the
/// Swift-set path wins; the fallback resolves the App Group
/// the LC way and caches it, so a later append never
/// re-resolves to a different group mid-launch.
static NSString *WTJITDiagPathLocked(void) {
    if (gWTJITDiagPath[0]) return [NSString stringWithUTF8String:gWTJITDiagPath];
    NSURL *group = [LCSharedUtils appGroupPath];
    if (!group) return nil;
    NSString *path = [[group URLByAppendingPathComponent:@"LiveContainer/jit-diagnostics.log"] path];
    strlcpy(gWTJITDiagPath, path.UTF8String, sizeof(gWTJITDiagPath));
    return path;
}

/// Copy src into dst (at most dstSize - 1 chars), turning
/// newlines into spaces so one event is always one line.
static void WTJITDiagSanitizeInto(char *dst, size_t dstSize, const char *src) {
    if (!src) src = "";
    size_t n = 0;
    for (size_t i = 0; src[i] && n + 1 < dstSize; i++) {
        char c = src[i];
        dst[n++] = (c == '\n' || c == '\r') ? ' ' : c;
    }
    dst[n] = '\0';
}

void WTJITDiagAppend(const char *step, const char *detail) {
    @synchronized([LCContainerPatch class]) {
        NSString *path = WTJITDiagPathLocked();
        if (!path) return;
        [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        char cleanStep[40];
        char cleanDetail[kWTJITDiagMaxDetail + 1];
        WTJITDiagSanitizeInto(cleanStep, sizeof(cleanStep), step);
        WTJITDiagSanitizeInto(cleanDetail, sizeof(cleanDetail), detail);
        time_t now = time(NULL);
        struct tm tmv;
        localtime_r(&now, &tmv);
        char ts[16];
        strftime(ts, sizeof(ts), "%H:%M:%S", &tmv);
        char line[600];
        int len = snprintf(line, sizeof(line), "%s [JIT] %s: %s\n", ts, cleanStep, cleanDetail);
        if (len <= 0) return;
        if (len >= (int)sizeof(line)) len = (int)sizeof(line) - 1;
        int fd = open(path.UTF8String, O_RDWR | O_CREAT, 0644);
        if (fd < 0) return;
        // Cap: when the file is already over 64 KB, drop the
        // oldest lines first (keep ~32 KB, cut at a line
        // boundary), then append. Worst case a line is lost;
        // the file stays valid.
        struct stat st;
        if (fstat(fd, &st) == 0 && st.st_size > kWTJITDiagMaxBytes) {
            off_t size = st.st_size;
            char *buf = malloc((size_t)size);
            if (buf) {
                ssize_t got = pread(fd, buf, (size_t)size, 0);
                if (got == size) {
                    off_t cut = size - kWTJITDiagKeepBytes;
                    while (cut < size && buf[cut] != '\n') cut++;
                    if (cut < size) cut++; // past the newline
                    if (cut < size) {
                        ftruncate(fd, 0);
                        const char *p = buf + cut;
                        size_t left = (size_t)(size - cut);
                        while (left > 0) {
                            ssize_t w = write(fd, p, left);
                            if (w <= 0) break;
                            p += w; left -= (size_t)w;
                        }
                    }
                }
                free(buf);
            }
        }
        lseek(fd, 0, SEEK_END);
        const char *p = line;
        size_t left = (size_t)len;
        while (left > 0) {
            ssize_t w = write(fd, p, left);
            if (w <= 0) break;
            p += w; left -= (size_t)w;
        }
        fsync(fd);
        close(fd);
    }
}
