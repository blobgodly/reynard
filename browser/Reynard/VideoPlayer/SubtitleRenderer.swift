//
//  SubtitleRenderer.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import UIKit

// MARK: - Subtitle Cue

/// A single timed subtitle cue with start time, end time, and text.
struct SubtitleCue {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

// MARK: - Subtitle Size

enum SubtitleSize: Int, CaseIterable {
    case small = 0
    case medium = 1
    case large = 2

    var font: UIFont {
        switch self {
        case .small:  return VideoPlayerTheme.Fonts.subtitleSmall
        case .medium: return VideoPlayerTheme.Fonts.subtitle
        case .large:  return VideoPlayerTheme.Fonts.subtitleLarge
        }
    }

    var displayName: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }
}

// MARK: - Subtitle Parser

/// Parses WebVTT and SRT subtitle files into an array of `SubtitleCue`.
final class SubtitleParser {

    // MARK: - WebVTT

    /// Parses a WebVTT string into subtitle cues.
    static func parseWebVTT(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let arrowIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }

            let timeLine = lines[arrowIndex]
            guard let (start, end) = parseTimeLine(timeLine) else { continue }

            let textLines = lines[(arrowIndex + 1)...]
            let cueText = textLines.joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) // Strip VTT tags
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cueText.isEmpty else { continue }
            cues.append(SubtitleCue(startTime: start, endTime: end, text: cueText))
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - SRT

    /// Parses an SRT string into subtitle cues.
    static func parseSRT(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard lines.count >= 3 else { continue }

            // The second line should contain the timecode
            guard let arrowIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }

            let timeLine = lines[arrowIndex].replacingOccurrences(of: ",", with: ".")
            guard let (start, end) = parseTimeLine(timeLine) else { continue }

            let textLines = lines[(arrowIndex + 1)...]
            let cueText = textLines.joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cueText.isEmpty else { continue }
            cues.append(SubtitleCue(startTime: start, endTime: end, text: cueText))
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Auto-detect Format

    /// Attempts to detect format and parse accordingly.
    static func parse(_ text: String) -> [SubtitleCue] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("WEBVTT") {
            return parseWebVTT(text)
        } else {
            return parseSRT(text)
        }
    }

    // MARK: - Time Parsing

    /// Parses a "HH:MM:SS.mmm --> HH:MM:SS.mmm" or "MM:SS.mmm --> MM:SS.mmm" line.
    private static func parseTimeLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        let endStr = parts[1].trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? parts[1].trimmingCharacters(in: .whitespaces) // Strip position info

        guard let start = parseTimestamp(startStr),
              let end = parseTimestamp(endStr) else { return nil }

        return (start, end)
    }

    /// Converts "HH:MM:SS.mmm" or "MM:SS.mmm" to seconds.
    private static func parseTimestamp(_ string: String) -> TimeInterval? {
        let clean = string.trimmingCharacters(in: .whitespaces)
        let components = clean.components(separatedBy: ":")
        guard components.count >= 2 else { return nil }

        if components.count == 3 {
            // HH:MM:SS.mmm
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        } else {
            // MM:SS.mmm
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else { return nil }
            return minutes * 60 + seconds
        }
    }
}

// MARK: - Subtitle Renderer

/// Renders subtitle cues as an overlay label on top of the video player.
final class SubtitleRenderer {

    // MARK: - Properties

    private let containerView: UIView
    private let label: UILabel
    private let backgroundView: UIView
    private var cues: [SubtitleCue] = []
    private var currentCueIndex: Int = -1
    var isEnabled: Bool = true { didSet { updateVisibility() } }
    var subtitleSize: SubtitleSize = .medium { didSet { label.font = subtitleSize.font } }
    var backgroundOpacity: CGFloat = 0.70 {
        didSet { backgroundView.backgroundColor = UIColor.black.withAlphaComponent(backgroundOpacity) }
    }

    // MARK: - Init

    init(containerView: UIView) {
        self.containerView = containerView

        backgroundView = UIView()
        backgroundView.backgroundColor = VideoPlayerTheme.Colors.subtitleBackground
        backgroundView.layer.cornerRadius = VideoPlayerTheme.Layout.smallCornerRadius
        backgroundView.clipsToBounds = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isHidden = true

        label = UILabel()
        label.font = subtitleSize.font
        label.textColor = VideoPlayerTheme.Colors.subtitleText
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        backgroundView.addSubview(label)
        containerView.addSubview(backgroundView)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),

            backgroundView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            backgroundView.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 24),
            backgroundView.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -24),
        ])
    }

    // MARK: - Load Cues

    /// Replaces current cues with new ones from parsed subtitle data.
    func loadCues(_ newCues: [SubtitleCue]) {
        cues = newCues
        currentCueIndex = -1
        backgroundView.isHidden = true
    }

    /// Loads subtitles from a string (auto-detects format).
    func loadSubtitles(from text: String) {
        let parsed = SubtitleParser.parse(text)
        loadCues(parsed)
    }

    // MARK: - Update

    /// Call periodically with the current playback time to display the correct cue.
    func update(currentTime: TimeInterval) {
        guard isEnabled, !cues.isEmpty else {
            backgroundView.isHidden = true
            return
        }

        // Binary-search–style find: check if we are still in current cue
        if currentCueIndex >= 0 && currentCueIndex < cues.count {
            let cue = cues[currentCueIndex]
            if currentTime >= cue.startTime && currentTime <= cue.endTime {
                return // Still displaying current cue
            }
        }

        // Find next matching cue
        if let index = cues.firstIndex(where: { currentTime >= $0.startTime && currentTime <= $0.endTime }) {
            currentCueIndex = index
            label.text = cues[index].text
            backgroundView.isHidden = false
        } else {
            currentCueIndex = -1
            backgroundView.isHidden = true
        }
    }

    // MARK: - Visibility

    private func updateVisibility() {
        if !isEnabled {
            backgroundView.isHidden = true
        }
    }

    /// Bring subtitle view to front (call after layout changes).
    func bringToFront() {
        containerView.bringSubviewToFront(backgroundView)
    }
}
