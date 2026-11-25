// wtidevice.h — MINIMAL header for the WorkTweaks JIT transport.
//
// Declares ONLY the idevice FFI functions the JIT session uses, with the
// signatures copied verbatim from the generated header
// (`rust-core/vendor/idevice-ffi/idevice.h`, cbindgen output for
// jkcoxson/idevice @ 7bd551c16c6dd2e058740d85a2d9399a51a776e9 — the same
// revision SideInstaller v2.2.0 ships). The 9032-line generated header is
// NOT shipped: the xcframework carries this file + plist.h only, and
// Swift imports the module as `WTIDevice` (see module.modulemap).
//
// plist helpers (plist_t, plist_get_node_type, plist_get_bool_val,
// plist_dict_get_item, plist_get_string_val, plist_get_uint_val,
// plist_free, plist_mem_free, PLIST_BOOLEAN) come from plist.h, copied
// byte-identical from vendor/idevice-ffi/plist.h (libimobiledevice
// libplist, LGPL-2.1).
//
// DELIBERATELY NOT DECLARED (v1 scope, see rust-core/README.md):
//   remote_server_* / process_control_* — DVT. The JIT session attaches
//   to WorkTweaks' OWN pid (a LiveContainer guest runs in-process), so
//   nothing is ever launched via DVT process_control_launch_app, and
//   debug_proxy_connect_rsd reaches debugserver directly over RSD.
//   tunnel_create_usb / idevice_tcp_provider_new / lockdownd_new /
//   lockdownd_pair — the CoreDeviceProxy / lockdown route. v1 is
//   RPPairing-only (tunnel_create_rppairing_multihost).
//   si_probe_pairing_port / si_find_pairing_port — SideInstaller's own
//   Rust helpers (rust-core/src/pairing_port.rs). v1 dials port 49152,
//   then the port this iPhone advertises over Bonjour.

#ifndef WTIDEVICE_H
#define WTIDEVICE_H

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/socket.h>

typedef socklen_t          idevice_socklen_t;
typedef struct sockaddr    idevice_sockaddr;

#include "plist.h"

/**
 * Why a tunnel attempt ultimately failed, so the caller can say something more
 * useful than whichever OS error happened to come last. Written through the
 * `out_failure_kind` argument of `tunnel_create_rppairing_multihost`.
 *
 * The raw error still comes back in the `IdeviceFfiError` message, and every
 * step is logged as it happens; this only says *which* wall was hit.
 */
typedef enum TunnelFailureKind {
  /**
   * No failure — the tunnel came up.
   */
  TunnelFailureNone = 0,
  /**
   * The device's RSD port never answered, so nothing below it was attempted.
   */
  TunnelFailureRsdUnreachable = 1,
  /**
   * RSD answered but pair-verify was refused: this pairing file no longer
   * matches the device.
   */
  TunnelFailurePairVerify = 2,
  /**
   * The port `createListener` opened was unreachable — refused outright, or
   * dropped with no answer — on the very host RSD had just answered on, while
   * RSD itself kept working. The device is there; the route in front of it
   * forwards some ports and not others. Also covers the case where every
   * candidate refused.
   */
  TunnelFailureHostsRefused = 3,
  /**
   * Candidates swallowed the connection: no refusal, no answer.
   */
  TunnelFailureTimeout = 4,
  /**
   * A candidate accepted the TCP connection but the TLS-PSK or CDTunnel
   * handshake on top of it failed.
   */
  TunnelFailureTlsHandshake = 5,
  /**
   * Anything else — the RSD handshake inside the tunnel, a parse failure, …
   */
  TunnelFailureOther = 6,
} TunnelFailureKind;

typedef struct AdapterHandle AdapterHandle;
typedef struct AmfiClientHandle AmfiClientHandle;
typedef struct DebugProxyHandle DebugProxyHandle;
typedef struct HeartbeatClientHandle HeartbeatClientHandle;
typedef struct ImageMounterHandle ImageMounterHandle;
typedef struct LockdowndClientHandle LockdowndClientHandle;
typedef struct RpPairingFileHandle RpPairingFileHandle;
typedef struct RsdHandshakeHandle RsdHandshakeHandle;

/**
 * Represents a debugserver command
 */
typedef struct DebugserverCommandHandle {
  char *name;
  char **argv;
  uintptr_t argv_count;
} DebugserverCommandHandle;

typedef struct IdeviceFfiError {
  int32_t code;
  int32_t sub_code;
  const char *message;
} IdeviceFfiError;

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Errors / memory

void idevice_error_free(struct IdeviceFfiError *err);
void idevice_string_free(char *string);
void idevice_data_free(uint8_t *data, uintptr_t len);

// MARK: - Tunnel (RPPairing) + RSD handshake

struct IdeviceFfiError *rp_pairing_file_read(const char *path, struct RpPairingFileHandle **out);
void rp_pairing_file_free(struct RpPairingFileHandle *handle);

