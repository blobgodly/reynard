use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering};
use std::sync::{Arc, RwLock};
use std::thread;
use std::time::{Duration, Instant};

pub const STATUS_QUEUED: i32 = 0;
pub const STATUS_DOWNLOADING: i32 = 1;
pub const STATUS_PAUSED: i32 = 2;
pub const STATUS_COMPLETED: i32 = 3;
pub const STATUS_FAILED: i32 = 4;
pub const STATUS_CANCELLED: i32 = 5;

pub type DownloadProgressCallback = extern "C" fn(callback_id: u64, downloaded_bytes: u64, total_bytes: u64, status: i32);

struct DownloadTask {
    id: u64,
    url: String,
    output_path: String,
    callback_id: u64,
    callback: Option<DownloadProgressCallback>,
    status: AtomicI32,
    should_pause: AtomicBool,
    should_cancel: AtomicBool,
    downloaded_bytes: AtomicU64,
    total_bytes: AtomicU64,
}

static NEXT_DOWNLOAD_ID: AtomicU64 = AtomicU64::new(1);
static DOWNLOAD_MANAGER: RwLock<Option<HashMap<u64, Arc<DownloadTask>>>> = RwLock::new(None);

fn get_tasks_map() -> std::sync::RwLockWriteGuard<'static, Option<HashMap<u64, Arc<DownloadTask>>>> {
    let mut guard = DOWNLOAD_MANAGER.write().unwrap_or_else(|p| p.into_inner());
    if guard.is_none() {
        *guard = Some(HashMap::new());
    }
    guard
}

pub fn start_download(
    url: &str,
    output_path: &str,
    callback_id: u64,
    callback: Option<DownloadProgressCallback>,
) -> u64 {
    let id = NEXT_DOWNLOAD_ID.fetch_add(1, Ordering::SeqCst);
    let task = Arc::new(DownloadTask {
        id,
        url: url.to_string(),
        output_path: output_path.to_string(),
        callback_id,
        callback,
        status: AtomicI32::new(STATUS_QUEUED),
        should_pause: AtomicBool::new(false),
        should_cancel: AtomicBool::new(false),
        downloaded_bytes: AtomicU64::new(0),
        total_bytes: AtomicU64::new(0),
    });

    {
        let mut map = get_tasks_map();
        if let Some(tasks) = map.as_mut() {
            tasks.insert(id, Arc::clone(&task));
        }
    }

    spawn_download_worker(task);
    id
}

pub fn pause_download(download_id: u64) -> bool {
    let guard = DOWNLOAD_MANAGER.read().unwrap_or_else(|p| p.into_inner());
    if let Some(tasks) = guard.as_ref() {
        if let Some(task) = tasks.get(&download_id) {
            let current = task.status.load(Ordering::SeqCst);
            if current == STATUS_DOWNLOADING || current == STATUS_QUEUED {
                task.should_pause.store(true, Ordering::SeqCst);
                return true;
            }
        }
    }
    false
}

pub fn resume_download(download_id: u64) -> bool {
    let guard = DOWNLOAD_MANAGER.read().unwrap_or_else(|p| p.into_inner());
    if let Some(tasks) = guard.as_ref() {
        if let Some(task) = tasks.get(&download_id) {
            let current = task.status.load(Ordering::SeqCst);
            if current == STATUS_PAUSED || current == STATUS_FAILED {
                task.should_pause.store(false, Ordering::SeqCst);
                task.should_cancel.store(false, Ordering::SeqCst);
                task.status.store(STATUS_QUEUED, Ordering::SeqCst);
                spawn_download_worker(Arc::clone(task));
                return true;
            }
        }
    }
    false
}

pub fn cancel_download(download_id: u64) -> bool {
    let guard = DOWNLOAD_MANAGER.read().unwrap_or_else(|p| p.into_inner());
    if let Some(tasks) = guard.as_ref() {
        if let Some(task) = tasks.get(&download_id) {
            task.should_cancel.store(true, Ordering::SeqCst);
            task.status.store(STATUS_CANCELLED, Ordering::SeqCst);
            if let Some(cb) = task.callback {
                cb(
                    task.callback_id,
                    task.downloaded_bytes.load(Ordering::Relaxed),
                    task.total_bytes.load(Ordering::Relaxed),
                    STATUS_CANCELLED,
                );
            }
            return true;
        }
    }
    false
}

pub fn get_download_status(download_id: u64) -> i32 {
    let guard = DOWNLOAD_MANAGER.read().unwrap_or_else(|p| p.into_inner());
    if let Some(tasks) = guard.as_ref() {
        if let Some(task) = tasks.get(&download_id) {
            return task.status.load(Ordering::SeqCst);
        }
    }
    -1 // Not found
}

pub fn get_download_progress(download_id: u64) -> (u64, u64) {
    let guard = DOWNLOAD_MANAGER.read().unwrap_or_else(|p| p.into_inner());
    if let Some(tasks) = guard.as_ref() {
        if let Some(task) = tasks.get(&download_id) {
            return (
                task.downloaded_bytes.load(Ordering::Relaxed),
                task.total_bytes.load(Ordering::Relaxed),
            );
        }
    }
    (0, 0)
}

