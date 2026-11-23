//
//  ReynardRustBridge.swift
//  Reynard
//
//  Created for Reynard Browser iOS (iOS 13.0+)
//  High-performance Swift bridge to the Reynard Rust Acceleration Engine
//

import Foundation

// MARK: - Enums & Model Types

public enum ReynardDownloadStatus: Int32 {
    case queued = 0
    case downloading = 1
    case paused = 2
    case completed = 3
    case failed = 4
    case cancelled = 5
    case unknown = -1
}

public struct HlsStreamInfo: Codable {
    public let bandwidth: UInt64
    public let resolution: String?
    public let codecs: String?
    public let frameRate: Float?
    public let name: String?
    public let url: String

    enum CodingKeys: String, CodingKey {
        case bandwidth
        case resolution
        case codecs
        case frameRate = "frame_rate"
        case name
        case url
    }
}

public struct HlsSegmentInfo: Codable {
    public let duration: Double
    public let title: String?
    public let url: String
}

public struct HlsPlaylistInfo: Codable {
    public let isMaster: Bool
    public let targetDuration: Double?
    public let mediaSequence: UInt64?
    public let streams: [HlsStreamInfo]
    public let segments: [HlsSegmentInfo]
    public let isEndlist: Bool

    enum CodingKeys: String, CodingKey {
        case isMaster = "is_master"
        case targetDuration = "target_duration"
        case mediaSequence = "media_sequence"
        case streams
        case segments
        case isEndlist = "is_endlist"
    }
}

public struct SubtitleCueInfo: Codable {
    public let index: UInt32
    public let startMs: UInt64
    public let endMs: UInt64
    public let text: String

    public var startTimeSeconds: Double {
        return Double(startMs) / 1000.0
    }

    public var endTimeSeconds: Double {
        return Double(endMs) / 1000.0
    }

    enum CodingKeys: String, CodingKey {
        case index
        case startMs = "start_ms"
        case endMs = "end_ms"
        case text
    }
}

// MARK: - Download Callback Handler Type

public typealias DownloadProgressHandler = (_ downloadedBytes: UInt64, _ totalBytes: UInt64, _ status: ReynardDownloadStatus) -> Void

// MARK: - ReynardRust Unified Swift Facade

public final class ReynardRust {
    // Download callback tracking
    private static var downloadCallbacks: [UInt64: DownloadProgressHandler] = [:]
    private static let callbackLock = NSLock()
    private static var nextCallbackId: UInt64 = 1

    private init() {}

    // MARK: - DNS-over-HTTPS (DoH)

