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

static int wtLastErrno = 0;

int wtTaskEntitlementsErrno(void) {
    return wtLastErrno;
}

NSData *wtTaskEntitlements(void) {
    // Start generous (entitlements are usually a few KB); double on
    // ERANGE up to 1 MiB. csops returns 0 on success, -1 on failure.
    size_t capacity = 65536;
    for (int attempt = 0; attempt < 5; attempt++) {
        void *buffer = malloc(capacity);
        if (!buffer) return nil;
        long result = syscall(SYS_csops, getpid(), WT_CSOPS_ENTITLEMENTS_BLOB, buffer, capacity);
        if (result == 0) {
            // The blob is the entitlements plist, but the kernel may
            // hand it back with its blob header in front (magic
            // 0xfade7171 + length). Find the plist itself: start at
            // "<?xml" and end at "</plist>" — starting at byte 0
            // makes the plist parser choke on the header.
            static const char startMarker[] = "<?xml";
            static const char endMarker[] = "</plist>";
            size_t startLength = sizeof(startMarker) - 1;
            size_t endLength = sizeof(endMarker) - 1;
            size_t start = SIZE_MAX;
            size_t end = 0;
            for (size_t i = 0; i + startLength <= capacity; i++) {
                if (memcmp((char *)buffer + i, startMarker, startLength) == 0) {
                    start = i;
                    break;
                }
            }
            if (start != SIZE_MAX) {
                for (size_t i = start; i + endLength <= capacity; i++) {
                    if (memcmp((char *)buffer + i, endMarker, endLength) == 0) {
                        end = i + endLength;
                        break;
                    }
                }
            }
            if (start == SIZE_MAX || end == 0) {
                free(buffer);
                return nil;
            }
            NSData *data = [NSData dataWithBytes:(char *)buffer + start length:end - start];
            free(buffer);
            wtLastErrno = 0;
            return data;
        }
        int savedErrno = errno;
        free(buffer);
        wtLastErrno = savedErrno;
        if (savedErrno != ERANGE) return nil;
        capacity *= 2;
    }
    return nil;
}
