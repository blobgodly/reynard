//
//  ProxyConfig.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import Foundation

// MARK: - Proxy Type

enum ProxyType: Int, CaseIterable {
    case none = 0
    case httpProxy = 1
    case socks5 = 2

    var displayName: String {
        switch self {
        case .none:      return "No Proxy"
        case .httpProxy: return "HTTP Proxy"
        case .socks5:    return "SOCKS5 Proxy"
        }
    }

    /// Maps to Gecko's `network.proxy.type` values:
    /// 0 = direct, 1 = manual proxy
    var geckoProxyType: Int {
        switch self {
        case .none:      return 0
        case .httpProxy: return 1
        case .socks5:    return 1
        }
    }
}

// MARK: - Proxy Configuration

/// Manages SOCKS5 and HTTP proxy settings via Gecko preferences.
final class ProxyConfig {

    // MARK: - Storage Keys

    private static let typeKey = "reynard.proxy.type"
    private static let hostKey = "reynard.proxy.host"
    private static let portKey = "reynard.proxy.port"
    private static let usernameKey = "reynard.proxy.username"
    private static let passwordKey = "reynard.proxy.password"

    // MARK: - Properties

    static var proxyType: ProxyType {
        get { ProxyType(rawValue: UserDefaults.standard.integer(forKey: typeKey)) ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: typeKey) }
    }

    static var host: String {
        get { UserDefaults.standard.string(forKey: hostKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: hostKey) }
    }

    static var port: Int {
        get { UserDefaults.standard.integer(forKey: portKey) }
        set { UserDefaults.standard.set(newValue, forKey: portKey) }
    }

    static var username: String {
        get { UserDefaults.standard.string(forKey: usernameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: usernameKey) }
    }

    static var password: String {
        get { UserDefaults.standard.string(forKey: passwordKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: passwordKey) }
    }

    // MARK: - Apply

    /// Applies the saved proxy configuration to Gecko runtime preferences.
    static func applySavedConfig() {
        switch proxyType {
        case .none:
            GeckoRuntime.setDefaultPrefs([
                "network.proxy.type": 0,
            ])

        case .httpProxy:
            GeckoRuntime.setDefaultPrefs([
                "network.proxy.type": 1,
                "network.proxy.http": host,
                "network.proxy.http_port": port,
                "network.proxy.ssl": host,
                "network.proxy.ssl_port": port,
                "network.proxy.no_proxies_on": "localhost, 127.0.0.1",
            ])

        case .socks5:
            GeckoRuntime.setDefaultPrefs([
                "network.proxy.type": 1,
                "network.proxy.socks": host,
                "network.proxy.socks_port": port,
                "network.proxy.socks_version": 5,
                "network.proxy.socks_remote_dns": true,
                "network.proxy.no_proxies_on": "localhost, 127.0.0.1",
            ])
        }
    }

    /// Clears all proxy settings.
    static func clearProxy() {
        proxyType = .none
        host = ""
        port = 0
        username = ""
        password = ""
        applySavedConfig()
    }
}