    /// Resolves a domain via DoH.
    /// - Parameters:
    ///   - domain: The hostname to resolve (e.g., "apple.com")
    ///   - recordType: DNS record type, default "A" (e.g. "A", "AAAA")
    ///   - serverUrl: Optional custom DoH endpoint ("cloudflare", "google", or custom URL)
    /// - Returns: List of resolved IP addresses or records
    public static func resolveDns(domain: String, recordType: String = "A", serverUrl: String? = nil) -> [String] {
        guard let domainCStr = domain.cString(using: .utf8) else { return [] }
        let recordCStr = recordType.cString(using: .utf8)
        let serverCStr = serverUrl?.cString(using: .utf8)

        let ptr = reynard_dns_resolve(
            domainCStr,
            recordCStr,
            serverCStr
        )
        guard let ptr = ptr else { return [] }
        defer { reynard_free_string(ptr) }

        guard let jsonString = String(cString: ptr).data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: jsonString)) ?? []
    }

    /// Clears cached DNS results in Rust memory
    public static func clearDnsCache() {
        reynard_dns_clear_cache()
    }

    // MARK: - AdBlock & Content Blocking

    /// Loads EasyList format rules into the blocking engine
    /// - Parameter rulesText: EasyList format content string
    /// - Returns: Count of valid rules loaded
    @discardableResult
    public static func loadAdblockRules(_ rulesText: String) -> Int {
        guard let cStr = rulesText.cString(using: .utf8) else { return 0 }
        return Int(reynard_adblock_load_rules(cStr))
    }

    /// Clears all loaded adblock rules
    public static func clearAdblockRules() {
        reynard_adblock_clear_rules()
    }

    /// Tests whether a URL request should be blocked
    /// - Parameters:
    ///   - url: Target request URL
    ///   - sourceUrl: Origin document URL
    ///   - resourceType: Resource type string (e.g., "script", "image", "stylesheet")
    /// - Returns: True if blocked, false if allowed
    public static func shouldBlock(url: String, sourceUrl: String = "", resourceType: String = "other") -> Bool {
        guard let urlCStr = url.cString(using: .utf8) else { return false }
        let srcCStr = sourceUrl.cString(using: .utf8)
        let typeCStr = resourceType.cString(using: .utf8)

        return reynard_adblock_should_block(urlCStr, srcCStr, typeCStr)
    }

    /// Returns the total number of blocked requests
    public static var blockedRequestCount: UInt64 {
        return reynard_adblock_get_blocked_count()
    }

    /// Resets the blocked request counter
    public static func resetBlockedCount() {
        reynard_adblock_reset_blocked_count()
    }

    // MARK: - Chunked Download Manager

    /// Starts a resumable chunked background download
    /// - Parameters:
    ///   - url: Remote URL to download
    ///   - outputPath: Destination local file path
    ///   - progress: Callback closure called on download progress or status changes
    /// - Returns: Unique download ID (> 0) on success, or 0 on failure
    public static func startDownload(
        url: String,
        outputPath: String,
        progress: DownloadProgressHandler? = nil
    ) -> UInt64 {
        guard let urlCStr = url.cString(using: .utf8),
              let pathCStr = outputPath.cString(using: .utf8) else {
            return 0
        }

        var assignedCallbackId: UInt64 = 0

        if let handler = progress {
            callbackLock.lock()
            assignedCallbackId = nextCallbackId
            nextCallbackId += 1
            downloadCallbacks[assignedCallbackId] = handler
            callbackLock.unlock()
        }

        let downloadId = reynard_download_start(
            urlCStr,
            pathCStr,
            assignedCallbackId,
            nativeDownloadCallback
        )

        if downloadId == 0 && assignedCallbackId > 0 {
            callbackLock.lock()
            downloadCallbacks.removeValue(forKey: assignedCallbackId)
            callbackLock.unlock()
        }

        return downloadId
    }

    /// Pauses an active download
    public static func pauseDownload(id: UInt64) -> Bool {
        return reynard_download_pause(id)
    }

    /// Resumes a paused download
    public static func resumeDownload(id: UInt64) -> Bool {
        return reynard_download_resume(id)
    }

    /// Cancels a download
    public static func cancelDownload(id: UInt64) -> Bool {
        return reynard_download_cancel(id)
    }

    /// Gets download status
    public static func getDownloadStatus(id: UInt64) -> ReynardDownloadStatus {
        let code = reynard_download_get_status(id)
        return ReynardDownloadStatus(rawValue: code) ?? .unknown
    }

    // MARK: - Media & Subtitles Parser

    /// Parses M3U8 HLS playlist into structured streams and segments
    /// - Parameters:
    ///   - content: Raw M3U8 string
    ///   - baseUrl: Base URL for resolving relative links
    /// - Returns: Parsed HlsPlaylistInfo or nil on failure
    public static func parseM3U8(content: String, baseUrl: String = "") -> HlsPlaylistInfo? {
        guard let contentCStr = content.cString(using: .utf8) else { return nil }
        let baseCStr = baseUrl.cString(using: .utf8)

        let ptr = reynard_media_parse_m3u8(contentCStr, baseCStr)
        guard let ptr = ptr else { return nil }
        defer { reynard_free_string(ptr) }

        guard let data = String(cString: ptr).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HlsPlaylistInfo.self, from: data)
    }

    /// Parses SRT subtitles into cues
    public static func parseSRT(content: String) -> [SubtitleCueInfo] {
        guard let contentCStr = content.cString(using: .utf8) else { return [] }

        let ptr = reynard_media_parse_srt(contentCStr)
        guard let ptr = ptr else { return [] }
        defer { reynard_free_string(ptr) }

        guard let data = String(cString: ptr).data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SubtitleCueInfo].self, from: data)) ?? []
    }

    /// Parses WebVTT subtitles into cues
    public static func parseWebVTT(content: String) -> [SubtitleCueInfo] {
        guard let contentCStr = content.cString(using: .utf8) else { return [] }

        let ptr = reynard_media_parse_vtt(contentCStr)
        guard let ptr = ptr else { return [] }
        defer { reynard_free_string(ptr) }

        guard let data = String(cString: ptr).data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SubtitleCueInfo].self, from: data)) ?? []
    }

    // MARK: - Fast LRU & Disk Cache

    /// Initializes cache with byte size and optional storage folder
    /// - Parameters:
    ///   - maxBytes: Max size in RAM (default 50 MB)
    ///   - storageDir: Directory path for memory-mapped file persistence
    public static func configureCache(maxBytes: Int = 50 * 1024 * 1024, storageDir: String? = nil) {
        let dirCStr = storageDir?.cString(using: .utf8)
        reynard_cache_init(maxBytes, dirCStr)
    }

    /// Stores binary data in cache
    @discardableResult
    public static func cachePut(key: String, data: Data) -> Bool {
        guard let keyCStr = key.cString(using: .utf8) else { return false }
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }
            return reynard_cache_put(keyCStr, baseAddress, data.count)
        }
    }

    /// Retrieves binary data from cache
    public static func cacheGet(key: String) -> Data? {
        guard let keyCStr = key.cString(using: .utf8) else { return nil }

        var outLen: Int = 0
        let ptr = reynard_cache_get(keyCStr, &outLen)
        guard let ptr = ptr, outLen > 0 else { return nil }
        defer { reynard_free_bytes(ptr, outLen) }

        return Data(bytes: ptr, count: outLen)
    }

    /// Clears all cached items
    public static func clearCache() {
        reynard_cache_clear()
    }
}

// MARK: - C Callback Trampoline

private func nativeDownloadCallback(callbackId: UInt64, downloadedBytes: UInt64, totalBytes: UInt64, status: Int32) {
    let handler: DownloadProgressHandler? = {
        ReynardRust.callbackLock.lock()
        defer { ReynardRust.callbackLock.unlock() }
        let h = ReynardRust.downloadCallbacks[callbackId]
        if status == REYNARD_DOWNLOAD_STATUS_COMPLETED ||
           status == REYNARD_DOWNLOAD_STATUS_FAILED ||
           status == REYNARD_DOWNLOAD_STATUS_CANCELLED {
            ReynardRust.downloadCallbacks.removeValue(forKey: callbackId)
        }
        return h
    }()

    if let handler = handler {
        let downloadStatus = ReynardDownloadStatus(rawValue: status) ?? .unknown
        DispatchQueue.main.async {
            handler(downloadedBytes, totalBytes, downloadStatus)
        }
    }
}
