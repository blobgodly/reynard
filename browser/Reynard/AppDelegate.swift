//
//  AppDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        JITController.shared.startBackgroundAudioIfNeeded()
        
        // Apply Gecko optimizations for iPhone 7 performance & anti-restriction
        GeckoOptimizations.applyAll()
        UserAgentConfig.restoreSavedPreset()
        ProxyConfig.applySavedConfig()
        
        // Initialize Rust acceleration cache (50 MB limit for iPhone 7)
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ReynardCache").path
        ReynardRust.configureCache(maxBytes: 50 * 1024 * 1024, storageDir: cacheDir)
        
        return true
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}
}
