use once_cell::sync::Lazy;
use regex::Regex;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::RwLock;

#[derive(Debug, Clone)]
pub struct FilterRule {
    pub is_exception: bool,
    pub domain_anchor: Option<String>,
    pub regex: Option<Regex>,
    pub third_party: Option<bool>,
    pub resource_types: Vec<String>,
    pub excluded_types: Vec<String>,
    pub source_domains: Vec<String>,
    pub excluded_source_domains: Vec<String>,
}

impl FilterRule {
    pub fn matches(&self, url: &str, url_host: &str, source_host: &str, resource_type: &str) -> bool {
        // 1. Check third-party option
        if let Some(tp_required) = self.third_party {
            let is_tp = is_third_party(url_host, source_host);
            if tp_required != is_tp {
                return false;
            }
        }

        // 2. Check resource types
        let res_type_lower = resource_type.to_lowercase();
        if !self.excluded_types.is_empty() && self.excluded_types.contains(&res_type_lower) {
            return false;
        }
        if !self.resource_types.is_empty() && !self.resource_types.contains(&res_type_lower) {
            return false;
        }

        // 3. Check source domain restrictions
        if !source_host.is_empty() {
            let src_lower = source_host.to_lowercase();
            if !self.excluded_source_domains.is_empty() {
                for excl in &self.excluded_source_domains {
                    if domain_matches(&src_lower, excl) {
                        return false;
                    }
                }
            }
            if !self.source_domains.is_empty() {
                let mut matched = false;
                for inc in &self.source_domains {
                    if domain_matches(&src_lower, inc) {
                        matched = true;
                        break;
                    }
                }
                if !matched {
                    return false;
                }
            }
        }

        // 4. Check domain anchor or regex
        if let Some(anchor) = &self.domain_anchor {
            if !domain_matches(url_host, anchor) {
                return false;
            }
        }

        if let Some(re) = &self.regex {
            if !re.is_match(url) {
                return false;
            }
        }

        true
    }
}

pub struct AdBlockEngine {
    // Fast domain lookups: domain -> list of rules
    domain_block_rules: HashMap<String, Vec<FilterRule>>,
    domain_exception_rules: HashMap<String, Vec<FilterRule>>,
    // Generic URL/regex rules
    generic_block_rules: Vec<FilterRule>,
    generic_exception_rules: Vec<FilterRule>,
    blocked_count: AtomicU64,
}

impl AdBlockEngine {
    pub fn new() -> Self {
        Self {
            domain_block_rules: HashMap::new(),
            domain_exception_rules: HashMap::new(),
            generic_block_rules: Vec::new(),
            generic_exception_rules: Vec::new(),
            blocked_count: AtomicU64::new(0),
        }
    }

    pub fn clear(&mut self) {
        self.domain_block_rules.clear();
        self.domain_exception_rules.clear();
        self.generic_block_rules.clear();
        self.generic_exception_rules.clear();
        self.blocked_count.store(0, Ordering::Relaxed);
    }

    pub fn load_rules(&mut self, content: &str) -> usize {
        let mut count = 0;
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('!') || trimmed.starts_with('[') {
                continue;
            }
            if let Some(rule) = parse_filter_line(trimmed) {
                if let Some(anchor) = &rule.domain_anchor {
                    let key = anchor.to_lowercase();
                    if rule.is_exception {
                        self.domain_exception_rules.entry(key).or_default().push(rule);
                    } else {
                        self.domain_block_rules.entry(key).or_default().push(rule);
                    }
                } else if rule.is_exception {
                    self.generic_exception_rules.push(rule);
                } else {
                    self.generic_block_rules.push(rule);
                }
                count += 1;
            }
        }
        count
    }

    pub fn should_block(&self, url: &str, source_url: &str, resource_type: &str) -> bool {
        let url_host = extract_host(url);
        let source_host = extract_host(source_url);

        // 1. Check Exceptions First: Domain exceptions
        for parent_domain in get_domain_hierarchy(&url_host) {
            if let Some(rules) = self.domain_exception_rules.get(&parent_domain) {
                for rule in rules {
                    if rule.matches(url, &url_host, &source_host, resource_type) {
                        return false;
                    }
                }
            }
        }

        // Generic exceptions
        for rule in &self.generic_exception_rules {
            if rule.matches(url, &url_host, &source_host, resource_type) {
                return false;
            }
        }

        // 2. Check Domain Blocking Rules
        for parent_domain in get_domain_hierarchy(&url_host) {
            if let Some(rules) = self.domain_block_rules.get(&parent_domain) {
                for rule in rules {
                    if rule.matches(url, &url_host, &source_host, resource_type) {
                        self.blocked_count.fetch_add(1, Ordering::Relaxed);
                        return true;
                    }
                }
            }
        }

        // 3. Check Generic Blocking Rules
        for rule in &self.generic_block_rules {
            if rule.matches(url, &url_host, &source_host, resource_type) {
                self.blocked_count.fetch_add(1, Ordering::Relaxed);
                return true;
            }
        }

        false
    }

    pub fn get_blocked_count(&self) -> u64 {
        self.blocked_count.load(Ordering::Relaxed)
    }

    pub fn reset_blocked_count(&self) {
        self.blocked_count.store(0, Ordering::Relaxed);
    }
}

