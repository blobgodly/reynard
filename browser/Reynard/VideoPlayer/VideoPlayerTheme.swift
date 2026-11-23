//
//  VideoPlayerTheme.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import UIKit

// MARK: - Video Player Theme

/// Centralized theme constants for the Reynard video player.
/// Provides consistent colors, iconography, blur effects, and layout
/// values for a premium dark-mode media experience.
struct VideoPlayerTheme {

    // MARK: - Colors

    struct Colors {
        /// Primary background overlay (semi-transparent black)
        static let overlayBackground = UIColor.black.withAlphaComponent(0.45)

        /// Deeper overlay used for top/bottom control bars
        static let controlBarBackground = UIColor.black.withAlphaComponent(0.60)

        /// Tint color for interactive controls
        static let tint = UIColor.white

        /// Accent color used for active seek position, speed badge, etc.
        static let accent = UIColor(red: 0.0, green: 0.68, blue: 1.0, alpha: 1.0) // system-blue-ish

        /// Secondary text (elapsed / remaining labels)
        static let secondaryText = UIColor(white: 0.78, alpha: 1.0)

        /// Seek bar minimum-track color
        static let seekBarMinimum = accent

        /// Seek bar maximum-track color
        static let seekBarMaximum = UIColor(white: 1.0, alpha: 0.30)

        /// Buffered progress color
        static let seekBarBuffer = UIColor(white: 1.0, alpha: 0.50)

        /// Slider thumb tint
        static let sliderThumb = UIColor.white

        /// Error / destructive action
        static let error = UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0)

        /// Subtitle background
        static let subtitleBackground = UIColor.black.withAlphaComponent(0.70)

        /// Subtitle text
        static let subtitleText = UIColor.white

        /// Speed badge background
        static let speedBadge = UIColor(white: 0.20, alpha: 0.85)
    }

    // MARK: - Icons (SF Symbols)

    struct Icons {
        static let play            = "play.fill"
        static let pause           = "pause.fill"
        static let forward15       = "goforward.15"
        static let backward15      = "gobackward.15"
        static let forward10       = "goforward.10"
        static let backward10      = "gobackward.10"
        static let close           = "xmark"
        static let lock            = "lock.fill"
        static let lockOpen        = "lock.open.fill"
        static let pip             = "pip.enter"
        static let pipExit         = "pip.exit"
        static let airplay         = "airplayaudio"
        static let speed           = "speedometer"
        static let volumeUp        = "speaker.wave.3.fill"
        static let volumeDown      = "speaker.wave.1.fill"
        static let volumeMute      = "speaker.slash.fill"
        static let brightness      = "sun.max.fill"
        static let subtitles       = "captions.bubble.fill"
        static let settings        = "gearshape.fill"
        static let download        = "arrow.down.circle.fill"
        static let retry           = "arrow.clockwise"
        static let expand          = "arrow.up.left.and.arrow.down.right"
        static let compress        = "arrow.down.right.and.arrow.up.left"
        static let checkmark       = "checkmark"
        static let quality         = "slider.horizontal.3"
    }

    // MARK: - Layout

    struct Layout {
        /// Corner radius for pill-shaped buttons and panels
        static let cornerRadius: CGFloat = 12.0

        /// Small corner radius for badges / labels
        static let smallCornerRadius: CGFloat = 6.0

        /// Standard control padding
        static let controlPadding: CGFloat = 16.0

        /// Large button hit area
        static let largeButtonSize: CGFloat = 56.0

        /// Medium button hit area
        static let mediumButtonSize: CGFloat = 44.0

        /// Small button hit area
        static let smallButtonSize: CGFloat = 36.0

        /// Side slider width
        static let sideSliderWidth: CGFloat = 36.0

        /// Side slider height
        static let sideSliderHeight: CGFloat = 160.0

        /// Seek bar height
        static let seekBarHeight: CGFloat = 32.0

        /// Top/bottom bar height
        static let barHeight: CGFloat = 54.0

        /// Animation duration for show/hide
        static let animationDuration: TimeInterval = 0.30

        /// Fast animation (button press feedback, etc.)
        static let fastAnimationDuration: TimeInterval = 0.15

        /// Auto-hide delay for controls
        static let autoHideDelay: TimeInterval = 3.0

        /// Double-tap seek amount in seconds
        static let doubleTapSeekSeconds: Double = 10.0

        /// Skip button seek amount in seconds
        static let skipSeekSeconds: Double = 15.0

        /// Long-press fast speed multiplier
        static let longPressSpeed: Float = 2.0
    }

    // MARK: - Fonts

    struct Fonts {
        static let title = UIFont.systemFont(ofSize: 16, weight: .semibold)
        static let timeLabel = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        static let speedBadge = UIFont.systemFont(ofSize: 13, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 18, weight: .medium)
        static let subtitleSmall = UIFont.systemFont(ofSize: 15, weight: .medium)
        static let subtitleLarge = UIFont.systemFont(ofSize: 22, weight: .medium)
        static let errorTitle = UIFont.systemFont(ofSize: 17, weight: .semibold)
        static let errorBody = UIFont.systemFont(ofSize: 14, weight: .regular)
        static let menuItem = UIFont.systemFont(ofSize: 15, weight: .medium)
    }

    // MARK: - Blur

    struct Blur {
        /// Dark blur style for control backgrounds
        static let controlStyle: UIBlurEffect.Style = .dark

        /// Creates a configured blur effect view for control panels
        static func controlBlurView() -> UIVisualEffectView {
            let blur = UIBlurEffect(style: controlStyle)
            let view = UIVisualEffectView(effect: blur)
            view.layer.cornerRadius = Layout.cornerRadius
            view.clipsToBounds = true
            return view
        }

        /// Creates a blur view for the top/bottom bars (no corner radius)
        static func barBlurView() -> UIVisualEffectView {
            let blur = UIBlurEffect(style: controlStyle)
            let view = UIVisualEffectView(effect: blur)
            view.clipsToBounds = true
            return view
        }
    }

    // MARK: - Helpers

    /// Creates a configured SF Symbol image for use in buttons.
    static func icon(_ systemName: String, pointSize: CGFloat = 22, weight: UIImage.SymbolWeight = .medium) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return UIImage(systemName: systemName, withConfiguration: config)
    }

    /// Creates a button with standard player styling.
    static func makeControlButton(icon systemName: String, pointSize: CGFloat = 22, target: Any?, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(VideoPlayerTheme.icon(systemName, pointSize: pointSize), for: .normal)
        button.tintColor = Colors.tint
        button.addTarget(target, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
