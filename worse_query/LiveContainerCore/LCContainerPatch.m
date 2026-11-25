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

    BOOL dontInjectTweakLoader = [info[@"dontInjectTweakLoader"] boolValue];
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
    SecIdentityRef identity = NULL;
    SecCertificateRef certificate = NULL;
    NSDictionary *query = @{(__bridge id)kSecImportExportPassphrase: password};
    CFArrayRef items = NULL;
    OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)query, &items);
    if (status != errSecSuccess || !items || CFArrayGetCount(items) == 0) {
        if (items) CFRelease(items);
        if (outError) *outError = [self errorWithMessage:@"The stored certificate no longer parses — remove it and import it again."];
        return nil;
    }
    CFDictionaryRef item = CFArrayGetValueAtIndex(items, 0);
    identity = (SecIdentityRef)CFDictionaryGetValue(item, kSecImportItemIdentity);
    if (identity) {
        SecIdentityCopyCertificate(identity, &certificate);
    }
    CFRelease(items);
    if (!certificate) {
        if (outError) *outError = [self errorWithMessage:@"The stored certificate has no identity."];
        return nil;
    }
    NSString *teamID = nil;
    NSDate *expiration = nil;
    CFArrayRef keys = (__bridge CFArrayRef)@[(__bridge id)kSecOIDOrganizationalUnitName, (__bridge id)kSecOIDX509V1ValidityNotAfter];
    CFErrorRef cfError = NULL;
    CFDictionaryRef values = SecCertificateCopyValues(certificate, keys, &cfError);
    if (values) {
        CFDictionaryRef ouEntry = CFDictionaryGetValue(values, kSecOIDOrganizationalUnitName);
        if (ouEntry) {
            CFTypeRef ouValue = CFDictionaryGetValue(ouEntry, kSecPropertyKeyValue);
            if (ouValue && CFGetTypeID(ouValue) == CFArrayGetTypeID() && CFArrayGetCount(ouValue) > 0) {
                CFTypeRef first = CFArrayGetValueAtIndex(ouValue, 0);
                if (first && CFGetTypeID(first) == CFStringGetTypeID()) {
                    teamID = (__bridge NSString *)first;
                }
            }
        }
        CFDictionaryRef expEntry = CFDictionaryGetValue(values, kSecOIDX509V1ValidityNotAfter);
        if (expEntry) {
            CFTypeRef expValue = CFDictionaryGetValue(expEntry, kSecPropertyKeyValue);
            if (expValue && CFGetTypeID(expValue) == CFDateGetTypeID()) {
                expiration = (__bridge NSDate *)expValue;
            }
        }
        CFRelease(values);
    }
    CFRelease(certificate);
    if (!teamID) teamID = @"—";
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"teamId"] = teamID;
    if (expiration) result[@"expirationDate"] = expiration;
    return result;
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

+ (void)launchGuestWithFolderName:(NSString *)folderName dataUUID:(NSString *)dataUUID {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:folderName forKey:@"selected"];
    [defaults setObject:dataUUID forKey:@"selectedContainer"];
    [LCSharedUtils launchToGuestAppWithClassicMode:0];
}

@end
