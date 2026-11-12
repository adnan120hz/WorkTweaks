#ifndef task_entitlements_h
#define task_entitlements_h

#import <Foundation/Foundation.h>

/// The running process's signed entitlements as an XML plist (NSData),
/// read from the kernel with csops(CS_OPS_ENTITLEMENTS_BLOB) — the
/// entitlements this process REALLY has, whatever host or signer put
/// them there (SideStore, AltStore, LiveContainer's host process).
/// Nil when the kernel refuses or there is no blob.
///
/// SecTask is macOS-only (its headers are not in the iOS SDK), so iOS
/// apps read their own entitlements this way instead: csops is the
/// same syscall SecTask itself calls under the hood, and it is also
/// what anti-tamper checks in App Store apps use, so it is not
/// blocked by the sandbox.

NSData * _Nullable wtTaskEntitlements(void);

/// errno from the most recent failed csops call inside
/// wtTaskEntitlements() (0 when the last call succeeded or no call
/// has been made yet). Lets Swift log WHY discovery failed instead
/// of failing silently.
int wtTaskEntitlementsErrno(void);

#endif /* task_entitlements_h */