static GLOBAL_ENGINE: Lazy<RwLock<AdBlockEngine>> = Lazy::new(|| RwLock::new(AdBlockEngine::new()));

pub fn load_filter_rules(content: &str) -> usize {
    let mut engine = GLOBAL_ENGINE.write().unwrap_or_else(|p| p.into_inner());
    engine.load_rules(content)
}

pub fn clear_filter_rules() {
    let mut engine = GLOBAL_ENGINE.write().unwrap_or_else(|p| p.into_inner());
    engine.clear();
}

pub fn should_block(url: &str, source_url: &str, resource_type: &str) -> bool {
    let engine = GLOBAL_ENGINE.read().unwrap_or_else(|p| p.into_inner());
    engine.should_block(url, source_url, resource_type)
}

pub fn get_blocked_count() -> u64 {
    let engine = GLOBAL_ENGINE.read().unwrap_or_else(|p| p.into_inner());
    engine.get_blocked_count()
}

pub fn reset_blocked_count() {
    let engine = GLOBAL_ENGINE.read().unwrap_or_else(|p| p.into_inner());
    engine.reset_blocked_count();
}

/// Helper function to parse an adblock rule line into a FilterRule
fn parse_filter_line(line: &str) -> Option<FilterRule> {
    let (mut pattern_part, options_part) = match line.find('$') {
        Some(idx) => (&line[..idx], Some(&line[idx + 1..])),
        None => (line, None),
    };

    let mut is_exception = false;
    if pattern_part.starts_with("@@") {
        is_exception = true;
        pattern_part = &pattern_part[2..];
    }

    let mut third_party = None;
    let mut resource_types = Vec::new();
    let mut excluded_types = Vec::new();
    let mut source_domains = Vec::new();
    let mut excluded_source_domains = Vec::new();

    if let Some(opts) = options_part {
        for opt in opts.split(',') {
            let opt = opt.trim();
            if opt.eq_ignore_ascii_case("third-party") || opt.eq_ignore_ascii_case("3p") {
                third_party = Some(true);
            } else if opt.eq_ignore_ascii_case("~third-party") || opt.eq_ignore_ascii_case("~3p") {
                third_party = Some(false);
            } else if let Some(stripped) = opt.strip_prefix("domain=") {
                for dom in stripped.split('|') {
                    if let Some(excl) = dom.strip_prefix('~') {
                        excluded_source_domains.push(excl.to_lowercase());
                    } else if !dom.is_empty() {
                        source_domains.push(dom.to_lowercase());
                    }
                }
            } else if let Some(stripped) = opt.strip_prefix('~') {
                excluded_types.push(stripped.to_lowercase());
            } else if !opt.is_empty() {
                resource_types.push(opt.to_lowercase());
            }
        }
    }

    let mut domain_anchor = None;
    let mut regex_pattern = None;

    if pattern_part.starts_with("||") {
        let after_pipe = &pattern_part[2..];
        let end_idx = after_pipe.find(|c: char| c == '^' || c == '/' || c == '*' || c == '$')
            .unwrap_or(after_pipe.len());
        let domain = &after_pipe[..end_idx];
        domain_anchor = Some(domain.to_lowercase());

        let remainder = &after_pipe[end_idx..];
        if remainder.starts_with('^') && remainder.len() == 1 {
            // Pure domain anchor ||example.com^
            regex_pattern = None;
        } else if !remainder.is_empty() {
            // Remainder exists, convert to regex
            let re_str = wildcard_to_regex(remainder);
            regex_pattern = Regex::new(&re_str).ok();
        }
    } else if pattern_part.starts_with('/') && pattern_part.ends_with('/') && pattern_part.len() > 2 {
        // Direct regex
        let re_str = &pattern_part[1..pattern_part.len() - 1];
        regex_pattern = Regex::new(re_str).ok();
    } else if !pattern_part.is_empty() {
        let re_str = wildcard_to_regex(pattern_part);
        regex_pattern = Regex::new(&re_str).ok();
    }

    Some(FilterRule {
        is_exception,
        domain_anchor,
        regex: regex_pattern,
        third_party,
        resource_types,
        excluded_types,
        source_domains,
        excluded_source_domains,
    })
}

