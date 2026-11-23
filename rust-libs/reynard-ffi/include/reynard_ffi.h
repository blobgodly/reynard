//
//  reynard_ffi.h
//  Reynard Rust Acceleration Libraries C FFI
//
//  Generated for Reynard Browser iOS (iOS 13.0+)
//

#ifndef REYNARD_FFI_H
#define REYNARD_FFI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Memory Management
// ============================================================================

/**
 * Frees a string pointer allocated by Reynard Rust functions.
 */
void reynard_free_string(char *ptr);

/**
 * Frees a byte buffer pointer allocated by Reynard Rust functions.
 */
void reynard_free_bytes(uint8_t *ptr, size_t len);

// ============================================================================
// DNS-over-HTTPS (DoH)
// ============================================================================

/**
 * Resolves a domain via DoH.
 * @param domain Hostname to resolve (e.g. "example.com")
 * @param record_type DNS record type (e.g. "A", "AAAA", "CNAME", "TXT")
 * @param server_url Custom DoH endpoint, or "cloudflare" / "google" / NULL for default
 * @return JSON array of record strings (e.g. '["93.184.216.34"]'), or NULL on error.
 *         Must be freed with reynard_free_string.
 */
char *reynard_dns_resolve(const char *domain, const char *record_type, const char *server_url);

/**
 * Clears cached DoH entries.
 */
void reynard_dns_clear_cache(void);

// ============================================================================
// Content Blocking (AdBlock)
// ============================================================================

/**
 * Loads adblock filter rules in EasyList format.
 * @param rules Multi-line rule text
 * @return Number of rules successfully loaded
 */
size_t reynard_adblock_load_rules(const char *rules);

/**
 * Clears all loaded adblock filter rules.
 */
void reynard_adblock_clear_rules(void);

/**
 * Evaluates whether a network request should be blocked.
 * @param url Full request URL
 * @param source_url Page origin URL initiating the request
 * @param resource_type Resource type ("script", "image", "stylesheet", "subdocument", etc.)
 * @return true if request matches block rules and no exception matches; false otherwise.
 */
bool reynard_adblock_should_block(const char *url, const char *source_url, const char *resource_type);

/**
 * Returns total count of blocked requests since startup or reset.
 */
uint64_t reynard_adblock_get_blocked_count(void);

/**
 * Resets blocked request counter to zero.
 */
void reynard_adblock_reset_blocked_count(void);

// ============================================================================
// Chunked Download Manager
// ============================================================================

/**
 * Status constants for downloads:
 * 0: Queued
 * 1: Downloading
 * 2: Paused
 * 3: Completed
 * 4: Failed
 * 5: Cancelled
 */
#define REYNARD_DOWNLOAD_STATUS_QUEUED      0
#define REYNARD_DOWNLOAD_STATUS_DOWNLOADING 1
#define REYNARD_DOWNLOAD_STATUS_PAUSED      2
#define REYNARD_DOWNLOAD_STATUS_COMPLETED   3
#define REYNARD_DOWNLOAD_STATUS_FAILED      4
#define REYNARD_DOWNLOAD_STATUS_CANCELLED   5

/**
 * Callback function pointer for download progress updates.
 */
typedef void (*ReynardDownloadCallback)(uint64_t callback_id, uint64_t downloaded_bytes, uint64_t total_bytes, int32_t status);

/**
 * Starts a background resumable chunked download.
 * @param url Remote file URL
 * @param output_path Local destination path
 * @param callback_id Unique identifier passed back to callback
 * @param callback Function pointer for progress updates (can be NULL)
 * @return Unique download ID (> 0) on success, or 0 on error.
 */
uint64_t reynard_download_start(const char *url, const char *output_path, uint64_t callback_id, ReynardDownloadCallback callback);

/**
 * Pauses an active download.
 */
bool reynard_download_pause(uint64_t download_id);

/**
 * Resumes a paused download.
 */
bool reynard_download_resume(uint64_t download_id);

/**
 * Cancels a download.
 */
bool reynard_download_cancel(uint64_t download_id);

/**
 * Retrieves the current status of a download.
 * @return Status code (0-5) or -1 if download ID not found.
 */
int32_t reynard_download_get_status(uint64_t download_id);

// ============================================================================
// Media & Subtitle Parsers
// ============================================================================

/**
 * Parses M3U8 / HLS playlist content.
 * @param content Raw M3U8 text
 * @param base_url Base URL for resolving relative stream / segment URIs
 * @return JSON string of playlist streams and segments, or NULL on error.
 *         Must be freed with reynard_free_string.
 */
char *reynard_media_parse_m3u8(const char *content, const char *base_url);

/**
 * Parses SRT subtitle content into structured cues.
 * @param content Raw SRT text
 * @return JSON array string of cues [{"index":1,"start_ms":...,"end_ms":...,"text":"..."}], or NULL on error.
 *         Must be freed with reynard_free_string.
 */
char *reynard_media_parse_srt(const char *content);

/**
 * Parses WebVTT subtitle content into structured cues.
 * @param content Raw WebVTT text
 * @return JSON array string of cues [{"index":1,"start_ms":...,"end_ms":...,"text":"..."}], or NULL on error.
 *         Must be freed with reynard_free_string.
 */
char *reynard_media_parse_vtt(const char *content);

// ============================================================================
// Cache
// ============================================================================

/**
 * Configures the global LRU cache.
 * @param max_bytes Maximum byte size in RAM before LRU eviction (0 for default 50 MB)
 * @param storage_dir Optional filesystem path for persistent disk caching (can be NULL)
 */
void reynard_cache_init(size_t max_bytes, const char *storage_dir);

/**
 * Puts an item into cache.
 * @param key Unique key
 * @param data Byte pointer
 * @param len Data length in bytes
 * @return true on success, false otherwise
 */
bool reynard_cache_put(const char *key, const uint8_t *data, size_t len);

/**
 * Gets an item from cache.
 * @param key Unique key
 * @param out_len Pointer to store length of returned data
 * @return Pointer to byte buffer, or NULL if not found.
 *         Must be freed with reynard_free_bytes(ptr, *out_len).
 */
uint8_t *reynard_cache_get(const char *key, size_t *out_len);

/**
 * Clears all cached entries.
 */
void reynard_cache_clear(void);

#ifdef __cplusplus
}
#endif

#endif /* REYNARD_FFI_H */
