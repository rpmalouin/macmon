/* macmon C ABI — the sampler behind the CLI, for other UIs.
 *
 * One sampler object owns the low-level macOS handles, so it belongs to the thread that
 * created it: create, sample and free it on the same thread. Nothing here panics; every
 * failure is a null return, with the reason in macmon_last_error().
 *
 * Example:
 *
 *   void *sampler = macmon_sampler_new();
 *   char *json = macmon_sampler_next(sampler, 1000);
 *   if (json) { puts(json); macmon_free(json); }
 *   else { fprintf(stderr, "%s\n", macmon_last_error()); }
 *   macmon_sampler_free(sampler);
 *
 * Linking: this ships as a static archive, and the Rust library's `#[link]` attributes do not
 * carry into it, so the caller links the frameworks itself:
 *
 *   clang … libmacmon_ffi.a -framework CoreFoundation -framework IOKit \
 *     -framework Foundation -lIOReport
 *
 * IOReport is Apple's private stub, at `$(xcrun --show-sdk-path)/usr/lib/libIOReport.tbd`. The
 * same flags are needed by any linker that consumes the archive, SwiftPM included.
 */

#ifndef MACMON_FFI_H
#define MACMON_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Create a sampler, or return NULL with the reason in macmon_last_error(). */
void *macmon_sampler_new(void);

/* Collect one sample over `duration_ms` and return it as a JSON object, to be released with
 * macmon_free(). `duration_ms` is clamped to at least 100, as in the CLI. The document holds
 * the same field names as `macmon pipe`, minus its deprecated v0.7 aliases, plus `timestamp`
 * in Unix epoch seconds.
 *
 * The sampler keeps an IOReport baseline between calls, so sample it in a loop: the interval
 * between two calls is the interval the metrics describe. NULL on failure. */
char *macmon_sampler_next(void *sampler, uint32_t duration_ms);

/* Static machine and frequency-table information as a JSON object, to be released with
 * macmon_free(). It does not change while the sampler lives: read it once, for labels and
 * frequency scales. NULL on failure. */
char *macmon_sampler_soc_json(void *sampler);

/* Release a sampler. NULL is ignored. The pointer must not be used afterwards. */
void macmon_sampler_free(void *sampler);

/* The last error of the calling thread, or an empty string. The pointer stays valid until the
 * next call that sets or clears an error on this thread; copy it to keep it. */
const char *macmon_last_error(void);

/* Release a string returned by macmon_sampler_next or macmon_sampler_soc_json. NULL is
 * ignored. Use it only on strings this library returned. */
void macmon_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif /* MACMON_FFI_H */
