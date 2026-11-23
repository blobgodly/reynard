use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SubtitleCue {
    pub index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

pub fn parse_srt(content: &str) -> Vec<SubtitleCue> {
    let mut cues = Vec::new();
    let normalized = content.replace("\r\n", "\n").replace('\r', "\n");
    let blocks = normalized.split("\n\n");

    let mut auto_index = 1u32;

    for block in blocks {
        let lines: Vec<&str> = block.lines().map(|l| l.trim()).filter(|l| !l.is_empty()).collect();
        if lines.is_empty() {
            continue;
        }

        let mut line_idx = 0;
        let mut cue_index = auto_index;

        // Optional numeric index line
        if let Ok(idx) = lines[line_idx].parse::<u32>() {
            cue_index = idx;
            line_idx += 1;
        }

        if line_idx >= lines.len() {
            continue;
        }

        let time_line = lines[line_idx];
        if !time_line.contains("-->") {
            continue;
        }

        if let Some((start, end)) = parse_time_range(time_line) {
            line_idx += 1;
            let text_lines: Vec<&str> = lines[line_idx..].iter().copied().collect();
            let raw_text = text_lines.join("\n");
            let clean_text = clean_subtitle_tags(&raw_text);

            cues.push(SubtitleCue {
                index: cue_index,
                start_ms: start,
                end_ms: end,
                text: clean_text,
            });
            auto_index = cue_index + 1;
        }
    }

    cues
}

pub fn parse_vtt(content: &str) -> Vec<SubtitleCue> {
    let mut cues = Vec::new();
    let normalized = content.replace("\r\n", "\n").replace('\r', "\n");
    let lines: Vec<&str> = normalized.lines().map(|l| l.trim()).collect();

    let mut i = 0;
    // Skip WEBVTT header and notes
    while i < lines.len() {
        if lines[i].starts_with("WEBVTT") || lines[i].starts_with("NOTE") {
            while i < lines.len() && !lines[i].is_empty() {
                i += 1;
            }
        } else if lines[i].is_empty() {
            i += 1;
        } else {
            break;
        }
    }

    let mut auto_index = 1u32;

    while i < lines.len() {
        if lines[i].is_empty() {
            i += 1;
            continue;
        }

        // Could be cue identifier or timestamp line
        let mut cue_index = auto_index;
        let time_line;

        if lines[i].contains("-->") {
            time_line = lines[i];
            i += 1;
        } else {
            if let Ok(idx) = lines[i].parse::<u32>() {
                cue_index = idx;
            }
            i += 1;
            while i < lines.len() && lines[i].is_empty() {
                i += 1;
            }
            if i >= lines.len() {
                break;
            }
            time_line = lines[i];
            i += 1;
        }

        if let Some((start, end)) = parse_time_range(time_line) {
            let mut text_lines = Vec::new();
            while i < lines.len() && !lines[i].is_empty() {
                text_lines.push(lines[i]);
                i += 1;
            }
            let raw_text = text_lines.join("\n");
            let clean_text = clean_subtitle_tags(&raw_text);

            cues.push(SubtitleCue {
                index: cue_index,
                start_ms: start,
                end_ms: end,
                text: clean_text,
            });
            auto_index = cue_index + 1;
        }
    }

    cues
}

fn parse_time_range(line: &str) -> Option<(u64, u64)> {
    let parts: Vec<&str> = line.split("-->").collect();
    if parts.len() != 2 {
        return None;
    }

    let start_str = parts[0].trim();
    // End string may have cue settings like "00:00:05.000 position:50%"
    let end_str = parts[1].trim().split_whitespace().next().unwrap_or("");

    let start_ms = parse_timestamp(start_str)?;
    let end_ms = parse_timestamp(end_str)?;

    Some((start_ms, end_ms))
}

fn parse_timestamp(ts: &str) -> Option<u64> {
    // Format: [HH:]MM:SS[,.]mmm
    let sanitized = ts.replace(',', ".");
    let dot_parts: Vec<&str> = sanitized.split('.').collect();

    let (time_part, ms) = match dot_parts.len() {
        1 => (dot_parts[0], 0u64),
        2 => {
            let ms_str = dot_parts[1];
            // Normalize ms to 3 digits (e.g. 5 -> 500, 50 -> 500, 500 -> 500)
            let padded_ms = match ms_str.len() {
                1 => format!("{}00", ms_str),
                2 => format!("{}0", ms_str),
                _ => ms_str[..3.min(ms_str.len())].to_string(),
            };
            (dot_parts[0], padded_ms.parse::<u64>().ok()?)
        }
        _ => return None,
    };

    let colons: Vec<&str> = time_part.split(':').collect();
    let (hours, mins, secs) = match colons.len() {
        2 => (0u64, colons[0].parse::<u64>().ok()?, colons[1].parse::<u64>().ok()?),
        3 => (
            colons[0].parse::<u64>().ok()?,
            colons[1].parse::<u64>().ok()?,
            colons[2].parse::<u64>().ok()?,
        ),
        _ => return None,
    };

    Some(hours * 3600_000 + mins * 60_000 + secs * 1000 + ms)
}

fn clean_subtitle_tags(input: &str) -> String {
    let mut output = String::with_capacity(input.len());
    let mut in_tag = false;

    for c in input.chars() {
        if c == '<' {
            in_tag = true;
        } else if c == '>' {
            in_tag = false;
        } else if !in_tag {
            output.push(c);
        }
    }

    output.trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_srt() {
        let srt = "1\n00:01:20,000 --> 00:01:23,500\n<b>Hello world!</b>\n\n2\n00:01:24,000 --> 00:01:26,000\nSecond line";
        let cues = parse_srt(srt);
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[0].start_ms, 80_000);
        assert_eq!(cues[0].end_ms, 83_500);
        assert_eq!(cues[0].text, "Hello world!");
        assert_eq!(cues[1].text, "Second line");
    }

    #[test]
    fn test_parse_vtt() {
        let vtt = "WEBVTT\n\n00:00.500 --> 00:02.000 align:start\n<v Speaker>Intro</v>";
        let cues = parse_vtt(vtt);
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].start_ms, 500);
        assert_eq!(cues[0].end_ms, 2000);
        assert_eq!(cues[0].text, "Intro");
    }
}
