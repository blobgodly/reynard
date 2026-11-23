//
//  VideoPlayerControls.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import UIKit
import AVFoundation
import MediaPlayer

// MARK: - Video Player Controls

/// Full control overlay: top bar (title, close, PiP), center play/skip,
/// bottom bar (seek, time, speed, AirPlay), side sliders (volume, brightness).
final class VideoPlayerControls: UIView {

    // MARK: - References

    private weak var playerController: VideoPlayerViewController?
    private var autoHideTimer: Timer?
    private(set) var isLocked = false
    private(set) var controlsVisible = true

    // MARK: - Top Bar

    private let topBar = UIView()
    private let topBlur: UIVisualEffectView = VideoPlayerTheme.Blur.barBlurView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let pipButton = UIButton(type: .system)
    private let lockButton = UIButton(type: .system)

    // MARK: - Center Controls

    private let centerStack = UIStackView()
    private let skipBackButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let skipForwardButton = UIButton(type: .system)

    // MARK: - Bottom Bar

    private let bottomBar = UIView()
    private let bottomBlur: UIVisualEffectView = VideoPlayerTheme.Blur.barBlurView()
    private let seekSlider = UISlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let speedButton = UIButton(type: .system)
    private let airPlayContainer = UIView()

    // MARK: - Speed Indicator (long-press)

    private let speedIndicatorView = UIView()
    private let speedIndicatorLabel = UILabel()

    // MARK: - Init

    init(playerController: VideoPlayerViewController) {
        self.playerController = playerController
        super.init(frame: .zero)
        setupViews()
        scheduleAutoHide()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        isUserInteractionEnabled = true
        setupTopBar()
        setupCenterControls()
        setupBottomBar()
        setupSpeedIndicator()
        setupTapToToggle()
    }

