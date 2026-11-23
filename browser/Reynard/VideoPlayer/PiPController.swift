//
//  PiPController.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import UIKit
import AVFoundation
import AVKit

// MARK: - PiP Controller

/// Manages Picture-in-Picture for the video player.
/// Uses native AVPictureInPictureController on iOS 14+.
/// Falls back to a custom floating mini-player window on iOS 13.
final class PiPController: NSObject {

    // MARK: - Properties

    private weak var playerController: VideoPlayerViewController?
    private var playerLayer: AVPlayerLayer?

    @available(iOS 14.0, *)
    private lazy var nativePiP: AVPictureInPictureController? = {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let layer = playerLayer else { return nil }
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller.delegate = self
        return controller
    }()

    private var floatingWindow: UIWindow?
    private var floatingPlayerLayer: AVPlayerLayer?
    private var isMiniPlayerActive = false

    // MARK: - Init

    init(playerLayer: AVPlayerLayer, playerController: VideoPlayerViewController) {
        self.playerLayer = playerLayer
        self.playerController = playerController
        super.init()
    }

    // MARK: - Toggle PiP

    func togglePiP() {
        if #available(iOS 14.0, *) {
            guard let pip = nativePiP else {
                toggleFallbackMiniPlayer()
                return
            }
            if pip.isPictureInPictureActive {
                pip.stopPictureInPicture()
            } else {
                pip.startPictureInPicture()
            }
        } else {
            toggleFallbackMiniPlayer()
        }
    }

    var isActive: Bool {
        if #available(iOS 14.0, *) {
            if nativePiP?.isPictureInPictureActive == true { return true }
        }
        return isMiniPlayerActive
    }

    // MARK: - Auto-PiP on Background

    func startPiPIfPossible() {
        if #available(iOS 14.0, *) {
            if let pip = nativePiP, !pip.isPictureInPictureActive {
                pip.startPictureInPicture()
            }
        } else {
            if !isMiniPlayerActive {
                showFallbackMiniPlayer()
            }
        }
    }

    // MARK: - Fallback Mini-Player (iOS 13)

    private func toggleFallbackMiniPlayer() {
        if isMiniPlayerActive {
            hideFallbackMiniPlayer()
        } else {
            showFallbackMiniPlayer()
        }
    }

    private func showFallbackMiniPlayer() {
        guard let player = playerController?.player else { return }

        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first

        let window: UIWindow
        if let scene = windowScene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: .zero)
        }

        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isHidden = false

        let size = CGSize(width: 200, height: 112)
        let screenBounds = UIScreen.main.bounds
        window.frame = CGRect(
            x: screenBounds.width - size.width - 16,
            y: screenBounds.height - size.height - 100,
            width: size.width,
            height: size.height
        )

        let container = UIView(frame: window.bounds)
        container.backgroundColor = .black
        container.layer.cornerRadius = 12
        container.clipsToBounds = true
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.4
        container.layer.shadowRadius = 8

        let miniLayer = AVPlayerLayer(player: player)
        miniLayer.videoGravity = .resizeAspect
        miniLayer.frame = container.bounds
        container.layer.addSublayer(miniLayer)

        // Close button
        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(VideoPlayerTheme.icon(VideoPlayerTheme.Icons.close, pointSize: 14, weight: .bold), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeBtn.layer.cornerRadius = 12
        closeBtn.frame = CGRect(x: size.width - 32, y: 4, width: 24, height: 24)
        closeBtn.addTarget(self, action: #selector(miniPlayerCloseTapped), for: .touchUpInside)
        container.addSubview(closeBtn)

        // Pan gesture for dragging
        let pan = UIPanGestureRecognizer(target: self, action: #selector(miniPlayerPanned(_:)))
        container.addGestureRecognizer(pan)

        // Tap to restore
        let tap = UITapGestureRecognizer(target: self, action: #selector(miniPlayerTapped))
        container.addGestureRecognizer(tap)

        window.addSubview(container)
        window.makeKeyAndVisible()

        floatingWindow = window
        floatingPlayerLayer = miniLayer
        isMiniPlayerActive = true

        // Dismiss the main player
        playerController?.dismiss(animated: true)
    }

    private func hideFallbackMiniPlayer() {
        floatingPlayerLayer?.removeFromSuperlayer()
        floatingPlayerLayer = nil
        floatingWindow?.isHidden = true
        floatingWindow = nil
        isMiniPlayerActive = false
    }

    @objc private func miniPlayerCloseTapped() {
        playerController?.player?.pause()
        hideFallbackMiniPlayer()
    }

    @objc private func miniPlayerTapped() {
        hideFallbackMiniPlayer()
        // Re-present the full player
        // The calling code should handle re-presenting
    }

    @objc private func miniPlayerPanned(_ gesture: UIPanGestureRecognizer) {
        guard let window = floatingWindow else { return }
        let translation = gesture.translation(in: window)
        window.center = CGPoint(
            x: window.center.x + translation.x,
            y: window.center.y + translation.y
        )
        gesture.setTranslation(.zero, in: window)

        if gesture.state == .ended {
            // Snap to nearest edge
            let screenBounds = UIScreen.main.bounds
            var center = window.center
            if center.x < screenBounds.midX {
                center.x = window.bounds.width / 2 + 16
            } else {
                center.x = screenBounds.width - window.bounds.width / 2 - 16
            }
            center.y = max(window.bounds.height / 2 + 50, min(center.y, screenBounds.height - window.bounds.height / 2 - 50))

            UIView.animate(withDuration: 0.25) {
                window.center = center
            }
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

@available(iOS 14.0, *)
extension PiPController: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // Optionally dismiss the full-screen player
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // Restore UI
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // Re-present the player if needed
        completionHandler(true)
    }
}
