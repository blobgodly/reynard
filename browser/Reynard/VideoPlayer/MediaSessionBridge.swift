//
//  MediaSessionBridge.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import UIKit
import AVFoundation
import GeckoView
import MediaPlayer

// MARK: - Media Session Bridge

/// Bridges Gecko's MediaSessionDelegate to the native VideoPlayerViewController.
/// Intercepts video playback events from the Gecko engine, extracts the video URL,
/// and presents the custom video player for fullscreen or context-menu playback.
final class MediaSessionBridge: NSObject, MediaSessionDelegate {

    // MARK: - Properties

    static let shared = MediaSessionBridge()

    private weak var presentingViewController: UIViewController?
    private var activeVideoPlayer: VideoPlayerViewController?
    private var currentMetadata: MediaSessionMetadata?
    private var currentSession: GeckoSession?

    private override init() {
        super.init()
    }

    // MARK: - Configuration

    /// Sets the view controller that will present the video player.
    func configure(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
    }

    // MARK: - MediaSessionDelegate

    func onActivated(session: GeckoSession) {
        currentSession = session
    }

    func onDeactivated(session: GeckoSession) {
        if currentSession === session {
            currentSession = nil
            currentMetadata = nil
        }
    }

    func onMetadata(session: GeckoSession, metadata: MediaSessionMetadata) {
        currentMetadata = metadata
        // Update now-playing if video player is active
        if let player = activeVideoPlayer {
            let title = metadata.title ?? metadata.artist ?? "Video"
            player.videoTitle = title
            player.controls?.setTitle(title)
        }
    }

    func onPlaybackPlaying(session: GeckoSession) {
        updateNowPlayingPlaybackState(isPlaying: true)
    }

    func onPlaybackPaused(session: GeckoSession) {
        updateNowPlayingPlaybackState(isPlaying: false)
    }

    func onPlaybackNone(session: GeckoSession) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func onFeatures(session: GeckoSession, features: MediaSessionFeatures) {
        // Features describe what media controls are available
        // The video player supports all of them natively
    }

    func onPositionState(session: GeckoSession, state: MediaSessionPositionState) {
        updateNowPlayingPosition(position: state.position, duration: state.duration, rate: state.playbackRate)
    }

    // MARK: - Present Video Player

    /// Presents the custom video player for a given URL.
    /// Called when the user triggers fullscreen video or selects "Open in Player" from context menu.
    func presentVideoPlayer(url: URL, title: String? = nil, from viewController: UIViewController? = nil) {
        let vc = viewController ?? presentingViewController
        guard let presenter = vc else { return }

        let playerVC = VideoPlayerViewController()
        playerVC.videoURL = url
        playerVC.videoTitle = title ?? currentMetadata?.title ?? "Video"
        playerVC.modalPresentationStyle = .fullScreen
        playerVC.modalTransitionStyle = .crossDissolve

        activeVideoPlayer = playerVC
        presenter.present(playerVC, animated: true)
    }

    /// Presents the video player for a context menu video element.
    func presentVideoPlayer(for element: ContextElement, from viewController: UIViewController) {
        guard element.type == .video, let srcUri = element.srcUri, let url = URL(string: srcUri) else { return }
        let title = element.title ?? element.altText ?? currentMetadata?.title
        presentVideoPlayer(url: url, title: title, from: viewController)
    }

    // MARK: - Download Video

    /// Enqueues a video download via the VideoDownloadManager.
    func downloadVideo(url: URL, title: String? = nil) {
        let name = title ?? currentMetadata?.title ?? url.lastPathComponent
        VideoDownloadManager.shared.enqueue(url: url, title: name)
    }

    // MARK: - Now Playing

    private func updateNowPlayingPlaybackState(isPlaying: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let metadata = currentMetadata {
            info[MPMediaItemPropertyTitle] = metadata.title ?? "Video"
            info[MPMediaItemPropertyArtist] = metadata.artist
            info[MPMediaItemPropertyAlbumTitle] = metadata.album
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPosition(position: Double, duration: Double, rate: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Cleanup

    func dismissVideoPlayer() {
        activeVideoPlayer?.dismissPlayer()
        activeVideoPlayer = nil
    }
}
