//
//  GeckoOptimizations.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import Foundation

// MARK: - Gecko Optimizations

/// Configures Gecko engine preferences for optimal performance on iPhone 7
/// (A10 Fusion, 2 GB RAM, iOS 15.x) and enables anti-restriction features
/// (DNS-over-HTTPS, Encrypted Client Hello, TLS 1.3).
final class GeckoOptimizations {

    // MARK: - Apply All Optimizations

    /// Call this once during app startup, after GeckoRuntime.main().
    static func applyAll() {
        applyPerformancePrefs()
        applyNetworkPrefs()
        applyAntiRestrictionPrefs()
        applyRenderingPrefs()
    }

    // MARK: - Performance (iPhone 7 / A10 / 2 GB RAM)

    private static func applyPerformancePrefs() {
        GeckoRuntime.setDefaultPrefs([
            // JavaScript memory limits
            "javascript.options.mem.max": 128 * 1024,              // 128 MB JS heap limit
            "javascript.options.mem.gc_incremental_slice_ms": 5,    // Shorter GC slices
            "javascript.options.mem.gc_compacting": true,

            // Limit content processes for memory savings
            "dom.ipc.processCount": 2,
            "dom.ipc.processCount.webIsolated": 1,

            // Image memory
            "image.mem.surfacecache.max_size_kb": 65536,           // 64 MB image surface cache
            "image.mem.surfacecache.min_expiration_ms": 30000,

            // Browser cache
            "browser.cache.memory.capacity": 32768,                // 32 MB memory cache
            "browser.cache.disk.capacity": 262144,                 // 256 MB disk cache
            "browser.cache.disk.smart_size.enabled": true,

            // Session history
            "browser.sessionhistory.max_total_viewers": 2,          // Limit back/forward cache
        ])
    }

    // MARK: - Network Performance

    private static func applyNetworkPrefs() {
        GeckoRuntime.setDefaultPrefs([
            // Connections
            "network.http.max-connections": 48,
            "network.http.max-persistent-connections-per-server": 8,
            "network.http.max-urgent-start-excessive-connections-per-host": 3,

            // Pipelining / prefetch
            "network.dns.disablePrefetch": false,
            "network.prefetch-next": true,
            "network.predictor.enabled": true,

            // Faster initial paint
            "nglayout.initialpaint.delay": 0,
            "content.notify.interval": 100000,

            // HTTP/3 and QUIC
            "network.http.http3.enabled": true,
        ])
    }

    // MARK: - Anti-Restriction Features

    private static func applyAntiRestrictionPrefs() {
        GeckoRuntime.setDefaultPrefs([
            // DNS-over-HTTPS (bypass ISP DNS blocks)
            "network.trr.mode": 3,                                  // DoH only
            "network.trr.uri": "https://cloudflare-dns.com/dns-query",
            "network.trr.bootstrapAddr": "1.1.1.1",

            // Encrypted Client Hello (hide requested hostname from ISP)
            "network.dns.echconfig.enabled": true,
            "network.dns.use_https_rr_as_altsvc": true,

            // TLS configuration
            "security.tls.version.min": 1,                          // TLS 1.0 for compat
            "security.tls.version.max": 4,                          // TLS 1.3
            "security.tls.enable_0rtt_data": true,

            // Privacy (without breaking sites)
            "network.http.referer.defaultPolicy": 2,                // Strict-origin-when-cross-origin
            "privacy.donottrackheader.enabled": true,

            // WebRTC leak prevention
            "media.peerconnection.ice.default_address_only": true,
        ])
    }

    // MARK: - Rendering Performance

    private static func applyRenderingPrefs() {
        GeckoRuntime.setDefaultPrefs([
            // WebRender
            "gfx.webrender.compositor": true,

            // Save memory — disable GPU process on constrained devices
            "layers.gpu-process.enabled": false,

            // Reduce animation jank
            "ui.submenuDelay": 0,

            // Font cache
            "gfx.font_rendering.opentype_svg.enabled": true,
        ])
    }

    // MARK: - Low Memory Mode

    /// Applies aggressive memory reduction for critically low memory situations.
    static func enableLowMemoryMode() {
        GeckoRuntime.setDefaultPrefs([
            "javascript.options.mem.max": 64 * 1024,
            "dom.ipc.processCount": 1,
            "image.mem.surfacecache.max_size_kb": 32768,
            "browser.cache.memory.capacity": 16384,
            "browser.sessionhistory.max_total_viewers": 0,
        ])
    }

    /// Restores normal memory settings.
    static func disableLowMemoryMode() {
        applyPerformancePrefs()
    }
}
