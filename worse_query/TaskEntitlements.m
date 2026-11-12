#include "TaskEntitlements.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef SYS_csops
#define SYS_csops 169
#endif

/// csops op that returns the process's entitlements blob (the raw
/// embedded entitlements plist). Defined here because the op number
/// is not in the public iOS SDK headers.
#define WT_CSOPS_ENTITLEMENTS_BLOB 7

NSData *wtTaskEntitlements(void) {
    // Start generous (entitlements are usually a few KB); double on
    // ERANGE up to 1 MiB. csops returns 0 on success, -1 on failure.
    size_t capacity = 65536;
    for (int attempt = 0; attempt < 5; attempt++) {
        void *buffer = malloc(capacity);
        if (!buffer) return nil;
        long result = syscall(SYS_csops, getpid(), WT_CSOPS_ENTITLEMENTS_BLOB, buffer, capacity);
        if (result == 0) {
            // The blob is the raw entitlements plist; find its end
            // marker so the length is exact even if the kernel padded
            // the copy.
            static const char endMarker[] = "</plist>";
            size_t endLength = sizeof(endMarker) - 1;
            size_t found = 0;
            for (size_t i = 0; i + endLength <= capacity; i++) {
                if (memcmp((char *)buffer + i, endMarker, endLength) == 0) {
                    found = i + endLength;
                    break;
                }
            }
            if (found == 0) {
                free(buffer);
                return nil;
            }
            NSData *data = [NSData dataWithBytes:buffer length:found];
            free(buffer);
            return data;
        }
        int savedErrno = errno;
        free(buffer);
        if (savedErrno != ERANGE) return nil;
        capacity *= 2;
    }
    return nil;
}