    // MARK: - Top Bar

    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBar)

        topBlur.translatesAutoresizingMaskIntoConstraints = false
        topBar.insertSubview(topBlur, at: 0)
        NSLayoutConstraint.activate([
            topBlur.topAnchor.constraint(equalTo: topBar.topAnchor),
            topBlur.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            topBlur.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            topBlur.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
        ])

        // Close button
        closeButton.setImage(VideoPlayerTheme.icon(VideoPlayerTheme.Icons.close, pointSize: 18, weight: .bold), for: .normal)
        closeButton.tintColor = VideoPlayerTheme.Colors.tint
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.font = VideoPlayerTheme.Fonts.title
        titleLabel.textColor = VideoPlayerTheme.Colors.tint
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // PiP
        pipButton.setImage(VideoPlayerTheme.icon(VideoPlayerTheme.Icons.pip, pointSize: 18), for: .normal)
        pipButton.tintColor = VideoPlayerTheme.Colors.tint
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)
        pipButton.translatesAutoresizingMaskIntoConstraints = false

        // Lock
        lockButton.setImage(VideoPlayerTheme.icon(VideoPlayerTheme.Icons.lockOpen, pointSize: 18), for: .normal)
        lockButton.tintColor = VideoPlayerTheme.Colors.tint
        lockButton.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)
        lockButton.translatesAutoresizingMaskIntoConstraints = false

        topBar.addSubview(closeButton)
        topBar.addSubview(titleLabel)
        topBar.addSubview(lockButton)
        topBar.addSubview(pipButton)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: VideoPlayerTheme.Layout.barHeight + safeAreaTopPadding),

            closeButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            closeButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: VideoPlayerTheme.Layout.mediumButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: VideoPlayerTheme.Layout.mediumButtonSize),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: lockButton.leadingAnchor, constant: -8),

            pipButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            pipButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            pipButton.widthAnchor.constraint(equalToConstant: VideoPlayerTheme.Layout.mediumButtonSize),

            lockButton.trailingAnchor.constraint(equalTo: pipButton.leadingAnchor, constant: -4),
            lockButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            lockButton.widthAnchor.constraint(equalToConstant: VideoPlayerTheme.Layout.mediumButtonSize),
        ])
    }

    // MARK: - Center Controls

    private func setupCenterControls() {
        centerStack.axis = .horizontal
        centerStack.spacing = 48
        centerStack.alignment = .center
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerStack)

        skipBackButton.setImage(VideoPlayerTheme.icon(VideoPlayerTheme.Icons.backward15, pointSize: 30), for: .normal)
        skipBackButton.tintColor = VideoPlayerTheme.Colors.tint
        skipBackButton.addTarget(self, action: #selector(skipBackTapped), for: .touchUpInside)

        playPauseButton.setImage(VideoPlayerTheme.icon(VideoPlayerTheme.Icons.play, pointSize: 44, weight: .bold), for: .normal)
        playPauseButton.tintColor = VideoPlayerTheme.Colors.tint
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)

        skipForwardButton.setImage(VideoPlayerTheme.icon(VideoPlayerTheme.Icons.forward15, pointSize: 30), for: .normal)
        skipForwardButton.tintColor = VideoPlayerTheme.Colors.tint
        skipForwardButton.addTarget(self, action: #selector(skipForwardTapped), for: .touchUpInside)

        centerStack.addArrangedSubview(skipBackButton)
        centerStack.addArrangedSubview(playPauseButton)
        centerStack.addArrangedSubview(skipForwardButton)

        NSLayoutConstraint.activate([
            centerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Bottom Bar

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBar)

        bottomBlur.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.insertSubview(bottomBlur, at: 0)
        NSLayoutConstraint.activate([
            bottomBlur.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            bottomBlur.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            bottomBlur.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            bottomBlur.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor),
        ])

        // Seek slider
        seekSlider.minimumTrackTintColor = VideoPlayerTheme.Colors.seekBarMinimum
        seekSlider.maximumTrackTintColor = VideoPlayerTheme.Colors.seekBarMaximum
        seekSlider.thumbTintColor = VideoPlayerTheme.Colors.sliderThumb
        seekSlider.addTarget(self, action: #selector(seekSliderChanged), for: .valueChanged)
        seekSlider.addTarget(self, action: #selector(seekSliderBegan), for: .touchDown)
        seekSlider.addTarget(self, action: #selector(seekSliderEnded), for: [.touchUpInside, .touchUpOutside])
        seekSlider.translatesAutoresizingMaskIntoConstraints = false

        // Time labels
        elapsedLabel.font = VideoPlayerTheme.Fonts.timeLabel
        elapsedLabel.textColor = VideoPlayerTheme.Colors.secondaryText
        elapsedLabel.text = "0:00"
        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false

        remainingLabel.font = VideoPlayerTheme.Fonts.timeLabel
        remainingLabel.textColor = VideoPlayerTheme.Colors.secondaryText
        remainingLabel.text = "-0:00"
        remainingLabel.translatesAutoresizingMaskIntoConstraints = false

        // Speed button
        speedButton.setTitle("1x", for: .normal)
        speedButton.titleLabel?.font = VideoPlayerTheme.Fonts.speedBadge
        speedButton.tintColor = VideoPlayerTheme.Colors.tint
        speedButton.backgroundColor = VideoPlayerTheme.Colors.speedBadge
        speedButton.layer.cornerRadius = VideoPlayerTheme.Layout.smallCornerRadius
        speedButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        speedButton.addTarget(self, action: #selector(speedTapped), for: .touchUpInside)
        speedButton.translatesAutoresizingMaskIntoConstraints = false

        // AirPlay
        let airPlayButton = AVRoutePickerView()
        airPlayButton.tintColor = VideoPlayerTheme.Colors.tint
        airPlayButton.activeTintColor = VideoPlayerTheme.Colors.accent
        airPlayButton.translatesAutoresizingMaskIntoConstraints = false
        airPlayContainer.addSubview(airPlayButton)
        airPlayContainer.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.addSubview(seekSlider)
        bottomBar.addSubview(elapsedLabel)
        bottomBar.addSubview(remainingLabel)
        bottomBar.addSubview(speedButton)
        bottomBar.addSubview(airPlayContainer)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),

            seekSlider.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),
            seekSlider.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            seekSlider.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),

            elapsedLabel.topAnchor.constraint(equalTo: seekSlider.bottomAnchor, constant: 2),
            elapsedLabel.leadingAnchor.constraint(equalTo: seekSlider.leadingAnchor),

            remainingLabel.topAnchor.constraint(equalTo: seekSlider.bottomAnchor, constant: 2),
            remainingLabel.trailingAnchor.constraint(equalTo: seekSlider.trailingAnchor),

            speedButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 4),
            speedButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            speedButton.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            airPlayContainer.centerYAnchor.constraint(equalTo: speedButton.centerYAnchor),
            airPlayContainer.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            airPlayContainer.widthAnchor.constraint(equalToConstant: 36),
            airPlayContainer.heightAnchor.constraint(equalToConstant: 36),

            airPlayButton.centerXAnchor.constraint(equalTo: airPlayContainer.centerXAnchor),
            airPlayButton.centerYAnchor.constraint(equalTo: airPlayContainer.centerYAnchor),
            airPlayButton.widthAnchor.constraint(equalToConstant: 36),
            airPlayButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    // MARK: - Speed Indicator

    private func setupSpeedIndicator() {
        speedIndicatorView.backgroundColor = VideoPlayerTheme.Colors.speedBadge
        speedIndicatorView.layer.cornerRadius = VideoPlayerTheme.Layout.smallCornerRadius
        speedIndicatorView.isHidden = true
        speedIndicatorView.translatesAutoresizingMaskIntoConstraints = false

        speedIndicatorLabel.font = VideoPlayerTheme.Fonts.speedBadge
        speedIndicatorLabel.textColor = .white
        speedIndicatorLabel.textAlignment = .center
        speedIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false

        speedIndicatorView.addSubview(speedIndicatorLabel)
        addSubview(speedIndicatorView)

        NSLayoutConstraint.activate([
            speedIndicatorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            speedIndicatorView.topAnchor.constraint(equalTo: centerYAnchor, constant: 48),
            speedIndicatorLabel.topAnchor.constraint(equalTo: speedIndicatorView.topAnchor, constant: 6),
            speedIndicatorLabel.bottomAnchor.constraint(equalTo: speedIndicatorView.bottomAnchor, constant: -6),
            speedIndicatorLabel.leadingAnchor.constraint(equalTo: speedIndicatorView.leadingAnchor, constant: 12),
            speedIndicatorLabel.trailingAnchor.constraint(equalTo: speedIndicatorView.trailingAnchor, constant: -12),
        ])
    }

    // MARK: - Tap to Toggle

    private func setupTapToToggle() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(overlayTapped))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        playerController?.dismissPlayer()
    }

    @objc private func playPauseTapped() {
        playerController?.togglePlayPause()
    }

    @objc private func skipBackTapped() {
        playerController?.skipBackward()
    }

    @objc private func skipForwardTapped() {
        playerController?.skipForward()
    }

    @objc private func pipTapped() {
        playerController?.pipController.togglePiP()
    }

    @objc private func lockTapped() {
        isLocked.toggle()
        lockButton.setImage(VideoPlayerTheme.icon(
            isLocked ? VideoPlayerTheme.Icons.lock : VideoPlayerTheme.Icons.lockOpen, pointSize: 18
        ), for: .normal)

        let shouldShow = !isLocked
        centerStack.isHidden = !shouldShow
        topBar.subviews.forEach { v in
            if v !== lockButton && v !== topBlur { v.isHidden = !shouldShow }
        }
        bottomBar.isHidden = !shouldShow
    }

    @objc private func speedTapped() {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        let alert = UIAlertController(title: "Playback Speed", message: nil, preferredStyle: .actionSheet)

        for speed in speeds {
            let title = speed == 1.0 ? "Normal" : "\(speed)x"
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.playerController?.setPlaybackSpeed(speed)
            }
            if speed == playerController?.currentPlaybackSpeed {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = speedButton
            popover.sourceRect = speedButton.bounds
        }
        playerController?.present(alert, animated: true)
    }

    @objc private func seekSliderBegan() {
        cancelAutoHide()
    }

    @objc private func seekSliderChanged() {
        guard let pc = playerController else { return }
        let target = Double(seekSlider.value) * pc.duration
        pc.seek(to: target)
        updateTimeLabels(current: target, duration: pc.duration)
    }

    @objc private func seekSliderEnded() {
        scheduleAutoHide()
    }

    @objc private func overlayTapped(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: self)
        // Don't toggle if tapping on controls
        if topBar.frame.contains(location) || bottomBar.frame.contains(location) || centerStack.frame.contains(location) {
            return
        }
        toggleControls()
    }

    // MARK: - Visibility

    func toggleControls() {
        controlsVisible.toggle()
        let alpha: CGFloat = controlsVisible ? 1 : 0
        UIView.animate(withDuration: VideoPlayerTheme.Layout.animationDuration) {
            self.topBar.alpha = alpha
            self.centerStack.alpha = alpha
            self.bottomBar.alpha = alpha
        }
        if controlsVisible {
            scheduleAutoHide()
        }
    }

    func showControls() {
        guard !controlsVisible else { return }
        toggleControls()
    }

    func hideControls() {
        guard controlsVisible else { return }
        toggleControls()
    }

    // MARK: - Auto-hide

    func scheduleAutoHide() {
        cancelAutoHide()
        guard playerController?.isPlaying == true else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: VideoPlayerTheme.Layout.autoHideDelay, repeats: false) { [weak self] _ in
            self?.hideControls()
        }
    }

    func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    // MARK: - Update Methods

    func updatePlayPauseButton(isPlaying: Bool) {
        let icon = isPlaying ? VideoPlayerTheme.Icons.pause : VideoPlayerTheme.Icons.play
        playPauseButton.setImage(VideoPlayerTheme.icon(icon, pointSize: 44, weight: .bold), for: .normal)
        if isPlaying { scheduleAutoHide() } else { cancelAutoHide() }
    }

    func updateTime(current: Double, duration: Double) {
        guard !seekSlider.isTracking else { return }
        seekSlider.value = Float(current / max(duration, 1))
        updateTimeLabels(current: current, duration: duration)
    }

    private func updateTimeLabels(current: Double, duration: Double) {
        elapsedLabel.text = formatTime(current)
        remainingLabel.text = "-\(formatTime(max(duration - current, 0)))"
    }

    func updateSpeedLabel(_ speed: Float) {
        let title = speed == 1.0 ? "1x" : String(format: "%.2gx", speed)
        speedButton.setTitle(title, for: .normal)
    }

    func showSpeedIndicator(_ speed: Float) {
        speedIndicatorLabel.text = "\(String(format: "%.1f", speed))× Speed"
        speedIndicatorView.isHidden = false
    }

    func hideSpeedIndicator() {
        speedIndicatorView.isHidden = true
    }

    func updateVolumeIndicator(_ volume: Float) {
        // Could add a temporary HUD; keep it simple for now
    }

    func updateBrightnessIndicator(_ brightness: Float) {
        // Could add a temporary HUD; keep it simple for now
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private var safeAreaTopPadding: CGFloat {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.windows.first?.safeAreaInsets.top ?? 20
        }
        return 20
    }
}
