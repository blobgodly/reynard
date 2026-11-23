use serde::Deserialize;
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration, Instant};

const DEFAULT_CLOUDFLARE_DOH: &str = "https://cloudflare-dns.com/dns-query";
const DEFAULT_GOOGLE_DOH: &str = "https://dns.google/resolve";

#[derive(Debug, Clone, Deserialize)]
pub struct DnsResponseAnswer {
    pub name: Option<String>,
    #[serde(rename = "type")]
    pub record_type: Option<u16>,
    #[serde(rename = "TTL")]
    pub ttl: Option<u64>,
    pub data: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DnsResponse {
    #[serde(rename = "Status")]
    pub status: Option<i32>,
    #[serde(rename = "Answer")]
    pub answer: Option<Vec<DnsResponseAnswer>>,
}

#[derive(Debug, Clone)]
struct CacheEntry {
    records: Vec<String>,
    expires_at: Instant,
}

static DNS_CACHE: RwLock<Option<HashMap<String, CacheEntry>>> = RwLock::new(None);

fn get_cache() -> std::sync::RwLockWriteGuard<'static, Option<HashMap<String, CacheEntry>>> {
    let mut guard = DNS_CACHE.write().unwrap_or_else(|poisoned| poisoned.into_inner());
    if guard.is_none() {
        *guard = Some(HashMap::new());
    }
    guard
}

fn cache_lookup(cache_key: &str) -> Option<Vec<String>> {
    let guard = DNS_CACHE.read().unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(map) = guard.as_ref() {
        if let Some(entry) = map.get(cache_key) {
            if Instant::now() < entry.expires_at {
                return Some(entry.records.clone());
            }
        }
    }
    None
}

fn cache_store(cache_key: String, records: Vec<String>, ttl_secs: u64) {
    let clamped_ttl = ttl_secs.clamp(5, 86400);
    let mut guard = get_cache();
    if let Some(map) = guard.as_mut() {
        map.insert(
            cache_key,
            CacheEntry {
                records,
                expires_at: Instant::now() + Duration::from_secs(clamped_ttl),
            },
        );
    }
}

pub fn clear_dns_cache() {
    let mut guard = get_cache();
    if let Some(map) = guard.as_mut() {
        map.clear();
    }
}

/// Resolves a domain name via DNS-over-HTTPS (DoH).
/// `server_url` can be:
/// - "cloudflare" or "1.1.1.1" -> uses https://cloudflare-dns.com/dns-query
/// - "google" or "8.8.8.8" -> uses https://dns.google/resolve
/// - empty ("") -> defaults to Cloudflare
/// - any custom DoH endpoint URL
pub fn resolve_doh(domain: &str, record_type: &str, server_url: &str) -> Result<Vec<String>, String> {
    let trimmed_domain = domain.trim().trim_end_matches('.');
    if trimmed_domain.is_empty() {
        return Err("Domain cannot be empty".to_string());
    }

    let rec_type = if record_type.trim().is_empty() {
        "A"
    } else {
        record_type.trim()
    };

    let endpoint = match server_url.trim().to_lowercase().as_str() {
        "" | "cloudflare" | "1.1.1.1" => DEFAULT_CLOUDFLARE_DOH,
        "google" | "8.8.8.8" => DEFAULT_GOOGLE_DOH,
        custom => custom,
    };

    let cache_key = format!("{}:{}:{}", trimmed_domain.to_lowercase(), rec_type.to_uppercase(), endpoint);

    // Check cache
    if let Some(cached) = cache_lookup(&cache_key) {
        return Ok(cached);
    }

    // Perform HTTP GET request with ureq
    let response = ureq::get(endpoint)
        .query("name", trimmed_domain)
        .query("type", rec_type)
        .set("Accept", "application/dns-json")
        .timeout(Duration::from_secs(5))
        .call()
        .map_err(|e| format!("DoH HTTP request failed: {}", e))?;

    let dns_res: DnsResponse = response
        .into_json()
        .map_err(|e| format!("Failed to parse DoH response JSON: {}", e))?;

    if let Some(status) = dns_res.status {
        if status != 0 {
            return Err(format!("DNS query returned non-zero status code: {}", status));
        }
    }

    let mut results = Vec::new();
    let mut min_ttl = 300u64;

    if let Some(answers) = dns_res.answer {
        for ans in answers {
            if let Some(data) = ans.data {
                // Strip possible wrapping quotes if TXT record
                let clean_data = data.trim_matches('"').to_string();
                results.push(clean_data);
            }
            if let Some(ttl) = ans.ttl {
                if ttl > 0 && ttl < min_ttl {
                    min_ttl = ttl;
                }
            }
        }
    }

    if !results.is_empty() {
        cache_store(cache_key, results.clone(), min_ttl);
    }

    Ok(results)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache() {
        clear_dns_cache();
        let key = "example.com:A:https://cloudflare-dns.com/dns-query".to_string();
        cache_store(key.clone(), vec!["93.184.216.34".to_string()], 60);
        let cached = cache_lookup(&key);
        assert_eq!(cached, Some(vec!["93.184.216.34".to_string()]));
    }
}