struct IdeviceFfiError *tunnel_create_rppairing_multihost(const idevice_sockaddr *addr,
                                                          idevice_socklen_t addr_len,
                                                          const char *hostname,
                                                          struct RpPairingFileHandle *pairing_file,
                                                          const char *(*pin_callback)(void *context),
                                                          void *pin_context,
                                                          const char *const *extra_hosts,
                                                          uintptr_t extra_host_count,
                                                          enum TunnelFailureKind *out_failure_kind,
                                                          struct AdapterHandle **out_adapter,
                                                          struct RsdHandshakeHandle **out_handshake);

void adapter_free(struct AdapterHandle *handle);
void rsd_handshake_free(struct RsdHandshakeHandle *handle);
struct IdeviceFfiError *rsd_get_protocol_version(struct RsdHandshakeHandle *handle,
                                                 size_t *version);
struct IdeviceFfiError *rsd_get_uuid(struct RsdHandshakeHandle *handle, char **uuid);

// MARK: - Lockdown (over RSD)

struct IdeviceFfiError *lockdownd_connect_rsd(struct AdapterHandle *provider,
                                              struct RsdHandshakeHandle *handshake,
                                              struct LockdowndClientHandle **client);
struct IdeviceFfiError *lockdownd_get_value(struct LockdowndClientHandle *client,
                                            const char *key,
                                            const char *domain,
                                            plist_t *out_plist);
void lockdownd_client_free(struct LockdowndClientHandle *handle);

// MARK: - AMFI / Developer Mode (over RSD)

struct IdeviceFfiError *amfi_connect_rsd(struct AdapterHandle *provider,
                                         struct RsdHandshakeHandle *handshake,
                                         struct AmfiClientHandle **client);
struct IdeviceFfiError *amfi_reveal_developer_mode_option_in_ui(struct AmfiClientHandle *client);
struct IdeviceFfiError *amfi_enable_developer_mode(struct AmfiClientHandle *client);
void amfi_client_free(struct AmfiClientHandle *handle);

// MARK: - Debug proxy (debugserver over RSD)

struct IdeviceFfiError *debug_proxy_connect_rsd(struct AdapterHandle *provider,
                                                struct RsdHandshakeHandle *handshake,
                                                struct DebugProxyHandle **handle);
void debug_proxy_free(struct DebugProxyHandle *handle);

struct DebugserverCommandHandle *debugserver_command_new(const char *name,
                                                         const char *const *argv,
                                                         uintptr_t argv_count);
void debugserver_command_free(struct DebugserverCommandHandle *command);
struct IdeviceFfiError *debug_proxy_send_command(struct DebugProxyHandle *handle,
                                                 struct DebugserverCommandHandle *command,
                                                 char **response);
struct IdeviceFfiError *debug_proxy_read_response(struct DebugProxyHandle *handle, char **response);
struct IdeviceFfiError *debug_proxy_send_raw(struct DebugProxyHandle *handle,
                                             const uint8_t *data,
                                             uintptr_t len);
struct IdeviceFfiError *debug_proxy_send_ack(struct DebugProxyHandle *handle);
void debug_proxy_set_ack_mode(struct DebugProxyHandle *handle, int enabled);

// MARK: - Heartbeat (over RSD, while the debugger stays attached)

struct IdeviceFfiError *heartbeat_connect_rsd(struct AdapterHandle *provider,
                                              struct RsdHandshakeHandle *handshake,
                                              struct HeartbeatClientHandle **client);
struct IdeviceFfiError *heartbeat_send_polo(struct HeartbeatClientHandle *client);
struct IdeviceFfiError *heartbeat_get_marco(struct HeartbeatClientHandle *client,
                                            uint64_t interval,
                                            uint64_t *new_interval);
void heartbeat_client_free(struct HeartbeatClientHandle *handle);

// MARK: - Developer disk image mounter (over RSD)

struct IdeviceFfiError *image_mounter_connect_rsd(struct AdapterHandle *provider,
                                                  struct RsdHandshakeHandle *handshake,
                                                  struct ImageMounterHandle **client);
void image_mounter_free(struct ImageMounterHandle *handle);
struct IdeviceFfiError *image_mounter_copy_devices(struct ImageMounterHandle *client,
                                                   plist_t **devices,
                                                   size_t *devices_len);
struct IdeviceFfiError *image_mounter_mount_personalized_with_callback_rsd(struct ImageMounterHandle *client,
                                                                           struct AdapterHandle *provider,
                                                                           struct RsdHandshakeHandle *handshake,
                                                                           const uint8_t *image,
                                                                           size_t image_len,
                                                                           const uint8_t *trust_cache,
                                                                           size_t trust_cache_len,
                                                                           const uint8_t *build_manifest,
                                                                           size_t build_manifest_len,
                                                                           const void *info_plist,
                                                                           uint64_t unique_chip_id,
                                                                           void (*callback)(size_t progress,
                                                                                            size_t total,
                                                                                            void *context),
                                                                           void *context);

#ifdef __cplusplus
}
#endif

#endif // WTIDEVICE_H