fn spawn_download_worker(task: Arc<DownloadTask>) {
    thread::spawn(move || {
        task.status.store(STATUS_DOWNLOADING, Ordering::SeqCst);

        // Check existing file size for HTTP Range resume
        let out_path = Path::new(&task.output_path);
        let existing_bytes = if out_path.exists() {
            out_path.metadata().map(|m| m.len()).unwrap_or(0)
        } else {
            0
        };

        let mut req = ureq::get(&task.url).timeout(Duration::from_secs(30));
        let resuming = existing_bytes > 0;
        if resuming {
            req = req.set("Range", &format!("bytes={}-", existing_bytes));
        }

        let resp = match req.call() {
            Ok(r) => r,
            Err(e) => {
                task.status.store(STATUS_FAILED, Ordering::SeqCst);
                if let Some(cb) = task.callback {
                    cb(task.callback_id, existing_bytes, 0, STATUS_FAILED);
                }
                eprintln!("Download HTTP error: {}", e);
                return;
            }
        };

        let status_code = resp.status();
        let is_range_ok = status_code == 206;
        let is_full_ok = status_code == 200;

        if !is_range_ok && !is_full_ok {
            task.status.store(STATUS_FAILED, Ordering::SeqCst);
            if let Some(cb) = task.callback {
                cb(task.callback_id, existing_bytes, 0, STATUS_FAILED);
            }
            return;
        }

        let (mut file, mut downloaded_so_far, total_expected) = if resuming && is_range_ok {
            let total_len = if let Some(cr) = resp.header("Content-Range") {
                // Example: bytes 100-999/1000
                cr.rsplit('/')
                    .next()
                    .and_then(|s| s.parse::<u64>().ok())
                    .unwrap_or(0)
            } else {
                let content_len = resp
                    .header("Content-Length")
                    .and_then(|s| s.parse::<u64>().ok())
                    .unwrap_or(0);
                if content_len > 0 {
                    existing_bytes + content_len
                } else {
                    0
                }
            };

            let f = match OpenOptions::new().create(true).append(true).open(out_path) {
                Ok(f) => f,
                Err(_) => {
                    task.status.store(STATUS_FAILED, Ordering::SeqCst);
                    if let Some(cb) = task.callback {
                        cb(task.callback_id, existing_bytes, 0, STATUS_FAILED);
                    }
                    return;
                }
            };
            (f, existing_bytes, total_len)
        } else {
            let total_len = resp
                .header("Content-Length")
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(0);

            let f = match OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(out_path)
            {
                Ok(f) => f,
                Err(_) => {
                    task.status.store(STATUS_FAILED, Ordering::SeqCst);
                    if let Some(cb) = task.callback {
                        cb(task.callback_id, 0, 0, STATUS_FAILED);
                    }
                    return;
                }
            };
            (f, 0, total_len)
        };

        task.total_bytes.store(total_expected, Ordering::Relaxed);
        task.downloaded_bytes.store(downloaded_so_far, Ordering::Relaxed);

        let mut reader = resp.into_reader();
        let mut buffer = [0u8; 64 * 1024]; // 64 KB chunk
        let mut last_callback_time = Instant::now();

        loop {
            if task.should_cancel.load(Ordering::SeqCst) {
                task.status.store(STATUS_CANCELLED, Ordering::SeqCst);
                let _ = file.flush();
                if let Some(cb) = task.callback {
                    cb(task.callback_id, downloaded_so_far, total_expected, STATUS_CANCELLED);
                }
                return;
            }

            if task.should_pause.load(Ordering::SeqCst) {
                task.status.store(STATUS_PAUSED, Ordering::SeqCst);
                let _ = file.flush();
                if let Some(cb) = task.callback {
                    cb(task.callback_id, downloaded_so_far, total_expected, STATUS_PAUSED);
                }
                return;
            }

            match reader.read(&mut buffer) {
                Ok(0) => {
                    // EOF - completed!
                    let _ = file.flush();
                    task.status.store(STATUS_COMPLETED, Ordering::SeqCst);
                    task.downloaded_bytes.store(downloaded_so_far, Ordering::Relaxed);
                    if let Some(cb) = task.callback {
                        cb(task.callback_id, downloaded_so_far, total_expected, STATUS_COMPLETED);
                    }
                    break;
                }
                Ok(n) => {
                    if let Err(_) = file.write_all(&buffer[..n]) {
                        task.status.store(STATUS_FAILED, Ordering::SeqCst);
                        if let Some(cb) = task.callback {
                            cb(task.callback_id, downloaded_so_far, total_expected, STATUS_FAILED);
                        }
                        return;
                    }

                    downloaded_so_far += n as u64;
                    task.downloaded_bytes.store(downloaded_so_far, Ordering::Relaxed);

                    // Throttle callback updates to max 10 times per second
                    if last_callback_time.elapsed() >= Duration::from_millis(100) {
                        last_callback_time = Instant::now();
                        if let Some(cb) = task.callback {
                            cb(
                                task.callback_id,
                                downloaded_so_far,
                                total_expected,
                                STATUS_DOWNLOADING,
                            );
                        }
                    }
                }
                Err(e) => {
                    eprintln!("Download read error: {}", e);
                    let _ = file.flush();
                    task.status.store(STATUS_FAILED, Ordering::SeqCst);
                    if let Some(cb) = task.callback {
                        cb(task.callback_id, downloaded_so_far, total_expected, STATUS_FAILED);
                    }
                    return;
                }
            }
        }
    });
}
