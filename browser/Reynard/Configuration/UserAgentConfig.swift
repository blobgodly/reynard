//
//  UserAgentConfig.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import UIKit

// MARK: - User Agent Preset

/// Predefined user-agent strings for bypassing browser detection blocks.
enum UserAgentPreset: Int, CaseIterable {
    case defaultGecko = 0
    case safariIOS
    case chromeIOS
    case desktopChrome
    case desktopFirefox

    var displayName: String {
        switch self {
        case .defaultGecko:   return "Default (Gecko)"
        case .safariIOS:      return "Safari (iOS)"
        case .chromeIOS:      return "Chrome (iOS)"
        case .desktopChrome:  return "Desktop Chrome"
        case .desktopFirefox: return "Desktop Firefox"
        }
    }

    var userAgentString: String? {
        let iOSVersion = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        switch self {
        case .defaultGecko:
            return nil  // Use Gecko's built-in UA
        case .safariIOS:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS \(iOSVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
        case .chromeIOS:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS \(iOSVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.6778.73 Mobile/15E148 Safari/604.1"
        case .desktopChrome:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        case .desktopFirefox:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:133.0) Gecko/20100101 Firefox/133.0"
        }
    }
}

// MARK: - User Agent Config

/// Manages user-agent spoofing via Gecko preferences.
final class UserAgentConfig {

    private static let storageKey = "reynard.useragent.preset"

    /// The currently selected user-agent preset.
    static var currentPreset: UserAgentPreset {
        get {
            UserAgentPreset(rawValue: UserDefaults.standard.integer(forKey: storageKey)) ?? .defaultGecko
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            applyUserAgent(newValue)
        }
    }

    /// Applies the given user-agent preset to the Gecko runtime.
    static func applyUserAgent(_ preset: UserAgentPreset) {
        if let ua = preset.userAgentString {
            GeckoRuntime.setDefaultPrefs([
                "general.useragent.override": ua
            ])
        } else {
            // Clear override → use default Gecko UA
            GeckoRuntime.setDefaultPrefs([
                "general.useragent.override": ""
            ])
        }
    }

    /// Call at startup to apply the saved user-agent preference.
    static func restoreSavedPreset() {
        applyUserAgent(currentPreset)
    }
}
