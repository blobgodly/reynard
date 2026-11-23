use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HlsStream {
    pub bandwidth: u64,
    pub resolution: Option<String>,
    pub codecs: Option<String>,
    pub frame_rate: Option<f32>,
    pub name: Option<String>,
    pub url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HlsSegment {
    pub duration: f64,
    pub title: Option<String>,
    pub url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HlsPlaylist {
    pub is_master: bool,
    pub target_duration: Option<f64>,
    pub media_sequence: Option<u64>,
    pub streams: Vec<HlsStream>,
    pub segments: Vec<HlsSegment>,
    pub is_endlist: bool,
}

pub fn parse_m3u8(content: &str, base_url: &str) -> HlsPlaylist {
    let mut is_master = false;
    let mut streams = Vec::new();
    let mut segments = Vec::new();
    let mut target_duration = None;
    let mut media_sequence = None;
    let mut is_endlist = false;

    let lines: Vec<&str> = content.lines().map(|l| l.trim()).collect();
    let mut i = 0;

    while i < lines.len() {
        let line = lines[i];

        if line.starts_with("#EXT-X-TARGETDURATION:") {
            if let Ok(d) = line["#EXT-X-TARGETDURATION:".len()..].trim().parse::<f64>() {
                target_duration = Some(d);
            }
        } else if line.starts_with("#EXT-X-MEDIA-SEQUENCE:") {
            if let Ok(seq) = line["#EXT-X-MEDIA-SEQUENCE:".len()..].trim().parse::<u64>() {
                media_sequence = Some(seq);
            }
        } else if line.starts_with("#EXT-X-ENDLIST") {
            is_endlist = true;
        } else if line.starts_with("#EXT-X-STREAM-INF:") {
            is_master = true;
            let attrs = &line["#EXT-X-STREAM-INF:".len()..];
            let mut bandwidth = 0u64;
            let mut resolution = None;
            let mut codecs = None;
            let mut frame_rate = None;
            let mut name = None;

            for attr in split_attributes(attrs) {
                let parts: Vec<&str> = attr.splitn(2, '=').collect();
                if parts.len() == 2 {
                    let key = parts[0].trim();
                    let val = parts[1].trim().trim_matches('"');
                    match key {
                        "BANDWIDTH" => {
                            if let Ok(b) = val.parse::<u64>() {
                                bandwidth = b;
                            }
                        }
                        "RESOLUTION" => resolution = Some(val.to_string()),
                        "CODECS" => codecs = Some(val.to_string()),
                        "FRAME-RATE" => frame_rate = val.parse::<f32>().ok(),
                        "NAME" => name = Some(val.to_string()),
                        _ => {}
                    }
                }
            }

            // Next non-empty, non-comment line is the URI
            let mut j = i + 1;
            while j < lines.len() && (lines[j].is_empty() || lines[j].starts_with('#')) {
                j += 1;
            }
            if j < lines.len() {
                let stream_url = resolve_relative_url(base_url, lines[j]);
                streams.push(HlsStream {
                    bandwidth,
                    resolution,
                    codecs,
                    frame_rate,
                    name,
                    url: stream_url,
                });
                i = j;
            }
        } else if line.starts_with("#EXTINF:") {
            let info = &line["#EXTINF:".len()..];
            let mut duration = 0.0;
            let mut title = None;

            let comma_pos = info.find(',');
            if let Some(pos) = comma_pos {
                if let Ok(d) = info[..pos].trim().parse::<f64>() {
                    duration = d;
                }
                let t = info[pos + 1..].trim();
                if !t.is_empty() {
                    title = Some(t.to_string());
                }
            } else if let Ok(d) = info.trim().parse::<f64>() {
                duration = d;
            }

            // Next non-empty, non-comment line is segment URI
            let mut j = i + 1;
            while j < lines.len() && (lines[j].is_empty() || lines[j].starts_with('#')) {
                j += 1;
            }
            if j < lines.len() {
                let segment_url = resolve_relative_url(base_url, lines[j]);
                segments.push(HlsSegment {
                    duration,
                    title,
                    url: segment_url,
                });
                i = j;
            }
        }

        i += 1;
    }

    // Sort streams by bandwidth descending for quality selector
    streams.sort_by(|a, b| b.bandwidth.cmp(&a.bandwidth));

    HlsPlaylist {
        is_master,
        target_duration,
        media_sequence,
        streams,
        segments,
        is_endlist,
    }
}

fn split_attributes(attrs: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;

    for c in attrs.chars() {
        if c == '"' {
            in_quotes = !in_quotes;
            current.push(c);
        } else if c == ',' && !in_quotes {
            let trimmed = current.trim();
            if !trimmed.is_empty() {
                result.push(trimmed.to_string());
            }
            current.clear();
        } else {
            current.push(c);
        }
    }

    let trimmed = current.trim();
    if !trimmed.is_empty() {
        result.push(trimmed.to_string());
    }

    result
}

fn resolve_relative_url(base: &str, relative: &str) -> String {
    let rel = relative.trim();
    if rel.starts_with("http://") || rel.starts_with("https://") {
        return rel.to_string();
    }

    if base.is_empty() {
        return rel.to_string();
    }

    let base_trimmed = base.trim();
    if rel.starts_with('/') {
        // Absolute path from origin
        if let Some(idx) = base_trimmed.find("://") {
            let after_scheme = &base_trimmed[idx + 3..];
            let host_end = after_scheme.find('/').unwrap_or(after_scheme.len());
            let origin = &base_trimmed[..idx + 3 + host_end];
            return format!("{}{}", origin, rel);
        }
    }

    // Directory-relative path
    let last_slash = base_trimmed.rfind('/').unwrap_or(0);
    if last_slash > 0 {
        let dir = &base_trimmed[..=last_slash];
        format!("{}{}", dir, rel.trim_start_matches("./"))
    } else {
        format!("{}/{}", base_trimmed, rel)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_master_m3u8() {
        let sample = "
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=720x480,CODECS=\"avc1.4d401f,mp4a.40.2\"
low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1280x720,CODECS=\"avc1.4d401f,mp4a.40.2\"
mid.m3u8
        ";
        let pl = parse_m3u8(sample, "https://cdn.example.com/hls/playlist.m3u8");
        assert!(pl.is_master);
        assert_eq!(pl.streams.len(), 2);
        assert_eq!(pl.streams[0].bandwidth, 2560000); // Sorted descending
        assert_eq!(pl.streams[0].url, "https://cdn.example.com/hls/mid.m3u8");
    }
}
