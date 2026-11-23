//
//  VideoPlayerGestures.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import UIKit

// MARK: - Video Player Gestures

/// Handles all gesture interactions for the video player:
/// - Double-tap left/right to skip 10 seconds
/// - Swipe up/down on LEFT side → brightness, RIGHT side → volume
/// - Pinch to toggle aspect fill/fit
/// - Long press for 2× speed
/// - Horizontal pan to seek
final class VideoPlayerGestures: NSObject {

    // MARK: - Properties

    private weak var playerController: VideoPlayerViewController?
    private weak var controlsView: VideoPlayerControls?

    private var panStartLocation: CGPoint = .zero
    private var panStartBrightness: CGFloat = 0
    private var panStartVolume: Float = 0
    private var isVerticalPan = false
    private var isHorizontalPan = false
    private var panStartTime: Double = 0
    private var seekPreviewAccumulator: Double = 0

    // Double-tap ripple views
    private let leftRipple = UIView()
    private let rightRipple = UIView()
    private let leftSkipLabel = UILabel()
    private let rightSkipLabel = UILabel()

    // MARK: - Init

    init(playerController: VideoPlayerViewController, controlsView: VideoPlayerControls) {
        self.playerController = playerController
        self.controlsView = controlsView
        super.init()
        setupGestures()
        setupRippleViews()
    }

    // MARK: - Setup

