//
//  VideoPlayerViewController.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import UIKit
import AVFoundation
import AVKit
import MediaPlayer

// MARK: - Video Player View Controller

/// Professional full-screen video player with custom controls, gestures,
/// PiP support, and subtitle rendering. Designed for iPhone 7 (iOS 13+).
final class VideoPlayerViewController: UIViewController {

    // MARK: - Properties

    private(set) var player: AVPlayer?
    private var playerLayer: AVPlayerLayer!
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    private(set) var controls: VideoPlayerControls!
    private var gestures: VideoPlayerGestures!
    private(set) var subtitleRenderer: SubtitleRenderer!
    private(set) var pipController: PiPController!

    private let loadingSpinner = UIActivityIndicatorView(style: .large)
    private let errorView = UIView()
    private let errorTitleLabel = UILabel()
    private let errorBodyLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    var videoTitle: String = ""
    var videoURL: URL?
    private var isSeekInProgress = false
    private var seekTargetTime: CMTime = .zero
    private(set) var currentPlaybackSpeed: Float = 1.0
    private var speedBeforeLongPress: Float = 1.0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        modalPresentationCapturesStatusBarAppearance = true

        setupPlayerLayer()
        setupLoadingSpinner()
        setupErrorView()
        setupSubtitles()
        setupControls()
        setupGestures()
        setupPiP()
        setupAudioSession()
        setupRemoteCommands()

        if let url = videoURL {
            loadVideo(url: url)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
        subtitleRenderer.bringToFront()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeObservers()
    }

    deinit {
        removeObservers()
        player?.pause()
        player = nil
    }

    // MARK: - Status Bar

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    // MARK: - Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var shouldAutorotate: Bool { true }

    // MARK: - Setup

    private func setupPlayerLayer() {
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(playerLayer)
    }

