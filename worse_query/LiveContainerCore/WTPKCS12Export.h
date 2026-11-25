// WTPKCS12Export.h
//
// Build a .p12 (PKCS#12) from the Container's provisioned signing
// identity: the RSA private key (PKCS#1 DER, as SecKey exports it),
// the leaf certificate (DER), and the public WWDR chain (DER).
// The .p12 is stored exactly the way a manually imported one is
// (LCContainerPatch.storeCertificateData), so guests sign and
// launch the same either way. The password is a random UUID made
// per export — never shown, never logged.
//
// OpenSSL's d2i_PrivateKey_bio mirrors ZSign's own key loading
// (ZSign/openssl.cpp): it reads PKCS#8 or the traditional PKCS#1
// form, so the SecKey-exported PKCS#1 parses as-is.

#import <Foundation/Foundation.h>

@interface WTPKCS12Export : NSObject

/// Build a .p12 from an RSA private key (PKCS#1 DER), a leaf
/// certificate (DER) and a chain (DER certs, may be empty).
/// Returns nil + error when the key/cert don't parse or the
/// .p12 can't be built.
+ (nullable NSData *)exportPKCS12WithPrivateKeyPKCS1:(NSData *)privateKeyPKCS1
                                         certificate:(NSData *)certificateDER
                                               chain:(NSArray<NSData *> *)chain
                                            password:(NSString *)password
                                               error:(NSError * _Nullable * _Nullable)outError;

@end
