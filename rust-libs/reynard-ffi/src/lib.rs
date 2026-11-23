use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::catch_unwind;
use std::ptr;
use std::slice;

// ============================================================================
// Memory Management FFI
// ============================================================================

/// Frees a string previously allocated by Reynard Rust FFI functions.
#[no_mangle]
pub unsafe extern "C" fn reynard_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// Frees a byte buffer previously allocated by Reynard Rust FFI functions.
#[no_mangle]
pub unsafe extern "C" fn reynard_free_bytes(ptr: *mut u8, len: usize) {
    if !ptr.is_null() && len > 0 {
        let _ = Vec::from_raw_parts(ptr, len, len);
    }
}

// ============================================================================
// DNS-over-HTTPS (DoH) FFI
// ============================================================================

/// Resolves a domain via DNS-over-HTTPS.
/// Returns a JSON array of record strings (e.g. `["1.2.3.4"]`), or NULL on failure.
/// The returned pointer must be freed with `reynard_free_string`.
#[no_mangle]
pub unsafe extern "C" fn reynard_dns_resolve(
    domain: *const c_char,
    record_type: *const c_char,
    server_url: *const c_char,
) -> *mut c_char {
    let result = catch_unwind(|| {
        if domain.is_null() {
            return ptr::null_mut();
        }
        let domain_str = match CStr::from_ptr(domain).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        };

        let record_type_str = if !record_type.is_null() {
            CStr::from_ptr(record_type).to_str().unwrap_or("A")
        } else {
            "A"
        };

        let server_url_str = if !server_url.is_null() {
            CStr::from_ptr(server_url).to_str().unwrap_or("")
        } else {
            ""
        };

        match reynard_dns::resolve_doh(domain_str, record_type_str, server_url_str) {
            Ok(records) => {
                let json = serde_json::to_string(&records).unwrap_or_default();
                CString::new(json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut())
            }
            Err(_) => ptr::null_mut(),
        }
    });

    result.unwrap_or(ptr::null_mut())
}

/// Clears cached DNS entries.
#[no_mangle]
pub unsafe extern "C" fn reynard_dns_clear_cache() {
    let _ = catch_unwind(|| {
        reynard_dns::clear_dns_cache();
    });
}

// ============================================================================
// Content Blocking (AdBlock) FFI
// ============================================================================

/// Loads filter rules (EasyList format).
/// Returns number of rules successfully loaded.
#[no_mangle]
pub unsafe extern "C" fn reynard_adblock_load_rules(rules: *const c_char) -> usize {
    let result = catch_unwind(|| {
        if rules.is_null() {
            return 0;
        }
        if let Ok(content) = CStr::from_ptr(rules).to_str() {
            reynard_adblock::load_filter_rules(content)
        } else {
            0
        }
    });
    result.unwrap_or(0)
}

/// Clears all loaded adblock rules.
#[no_mangle]
pub unsafe extern "C" fn reynard_adblock_clear_rules() {
    let _ = catch_unwind(|| {
        reynard_adblock::clear_filter_rules();
    });
}

/// Checks whether a network request should be blocked.
#[no_mangle]
pub unsafe extern "C" fn reynard_adblock_should_block(
    url: *const c_char,
    source_url: *const c_char,
    resource_type: *const c_char,
) -> bool {
    let result = catch_unwind(|| {
        if url.is_null() {
            return false;
        }
        let url_str = match CStr::from_ptr(url).to_str() {
            Ok(s) => s,
            Err(_) => return false,
        };

        let source_str = if !source_url.is_null() {
            CStr::from_ptr(source_url).to_str().unwrap_or("")
        } else {
            ""
        };

        let type_str = if !resource_type.is_null() {
            CStr::from_ptr(resource_type).to_str().unwrap_or("other")
        } else {
            "other"
        };

        reynard_adblock::should_block(url_str, source_str, type_str)
    });
    result.unwrap_or(false)
}

/// Returns the total number of blocked requests.
#[no_mangle]
pub unsafe extern "C" fn reynard_adblock_get_blocked_count() -> u64 {
    let result = catch_unwind(|| reynard_adblock::get_blocked_count());
    result.unwrap_or(0)
}

/// Resets the blocked request counter to zero.
#[no_mangle]
pub unsafe extern "C" fn reynard_adblock_reset_blocked_count() {
    let _ = catch_unwind(|| {
        reynard_adblock::reset_blocked_count();
    });
}

// ============================================================================
// Chunked Download Manager FFI
// ============================================================================

pub type ReynardDownloadCallback = reynard_download::DownloadProgressCallback;

/// Starts a chunked, resumable download on a background worker thread.
/// Returns a unique download ID (> 0) on success, or 0 on error.
#[no_mangle]
pub unsafe extern "C" fn reynard_download_start(
    url: *const c_char,
    output_path: *const c_char,
    callback_id: u64,
    callback: Option<ReynardDownloadCallback>,
) -> u64 {
    let result = catch_unwind(|| {
        if url.is_null() || output_path.is_null() {
            return 0;
        }
        let url_str = match CStr::from_ptr(url).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        };
        let out_str = match CStr::from_ptr(output_path).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        };

        reynard_download::start_download(url_str, out_str, callback_id, callback)
    });
    result.unwrap_or(0)
}

/// Pauses an active download.
#[no_mangle]
pub unsafe extern "C" fn reynard_download_pause(download_id: u64) -> bool {
    let result = catch_unwind(|| reynard_download::pause_download(download_id));
    result.unwrap_or(false)
}

