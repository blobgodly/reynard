pub mod m3u8;
pub mod subtitle;

pub use m3u8::{parse_m3u8, HlsPlaylist, HlsSegment, HlsStream};
pub use subtitle::{parse_srt, parse_vtt, SubtitleCue};

/// Parses M3U8 content and returns serialized JSON string
pub fn parse_m3u8_to_json(content: &str, base_url: &str) -> Result<String, String> {
    let playlist = parse_m3u8(content, base_url);
    serde_json::to_string(&playlist).map_err(|e| format!("Failed to serialize HLS playlist: {}", e))
}

/// Parses SRT content and returns serialized JSON string
pub fn parse_srt_to_json(content: &str) -> Result<String, String> {
    let cues = parse_srt(content);
    serde_json::to_string(&cues).map_err(|e| format!("Failed to serialize SRT cues: {}", e))
}

/// Parses WebVTT content and returns serialized JSON string
pub fn parse_vtt_to_json(content: &str) -> Result<String, String> {
    let cues = parse_vtt(content);
    serde_json::to_string(&cues).map_err(|e| format!("Failed to serialize VTT cues: {}", e))
}
