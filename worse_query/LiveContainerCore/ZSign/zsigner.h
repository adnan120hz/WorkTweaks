//
//  zsigner.h
//  LiveContainer
//
//  Created by s s on 2024/11/10.
//
#import <Foundation/Foundation.h>


@interface ZSigner : NSObject
+ (NSProgress*)signWithAppPath:(NSString *)appPath bundleId:(NSString *)bundleId cert:(NSData *)key pass:(NSString *)pass completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (BOOL)adhocSignMachOAtPath:(NSString *)path bundleId:(NSString*)bundleId entitlementData:(NSData *)entitlementData;
+ (NSProgress*)signMachOPathArr:(NSArray<NSString*>*)machoPathArr bundleId:(NSString *)bundleId cert:(NSData *)key
                           pass:(NSString *)pass completionHandler:(void(^)(BOOL success, NSError *error))completionHandler;
// this method is used to get teamId for ADP/Enterprise certs ,don't use it in normal jitless
+ (NSString*)getTeamIdWithCert:(NSData *)cert pass:(NSString *)pass;
// Offline, synchronous certificate info (teamId + expirationDate) for a
// .p12. SecCertificateCopyValues is macOS-only (__IPHONE_NA), so this
// parses the cert with OpenSSL the same way checkCert does, minus the
// live OCSP round-trip. Returns nil when the .p12 does not open with
// this password. Keys: @"teamId" (NSString), @"expirationDate" (NSDate,
// only when the notAfter value parses).
+ (NSDictionary *)certificateInfoWithCert:(NSData *)cert pass:(NSString *)pass;
+ (int)checkCert:(NSData *)cert pass:(NSString *)pass completionHandler:(void(^)(int status, NSDate* expirationDate, NSString* organizationalUnitName, NSString *error))completionHandler;
@end