    private func setupLoadingSpinner() {
        loadingSpinner.color = .white
        loadingSpinner.hidesWhenStopped = true
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingSpinner)
        NSLayoutConstraint.activate([
            loadingSpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingSpinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupErrorView() {
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorView)

        errorTitleLabel.text = "Unable to Play"
        errorTitleLabel.font = VideoPlayerTheme.Fonts.errorTitle
        errorTitleLabel.textColor = .white
        errorTitleLabel.textAlignment = .center
        errorTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        errorBodyLabel.text = "An error occurred while loading the video."
        errorBodyLabel.font = VideoPlayerTheme.Fonts.errorBody
        errorBodyLabel.textColor = VideoPlayerTheme.Colors.secondaryText
        errorBodyLabel.textAlignment = .center
        errorBodyLabel.numberOfLines = 0
        errorBodyLabel.translatesAutoresizingMaskIntoConstraints = false

        retryButton.setTitle("Retry", for: .normal)
        retryButton.setImage(VideoPlayerTheme.icon(VideoPlayerTheme.Icons.retry, pointSize: 16), for: .normal)
        retryButton.tintColor = VideoPlayerTheme.Colors.accent
        retryButton.titleLabel?.font = VideoPlayerTheme.Fonts.menuItem
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.translatesAutoresizingMaskIntoConstraints = false

        errorView.addSubview(errorTitleLabel)
        errorView.addSubview(errorBodyLabel)
        errorView.addSubview(retryButton)

        NSLayoutConstraint.activate([
            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),

            errorTitleLabel.topAnchor.constraint(equalTo: errorView.topAnchor),
            errorTitleLabel.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),

            errorBodyLabel.topAnchor.constraint(equalTo: errorTitleLabel.bottomAnchor, constant: 8),
            errorBodyLabel.leadingAnchor.constraint(equalTo: errorView.leadingAnchor),
            errorBodyLabel.trailingAnchor.constraint(equalTo: errorView.trailingAnchor),

            retryButton.topAnchor.constraint(equalTo: errorBodyLabel.bottomAnchor, constant: 16),
            retryButton.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            retryButton.bottomAnchor.constraint(equalTo: errorView.bottomAnchor),
        ])
    }

    private func setupSubtitles() {
        subtitleRenderer = SubtitleRenderer(containerView: view)
    }

    private func setupControls() {
        controls = VideoPlayerControls(playerController: self)
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: view.topAnchor),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupGestures() {
        gestures = VideoPlayerGestures(playerController: self, controlsView: controls)
    }

    private func setupPiP() {
        pipController = PiPController(playerLayer: playerLayer, playerController: self)
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[VideoPlayer] Audio session setup error: \(error)")
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    // MARK: - Loading

    func loadVideo(url: URL) {
        videoURL = url
        errorView.isHidden = true
        loadingSpinner.startAnimating()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        if player == nil {
            player = AVPlayer(playerItem: item)
            playerLayer.player = player
        } else {
            player?.replaceCurrentItem(with: item)
        }

        setupObservers()
    }

    // MARK: - Observers

    private func setupObservers() {
        guard let player = player, let item = player.currentItem else { return }

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.loadingSpinner.stopAnimating()
                    self?.player?.play()
                    self?.controls.updatePlayPauseButton(isPlaying: true)
                    self?.updateNowPlayingInfo()
                case .failed:
                    self?.loadingSpinner.stopAnimating()
                    self?.showError(item.error)
                default:
                    break
                }
            }
        }

        bufferObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.isPlaybackBufferEmpty {
                    self?.loadingSpinner.startAnimating()
                } else {
                    self?.loadingSpinner.stopAnimating()
                }
            }
        }

        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.controls.updatePlayPauseButton(isPlaying: player.rate > 0)
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeekInProgress else { return }
            let currentTime = CMTimeGetSeconds(time)
            let duration = CMTimeGetSeconds(item.duration)
            guard duration.isFinite && duration > 0 else { return }
            self.controls.updateTime(current: currentTime, duration: duration)
            self.subtitleRenderer.update(currentTime: currentTime)
            self.updateNowPlayingInfo()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime, object: item
        )
    }

    private func removeObservers() {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()
        rateObserver?.invalidate()
        statusObserver = nil
        bufferObserver = nil
        rateObserver = nil

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        NotificationCenter.default.removeObserver(self)
        MPRemoteCommandCenter.shared().playCommand.removeTarget(self)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(self)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(self)
        MPRemoteCommandCenter.shared().skipForwardCommand.removeTarget(self)
        MPRemoteCommandCenter.shared().skipBackwardCommand.removeTarget(self)
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(self)
    }

    // MARK: - Playback Controls

    func play() {
        player?.play()
        player?.rate = currentPlaybackSpeed
    }

    func pause() {
        player?.pause()
    }

    func togglePlayPause() {
        if player?.rate ?? 0 > 0 {
            pause()
        } else {
            play()
        }
    }

    func skipForward() {
        guard let player = player, let item = player.currentItem else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        let duration = CMTimeGetSeconds(item.duration)
        let target = min(current + VideoPlayerTheme.Layout.skipSeekSeconds, duration)
        seek(to: target)
    }

    func skipBackward() {
        guard let player = player else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        let target = max(current - VideoPlayerTheme.Layout.skipSeekSeconds, 0)
        seek(to: target)
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        isSeekInProgress = true
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished {
                self?.isSeekInProgress = false
            }
        }
    }

    func setPlaybackSpeed(_ speed: Float) {
        currentPlaybackSpeed = speed
        if player?.rate ?? 0 > 0 {
            player?.rate = speed
        }
        controls.updateSpeedLabel(speed)
    }

    func setTemporarySpeed(_ speed: Float) {
        speedBeforeLongPress = currentPlaybackSpeed
        player?.rate = speed
        controls.showSpeedIndicator(speed)
    }

    func restoreSpeed() {
        player?.rate = speedBeforeLongPress
        controls.hideSpeedIndicator()
    }

    func toggleVideoGravity() {
        if playerLayer.videoGravity == .resizeAspect {
            playerLayer.videoGravity = .resizeAspectFill
        } else {
            playerLayer.videoGravity = .resizeAspect
        }
    }

    // MARK: - Volume & Brightness

    func adjustVolume(by delta: Float) {
        let session = AVAudioSession.sharedInstance()
        // Volume is managed via MPVolumeView (system slider)
        // We use the UI slider to reflect it
        controls.updateVolumeIndicator(session.outputVolume + delta)
    }

    func adjustBrightness(by delta: CGFloat) {
        UIScreen.main.brightness = max(0, min(1, UIScreen.main.brightness + delta))
        controls.updateBrightnessIndicator(Float(UIScreen.main.brightness))
    }

    // MARK: - Now Playing

    private func updateNowPlayingInfo() {
        guard let item = player?.currentItem else { return }
        let current = CMTimeGetSeconds(player?.currentTime() ?? .zero)
        let duration = CMTimeGetSeconds(item.duration)
        guard duration.isFinite else { return }

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = videoTitle.isEmpty ? "Video" : videoTitle
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Errors

    private func showError(_ error: Error?) {
        errorView.isHidden = false
        errorBodyLabel.text = error?.localizedDescription ?? "An unknown error occurred."
    }

    @objc private func retryTapped() {
        guard let url = videoURL else { return }
        loadVideo(url: url)
    }

    @objc private func playerDidFinish() {
        controls.updatePlayPauseButton(isPlaying: false)
    }

    // MARK: - Dismiss

    @objc func dismissPlayer() {
        player?.pause()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        dismiss(animated: true)
    }

    // MARK: - Duration helpers

    var currentTime: Double {
        CMTimeGetSeconds(player?.currentTime() ?? .zero)
    }

    var duration: Double {
        guard let d = player?.currentItem?.duration else { return 0 }
        let seconds = CMTimeGetSeconds(d)
        return seconds.isFinite ? seconds : 0
    }

    var isPlaying: Bool {
        (player?.rate ?? 0) > 0
    }
}