/// Resumes a paused or failed download.
#[no_mangle]
pub unsafe extern "C" fn reynard_download_resume(download_id: u64) -> bool {
    let result = catch_unwind(|| reynard_download::resume_download(download_id));
    result.unwrap_or(false)
}

/// Cancels a download.
#[no_mangle]
pub unsafe extern "C" fn reynard_download_cancel(download_id: u64) -> bool {
    let result = catch_unwind(|| reynard_download::cancel_download(download_id));
    result.unwrap_or(false)
}

/// Returns the status code of a download.
/// (0: Queued, 1: Downloading, 2: Paused, 3: Completed, 4: Failed, 5: Cancelled, -1: Not found)
#[no_mangle]
pub unsafe extern "C" fn reynard_download_get_status(download_id: u64) -> i32 {
    let result = catch_unwind(|| reynard_download::get_download_status(download_id));
    result.unwrap_or(-1)
}

// ============================================================================
// Media & Subtitle Parser FFI
// ============================================================================

/// Parses M3U8/HLS playlist content.
/// Returns a JSON string of streams and segments, or NULL on error.
/// Caller must free with `reynard_free_string`.
#[no_mangle]
pub unsafe extern "C" fn reynard_media_parse_m3u8(
    content: *const c_char,
    base_url: *const c_char,
) -> *mut c_char {
    let result = catch_unwind(|| {
        if content.is_null() {
            return ptr::null_mut();
        }
        let content_str = match CStr::from_ptr(content).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        };
        let base_url_str = if !base_url.is_null() {
            CStr::from_ptr(base_url).to_str().unwrap_or("")
        } else {
            ""
        };

        match reynard_media::parse_m3u8_to_json(content_str, base_url_str) {
            Ok(json) => CString::new(json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut()),
            Err(_) => ptr::null_mut(),
        }
    });
    result.unwrap_or(ptr::null_mut())
}

/// Parses SRT subtitle content into a JSON array of cues.
/// Caller must free with `reynard_free_string`.
#[no_mangle]
pub unsafe extern "C" fn reynard_media_parse_srt(content: *const c_char) -> *mut c_char {
    let result = catch_unwind(|| {
        if content.is_null() {
            return ptr::null_mut();
        }
        let content_str = match CStr::from_ptr(content).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        };

        match reynard_media::parse_srt_to_json(content_str) {
            Ok(json) => CString::new(json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut()),
            Err(_) => ptr::null_mut(),
        }
    });
    result.unwrap_or(ptr::null_mut())
}

/// Parses WebVTT subtitle content into a JSON array of cues.
/// Caller must free with `reynard_free_string`.
#[no_mangle]
pub unsafe extern "C" fn reynard_media_parse_vtt(content: *const c_char) -> *mut c_char {
    let result = catch_unwind(|| {
        if content.is_null() {
            return ptr::null_mut();
        }
        let content_str = match CStr::from_ptr(content).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        };

        match reynard_media::parse_vtt_to_json(content_str) {
            Ok(json) => CString::new(json).map(|c| c.into_raw()).unwrap_or(ptr::null_mut()),
            Err(_) => ptr::null_mut(),
        }
    });
    result.unwrap_or(ptr::null_mut())
}

// ============================================================================
// Cache FFI
// ============================================================================

/// Initializes the global cache with maximum byte size and optional disk storage directory.
#[no_mangle]
pub unsafe extern "C" fn reynard_cache_init(max_bytes: usize, storage_dir: *const c_char) {
    let _ = catch_unwind(|| {
        let dir = if !storage_dir.is_null() {
            CStr::from_ptr(storage_dir).to_str().ok()
        } else {
            None
        };
        reynard_cache::init_cache(max_bytes, dir);
    });
}

/// Stores binary data in cache. Returns true on success.
#[no_mangle]
pub unsafe extern "C" fn reynard_cache_put(
    key: *const c_char,
    data: *const u8,
    len: usize,
) -> bool {
    let result = catch_unwind(|| {
        if key.is_null() || data.is_null() || len == 0 {
            return false;
        }
        let key_str = match CStr::from_ptr(key).to_str() {
            Ok(s) => s,
            Err(_) => return false,
        };
        let slice = slice::from_raw_parts(data, len);
        reynard_cache::cache_put(key_str, slice)
    });
    result.unwrap_or(false)
}

/// Retrieves binary data from cache.
/// Writes length to `*out_len` and returns pointer to buffer.
/// Caller must free returned pointer with `reynard_free_bytes(ptr, *out_len)`.
#[no_mangle]
pub unsafe extern "C" fn reynard_cache_get(key: *const c_char, out_len: *mut usize) -> *mut u8 {
    let result = catch_unwind(|| {
        if key.is_null() || out_len.is_null() {
            return ptr::null_mut();
        }
        let key_str = match CStr::from_ptr(key).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        };

        if let Some(data) = reynard_cache::cache_get(key_str) {
            *out_len = data.len();
            let mut boxed = data.into_boxed_slice();
            let raw = boxed.as_mut_ptr();
            std::mem::forget(boxed);
            raw
        } else {
            *out_len = 0;
            ptr::null_mut()
        }
    });
    result.unwrap_or(ptr::null_mut())
}

/// Clears all in-memory and persisted cached items.
#[no_mangle]
pub unsafe extern "C" fn reynard_cache_clear() {
    let _ = catch_unwind(|| {
        reynard_cache::cache_clear();
    });
}