fn wildcard_to_regex(pattern: &str) -> String {
    let mut regex = String::with_capacity(pattern.len() * 2);
    let mut chars = pattern.chars().peekable();

    if pattern.starts_with('|') && !pattern.starts_with("||") {
        regex.push('^');
        chars.next();
    }

    while let Some(c) = chars.next() {
        match c {
            '*' => regex.push_str(".*"),
            '^' => regex.push_str("(?:[^a-zA-Z0-9_\\-.%]|$)"),
            '|' if chars.peek().is_none() => regex.push('$'),
            '.' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '\\' | '$' => {
                regex.push('\\');
                regex.push(c);
            }
            other => regex.push(other),
        }
    }

    regex
}

pub fn extract_host(url: &str) -> String {
    let s = url.trim();
    let without_scheme = if let Some(idx) = s.find("://") {
        &s[idx + 3..]
    } else {
        s
    };

    let host_end = without_scheme.find(|c: char| c == '/' || c == ':' || c == '?' || c == '#')
        .unwrap_or(without_scheme.len());

    without_scheme[..host_end].trim().to_lowercase()
}

fn domain_matches(host: &str, target_domain: &str) -> bool {
    let host = host.trim().to_lowercase();
    let target = target_domain.trim().to_lowercase();
    if host == target {
        return true;
    }
    if host.ends_with(&format!(".{}", target)) {
        return true;
    }
    false
}

fn is_third_party(url_host: &str, source_host: &str) -> bool {
    if source_host.is_empty() || url_host.is_empty() {
        return false;
    }
    let u_parts: Vec<&str> = url_host.split('.').collect();
    let s_parts: Vec<&str> = source_host.split('.').collect();

    let u_root = if u_parts.len() >= 2 {
        format!("{}.{}", u_parts[u_parts.len() - 2], u_parts[u_parts.len() - 1])
    } else {
        url_host.to_string()
    };

    let s_root = if s_parts.len() >= 2 {
        format!("{}.{}", s_parts[s_parts.len() - 2], s_parts[s_parts.len() - 1])
    } else {
        source_host.to_string()
    };

    u_root != s_root
}

fn get_domain_hierarchy(host: &str) -> Vec<String> {
    let mut result = Vec::new();
    let parts: Vec<&str> = host.split('.').collect();
    for i in 0..parts.len() {
        result.push(parts[i..].join("."));
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_adblock_basic() {
        let mut engine = AdBlockEngine::new();
        let rules = "
            ! Comment line
            ||doubleclick.net^
            ||badads.com^$image,third-party
            @@||doubleclick.net/good_ad.js
            /banner/*$script
        ";
        engine.load_rules(rules);

        assert!(engine.should_block("https://ad.doubleclick.net/ads.js", "https://example.com", "script"));
        assert!(!engine.should_block("https://doubleclick.net/good_ad.js", "https://example.com", "script"));
        assert!(engine.should_block("https://badads.com/img.png", "https://example.com", "image"));
        // First party should not block
        assert!(!engine.should_block("https://badads.com/img.png", "https://badads.com", "image"));
        assert_eq!(engine.get_blocked_count(), 2);
    }
}
