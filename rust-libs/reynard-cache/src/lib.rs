use std::collections::{BTreeMap, HashMap};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::RwLock;

struct CacheEntry {
    data: Option<Vec<u8>>,
    file_path: Option<PathBuf>,
    size: usize,
    access_id: u64,
}

pub struct ReynardCache {
    max_bytes: usize,
    current_bytes: usize,
    storage_dir: Option<PathBuf>,
    entries: HashMap<String, CacheEntry>,
    order_map: BTreeMap<u64, String>,
    access_counter: AtomicU64,
}

impl ReynardCache {
    pub fn new(max_bytes: usize, storage_dir: Option<PathBuf>) -> Self {
        if let Some(ref dir) = storage_dir {
            let _ = fs::create_dir_all(dir);
        }
        Self {
            max_bytes: if max_bytes == 0 { 50 * 1024 * 1024 } else { max_bytes },
            current_bytes: 0,
            storage_dir,
            entries: HashMap::new(),
            order_map: BTreeMap::new(),
            access_counter: AtomicU64::new(1),
        }
    }

    pub fn set_max_size(&mut self, max_bytes: usize) {
        self.max_bytes = max_bytes;
        self.evict_if_needed();
    }

    pub fn set_storage_dir(&mut self, dir: PathBuf) {
        let _ = fs::create_dir_all(&dir);
        self.storage_dir = Some(dir);
    }

    pub fn put(&mut self, key: &str, data: &[u8]) -> bool {
        let size = data.len();
        if size > self.max_bytes {
            return false;
        }

        // If key already exists, remove previous entry
        self.remove_internal(key);

        let access_id = self.access_counter.fetch_add(1, Ordering::Relaxed);

        // Optional file persistence with memory-mapping support
        let mut file_path = None;
        if let Some(ref dir) = self.storage_dir {
            let file_name = key_to_filename(key);
            let path = dir.join(&file_name);
            if let Ok(mut f) = OpenOptions::new().create(true).write(true).truncate(true).open(&path) {
                if f.write_all(data).is_ok() {
                    file_path = Some(path);
                }
            }
        }

        self.order_map.insert(access_id, key.to_string());
        self.entries.insert(
            key.to_string(),
            CacheEntry {
                data: Some(data.to_vec()),
                file_path,
                size,
                access_id,
            },
        );

        self.current_bytes += size;
        self.evict_if_needed();
        true
    }

    pub fn get(&mut self, key: &str) -> Option<Vec<u8>> {
        let entry = self.entries.get_mut(key)?;

        let old_access_id = entry.access_id;
        self.order_map.remove(&old_access_id);

        let new_access_id = self.access_counter.fetch_add(1, Ordering::Relaxed);
        entry.access_id = new_access_id;
        self.order_map.insert(new_access_id, key.to_string());

        if let Some(ref d) = entry.data {
            return Some(d.clone());
        }

        // Try memory-mapped reading if data was flushed from RAM to disk
        if let Some(ref path) = entry.file_path {
            if let Ok(file) = File::open(path) {
                if let Ok(mmap) = unsafe { memmap2::Mmap::map(&file) } {
                    let vec_data = mmap[..].to_vec();
                    entry.data = Some(vec_data.clone());
                    return Some(vec_data);
                }
            }
        }

        None
    }

    pub fn remove(&mut self, key: &str) -> bool {
        self.remove_internal(key)
    }

    fn remove_internal(&mut self, key: &str) -> bool {
        if let Some(entry) = self.entries.remove(key) {
            self.order_map.remove(&entry.access_id);
            self.current_bytes = self.current_bytes.saturating_sub(entry.size);
            if let Some(ref path) = entry.file_path {
                let _ = fs::remove_file(path);
            }
            return true;
        }
        false
    }

    pub fn clear(&mut self) {
        if let Some(ref dir) = self.storage_dir {
            for entry in self.entries.values() {
                if let Some(ref path) = entry.file_path {
                    let _ = fs::remove_file(path);
                }
            }
            let _ = fs::remove_dir_all(dir);
            let _ = fs::create_dir_all(dir);
        }
        self.entries.clear();
        self.order_map.clear();
        self.current_bytes = 0;
    }

    fn evict_if_needed(&mut self) {
        while self.current_bytes > self.max_bytes && !self.order_map.is_empty() {
            let lru_key = {
                let (first_id, first_key) = self.order_map.iter().next().unwrap();
                (*first_id, first_key.clone())
            };

            self.remove_internal(&lru_key.1);
        }
    }
}

fn key_to_filename(key: &str) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    key.hash(&mut hasher);
    let hash = hasher.finish();

    // Sanitize first 16 alphanumeric characters of key for readability + hash suffix
    let clean_prefix: String = key
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .take(16)
        .collect();

    format!("{}_{:016x}.cache", clean_prefix, hash)
}

static GLOBAL_CACHE: RwLock<Option<ReynardCache>> = RwLock::new(None);

pub fn init_cache(max_bytes: usize, storage_dir: Option<&str>) {
    let mut guard = GLOBAL_CACHE.write().unwrap_or_else(|p| p.into_inner());
    let path_buf = storage_dir.map(PathBuf::from);
    *guard = Some(ReynardCache::new(max_bytes, path_buf));
}

fn get_global_cache() -> std::sync::RwLockWriteGuard<'static, Option<ReynardCache>> {
    let mut guard = GLOBAL_CACHE.write().unwrap_or_else(|p| p.into_inner());
    if guard.is_none() {
        *guard = Some(ReynardCache::new(50 * 1024 * 1024, None));
    }
    guard
}

pub fn cache_put(key: &str, data: &[u8]) -> bool {
    let mut guard = get_global_cache();
    if let Some(cache) = guard.as_mut() {
        cache.put(key, data)
    } else {
        false
    }
}

pub fn cache_get(key: &str) -> Option<Vec<u8>> {
    let mut guard = get_global_cache();
    if let Some(cache) = guard.as_mut() {
        cache.get(key)
    } else {
        None
    }
}

pub fn cache_clear() {
    let mut guard = get_global_cache();
    if let Some(cache) = guard.as_mut() {
        cache.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lru_eviction() {
        let mut cache = ReynardCache::new(100, None);
        cache.put("item1", &[0u8; 60]);
        cache.put("item2", &[1u8; 30]);
        assert_eq!(cache.current_bytes, 90);

        // Access item1 to make item2 the LRU
        assert!(cache.get("item1").is_some());

        // Put item3 which causes eviction of item2
        cache.put("item3", &[2u8; 30]);
        assert!(cache.get("item1").is_some());
        assert!(cache.get("item2").is_none());
        assert!(cache.get("item3").is_some());
    }
}