    private func setupGestures() {
        guard let view = playerController?.view else { return }

        // Double-tap left side
        let doubleTapLeft = UITapGestureRecognizer(target: self, action: #selector(doubleTapLeftHandler(_:)))
        doubleTapLeft.numberOfTapsRequired = 2
        doubleTapLeft.delegate = self

        // Double-tap right side
        let doubleTapRight = UITapGestureRecognizer(target: self, action: #selector(doubleTapRightHandler(_:)))
        doubleTapRight.numberOfTapsRequired = 2
        doubleTapRight.delegate = self

        // Pan (volume/brightness/seek)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panHandler(_:)))
        pan.delegate = self

        // Pinch (zoom)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchHandler(_:)))
        pinch.delegate = self

        // Long press (2× speed)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressHandler(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = self

        view.addGestureRecognizer(doubleTapLeft)
        view.addGestureRecognizer(doubleTapRight)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(longPress)
    }

    private func setupRippleViews() {
        guard let view = playerController?.view else { return }

        for (ripple, label, isLeft) in [(leftRipple, leftSkipLabel, true), (rightRipple, rightSkipLabel, false)] {
            ripple.backgroundColor = UIColor.white.withAlphaComponent(0.15)
            ripple.alpha = 0
            ripple.layer.cornerRadius = 60
            ripple.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(ripple)

            label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            label.textColor = .white
            label.textAlignment = .center
            label.alpha = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)

            NSLayoutConstraint.activate([
                ripple.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                ripple.widthAnchor.constraint(equalToConstant: 120),
                ripple.heightAnchor.constraint(equalToConstant: 120),
                label.centerXAnchor.constraint(equalTo: ripple.centerXAnchor),
                label.topAnchor.constraint(equalTo: ripple.bottomAnchor, constant: 8),
            ])

            if isLeft {
                ripple.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: view.bounds.width * 0.25).isActive = true
            } else {
                ripple.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: -view.bounds.width * 0.25).isActive = true
            }
        }
    }

    // MARK: - Handlers

    @objc private func doubleTapLeftHandler(_ gesture: UITapGestureRecognizer) {
        guard let view = playerController?.view else { return }
        let location = gesture.location(in: view)
        guard location.x < view.bounds.midX else { return }
        guard controlsView?.isLocked != true else { return }

        playerController?.skipBackward()
        showRipple(leftRipple, label: leftSkipLabel, text: "-\(Int(VideoPlayerTheme.Layout.doubleTapSeekSeconds))s")
    }

    @objc private func doubleTapRightHandler(_ gesture: UITapGestureRecognizer) {
        guard let view = playerController?.view else { return }
        let location = gesture.location(in: view)
        guard location.x >= view.bounds.midX else { return }
        guard controlsView?.isLocked != true else { return }

        playerController?.skipForward()
        showRipple(rightRipple, label: rightSkipLabel, text: "+\(Int(VideoPlayerTheme.Layout.doubleTapSeekSeconds))s")
    }

    @objc private func panHandler(_ gesture: UIPanGestureRecognizer) {
        guard let view = playerController?.view, controlsView?.isLocked != true else { return }

        switch gesture.state {
        case .began:
            panStartLocation = gesture.location(in: view)
            panStartBrightness = UIScreen.main.brightness
            panStartVolume = AVAudioSession.sharedInstance().outputVolume
            panStartTime = playerController?.currentTime ?? 0
            seekPreviewAccumulator = 0
            isVerticalPan = false
            isHorizontalPan = false

        case .changed:
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)

            // Determine direction on first significant movement
            if !isVerticalPan && !isHorizontalPan {
                if abs(velocity.x) > abs(velocity.y) * 1.5 {
                    isHorizontalPan = true
                } else if abs(velocity.y) > abs(velocity.x) * 1.5 {
                    isVerticalPan = true
                }
            }

            if isVerticalPan {
                let delta = -translation.y / view.bounds.height
                let isLeftSide = panStartLocation.x < view.bounds.midX

                if isLeftSide {
                    // Brightness
                    let newBrightness = panStartBrightness + delta
                    playerController?.adjustBrightness(by: newBrightness - UIScreen.main.brightness)
                } else {
                    // Volume
                    let newVolume = panStartVolume + Float(delta)
                    playerController?.adjustVolume(by: newVolume - AVAudioSession.sharedInstance().outputVolume)
                }
            } else if isHorizontalPan {
                // Horizontal seek
                let seekDelta = Double(translation.x / view.bounds.width) * (playerController?.duration ?? 0) * 0.5
                seekPreviewAccumulator = seekDelta
                let targetTime = max(0, min(panStartTime + seekDelta, playerController?.duration ?? 0))
                playerController?.seek(to: targetTime)
            }

        case .ended, .cancelled:
            isVerticalPan = false
            isHorizontalPan = false

        default:
            break
        }
    }

    @objc private func pinchHandler(_ gesture: UIPinchGestureRecognizer) {
        guard controlsView?.isLocked != true else { return }
        if gesture.state == .ended {
            playerController?.toggleVideoGravity()
        }
    }

    @objc private func longPressHandler(_ gesture: UILongPressGestureRecognizer) {
        guard controlsView?.isLocked != true else { return }
        switch gesture.state {
        case .began:
            playerController?.setTemporarySpeed(VideoPlayerTheme.Layout.longPressSpeed)
        case .ended, .cancelled:
            playerController?.restoreSpeed()
        default:
            break
        }
    }

    // MARK: - Ripple Animation

    private func showRipple(_ ripple: UIView, label: UILabel, text: String) {
        label.text = text
        ripple.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        ripple.alpha = 1
        label.alpha = 1

        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut, animations: {
            ripple.transform = .identity
            ripple.alpha = 0
        })

        UIView.animate(withDuration: 0.3, delay: 0.3, options: .curveEaseOut, animations: {
            label.alpha = 0
        })
    }
}

// MARK: - UIGestureRecognizerDelegate

extension VideoPlayerGestures: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow double-taps to coexist, block others from conflicting
        if gestureRecognizer is UITapGestureRecognizer && otherGestureRecognizer is UITapGestureRecognizer {
            return true
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Single tap should require double-tap to fail
        if gestureRecognizer is UITapGestureRecognizer,
           let other = otherGestureRecognizer as? UITapGestureRecognizer,
           other.numberOfTapsRequired == 2 {
            return true
        }
        return false
    }
}
