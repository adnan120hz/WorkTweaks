// WTPKCS12Export.m
//
// See WTPKCS12Export.h. PKCS12_create with the defaults
// (PBE-SHA1 + 3DES for the key bag, RC2-40 for the cert bag,
// 2048 MAC iterations) — the same shape Keychain Access
// writes when it exports a .p12, and the shape SecPKCS12Import
// (which validates the stored .p12) expects.

#import "WTPKCS12Export.h"
#include <openssl/pkcs12.h>
#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/err.h>

@implementation WTPKCS12Export

+ (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:@"WTPKCS12Export" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// Build a PKCS#12 blob from an identity and encode it as DER.
/// Shared by the fresh export and the re-wrap below.
static NSData *WTDataFromPKCS12(EVP_PKEY *pkey, X509 *cert, STACK_OF(X509) *ca,
                                NSString *password, NSError **outError) {
    PKCS12 *p12 = PKCS12_create(password.UTF8String, "WorkTweaks", pkey, cert, ca, 0, 0, 0, 0, 0);
    if (!p12) {
        if (outError) *outError = [WTPKCS12Export errorWithMessage:@"Could not build the .p12."];
        return nil;
    }
    int derLen = i2d_PKCS12(p12, NULL);
    if (derLen <= 0) {
        PKCS12_free(p12);
        if (outError) *outError = [WTPKCS12Export errorWithMessage:@"Could not encode the .p12."];
        return nil;
    }
    NSMutableData *der = [NSMutableData dataWithLength:(NSUInteger)derLen];
    unsigned char *derPtr = (unsigned char *)der.mutableBytes;
    if (i2d_PKCS12(p12, &derPtr) != derLen) {
        PKCS12_free(p12);
        if (outError) *outError = [WTPKCS12Export errorWithMessage:@"Could not encode the .p12."];
        return nil;
    }
    PKCS12_free(p12);
    return [der copy];
}

+ (nullable NSData *)exportPKCS12WithPrivateKeyPKCS1:(NSData *)privateKeyPKCS1
                                         certificate:(NSData *)certificateDER
                                               chain:(NSArray<NSData *> *)chain
                                            password:(NSString *)password
                                               error:(NSError **)outError {
    EVP_PKEY *pkey = NULL;
    X509 *cert = NULL;
    STACK_OF(X509) *ca = NULL;

    // Private key: memory BIO + d2i_PrivateKey_bio, the same call
    // ZSign uses (ZSign/openssl.cpp) — reads PKCS#1 as-is.
    BIO *keyBio = BIO_new_mem_buf(privateKeyPKCS1.bytes, (int)privateKeyPKCS1.length);
    if (!keyBio) {
        if (outError) *outError = [self errorWithMessage:@"Could not read the private key."];
        return nil;
    }
    pkey = d2i_PrivateKey_bio(keyBio, NULL);
    BIO_free(keyBio);
    if (!pkey) {
        if (outError) *outError = [self errorWithMessage:@"The private key did not parse as an RSA key."];
        return nil;
    }

    BIO *certBio = BIO_new_mem_buf(certificateDER.bytes, (int)certificateDER.length);
    if (!certBio) {
        EVP_PKEY_free(pkey);
        if (outError) *outError = [self errorWithMessage:@"Could not read the certificate."];
        return nil;
    }
    cert = d2i_X509_bio(certBio, NULL);
    BIO_free(certBio);
    if (!cert) {
        EVP_PKEY_free(pkey);
        if (outError) *outError = [self errorWithMessage:@"The certificate did not parse."];
        return nil;
    }

    ca = sk_X509_new_null();
    if (!ca) {
        X509_free(cert);
        EVP_PKEY_free(pkey);
        if (outError) *outError = [self errorWithMessage:@"Could not build the certificate chain."];
        return nil;
    }
    for (NSData *chainDER in chain) {
        BIO *chainBio = BIO_new_mem_buf(chainDER.bytes, (int)chainDER.length);
        if (!chainBio) { continue; }
        X509 *chainCert = d2i_X509_bio(chainBio, NULL);
        BIO_free(chainBio);
        if (chainCert) { sk_X509_push(ca, chainCert); }
    }

    NSData *result = WTDataFromPKCS12(pkey, cert, ca, password, outError);
    sk_X509_pop_free(ca, X509_free);
    X509_free(cert);
    EVP_PKEY_free(pkey);
    return result;
}

+ (nullable NSData *)rewrapPKCS12:(NSData *)p12Data
                   storedPassword:(NSString *)storedPassword
                      newPassword:(NSString *)newPassword
                            error:(NSError **)outError {
    BIO *bio = BIO_new_mem_buf(p12Data.bytes, (int)p12Data.length);
    if (!bio) {
        if (outError) *outError = [self errorWithMessage:@"Could not read the stored certificate."];
        return nil;
    }
    EVP_PKEY *pkey = NULL;
    X509 *cert = NULL;
    STACK_OF(X509) *ca = NULL;
    if (!PKCS12_parse(bio, storedPassword.UTF8String, &pkey, &cert, &ca) || !pkey || !cert) {
        BIO_free(bio);
        if (pkey) EVP_PKEY_free(pkey);
        if (cert) X509_free(cert);
        if (ca) sk_X509_pop_free(ca, X509_free);
        if (outError) *outError = [self errorWithMessage:@"The stored certificate could not be opened."];
        return nil;
    }
    BIO_free(bio);
    NSData *result = WTDataFromPKCS12(pkey, cert, ca, newPassword, outError);
    EVP_PKEY_free(pkey);
    X509_free(cert);
    if (ca) sk_X509_pop_free(ca, X509_free);
    return result;
}

@end
